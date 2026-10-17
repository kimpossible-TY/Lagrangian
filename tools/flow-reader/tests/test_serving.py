"""Exercise reader serving across an actual successful and failed compilation."""

from http.server import ThreadingHTTPServer
import json
import gzip
import hashlib
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
    def test_public_state_reports_the_actual_native_canvas_option(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "main.typ").write_text("A document")
            for enabled in (False, True):
                project = Project(root, Path("main.typ"), root / "packages", semantic_canvases=enabled)
                state = ReaderState(project, root / "output", "https://example.test/paged/", False)
                self.assertIs(state.public()["semanticCanvases"], enabled)

    def test_directory_metadata_does_not_change_inputs_but_a_new_import_does(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "main.typ").write_text('#include "missing.typ"')
            project = Project(root, Path("main.typ"), root / "packages", compiler="missing-compiler")
            before = source_signature(project)
            stat = root.stat()
            os.utime(root, ns=(stat.st_atime_ns, stat.st_mtime_ns + 1000000000))
            self.assertEqual(source_signature(project), before)
            (root / ".DS_Store").write_bytes(b"Finder metadata")
            self.assertEqual(source_signature(project), before)
            (root / "missing.typ").write_text("Now available")
            self.assertNotEqual(source_signature(project), before)

    def test_local_math_assets_match_the_manifest_and_use_versioned_caching(self):
        server = ThreadingHTTPServer(("127.0.0.1", 0), handler_for(None))
        worker = threading.Thread(target=server.serve_forever, daemon=True)
        worker.start()
        base = f"http://127.0.0.1:{server.server_port}"
        vendor = "/vendor/mathjax-4.1.3/"
        try:
            manifest = json.load(urlopen(base + vendor + "manifest.json"))
            for name, digest in manifest["files"].items():
                with self.subTest(asset=name), urlopen(base + vendor + name) as response:
                    self.assertEqual(hashlib.sha256(response.read()).hexdigest(), digest)
                    self.assertIn("immutable", response.headers["Cache-Control"])
                    if name.endswith(".woff2"):
                        self.assertEqual(response.headers["Content-Type"], "font/woff2")
            with urlopen(Request(base + vendor + "mathjax/mml-chtml.js",
                                 headers={"Accept-Encoding": "gzip"})) as response:
                self.assertEqual(response.headers["Content-Encoding"], "gzip")
                self.assertEqual(hashlib.sha256(gzip.decompress(response.read())).hexdigest(),
                                 manifest["files"]["mathjax/mml-chtml.js"])
            for name in ("language.js", "math-renderer.js", "math-frames.js", "mathjax-loader.js", "math-layout.js", "connector-routing.js", "canvas-labels.js", "tables.js"):
                with urlopen(base + "/" + name) as response:
                    self.assertIn("javascript", response.headers["Content-Type"])
                    self.assertEqual(response.headers["Cache-Control"], "no-store")
            for path in ("missing.js", "../README.md", "%2e%2e/README.md"):
                with self.assertRaises(HTTPError) as missing:
                    urlopen(base + vendor + path)
                self.assertEqual(missing.exception.code, 404)
                missing.exception.close()
        finally:
            server.shutdown()
            server.server_close()
            worker.join()

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
            stat = source.stat()
            os.utime(source, ns=(stat.st_atime_ns, stat.st_mtime_ns + 1000000000))
            self.assertEqual(source_signature(project=state.project, dependencies=state.accepted_dependencies), stamp)
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

    def test_graphics_reuse_components_across_batches_and_compile_only_changed_layouts(self):
        compiler = os.environ.get("FLOW_READER_TYPST") or shutil.which("typst")
        packages = os.environ.get("FLOW_READER_PACKAGES")
        if not compiler or not packages:
            self.skipTest("Set FLOW_READER_PACKAGES and optionally FLOW_READER_TYPST")
        from build import compile_project
        from figures import geometry_identity
        from graphics import extract_graphics
        from serve import RevisionChanged
        from test_graphics import geometry
        with tempfile.TemporaryDirectory() as temporary:
            work = Path(temporary)
            source = work / "source"
            source.mkdir()
            fixture = (ROOT / "tests/fixtures/graphics.typ").read_text()
            second = fixture[fixture.index("$"):].replace("left", "left-two").replace("right", "right-two")
            entry = source / "main.typ"
            entry.write_text(fixture + "\n" + second)
            state = ReaderState(Project(source, Path("main.typ"), Path(packages), compiler=compiler),
                                work / "output", "https://example.test/paged/", False)
            state.compile()
            revision = state.revision
            self.assertIsNotNone(revision, state.report)
            other = geometry()["graphic-1"]
            other["markers"] = {key + "-two": value for key, value in other["markers"].items()}
            batch = geometry() | {"graphic-2": other}
            rendered = state.render_graphics(revision, batch)
            with patch("serve.compile_project", side_effect=AssertionError("Unexpected recompilation")):
                for identifier, layout in batch.items():
                    reused = state.render_graphics(revision, {identifier: layout})
                    self.assertEqual(reused["graphics"], {identifier: rendered["graphics"][identifier]})
            changed = geometry(220) | {"graphic-2": other}
            with patch("serve.compile_project", wraps=compile_project) as compile_spy:
                updated = state.render_graphics(revision, changed)
            self.assertEqual(compile_spy.call_count, 1)
            self.assertEqual(compile_spy.call_args.kwargs["geometry"], {"graphic-1": changed["graphic-1"]})
            self.assertEqual(updated["graphics"]["graphic-2"], rendered["graphics"]["graphic-2"])
            fresh = work / "fresh"
            report = compile_project(state.project, fresh, geometry={"graphic-2": other})
            self.assertTrue(report["contentGatePassed"], report)
            expected = extract_graphics((fresh / "document.html").read_text(), {"graphic-2": other}, "fresh")
            self.assertEqual(geometry_identity(expected["graphic-2"]),
                             geometry_identity(rendered["graphics"]["graphic-2"]))
            entry.write_text("#does-not-exist()")
            state.compile()
            self.assertEqual(state.revision, revision)
            with patch("serve.compile_project", side_effect=AssertionError("Unexpected recompilation")):
                self.assertEqual(state.render_graphics(revision, {"graphic-2": other})["graphics"],
                                 {"graphic-2": rendered["graphics"]["graphic-2"]})
            with self.assertRaises(RevisionChanged):
                state.render_graphics(revision, {"graphic-2": other | {"width": 450}})
            entry.write_text(fixture + "\n" + second.replace("(0, -0.5)", "(0, -0.9)"))
            state.compile()
            self.assertNotEqual(state.revision, revision)
            self.assertFalse(state.component_cache)

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
