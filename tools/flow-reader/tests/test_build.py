"""Reader content gates and real Typst adapter integration."""

import importlib.util
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
spec = importlib.util.spec_from_file_location("flow_reader_build", ROOT / "build.py")
build = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = build
spec.loader.exec_module(build)


class ContentAuditTests(unittest.TestCase):
    def audit(self, text):
        audit = build.ContentAudit()
        audit.feed(text)
        return audit.report()

    def test_valid_local_references_and_annotations(self):
        report = self.audit('<p id="eq one">Equation</p><a href="#eq%20one">1</a>'
                            '<mrow data-flow-mark="term">x</mrow>'
                            '<span data-flow-targets=\'["term"]\'>Explanation</span>')
        self.assertTrue(report["contentGatePassed"])

    def test_successful_html_with_missing_content_is_not_promotable(self):
        report = self.audit('<a href="#missing">1</a><p id="dup"></p><p id="dup"></p>'
                            '<span data-flow-targets=\'["lost"]\' '
                            'data-flow-diagnostic="graphical-annotation"></span>')
        self.assertFalse(report["contentGatePassed"])
        self.assertEqual(report["missingLinkTargets"], ["missing"])
        self.assertEqual(report["unresolvedAnnotationTargets"], ["lost"])
        self.assertEqual(report["duplicateIds"], ["dup"])

    def test_svg_definitions_are_scoped_but_document_links_are_not(self):
        svg = ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20">'
               '<defs><path id="glyph" d="M0 0L1 1"/></defs>'
               '<use href="#glyph" clip-path="url(#glyph)"/>'
               '<a href="#equation">Reference</a></svg>')
        source = '<p id="equation">Equation</p>' + svg + svg
        result = build.namespace_svg_ids(source)
        report = self.audit(result)
        self.assertTrue(report["contentGatePassed"], report)
        self.assertIn('viewBox="0 0 20 20"', result)
        self.assertIn('href="#flow-svg-1-glyph"', result)
        self.assertEqual(result.count('href="#equation"'), 2)

    def test_footnotes_inside_math_use_a_token_integration_point(self):
        source = ('<math><mrow><mi>x</mi><sup><a href="#note">1</a></sup>'
                  '<mfrac><mi>a</mi><mi>b</mi></mfrac></mrow></math>')
        result = build.normalize_math_html(source)
        self.assertIn('<mtext><sup><a href="#note">1</a></sup></mtext>', result)
        self.assertIn('<mfrac><mi>a</mi><mi>b</mi></mfrac>', result)
        self.assertEqual(build.normalize_math_html(result), result)

    def test_block_content_cannot_silently_escape_math_namespace(self):
        with self.assertRaisesRegex(ValueError, "Non-phrasing"):
            build.normalize_math_html('<math><mrow><div>note</div></mrow></math>')


class PackageOverlayTests(unittest.TestCase):
    def test_does_not_replace_the_installed_package(self):
        with tempfile.TemporaryDirectory() as temp:
            base = Path(temp)
            original = base / "installed"
            package = original / "local/math-blocks/0.2.0"
            package.mkdir(parents=True)
            (package / "typst.toml").write_text("original manifest")
            (package / "lib.typ").write_text("original source")
            build.prepare_packages(original, base / "overlay")
            overlay = base / "overlay/local/math-blocks/0.2.0/lib.typ"
            self.assertFalse(overlay.is_symlink())
            self.assertIn("flow-callout", overlay.read_text())
            self.assertEqual((package / "lib.typ").read_text(), "original source")


class TypstIntegrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.compiler = os.environ.get("FLOW_READER_TYPST") or shutil.which("typst")
        package_path = os.environ.get("FLOW_READER_PACKAGES")
        if not cls.compiler or not package_path:
            raise unittest.SkipTest("Set FLOW_READER_PACKAGES and optionally FLOW_READER_TYPST")
        cls.packages = Path(package_path)

    def test_semantic_output_keeps_nested_labels_and_annotations(self):
        with tempfile.TemporaryDirectory() as temp:
            project = build.Project(ROOT / "tests/fixtures", Path("main.typ"),
                                    self.packages, compiler=self.compiler)
            report = build.compile_project(project, Path(temp))
            self.assertEqual(report["exitCode"], 0, (Path(temp) / "compile.log").read_text())
            self.assertTrue(report["contentGatePassed"], report)
            self.assertEqual(report["annotations"], 2)
            self.assertGreater(report["elements"]["math"], 5)
            self.assertGreater(report["elements"]["svg"], 0)

    def test_paged_output_is_unchanged_by_package_overlay(self):
        with tempfile.TemporaryDirectory() as temp:
            work = Path(temp)
            build.prepare_packages(self.packages, work / "overlay")
            for name, packages in [("original", self.packages), ("reader", work / "overlay")]:
                command = [self.compiler, "compile", "--creation-timestamp", "1760000000",
                           "--package-path", str(packages), str(ROOT / "tests/fixtures/main.typ"),
                           str(work / f"{name}.pdf")]
                result = subprocess.run(command, capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual((work / "original.pdf").read_bytes(), (work / "reader.pdf").read_bytes())


if __name__ == "__main__":
    unittest.main()
