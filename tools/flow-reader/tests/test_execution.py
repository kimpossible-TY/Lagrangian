"""Execution substitution cannot bypass server acceptance or candidate validation."""
from dataclasses import replace
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from flow_reader.compiler.build import compile_document_source_map, compile_project, document_request
from flow_reader.compiler.execution import CompileRequest, CompileResult, local_compile
from flow_reader.compiler.project import Project
from flow_reader.compiler.source_map import compile_source_map
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

    def test_rejected_browser_output_retries_native_before_server_acceptance(self):
        class BrowserExecutor:
            def __init__(inner):
                inner.requests = []

            def prepare_request(inner, request):
                return replace(request, system_fonts=False, timestamp=123)

            def __call__(inner, request):
                inner.requests.append(request)
                return replace(self.result(request), artifact=b'<a href="#missing">Browser</a>',
                               executor="browser")

            def fallback_after_rejection(inner, request):
                inner.requests.append(request)
                return replace(self.result(request), artifact=b'<p>Native</p>', executor="server")

        executor = BrowserExecutor()
        report = compile_project(self.project(executor), self.root / "output", map_sources=False)
        self.assertTrue(report["contentGatePassed"], report)
        self.assertEqual(report["missingLinkTargets"], [])
        self.assertEqual(len(executor.requests), 2)
        self.assertEqual(executor.requests[0], executor.requests[1])
        self.assertEqual(executor.requests[0].timestamp, 123)
        self.assertIn("Native", (self.root / "output" / "document.html").read_text())

    def test_browser_result_that_passes_gate_does_not_use_native_retry(self):
        class BrowserExecutor:
            def __call__(inner, request):
                return replace(self.result(request), executor="browser")

            def fallback_after_rejection(inner, request):
                raise AssertionError("accepted browser result must not retry")

        report = compile_project(self.project(BrowserExecutor()), self.root / "output", map_sources=False)
        self.assertTrue(report["contentGatePassed"], report)
        self.assertIn("Hello", (self.root / "output" / "document.html").read_text())

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

    def test_document_budget_is_bounded_separately_from_interactive_work_and_source_mapping(self):
        compile_project(self.project(self.result), self.root / "output")
        self.assertEqual([(r.purpose, r.timeout) for r in self.requests], [("document", 180), ("source-map", 180)])
        for arguments, purpose in (({"geometry": {}}, "graphics"), ({"canvases": {}}, "canvases"),
                                   ({"decorations": {}}, "decorations")):
            self.requests.clear()
            compile_project(self.project(self.result), self.root / "output", map_sources=False, **arguments)
            self.assertEqual([(r.purpose, r.timeout) for r in self.requests], [(purpose, 90)])

    def test_paged_candidate_retains_executor_and_original_packages(self):
        project = replace(self.project(self.result), semantic_canvases=True)
        self.assertTrue(paged_candidate_compiles(project, self.root / "candidate.pdf"))
        request, = self.requests
        self.assertEqual(request.target, "pdf")
        self.assertEqual(request.packages, self.packages)
        self.assertEqual(request.inputs, ())
        self.assertEqual(request.entry, self.root / "main.typ")

    def test_source_mapping_failure_keeps_base_output(self):
        for error in (OSError("compiler unavailable"), ValueError("invalid map"),
                      RecursionError("nested source"), subprocess.TimeoutExpired("compiler", 180)):
            with self.subTest(error=type(error).__name__):
                self.requests.clear()
                def execute(request):
                    if request.purpose == "source-map":
                        raise error
                    return self.result(request)
                report = compile_project(self.project(execute), self.root / "output")
                self.assertTrue(report["contentGatePassed"])
                self.assertEqual(report["sourceMapStatus"], "unavailable")

    def test_deferred_source_mapping_uses_prepared_document_inputs_and_overlay(self):
        class Executor:
            def __init__(inner):
                inner.prepared = []

            def prepare_request(inner, request):
                self.assertTrue((request.packages / "local/flow-reader/0.1.0/typst.toml").is_file())
                request = replace(request, system_fonts=False, timestamp=123 + len(inner.prepared))
                inner.prepared.append(request)
                return request

            def __call__(inner, request):
                return self.result(request)

        executor = Executor()
        project = replace(self.project(executor), semantic_canvases=True, fonts=(Path("fonts"),))
        output = self.root / "output"
        with patch("flow_reader.compiler.build.document_request", wraps=document_request) as overlay, \
                patch("flow_reader.compiler.build.compile_source_map", wraps=compile_source_map) as mapping:
            report = compile_project(project, output)
            self.assertEqual(overlay.call_count, 1)
            prepared, work = mapping.call_args.args[2], mapping.call_args.args[4]
            self.assertIs(prepared, executor.prepared[0])
            self.assertEqual(work, prepared.packages.parent)
            self.assertEqual(self.requests[0].packages, self.requests[1].packages)
            frozen = json.loads((output / "report.json").read_text())["compileInputs"]
            self.assertEqual(frozen, {"timestamp": 123, "systemFonts": False})
            compile_document_source_map(project, output, report["dependencies"],
                                        (output / "document.html").read_text(),
                                        timestamp=frozen["timestamp"], system_fonts=frozen["systemFonts"])
            self.assertEqual(overlay.call_count, 2)
        self.assertEqual(len(executor.prepared), 1)
        self.assertEqual([r.purpose for r in self.requests], ["document", "source-map", "source-map"])
        for request in self.requests:
            self.assertEqual(request.inputs, (("flow-reader", "true"), ("flow-native-labels", "true")))
            self.assertEqual(request.source, self.requests[0].source)
            self.assertEqual(request.fonts, (self.root / "fonts",))
            self.assertFalse(request.system_fonts)
            self.assertEqual(request.timestamp, 123)
            self.assertFalse(request.packages.exists())

    def test_source_mapping_overlay_preparation_failure_is_optional(self):
        with patch("flow_reader.compiler.build.prepare_packages", side_effect=OSError("missing packages")):
            result = compile_document_source_map(self.project(self.result), self.root / "output", (), "Hello")
        self.assertEqual(result, {"sourceMap": {}, "sourceMapStatus": "unavailable"})
        self.assertEqual(self.requests, [])

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
