"""Real-engine checks for a desktop control relay on the reader's forwarded port."""
import importlib.util
import json
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import time
import unittest
import urllib.request
import uuid

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location(
    "preview_wire", ROOT / "tests/perf/incremental-performance/preview_demand.py")
wire = importlib.util.module_from_spec(spec)
spec.loader.exec_module(wire)


@unittest.skipUnless(os.environ.get("FLOW_TEST_ENGINE"), "Set FLOW_TEST_ENGINE for editor relay checks")
class EditorRelay(unittest.TestCase):
    def test_same_port_navigation_is_isolated_bounded_and_independent_of_rendering(self):
        with tempfile.TemporaryDirectory(prefix="flow-editor-relay-") as directory:
            root = Path(directory).resolve()
            document, focus, log_path = root / "main.typ", root / "focus.json", root / "engine.log"
            wire.write_document(document, 1)
            document.write_text(document.read_text() + "\n#pagebreak()\n= Second destination\n")
            line = document.read_text().splitlines().index("= Second destination")
            with socket.socket() as reservation:
                reservation.bind(("127.0.0.1", 0))
                port = reservation.getsockname()[1]
            env = dict(os.environ, TINYMIST_PREVIEW_FOCUS_FILE=str(focus))
            env.pop("TINYMIST_PREVIEW_CHANGE_FILE", None)
            sockets = []
            with log_path.open("wb") as log:
                process = subprocess.Popen([
                    env["FLOW_TEST_ENGINE"], "--log-filter", "tinymist_project::compiler=info",
                    "preview", str(document), "--root", str(root), "--follow-system-theme",
                    "--no-open", f"--data-plane-host=127.0.0.1:{port}",
                    "--control-plane-host=127.0.0.1:0"], env=env, stdout=log, stderr=log)
                try:
                    deadline = time.monotonic() + 30
                    while True:
                        try:
                            urllib.request.urlopen(f"http://127.0.0.1:{port}/", timeout=1).close()
                            break
                        except OSError:
                            if time.monotonic() > deadline or process.poll() is not None:
                                self.fail("Fixture preview did not start")
                            time.sleep(0.1)

                    def connect(route, **kwargs):
                        ws = wire.WebSocket(port, route, **kwargs)
                        sockets.append(ws)
                        return ws

                    def receive(ws, prefix=None):
                        deadline = time.monotonic() + 10
                        while time.monotonic() < deadline:
                            message = ws.receive(1)
                            if message and (prefix is None or message[1].startswith(prefix)):
                                return message[1]
                        self.fail("Missing editor relay response")

                    def json_message(ws):
                        return json.loads(receive(ws))

                    renderer = connect("/_theme/light")
                    renderer.send("current")
                    revision = receive(renderer, b"focus-revision,").split(b",", 1)[1].decode()
                    receive(renderer, (b"new,", b"diff-v1,"))
                    channel, other = str(uuid.uuid4()), str(uuid.uuid4())
                    # Host registration requires a direct loopback request without a browser Origin.
                    for kwargs in ({}, {"origin": None, "host": "remote.proxy.example"}):
                        with self.assertRaises(RuntimeError):
                            connect(f"/_editor/{channel}", **kwargs)
                    host = connect(f"/_editor/{channel}", origin=None)
                    self.assertEqual(json_message(host), {"event": "editorReady"})
                    with self.assertRaises(RuntimeError):
                        connect(f"/_editor/{channel}", origin=None)
                    with self.assertRaises(RuntimeError):
                        connect(f"/editor/{other}")
                    with self.assertRaises(RuntimeError):
                        connect(f"/editor/{channel}", origin="https://unrelated.example")
                    reader = connect(f"/editor/{channel}?forwarding=preserved")
                    self.assertEqual(json_message(host), {"event": "editorConnected", "connected": True})
                    other_host = connect(f"/_editor/{other}", origin=None)
                    self.assertEqual(json_message(other_host), {"event": "editorReady"})
                    other_reader = connect(f"/editor/{other}")
                    self.assertTrue(json_message(other_host)["connected"])
                    before = wire.quiet(log_path, 10, 0.2)

                    renderer.send("src-editor " + json.dumps({"page_no": 1, "x": 20, "y": 20, "revision": revision}))
                    jump = json.loads(receive(renderer, b"editor,").split(b",", 1)[1])
                    self.assertEqual(jump["event"], "editorScrollTo")
                    jump.pop("revision")
                    reader.send(json.dumps(jump))
                    self.assertEqual(json_message(host), jump)
                    self.assertIsNone(other_host.receive(0.2))
                    location = {"event": "panelScrollTo", "filepath": str(document), "line": line, "character": 4}
                    host.send(json.dumps(location))
                    self.assertEqual(json_message(reader), location)
                    self.assertIsNone(other_reader.receive(0.2))
                    renderer.send("editor " + json.dumps(dict(location, revision=revision)))
                    positions = receive(renderer, b"jump,").split(b",", 1)[1].decode()
                    self.assertTrue(any(p.split()[0] == "2" for p in positions.split(",")))
                    self.assertFalse(focus.exists())
                    for sender, receiver in ((host, reader), (reader, host)):
                        sender.send('{"event":"syncMemoryFiles","files":{}}')
                        sender.send("bad JSON")
                        self.assertIsNone(receiver.receive(0.2))
                    self.assertEqual(wire.quiet(log_path, 10, 0.2), before)
                    reader.send("x" * 9000)
                    with self.assertRaises(EOFError):
                        reader.receive(3)
                    self.assertFalse(json_message(host)["connected"])
                    host.close()
                    deadline = time.monotonic() + 5
                    while True:
                        try:
                            replacement = connect(f"/_editor/{channel}", origin=None)
                            break
                        except RuntimeError:
                            if time.monotonic() >= deadline:
                                raise
                            time.sleep(0.05)
                    self.assertEqual(json_message(replacement), {"event": "editorReady"})
                    replacement_reader = connect(f"/editor/{channel}")
                    self.assertTrue(json_message(replacement)["connected"])
                    replacement.close()
                    with self.assertRaises(EOFError):
                        replacement_reader.receive(3)
                    renderer.send("ping")
                    self.assertEqual(receive(renderer, b"pong,"), b"pong,")
                    self.assertIsNone(process.poll())
                finally:
                    for ws in sockets:
                        ws.close()
                    process.terminate()
                    try:
                        process.wait(timeout=10)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait()
