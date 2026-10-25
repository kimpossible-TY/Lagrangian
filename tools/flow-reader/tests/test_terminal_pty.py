"""Exercise real terminal ownership without requiring a browser installation.

Browser/document behavior is covered separately by terminal-browser.mjs. The page
stub here isolates raw input, signal cleanup, and the readable-stream lifecycle.
"""

import json
import os
from pathlib import Path
import select
import shutil
import signal
import subprocess
import tempfile
import time
import unittest

try:
    import fcntl
    import pty
    import struct
    import termios
except ImportError:
    pty = None


TERMINAL = Path(__file__).resolve().parents[1] / "terminal.mjs"
HOST = TERMINAL.parent / "terminal/host.mjs"
SERVICE = TERMINAL.parent / "terminal/service.mjs"
NODE = shutil.which("node")
PAGE_STUB = """
const { TerminalReader } = await import(process.argv[1]);
const page = {
  context() { return { async newCDPSession() { return {
    on() {}, off() {}, async send() {}, async detach() {},
  }; } }; },
  async setViewportSize() {},
  async evaluate() { return false; },
  async screenshot() {
    return Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==', 'base64');
  },
};
await new TerminalReader({ protocol: 'iterm2' }, page).run();
"""


@unittest.skipUnless(pty is not None and NODE, "Requires a POSIX PTY and Node.js")
class TerminalLifetimeTests(unittest.TestCase):
    def run_terminal(self, stop, script=PAGE_STUB, trigger=b"\x1b]1337;File="):
        master, slave = pty.openpty()
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 80, 720, 432))
        before = termios.tcgetattr(slave)
        environment = os.environ.copy()
        environment.pop("TMUX", None)
        environment.pop("NVIM", None)
        process = subprocess.Popen(
            [NODE, "--input-type=module", "-e", script, HOST.as_uri()],
            stdin=slave, stdout=slave, stderr=slave, env=environment,
        )
        output = bytearray()
        stopped = False
        deadline = time.monotonic() + 8
        try:
            while process.poll() is None and time.monotonic() < deadline:
                if select.select([master], [], [], 0.1)[0]:
                    output.extend(os.read(master, 65536))
                    if trigger in output and not stopped:
                        stop(process, master)
                        stopped = True
            self.assertIsNotNone(process.poll(), "Reader must exit after releasing input")
            while select.select([master], [], [], 0.01)[0]:
                output.extend(os.read(master, 65536))
            self.assertEqual(process.returncode, 0, bytes(output[-2000:]))
            self.assertTrue(stopped)
            self.assertIn(b"\x1b[?1049l", output)
            self.assertIn(b"\x1b[?1006l", output)
            self.assertEqual(before, termios.tcgetattr(slave))
        finally:
            if process.poll() is None:
                process.kill()
            process.wait(timeout=3)
            os.close(master)
            os.close(slave)

    def test_quit_restores_terminal_and_releases_initially_idle_stdin(self):
        self.run_terminal(lambda _process, master: os.write(master, b"q"))

    def test_sigterm_restores_terminal(self):
        self.run_terminal(lambda process, _master: process.send_signal(signal.SIGTERM))

    def test_sixel_quit_restores_terminal(self):
        self.run_terminal(
            lambda _process, master: os.write(master, b"q"),
            script=PAGE_STUB.replace("protocol: 'iterm2'", "protocol: 'sixel'"),
            trigger=b'\x1bP0;1;0q"1;1;1;1',
        )

    def test_attached_session_stops_when_editor_removes_manifest(self):
        with tempfile.TemporaryDirectory(prefix="terminal-attach-") as temporary:
            temporary = Path(temporary)
            control = temporary / "editor.json"
            browser = temporary / "playwright.mjs"
            browser.write_text("""
const page = {
  context() { return { async newCDPSession() { return {
    on() {}, off() {}, async send() {}, async detach() {},
  }; } }; },
  async goto() {}, async waitForFunction() {}, async evaluate() { return false; },
  async waitForTimeout() {}, async setViewportSize() {},
  request: { async get() { return { async json() { return { editorServer: 'editor.sock' }; } }; } },
  async screenshot() {
    return Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==', 'base64');
  },
};
export const chromium = { async launchPersistentContext() {
  return { pages() { return [page]; }, on() {}, async close() {} };
} };
""")
            control.write_text(json.dumps({"version": 1, "args": [
                "--url", "http://127.0.0.1:23626/", "--editor-server", "editor.sock",
                "--parent-pid", str(os.getpid()), "--control-file", str(control),
                "--playwright-module", str(browser), "--profile", str(temporary / "profile"),
            ]}))
            script = "const {main}=await import(new URL('./cli.mjs',process.argv[1])); await main(" + json.dumps([
                "--session", str(control), "--protocol", "sixel",
            ]) + ");"
            self.run_terminal(
                lambda _process, _master: control.unlink(), script=script,
                trigger=b'\x1bP0;1;0q"1;1;1;1',
            )
            self.assertFalse(control.exists())
            self.assertFalse(Path(str(control) + ".attached").exists())

    def test_startup_cell_report_cannot_race_initial_browser_resize(self):
        script = """
const { TerminalReader } = await import(process.argv[1]);
let viewport;
let resizeCount = 0;
const page = {
  context() { return { async newCDPSession() { return {
    on() {}, off() {}, async send() {}, async detach() {},
  }; } }; },
  async setViewportSize(size) {
    const count = ++resizeCount;
    await new Promise(resolve => setTimeout(resolve, count === 1 ? 120 : 0));
    viewport = size;
  },
  async evaluate() { return false; },
  async screenshot() {
    return Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==', 'base64');
  },
};
const terminal = new TerminalReader({ protocol: 'iterm2' }, page);
const stop = setTimeout(() => terminal.stop(), 350);
try { await terminal.run(); }
finally { clearTimeout(stop); }
if (resizeCount < 2 || terminal.size.width !== 560 || viewport.width !== terminal.size.width)
  throw new Error(`Initial browser resize raced the cell report: ${JSON.stringify({viewport, size: terminal.size, resizeCount})}`);
"""
        self.run_terminal(
            lambda _process, master: os.write(master, b"\x1b]1337;ReportCellSize=18;7;2\x07"),
            script=script, trigger=b"ReportCellSize\x07",
        )

    def test_capture_cannot_restore_an_old_viewport_over_a_cell_resize(self):
        script = """
const { TerminalReader } = await import(process.argv[1]);
let viewport;
let resizeCount = 0;
const page = {
  context() { return { async newCDPSession() { return {
    on() {}, off() {}, async send() {}, async detach() {},
  }; } }; },
  async setViewportSize(size) { resizeCount++; viewport = size; },
  async evaluate() { return false; },
  async screenshot() {
    const originalViewport = viewport;
    process.stdout.write('SNAPSHOT-START');
    await new Promise(resolve => setTimeout(resolve, 120));
    // Model a screenshot backend which restores metrics after taking a frame.
    viewport = originalViewport;
    return Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==', 'base64');
  },
};
const terminal = new TerminalReader({ protocol: 'iterm2' }, page);
const stop = setTimeout(() => terminal.stop(), 550);
try { await terminal.run(); }
finally { clearTimeout(stop); }
if (resizeCount < 2 || terminal.size.width !== 560 || viewport.width !== terminal.size.width)
  throw new Error(`Screenshot restored an obsolete browser viewport: ${JSON.stringify({viewport, size: terminal.size, resizeCount})}`);
"""
        self.run_terminal(
            lambda _process, master: os.write(master, b"\x1b]1337;ReportCellSize=18;7;2\x07"),
            script=script, trigger=b"SNAPSHOT-START",
        )

    def test_attachment_close_preserves_the_shared_service_process(self):
        with tempfile.TemporaryDirectory(prefix="terminal-shared-service-") as temporary:
            temporary = Path(temporary)
            attachment = temporary / 'attachment.json'
            attachment.write_text('private editor attachment')
            interpreter = temporary / 'fake-manager-python'
            interpreter.write_text(
                '#!' + shutil.which('python3') + '\nimport json\nprint(' +
                repr(json.dumps({'url': 'http://127.0.0.1:23626/', 'attachmentFile': str(attachment)})) + ')\n')
            interpreter.chmod(0o700)
            shared = subprocess.Popen([shutil.which('python3'), '-c', 'import time; time.sleep(30)'])
            try:
                script = "const {startReader}=await import(process.argv[1]); const reader=await startReader({root:process.argv[2]}); await reader.close(); await reader.close();"
                result = subprocess.run(
                    [NODE, '--input-type=module', '-e', script, SERVICE.as_uri(), str(temporary)],
                    env={**os.environ, 'PYTHON': str(interpreter)}, capture_output=True, timeout=8)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIsNone(shared.poll(), 'Closing presentation must not stop the shared service')
                self.assertFalse(attachment.exists())
            finally:
                shared.terminate()
                shared.wait(timeout=3)

    def test_browser_startup_failure_closes_only_the_view_and_attachment(self):
        with tempfile.TemporaryDirectory(prefix="terminal-service-exit-") as temporary:
            temporary = Path(temporary)
            opened, closed = temporary / "opened", temporary / "closed"
            control = temporary / "owner"
            control.write_text("running")
            interpreter = temporary / "fake-python"
            interpreter.write_text(
                "#!" + shutil.which("python3") + "\n"
                "import json,os\n"
                "print(json.dumps({'url':'http://127.0.0.1:23626/', 'attachmentFile':os.environ['FLOW_TEST_ATTACHMENT']}))\n"
            )
            interpreter.chmod(0o700)
            browser = temporary / "playwright.mjs"
            browser.write_text("""
import { writeFile } from 'node:fs/promises';
const page = { async goto() { throw new Error('Shared Reader unreachable'); } };
const context = {
  pages() { return [page]; }, on() {},
  async close() {
    await writeFile(process.env.FLOW_TEST_BROWSER_CLOSED, 'closed');
  },
};
export const chromium = { async launchPersistentContext() {
  await writeFile(process.env.FLOW_TEST_BROWSER_OPENED, 'opened');
  return context;
} };
""")
            environment = os.environ.copy()
            attachment = temporary / 'attachment.json'
            attachment.write_text('private')
            environment.update({
                "PYTHON": str(interpreter),
                "FLOW_TEST_BROWSER_OPENED": str(opened),
                "FLOW_TEST_BROWSER_CLOSED": str(closed),
                "FLOW_TEST_ATTACHMENT": str(attachment),
            })
            result = subprocess.run([
                NODE, str(TERMINAL), "--root", str(temporary),
                "--snapshot", str(temporary / "unused.png"),
                "--profile", str(temporary / "profile"),
                "--playwright-module", str(browser),
                "--control-file", str(control),
            ], env=environment, capture_output=True, timeout=5)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn(b"Shared Reader unreachable", result.stderr)
            self.assertTrue(opened.exists())
            self.assertTrue(closed.exists())
            self.assertFalse(control.exists())
            self.assertFalse(attachment.exists())

    def test_startup_failure_removes_editor_control_file(self):
        with tempfile.TemporaryDirectory(prefix="terminal-owner-") as temporary:
            control = Path(temporary) / "owner"
            control.write_text("owned")
            process = subprocess.run(
                [NODE, str(TERMINAL), "--control-file", str(control), "--root", temporary],
                stdin=subprocess.DEVNULL, capture_output=True, timeout=5,
            )
            self.assertNotEqual(process.returncode, 0)
            self.assertIn(b"native terminal pane", process.stderr)
            self.assertFalse(control.exists())


if __name__ == "__main__":
    unittest.main()
