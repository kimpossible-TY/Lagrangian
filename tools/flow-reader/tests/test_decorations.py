"""Semantic terms and authored decoration layers must survive independently."""
import json
import os
from pathlib import Path
import shutil
import sys
import tempfile
import unittest
from xml.etree import ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from build import Project, compile_project
from decorations import validate_decorations, extract_decorations


class DecorationValidationTests(unittest.TestCase):
    def test_empty_svg_is_a_present_layer_but_missing_or_duplicate_layers_fail(self):
        source = '''<mrow data-flow-decoration="d" data-flow-decoration-layers='["under"]'>x</mrow>
          <span data-flow-decoration-rendered="d" data-flow-decoration-fragment="0"
          data-flow-decoration-layer="under" data-flow-decoration-layout='{"width":100,"height":20}'>
          <svg xmlns="http://www.w3.org/2000/svg" /></span>'''
        requests = {"d": {"fragments": [{"width": 100, "height": 20}]}}
        result = extract_decorations(source, requests, "empty")
        self.assertEqual(len(result["d"]), 1)
        self.assertEqual(len(ET.fromstring(result["d"][0]["svg"])), 0)
        with self.assertRaises(ValueError):
            extract_decorations(source.replace('<svg xmlns="http://www.w3.org/2000/svg" />', ''),
                                requests, "missing")
        with self.assertRaises(ValueError):
            extract_decorations(source + source, requests, "duplicate")

    def test_only_known_finite_fragments_and_plain_ink_are_accepted(self):
        request = {"d": {"fontSize": 18, "ink": "#aabbcc", "fragments": [{"width": 100, "height": 20}]}}
        self.assertEqual(validate_decorations(request, {"d": ["over"]}), request)
        for key, value in [("fontSize", True), ("ink", "url(secret)"), ("fragments", []),
                           ("fragments", [{"width": float("nan"), "height": 2}])]:
            with self.assertRaises(ValueError):
                validate_decorations({"d": request["d"] | {key: value}}, {"d": ["over"]})
        with self.assertRaises(ValueError):
            validate_decorations(request, {})


class DecorationCompilerTests(unittest.TestCase):
    def test_native_math_and_all_authored_layers_for_multiple_fragments(self):
        compiler = os.environ.get("FLOW_READER_TYPST") or shutil.which("typst")
        packages = os.environ.get("FLOW_READER_PACKAGES")
        if not compiler or not packages:
            self.skipTest("Set FLOW_READER_PACKAGES and optionally FLOW_READER_TYPST")
        project = Project(ROOT / "tests/fixtures", Path("decorations.typ"), Path(packages), compiler=compiler)
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary)
            report = compile_project(project, output)
            self.assertTrue(report["contentGatePassed"], (output / "compile.log").read_text())
            source = (output / "document.html").read_text()
            self.assertEqual(len(report["decorations"]), 6)
            self.assertNotIn("<svg", source)
            self.assertNotIn(">color:#", source)
            self.assertIn("<msup>", source)
            self.assertIn('data-flow-mark="sum"', source)
            requests = {identifier: {"fontSize": 30, "ink": "#ffffff", "fragments": [
                {"width": 100, "height": 30}, {"width": 70, "height": 25}]}
                for identifier in report["decorations"]}
            requested = compile_project(project, output, decorations=requests)
            self.assertTrue(requested["contentGatePassed"], (output / "compile.log").read_text())
            drawings = extract_decorations((output / "document.html").read_text(), requests, "test")
            for identifier, layers in report["decorations"].items():
                self.assertEqual({(d["fragment"], d["layer"]) for d in drawings[identifier]},
                                 {(index, layer) for index in (0, 1) for layer in layers})
                for drawing in drawings[identifier]:
                    svg = ET.fromstring(drawing["svg"])
                    self.assertTrue(svg.attrib["style"].endswith("overflow:visible"))
                    self.assertGreater(drawing["layout"]["width"], 0)
                    # Only the under-bracket has glyphs. No decoration repeats
                    # mathematical body text (x, sums, powers, etc.).
                    if identifier != "decoration-5":
                        self.assertFalse(list(svg.iter("{http://www.w3.org/2000/svg}use")))
            first, second = drawings["decoration-1"]
            self.assertAlmostEqual(first["layout"]["width"] - second["layout"]["width"], 30)
            # Automatic document equation numbers must not become part of a
            # stretched under-bracket or inflate its anchor rectangle.
            for drawing in drawings["decoration-5"]:
                width = requests["decoration-5"]["fragments"][drawing["fragment"]]["width"]
                # Font stretch variants can overshoot their requested length.
                self.assertLess(drawing["layout"]["anchor"]["width"], width + 30)

    def test_revision_cache_reuse_and_failed_save_do_not_mix_decorations(self):
        from unittest.mock import patch
        from serve import ReaderState, RevisionChanged
        compiler = os.environ.get("FLOW_READER_TYPST") or shutil.which("typst")
        packages = os.environ.get("FLOW_READER_PACKAGES")
        if not compiler or not packages:
            self.skipTest("Set FLOW_READER_PACKAGES and optionally FLOW_READER_TYPST")
        with tempfile.TemporaryDirectory() as temporary:
            work = Path(temporary)
            source = work / "source"
            source.mkdir()
            entry = source / "main.typ"
            shutil.copyfile(ROOT / "tests/fixtures/decorations.typ", entry)
            state = ReaderState(Project(source, Path("main.typ"), Path(packages), compiler=compiler),
                                work / "output", "https://example.test/paged", False)
            state.compile()
            revision = state.revision
            self.assertIsNotNone(revision, state.report)
            layout = {"fontSize": 18, "ink": "#242c34", "fragments": [{"width": 100, "height": 25}]}
            request = {identifier: layout for identifier in ("decoration-1", "decoration-2")}
            result = state.render_dynamic(revision, request, "decorations")
            with patch("serve.compile_project", side_effect=AssertionError("Unexpected recompile")):
                reused = state.render_dynamic(revision, {"decoration-2": layout}, "decorations")
                self.assertEqual(reused["decorations"]["decoration-2"], result["decorations"]["decoration-2"])
            with self.assertRaises(RevisionChanged):
                state.render_dynamic("obsolete", request, "decorations")
            entry.write_text("#not-a-function()")
            state.compile()
            self.assertEqual(state.revision, revision)
            self.assertEqual(state.render_dynamic(revision, request, "decorations"), result)
            with self.assertRaises(RevisionChanged):
                state.render_dynamic(revision, {"decoration-3": layout}, "decorations")


if __name__ == "__main__":
    unittest.main()
