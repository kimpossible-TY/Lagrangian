"""Native reading orchestration and actual WebSocket readiness, with isolated fakes."""
import base64
import hashlib
import importlib.util
from pathlib import Path
import socket
import struct
import subprocess
import sys
import tempfile
import threading
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('flow_reading', ROOT / 'scripts/flow-app.py')
package = importlib.util.module_from_spec(spec)
spec.loader.exec_module(package)


@unittest.skipUnless(sys.platform == 'darwin', 'Native app tests require macOS')
class ReadingSessions(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        temp = tempfile.TemporaryDirectory(prefix='flow-reading-tests-')
        cls.addClassCleanup(temp.cleanup)
        cls.executable = Path(temp.name) / 'reading-tests'
        subprocess.run([
            '/usr/bin/swiftc', '-swift-version', '5', '-warnings-as-errors',
            *package.swift_sources(include_app=False),
            ROOT / 'tests/flow-app/ReadingSessionTests.swift', '-o', cls.executable,
        ], check=True)

    def scenario(self, name, *args):
        result = subprocess.run([self.executable, name, *map(str, args)], capture_output=True,
                                text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout.strip()

    def test_readiness_stages_and_double_read(self): self.scenario('read-once')
    def test_main_thread_stays_responsive_and_stop_is_serialized(self): self.scenario('responsive-and-serialized-stop')
    def test_changed_configuration_invalidates_old_read(self): self.scenario('switch-stale')
    def test_stop_invalidates_old_read(self): self.scenario('stop-stale')
    def test_stop_waits_for_actual_exit(self): self.scenario('stop-confirmation')
    def test_replaced_process_invalidates_old_document(self): self.scenario('process-replaced')
    def test_sleep_wake_network_and_power_policy(self): self.scenario('sleep-wake-power')
    def test_timeout_preserves_cause_and_does_not_retry(self): self.scenario('timeout')
    def test_validation_precedes_service_start(self): self.scenario('validation-failure')
    def test_compile_failure_is_inline(self): self.scenario('compile-failure')
    def test_browser_failure_is_inline(self): self.scenario('browser-failure')
    def test_storage_mutation_completes_across_sleep(self): self.scenario('mutation-sleep')
    def test_storage_failure_is_inline(self): self.scenario('mutation-failure')
    def test_mutation_supersedes_pending_read_without_dropping_callback(self): self.scenario('mutation-supersedes-read')
    def test_reentrant_selection_cancels_open(self): self.scenario('reentrant-ready')
    def test_startup_deadline_includes_command_execution(self): self.scenario('command-deadline')
    def test_process_runner_terminates_slow_child(self): self.scenario('command-timeout')
    def test_process_runner_drains_large_output_without_deadlock(self): self.scenario('command-output')
    def test_disposal_rejects_late_callbacks(self): self.scenario('dispose-stale')

    def wire(self, frames, expected, http_only=False):
        listener = socket.socket()
        listener.bind(('127.0.0.1', 0))
        listener.listen()
        listener.settimeout(5)
        received = []
        failures = []

        def server():
            try:
                with listener.accept()[0] as connection:
                    connection.settimeout(2)
                    request = b''
                    while b'\r\n\r\n' not in request:
                        request += connection.recv(4096)
                    if http_only:
                        connection.sendall(b'HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nOK')
                        return
                    headers = dict(line.split(':', 1) for line in request.decode().split('\r\n')[1:] if ':' in line)
                    key = next(value.strip() for name, value in headers.items() if name.lower() == 'sec-websocket-key')
                    accept = base64.b64encode(hashlib.sha1((key + '258EAFA5-E914-47DA-95CA-C5AB0DC85B11').encode()).digest())
                    connection.sendall(b'HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: ' + accept + b'\r\n\r\n')
                    data = b''
                    while len(data) < 2:
                        data += connection.recv(4096)
                    size = data[1] & 127
                    while len(data) < 6 + size:
                        data += connection.recv(4096)
                    mask = data[2:6]
                    received.append(bytes(byte ^ mask[index % 4] for index, byte in enumerate(data[6:6 + size])))
                    for opcode, payload in frames:
                        header = bytes([0x80 | opcode, len(payload)]) if len(payload) < 126 else bytes([0x80 | opcode, 126]) + struct.pack('!H', len(payload))
                        connection.sendall(header + payload)
                    # Keep a protocol-valid connection open until the bounded probe closes it.
                    try:
                        connection.recv(4096)
                    except (socket.timeout, ConnectionResetError):
                        pass
            except Exception as error:
                failures.append(error)

        thread = threading.Thread(target=server, daemon=True)
        thread.start()
        try:
            self.assertEqual(self.scenario('wire', listener.getsockname()[1]), expected)
        finally:
            thread.join(timeout=5)
            listener.close()
        self.assertFalse(thread.is_alive(), 'readiness server did not finish')
        self.assertEqual(failures, [])
        if not http_only:
            self.assertEqual(received, [b'current'])

    def test_http_success_is_not_document_readiness(self): self.wire([], 'waiting', http_only=True)
    def test_compile_success_without_document_is_not_ready(self): self.wire([(2, b'compile-status,success')], 'waiting')
    def test_empty_full_frame_is_not_ready(self): self.wire([(2, b'new,')], 'waiting')
    def test_incremental_frame_is_not_a_full_document(self): self.wire([(2, b'diff-v1,payload')], 'waiting')
    def test_text_frame_cannot_impersonate_document(self): self.wire([(1, b'new,payload')], 'waiting')
    def test_compile_error_without_document_is_reported(self): self.wire([(2, b'compile-status,error')], 'failed')
    def test_accepted_document_proves_readiness(self): self.wire([(2, b'compile-status,success'), (2, b'new,payload')], 'ready')
    def test_previous_document_does_not_hide_current_compile_error(self): self.wire([(2, b'compile-status,error'), (2, b'new,payload')], 'failed')
    def test_success_clears_previous_compile_failure(self): self.wire([(2, b'compile-status,error'), (2, b'compile-status,success'), (2, b'new,payload')], 'ready')


if __name__ == '__main__':
    unittest.main()
