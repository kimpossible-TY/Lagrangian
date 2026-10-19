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
from flow_reader.compiler import build
from flow_reader.compiler.audit import ContentAudit
from flow_reader.document.content import namespace_svg_ids, normalize_math_html



class ContentAuditTests(unittest.TestCase):
    def audit(self, text):
        audit = ContentAudit()
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
        result = namespace_svg_ids(source)
        report = self.audit(result)
        self.assertTrue(report["contentGatePassed"], report)
        self.assertIn('viewBox="0 0 20 20"', result)
        self.assertIn('href="#flow-svg-1-glyph"', result)
        self.assertEqual(result.count('href="#equation"'), 2)

    def test_footnotes_inside_math_use_a_token_integration_point(self):
        source = ('<math><mrow><mi>x</mi><sup><a href="#note">1</a></sup>'
                  '<mfrac><mi>a</mi><mi>b</mi></mfrac></mrow></math>')
        result = normalize_math_html(source)
        self.assertIn('<mtext><sup><a href="#note">1</a></sup></mtext>', result)
        self.assertIn('<mfrac><mi>a</mi><mi>b</mi></mfrac>', result)
        self.assertEqual(normalize_math_html(result), result)

    def test_block_content_cannot_silently_escape_math_namespace(self):
        with self.assertRaisesRegex(ValueError, "Non-phrasing"):
            normalize_math_html('<math><mrow><div>note</div></mrow></math>')

    def test_only_tagged_math_cancellation_is_promoted_to_a_semantic_enclosure(self):
        row = ('<mrow data-flow-cancel="updiagonalstrike" notation="updiagonalstrike">'
               '<mrow><mfrac><mi>a</mi><mi>b</mi></mfrac></mrow></mrow>')
        result = normalize_math_html('<math>' + row + '</math>')
        self.assertIn('<menclose data-flow-cancel="updiagonalstrike"', result)
        self.assertIn('<mfrac><mi>a</mi><mi>b</mi></mfrac></mrow></menclose>', result)
        self.assertEqual(normalize_math_html(result), result)
        self.assertEqual(normalize_math_html(row), row)
        mismatch = row.replace('notation="updiagonalstrike"', 'notation="box"')
        self.assertEqual(normalize_math_html('<math>' + mismatch + '</math>'), '<math>' + mismatch + '</math>')

    def test_overline_spans_a_grouped_body_with_a_stretchy_spacing_bar(self):
        body = '<mi>a</mi><mo>+</mo><mi>b</mi>'
        row = '<mrow accent="true" data-flow-overline="true">' + body + '</mrow>'
        result = normalize_math_html('<math>' + row + '</math>')
        expected = ('<math><mover accent="true" data-flow-overline="true"><mrow>' + body
                    + '</mrow><mo stretchy="true">¯</mo></mover></math>')
        self.assertEqual(result, expected)
        self.assertEqual(normalize_math_html(result), result)
        empty = normalize_math_html('<math><mrow accent="true" data-flow-overline="true"/></math>')
        self.assertIn('<mrow></mrow><mo stretchy="true">¯</mo></mover>', empty)
        self.assertEqual(normalize_math_html(empty), empty)

    def test_math_normalization_keeps_svg_case_for_later_xml_extraction(self):
        from xml.etree import ElementTree as ET
        svg = ('<svg xmlns="http://www.w3.org/2000/svg"><defs>'
               '<clipPath id="clip"><path d="M0 0L2 2"/></clipPath>'
               '<linearGradient id="paint"><stop offset="0"/></linearGradient>'
               '</defs></svg>')
        normalized = normalize_math_html(svg)
        self.assertEqual(ET.tostring(ET.fromstring(svg)), ET.tostring(ET.fromstring(normalized)))


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
            self.assertEqual(report["elements"].get("svg", 0), 0)
            self.assertGreater(report["elements"]["menclose"], 0)
            self.assertGreater(report["elements"]["mover"], 0)

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

    def test_native_labeled_groups_use_semantic_annotations_without_losing_bodies(self):
        with tempfile.TemporaryDirectory() as temp:
            project = build.Project(ROOT / "tests/fixtures", Path("adaptive-annotations.typ"),
                                    self.packages, compiler=self.compiler)
            report = build.compile_project(project, Path(temp))
            self.assertEqual(report["exitCode"], 0, (Path(temp) / "compile.log").read_text())
            self.assertTrue(report["contentGatePassed"], report)
            self.assertEqual(report["annotations"], 14)
            self.assertEqual(report["elements"].get("munder"), 1,
                             "Only the unlabeled grouping retains its original brace")
            self.assertEqual(report["elements"].get("mover", 0), 0)
            source = (Path(temp) / "document.html").read_text()
            for name in ("kernel", "sum", "lower group", "upper group"):
                self.assertEqual(source.count(">" + name + "<"), 1, name)

    def test_native_annotation_adapter_keeps_paged_group_rendering(self):
        with tempfile.TemporaryDirectory() as temp:
            work = Path(temp)
            build.prepare_packages(self.packages, work / "overlay")
            for name, prelude in [("original", ""), ("reader",
                    '#import "@local/flow-reader:0.1.0": apply-reader\n#show: apply-reader\n')]:
                command = [self.compiler, "compile", "--creation-timestamp", "1760000000",
                           "--root", str(ROOT / "tests/fixtures"),
                           "--package-path", str(work / "overlay"), "-", str(work / f"{name}.svg")]
                result = subprocess.run(command,
                    input=prelude + '$ underbrace(x+y, "kernel") + overbrace(a+b, "sum") '
                          '+ underbracket(c+d, "lower") + overbracket(e+f, "upper") $',
                    capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual((work / "original.svg").read_bytes(), (work / "reader.svg").read_bytes())

    def test_native_annotation_retains_mathematical_scripts_and_fences(self):
        with tempfile.TemporaryDirectory() as temp:
            work = Path(temp)
            (work / "main.typ").write_text('$ underbracket(a+b, T_A(X comma Y)) $')
            project = build.Project(work, Path("main.typ"), self.packages, compiler=self.compiler)
            report = build.compile_project(project, work / "output")
            self.assertEqual(report["exitCode"], 0, (work / "output/compile.log").read_text())
            self.assertTrue(report["contentGatePassed"], report)
            self.assertEqual(report["elements"].get("math"), 2)
            self.assertEqual(report["elements"].get("msub"), 1)
            self.assertEqual(report["annotations"], 1)

    def test_highlighted_preserves_text_and_native_math_in_html(self):
        from xml.etree import ElementTree as ET

        with tempfile.TemporaryDirectory() as temp:
            project = build.Project(ROOT / "tests/fixtures", Path("highlighted.typ"),
                                    self.packages, compiler=self.compiler)
            report = build.compile_project(project, Path(temp))
            self.assertEqual(report["exitCode"], 0, (Path(temp) / "compile.log").read_text())
            self.assertTrue(report["contentGatePassed"], report)
            source = (Path(temp) / "document.html").read_text()
            body = source.split("<body>", 1)[1].split("</body>", 1)[0]
            document = ET.fromstring("<body>" + body + "</body>")
            marks = document.findall('.//*[@class="flow-highlight"]')
            self.assertEqual(len(marks), 9)
            self.assertEqual(''.join(marks[0].itertext()), "Plain highlighted text.")
            self.assertEqual(''.join(marks[1].itertext()), "A highlighted string.")
            self.assertEqual(''.join(marks[2].itertext()), "One text child.")
            self.assertEqual(sum(len(mark.findall('.//{*}math')) for mark in marks), 5)
            self.assertEqual(len(marks[3].findall('.//{*}mfrac')), 1)
            self.assertEqual(len(marks[4].findall('.//{*}msqrt')), 1)
            self.assertEqual(len(marks[4].findall('.//{*}a')), 1)
            self.assertEqual(''.join(marks[7].itertext()).strip(), "First highlighted paragraph.")
            self.assertEqual(''.join(marks[8].itertext()).strip(), "Second highlighted paragraph.")
            self.assertEqual(report["elements"].get("svg", 0), 0)

    def test_highlighted_paged_output_matches_the_installed_helper(self):
        with tempfile.TemporaryDirectory() as temp:
            work = Path(temp)
            build.prepare_packages(self.packages, work / "overlay")
            for name, packages in [("original", self.packages), ("reader", work / "overlay")]:
                command = [self.compiler, "compile", "--creation-timestamp", "1760000000",
                           "--package-path", str(packages), str(ROOT / "tests/fixtures/highlighted.typ"),
                           str(work / f"{name}.pdf")]
                result = subprocess.run(command, capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual((work / "original.pdf").read_bytes(), (work / "reader.pdf").read_bytes())

    def test_paragraph_tabs_keep_authored_spacing_without_copy_text(self):
        from xml.etree import ElementTree as ET

        with tempfile.TemporaryDirectory() as temp:
            project = build.Project(ROOT / "tests/fixtures", Path("paragraph-tabs.typ"),
                                    self.packages, compiler=self.compiler)
            report = build.compile_project(project, Path(temp))
            self.assertEqual(report["exitCode"], 0, (Path(temp) / "compile.log").read_text())
            self.assertTrue(report["contentGatePassed"], report)
            source = (Path(temp) / "document.html").read_text()
            body = source.split("<body>", 1)[1].split("</body>", 1)[0]
            document = ET.fromstring("<body>" + body + "</body>")
            tabs = document.findall('.//span[@class="flow-paragraph-tab"]')
            self.assertEqual(len(tabs), 6)
            self.assertTrue(all(tab.get("aria-hidden") == "true" for tab in tabs))
            self.assertTrue(all(not ''.join(tab.itertext()) for tab in tabs))
            self.assertNotIn("\uf000", ''.join(document.itertext()))
            paragraphs = document.findall('p')
            self.assertEqual(len(paragraphs), 7)
            self.assertIn("lowercase paragraph", ''.join(paragraphs[0].itertext()))
            self.assertIn("Uppercase paragraph", ''.join(paragraphs[1].itertext()))
            self.assertIn("Before middle text", ''.join(paragraphs[5].itertext()))
            self.assertEqual(len(paragraphs[4].findall('.//mark/span[@class="flow-paragraph-tab"]')), 1)
            self.assertEqual(len(paragraphs[-1].findall('.//span[@class="flow-paragraph-tab"]')), 0)
            self.assertEqual(report["elements"]["math"], 2)

    def test_paragraph_tab_paged_output_matches_the_installed_helper(self):
        with tempfile.TemporaryDirectory() as temp:
            work = Path(temp)
            build.prepare_packages(self.packages, work / "overlay")
            for name, packages in [("original", self.packages), ("reader", work / "overlay")]:
                command = [self.compiler, "compile", "--creation-timestamp", "1760000000",
                           "--package-path", str(packages), str(ROOT / "tests/fixtures/paragraph-tabs.typ"),
                           str(work / f"{name}.pdf")]
                result = subprocess.run(command, capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual((work / "original.pdf").read_bytes(), (work / "reader.pdf").read_bytes())


if __name__ == "__main__":
    unittest.main()
