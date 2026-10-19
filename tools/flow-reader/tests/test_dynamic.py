"""Incremental paint must match cold compilation and never reuse stale output."""

import os
from pathlib import Path
import shutil
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from build import Project, compile_project
from decorations import extract_decorations
from dynamic import DynamicCompiler
from serve import ReaderState, RevisionChanged


class DynamicGateTests(unittest.TestCase):
    def test_unknown_warnings_errors_and_lost_content_are_rejected(self):
        for document, log in [('<html></html>', 'file.typ:2:3: warning: unsupported layout'),
                              ('<html></html>', 'error: compilation failed'),
                              ('<a href="#missing">gone</a>', '')]:
            with self.subTest(document=document, log=log), self.assertRaises(ValueError):
                DynamicCompiler.validate(document, log)


class DynamicCompilerTests(unittest.TestCase):
    def setUp(self):
        packages = os.environ.get("FLOW_READER_PACKAGES")
        compiler = os.environ.get("FLOW_READER_TYPST") or shutil.which("typst")
        if not packages or not compiler:
            self.skipTest("Set FLOW_READER_PACKAGES and optionally FLOW_READER_TYPST")
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.work = Path(self.temporary.name)
        self.source = self.work / "source"
        self.source.mkdir()
        self.output = self.work / "output"
        self.output.mkdir()
        self.entry = self.source / "main.typ"
        shutil.copyfile(ROOT / "tests/fixtures/decorations.typ", self.entry)
        self.project = Project(self.source, Path("main.typ"), Path(packages), compiler=compiler)

    def request(self, width, ink="#242c34"):
        return {f"decoration-{i}": {"fontSize": 24, "ink": ink, "fragments": [
            {"width": width, "height": 25}, {"width": 40, "height": 20}]} for i in range(1, 7)}

    def test_consecutive_geometry_theme_and_fragment_changes_match_cold_output(self):
        worker = DynamicCompiler(self.project, self.output)
        self.addCleanup(worker.close)
        worker.compile()
        source = self.entry.read_bytes()
        process = None
        for width, ink in [(100, "#242c34"), (130, "#ffffff"), (80, "#abcdef")]:
            request = self.request(width, ink)
            # Issue the next watch request immediately after completion to cover
            # the initial dependency registration gap as well as normal reuse.
            actual = worker.compile(decorations=request)
            if process is not None:
                self.assertIs(worker.process, process)
            process = worker.process
            report = compile_project(self.project, self.work / "cold", decorations=request)
            self.assertTrue(report["contentGatePassed"])
            expected = (self.work / "cold/document.html").read_text()
            self.assertEqual(extract_decorations(actual, request, "same"),
                             extract_decorations(expected, request, "same"))
        self.assertEqual(self.entry.read_bytes(), source)
        worker.close()
        self.assertIsNotNone(process.poll())
        self.assertFalse(worker.work.exists())

    def test_source_revision_dead_worker_fallback_and_recovery(self):
        state = ReaderState(self.project, self.output, "https://example.test", False)
        self.addCleanup(state.close)
        state.compile()
        revision = state.revision
        first = state.render_dynamic(revision, self.request(100), "decorations")
        worker = state.dynamic_compiler
        worker.process.kill()
        worker.process.wait()
        with patch("serve.compile_project", wraps=compile_project) as cold:
            fallback = state.render_dynamic(revision, self.request(110), "decorations")
            self.assertEqual(cold.call_count, 1)
            self.assertEqual(fallback["revision"], revision)
        self.assertIsNone(state.dynamic_compiler)
        state.render_dynamic(revision, self.request(120), "decorations")
        self.assertIsNotNone(state.dynamic_compiler)
        self.entry.write_text("#not-a-function()")
        state.compile()
        self.assertEqual(state.render_dynamic(revision, self.request(100), "decorations"), first)
        with self.assertRaises(RevisionChanged):
            state.render_dynamic(revision, self.request(130), "decorations")
        shutil.copyfile(ROOT / "tests/fixtures/decorations.typ", self.entry)
        self.entry.write_text(self.entry.read_text() + "\nChanged prose.\n")
        state.compile()
        self.assertNotEqual(state.revision, revision)
        state.render_dynamic(state.revision, self.request(130), "decorations")
        self.assertIsNot(state.dynamic_compiler, worker)
        with self.assertRaises(RevisionChanged):
            state.render_dynamic(revision, self.request(100), "decorations")


if __name__ == "__main__":
    unittest.main()
