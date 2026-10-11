"""Optional real-engine checks for viewer-local source coordinates."""
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

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location(
    "preview_wire", ROOT / "tests/perf/incremental-performance/preview_demand.py")
wire = importlib.util.module_from_spec(spec)
spec.loader.exec_module(wire)


@unittest.skipUnless(os.environ.get("FLOW_TEST_ENGINE"), "Set FLOW_TEST_ENGINE for source navigation checks")
class SourceNavigation(unittest.TestCase):
    def test_hit_coordinates_are_viewer_local_and_revision_checked(self):
        with tempfile.TemporaryDirectory(prefix="flow-source-navigation-") as directory:
            root = Path(directory).resolve()
            document, focus = root / "main.typ", root / "focus.json"
            wire.write_document(document, 1)
            with socket.socket() as reservation:
                reservation.bind(("127.0.0.1", 0))
                port = reservation.getsockname()[1]
            env = dict(os.environ, TINYMIST_PREVIEW_FOCUS_FILE=str(focus))
            env.pop("TINYMIST_PREVIEW_CHANGE_FILE", None)
            with (root / "engine.log").open("wb") as log:
                process = subprocess.Popen([
                    env["FLOW_TEST_ENGINE"], "preview", str(document), "--root", str(root),
                    "--follow-system-theme", "--no-open", f"--data-plane-host=127.0.0.1:{port}",
                    "--control-plane-host=127.0.0.1:0"], env=env, stdout=log, stderr=log)
                viewers = []
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
                    first = wire.WebSocket(port, "/_theme/light")
                    viewers.append(first)
                    first.send("current")
                    revision = None
                    deadline = time.monotonic() + 30
                    while time.monotonic() < deadline:
                        message = first.receive(5)
                        if not message:
                            continue
                        payload = message[1]
                        if payload.startswith(b"focus-revision,"):
                            revision = payload.split(b",", 1)[1].decode()
                        if payload.startswith((b"new,", b"diff-v1,")) and revision:
                            break
                    self.assertIsNotNone(revision)
                    second = wire.WebSocket(port, "/_theme/light")
                    viewers.append(second)
                    request = {"page_no": 1, "x": 20, "y": 20, "revision": revision}
                    first.send("src-point " + json.dumps(request))
                    def response():
                        limit = time.monotonic() + 10
                        while time.monotonic() < limit:
                            message = first.receive(2)
                            if message and message[1].startswith(b"focus,"):
                                return json.loads(message[1].split(b",", 1)[1])
                        self.fail("Missing hit-test response")
                    result = response()
                    self.assertEqual(result["status"], "selected")
                    source = json.loads(focus.read_text())["source"]
                    self.assertEqual({key: result[key] for key in ("filepath", "line", "column")},
                                     {key: source[key] for key in ("filepath", "line", "column")})
                    self.assertGreaterEqual(result["column"], 1)
                    self.assertNotIn("excerpt", result)
                    while (message := second.receive(0.2)) is not None:
                        self.assertFalse(message[1].startswith(b"focus,"))
                    first.send("src-point " + json.dumps(dict(request, revision="stale")))
                    stale = response()
                    self.assertEqual(stale["status"], "stale")
                    self.assertIsNone(stale["filepath"])
                    self.assertIsNone(stale["column"])
                finally:
                    for viewer in viewers:
                        viewer.close()
                    process.terminate()
                    try:
                        process.wait(timeout=10)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait()
