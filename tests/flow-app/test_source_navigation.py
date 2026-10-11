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

    def test_upstream_bidirectional_mapping_is_local_in_both_themes(self):
        with tempfile.TemporaryDirectory(prefix="flow-bidirectional-") as directory:
            root = Path(directory).resolve()
            document, focus = root / "main.typ", root / "focus.json"
            wire.write_document(document, 1)
            document.write_text(document.read_text() + "\n#pagebreak()\n= Second destination\nRendered component\n")
            destination_line = document.read_text().splitlines().index("= Second destination")
            with socket.socket() as reservation:
                reservation.bind(("127.0.0.1", 0))
                port = reservation.getsockname()[1]
            env = dict(os.environ, TINYMIST_PREVIEW_FOCUS_FILE=str(focus))
            env.pop("TINYMIST_PREVIEW_CHANGE_FILE", None)
            log_path = root / "engine.log"
            with log_path.open("wb") as log:
                process = subprocess.Popen([
                    env["FLOW_TEST_ENGINE"], "--log-filter", "tinymist_project::compiler=info",
                    "preview", str(document), "--root", str(root), "--follow-system-theme",
                    "--no-open", f"--data-plane-host=127.0.0.1:{port}",
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

                    def wait_for(viewer, prefix, timeout=10):
                        limit = time.monotonic() + timeout
                        while time.monotonic() < limit:
                            message = viewer.receive(1)
                            if message and message[1].startswith(prefix):
                                return message[1].split(b",", 1)[1]
                        self.fail(f"Missing {prefix!r} response")

                    def open_viewer(theme):
                        viewer = wire.WebSocket(port, f"/_theme/{theme}")
                        viewers.append(viewer)
                        viewer.send("current")
                        revision = wait_for(viewer, b"focus-revision,").decode()
                        wait_for(viewer, (b"new,", b"diff-v1,"))
                        return viewer, revision

                    def assert_no_navigation(viewer):
                        while (message := viewer.receive(0.15)) is not None:
                            self.assertFalse(message[1].startswith((b"editor,", b"jump,", b"focus,")))

                    for theme in ("light", "dark"):
                        desktop, revision = open_viewer(theme)
                        phone, _ = open_viewer(theme)
                        request = {"page_no": 1, "x": 20, "y": 20, "revision": revision}
                        # Establish a phone/Codex selection before desktop navigation.
                        phone.send("src-point " + json.dumps(request))
                        self.assertEqual(json.loads(wait_for(phone, b"focus,"))["status"], "selected")
                        saved_focus = focus.read_bytes()
                        before = wire.quiet(log_path, 10, 0.2)
                        assert_no_navigation(desktop)
                        desktop.send("src-editor " + json.dumps(request))
                        jump = json.loads(wait_for(desktop, b"editor,"))
                        self.assertEqual(jump["event"], "editorScrollTo")
                        self.assertEqual(jump["filepath"], str(document))
                        self.assertEqual(jump["revision"], revision)
                        self.assertLessEqual(jump["start"], jump["end"])
                        self.assertEqual(jump["start"][0], 4)
                        self.assertEqual(focus.read_bytes(), saved_focus)
                        assert_no_navigation(phone)

                        location = {"event": "panelScrollTo", "filepath": str(document),
                                    "line": destination_line, "character": 4, "revision": revision}
                        desktop.send("editor " + json.dumps(location))
                        positions = wait_for(desktop, b"jump,").decode().split(",")
                        self.assertTrue(any(int(p.split()[0]) == 2 for p in positions))
                        assert_no_navigation(phone)
                        self.assertEqual(focus.read_bytes(), saved_focus)

                        desktop.send("src-editor " + json.dumps(dict(request, revision="stale")))
                        self.assertEqual(json.loads(wait_for(desktop, b"editor,"))["status"], "stale")
                        desktop.send("editor " + json.dumps(dict(location, revision="stale")))
                        desktop.send("editor " + json.dumps({"event": "syncMemoryFiles",
                                     "revision": revision, "files": {str(document): "broken"}}))
                        assert_no_navigation(desktop)
                        self.assertEqual(wire.quiet(log_path, 10, 0.2), before)
                        self.assertIsNone(process.poll())
                        desktop.close()
                        phone.close()
                        viewers.clear()
                finally:
                    for viewer in viewers:
                        viewer.close()
                    process.terminate()
                    try:
                        process.wait(timeout=10)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait()
