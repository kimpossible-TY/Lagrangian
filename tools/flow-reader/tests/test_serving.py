"""Exercise reader serving across an actual successful and failed compilation."""

from http.server import ThreadingHTTPServer
import json
import os
from pathlib import Path
import shutil
import sys
import tempfile
import threading
import unittest
from urllib.error import HTTPError
from urllib.request import Request, urlopen
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from build import Project
from serve import ReaderState, handler_for, source_signature


class ReaderServingTests(unittest.TestCase):
    def test_only_compiler_dependencies_are_watched_and_import_edits_update_revision(self):
        compiler = os.environ.get("FLOW_READER_TYPST") or shutil.which("typst")
        packages = os.environ.get("FLOW_READER_PACKAGES")
        if not compiler or not packages:
            self.skipTest("Set FLOW_READER_PACKAGES and optionally FLOW_READER_TYPST")
        with tempfile.TemporaryDirectory() as temporary:
            work = Path(temporary)
            source = work / "source"
            source.mkdir()
            (source / "main.typ").write_text('#include "part.typ"')
            part = source / "part.typ"
            part.write_text("Before the saved edit.")
            unrelated = source / "unrelated-video-cache"
            unrelated.mkdir()
            (unrelated / "data.txt").write_text("Unrelated data")
            project = Project(source, Path("main.typ"), Path(packages), compiler=compiler)
            state = ReaderState(project, work / "output", "https://example.test/paged/", False)
            with patch.object(Path, "rglob", side_effect=AssertionError("Do not scan the project recursively")):
                state.compile()
                self.assertTrue(state.report["contentGatePassed"], state.report)
                self.assertIn(str(part.resolve()), state.dependencies)
                self.assertFalse(any("/compile-" in path for path in state.dependencies))
                before = state.source_stamp
                revision = state.revision
                (unrelated / "data.txt").write_text("Unrelated change")
                self.assertEqual(source_signature(project, state.dependencies), before)
                part.write_text("After the saved edit.")
                self.assertNotEqual(source_signature(project, state.dependencies), before)
                state.compile()
                self.assertNotEqual(state.revision, revision)
                self.assertIn(b"After the saved edit.", state.document)

    def test_graphics_cache_and_failed_save_use_the_published_revision(self):
        compiler = os.environ.get("FLOW_READER_TYPST") or shutil.which("typst")
        packages = os.environ.get("FLOW_READER_PACKAGES")
        if not compiler or not packages:
            self.skipTest("Set FLOW_READER_PACKAGES and optionally FLOW_READER_TYPST")
        from test_graphics import geometry
        with tempfile.TemporaryDirectory() as temporary:
            work = Path(temporary)
            source = work / "source"
            source.mkdir()
            shutil.copyfile(ROOT / "tests/fixtures/graphics.typ", source / "main.typ")
            state = ReaderState(Project(source, Path("main.typ"), Path(packages), compiler=compiler),
                                work / "output", "https://example.test/paged/", False)
            state.compile()
            revision, stamp = state.revision, state.source_stamp
            self.assertIsNotNone(revision, state.report)
            server = ThreadingHTTPServer(("127.0.0.1", 0), handler_for(state))
            worker = threading.Thread(target=server.serve_forever, daemon=True)
            worker.start()
            url = f"http://127.0.0.1:{server.server_port}/api/graphics"
            def request(graphs, rev=revision):
                return Request(url, json.dumps({"revision": rev, "graphs": graphs}).encode(),
                               {"Content-Type": "application/json"})
            try:
                with urlopen(request(geometry())) as response:
                    rendered = json.load(response)
                self.assertEqual(set(rendered["graphics"]), {"graphic-1"})
                with patch("serve.compile_project", side_effect=AssertionError("Unexpected recompilation")):
                    with urlopen(request(geometry())) as response:
                        self.assertEqual(json.load(response), rendered)
                previous_document = state.document
                entry = source / "main.typ"
                entry.write_text(entry.read_text().replace("(0, -0.5)", "(0, -0.9)"))
                state.compile()
                self.assertNotEqual(state.revision, revision)
                self.assertEqual(state.document, previous_document)
                # Placeholder HTML is unchanged; dynamic drawing changes still
                # invalidate the public revision and its geometry cache.
                revision, stamp = state.revision, state.source_stamp
                (source / "main.typ").write_text("#does-not-exist()")
                state.compile()
                self.assertEqual(state.source_stamp, stamp)
                self.assertEqual(state.revision, revision)
                with self.assertRaises(HTTPError) as changed:
                    urlopen(request(geometry(280), revision))
                self.assertEqual(changed.exception.code, 409)
                changed.exception.close()
                with self.assertRaises(HTTPError) as stale:
                    urlopen(request(geometry(), "outdated"))
                self.assertEqual(stale.exception.code, 409)
                stale.exception.close()
            finally:
                server.shutdown()
                server.server_close()
                worker.join()

    def test_compile_failure_keeps_the_previous_document_available(self):
        compiler = os.environ.get("FLOW_READER_TYPST") or shutil.which("typst")
        packages = os.environ.get("FLOW_READER_PACKAGES")
        if not compiler or not packages:
            self.skipTest("Set FLOW_READER_PACKAGES and optionally FLOW_READER_TYPST")
        with tempfile.TemporaryDirectory() as temporary:
            work = Path(temporary)
            source = work / "source"
            source.mkdir()
            shutil.copyfile(ROOT / "tests/fixtures/main.typ", source / "main.typ")
            project = Project(source, Path("main.typ"), Path(packages), compiler=compiler)
            state = ReaderState(project, work / "output", "https://example.test/paged/", False)
            state.compile()
            self.assertEqual(state.report["exitCode"], 0, state.report)
            self.assertTrue(state.report["contentGatePassed"], state.report)
            revision = state.revision
            server = ThreadingHTTPServer(("127.0.0.1", 0), handler_for(state))
            worker = threading.Thread(target=server.serve_forever, daemon=True)
            worker.start()
            base = f"http://127.0.0.1:{server.server_port}"
            try:
                original = urlopen(base + "/document.html").read()
                manifest = json.load(urlopen(base + "/api/manifest"))
                self.assertEqual(manifest["revision"], revision)
                section = manifest["sections"][0]["id"]
                with urlopen(base + "/api/sections/" + section) as response:
                    section_content = response.read()
                (source / "main.typ").write_text("#this-function-does-not-exist()")
                state.compile()
                public = json.load(urlopen(base + "/api/state"))
                self.assertEqual(public["exitCode"], 1)
                self.assertEqual(public["revision"], revision)
                self.assertEqual(urlopen(base + "/document.html").read(), original)
                self.assertEqual(json.load(urlopen(base + "/api/manifest")), manifest)
                with urlopen(base + "/api/sections/" + section) as response:
                    self.assertEqual(response.read(), section_content)
                self.assertTrue(json.load(urlopen(base + "/health"))["ready"])
                with self.assertRaises(HTTPError) as stale:
                    urlopen(base + "/document.html?revision=outdated")
                self.assertEqual(stale.exception.code, 409)
                stale.exception.close()
            finally:
                server.shutdown()
                server.server_close()
                worker.join()


if __name__ == "__main__":
    unittest.main()
