"""Execution substitution cannot bypass server acceptance or candidate validation."""
from dataclasses import replace
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from flow_reader.compiler.build import compile_project
from flow_reader.compiler.execution import CompileRequest, CompileResult, local_compile
from flow_reader.compiler.project import Project
from flow_reader.services.source_highlight import paged_candidate_compiles


class ExecutionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        (self.root / "main.typ").write_text("Hello")
        self.packages = self.root / "packages"
        self.packages.mkdir()
        self.requests = []

    def result(self, request):
        self.requests.append(request)
        return CompileResult(0, "", b'<html><body><p>Hello</p></body></html>',
                             (str(request.root / "main.typ"),), 0.01)

    def project(self, execute):
        return Project(self.root, Path("main.typ"), self.packages, execute=execute)

    def test_server_rejects_successful_execution_with_lost_content(self):
        def execute(request):
            return replace(self.result(request), artifact=b'<a href="#missing">Hello</a>')
        report = compile_project(self.project(execute), self.root / "output")
        self.assertFalse(report["contentGatePassed"])
        self.assertEqual(report["missingLinkTargets"], ["missing"])
        self.assertEqual(len(self.requests), 1)

    def test_server_rejects_unhandled_warning_from_any_executor(self):
        def execute(request):
            return replace(self.result(request), stderr="warning: unknown content dropped\n")
        report = compile_project(self.project(execute), self.root / "output")
        self.assertFalse(report["contentGatePassed"])
        self.assertEqual(len(self.requests), 1)

    def test_source_carriers_use_injected_executor_without_leaking_to_source(self):
        report = compile_project(self.project(self.result), self.root / "output")
        self.assertTrue(report["contentGatePassed"])
        self.assertEqual(len(self.requests), 2)
        self.assertNotEqual(self.requests[0].root, self.requests[1].root)
        self.assertEqual(self.requests[0].inputs, self.requests[1].inputs)
        self.assertEqual((self.root / "main.typ").read_text(), "Hello")

    def test_paged_candidate_retains_executor_and_original_packages(self):
        project = replace(self.project(self.result), semantic_canvases=True)
        self.assertTrue(paged_candidate_compiles(project, self.root / "candidate.pdf"))
        request, = self.requests
        self.assertEqual(request.target, "pdf")
        self.assertEqual(request.packages, self.packages)
        self.assertEqual(request.inputs, ())
        self.assertEqual(request.entry, self.root / "main.typ")

    def test_source_mapping_failure_keeps_base_output(self):
        def execute(request):
            if self.requests:
                raise subprocess.TimeoutExpired("compiler", 60)
            return self.result(request)
        report = compile_project(self.project(execute), self.root / "output")
        self.assertTrue(report["contentGatePassed"])
        self.assertEqual(report["sourceMapStatus"], "unavailable")

    @unittest.skipUnless(shutil.which("typst"), "Typst required")
    def test_local_executor_compiles_html_and_pdf_with_dependencies(self):
        for target in ("html", "pdf"):
            with self.subTest(target=target):
                result = local_compile(CompileRequest(
                    "typst", self.root, self.packages, target, entry=self.root / "main.typ"))
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn(self.root / "main.typ",
                              {(self.root / path).resolve() for path in result.dependencies})
                self.assertTrue(result.artifact)
                self.assertGreater(result.elapsed_seconds, 0)
                if target == "pdf":
                    self.assertTrue(result.artifact.startswith(b"%PDF"))
                else:
                    self.assertIn(b"Hello", result.artifact)

    @unittest.skipUnless(shutil.which("typst"), "Typst required")
    def test_local_compile_failure_has_no_publishable_artifact(self):
        result = local_compile(CompileRequest(
            "typst", self.root, self.packages, "html", source="#unknown-function()"))
        self.assertNotEqual(result.returncode, 0)
        self.assertIsNone(result.artifact)
        self.assertIn("error:", result.stderr)

    @unittest.skipUnless(shutil.which("typst"), "Typst required")
    def test_portable_timestamp_and_explicit_single_font_file(self):
        from flow_reader.compiler.execution import font_arguments
        font = self.root / "chosen.ttf"
        font.write_bytes(b"fixture")
        args = font_arguments((font,), self.root)
        directory = Path(args[1])
        self.assertEqual(list(directory.iterdir()), [directory / font.name])
        self.assertEqual((directory / font.name).resolve(), font)
        result = local_compile(CompileRequest("typst", self.root, self.packages, "html",
                              source="#datetime.today().display(\"[year]-[month]-[day]\")",
                              system_fonts=False, timestamp=0))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(b"1970-01-01", result.artifact)


if __name__ == "__main__":
    unittest.main()
