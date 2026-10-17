"""CeTZ programs must render at the reader's actual measured term positions."""

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
from graphics import extract_graphics, validate_geometry


def geometry(right_x=260):
    return {"graphic-1": {"width": 400, "height": 240, "markers": {
        "left": {"x": 80, "y": 70, "width": 35, "height": 25},
        "right": {"x": right_x, "y": 70, "width": 35, "height": 25},
    }}}


class GeometryValidationTests(unittest.TestCase):
    def test_unknown_tags_and_nonfinite_geometry_are_rejected(self):
        known = {"graphic-1": ["left", "right"]}
        self.assertEqual(validate_geometry(geometry(), known), geometry())
        for malformed in [geometry(float("nan")), geometry(500), {"unknown": {}}]:
            with self.assertRaises(ValueError):
                validate_geometry(malformed, known)
        value = geometry()
        value["graphic-1"]["markers"]["source-code"] = {}
        with self.assertRaises(ValueError):
            validate_geometry(value, known)
        value = geometry()
        value["graphic-1"]["fontSize"] = 30
        self.assertEqual(validate_geometry(value, known), value)
        for size in (True, 0, 31, float("nan")):
            value["graphic-1"]["fontSize"] = size
            with self.assertRaises(ValueError):
                validate_geometry(value, known)


class GraphicCompilerTests(unittest.TestCase):
    def test_label_measurement_and_drawing_follow_the_reading_font_size(self):
        compiler = os.environ.get("FLOW_READER_TYPST") or shutil.which("typst")
        packages = os.environ.get("FLOW_READER_PACKAGES")
        if not compiler or not packages:
            self.skipTest("Set FLOW_READER_PACKAGES and optionally FLOW_READER_TYPST")
        project = Project(ROOT / "tests/fixtures", Path("graphics-label.typ"), Path(packages), compiler=compiler)
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary)
            labels, glyphs = [], []
            for size in (18, 30):
                request = {"graphic-1": {"width": 300, "height": 80, "fontSize": size,
                           "markers": {"origin": {"x": 40, "y": 40, "width": 20, "height": 20}}}}
                report = compile_project(project, output, geometry=request)
                self.assertTrue(report["contentGatePassed"], (output / "compile.log").read_text())
                svg = ET.fromstring(extract_graphics((output / "document.html").read_text(), request, "font")["graphic-1"])
                labels.append(json.loads(svg.attrib["data-flow-graphic-layout"])["labels"][0])
                glyphs.append([node.attrib for node in svg.iter("{http://www.w3.org/2000/svg}use")])
            self.assertAlmostEqual(labels[1]["width"] / labels[0]["width"], 30 / 18)
            self.assertAlmostEqual(labels[1]["height"] / labels[0]["height"], 30 / 18)
            self.assertNotEqual(glyphs[0], glyphs[1])

    def test_actual_cetz_program_changes_with_term_geometry(self):
        compiler = os.environ.get("FLOW_READER_TYPST") or shutil.which("typst")
        packages = os.environ.get("FLOW_READER_PACKAGES")
        if not compiler or not packages:
            self.skipTest("Set FLOW_READER_PACKAGES and optionally FLOW_READER_TYPST")
        project = Project(ROOT / "tests/fixtures", Path("graphics.typ"), Path(packages), compiler=compiler)
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary)
            report = compile_project(project, output)
            self.assertTrue(report["contentGatePassed"], report)
            self.assertEqual(report["graphics"], {"graphic-1": ["left", "right"]})
            rendered = []
            for right_x in (220, 300):
                request = geometry(right_x)
                report = compile_project(project, output, geometry=request)
                self.assertTrue(report["contentGatePassed"], report)
                svg = extract_graphics((output / "document.html").read_text(), request, str(right_x))["graphic-1"]
                root = ET.fromstring(svg)
                # 400 CSS px * 0.75 pt, 240 CSS px * 0.75 pt.
                self.assertEqual(root.attrib["viewBox"], "0 0 300 180")
                self.assertGreater(len(list(root.iter("{http://www.w3.org/2000/svg}path"))), 1)
                rendered.append([node.attrib.get("d") for node in root.iter("{http://www.w3.org/2000/svg}path")])
            self.assertNotEqual(rendered[0], rendered[1])

    def test_literal_coordinates_follow_first_marker_and_report_complete_bounds(self):
        compiler = os.environ.get("FLOW_READER_TYPST") or shutil.which("typst")
        packages = os.environ.get("FLOW_READER_PACKAGES")
        if not compiler or not packages:
            self.skipTest("Set FLOW_READER_PACKAGES and optionally FLOW_READER_TYPST")
        project = Project(ROOT / "tests/fixtures", Path("graphics-origin.typ"), Path(packages), compiler=compiler)
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary)
            layouts = []
            for position in (0, 40):
                request = {"graphic-1": {"width": 100, "height": 80, "fontSize": 30,
                           "markers": {"origin": {"x": position, "y": position, "width": 20, "height": 20}}}}
                report = compile_project(project, output, geometry=request)
                self.assertTrue(report["contentGatePassed"], (output / "compile.log").read_text())
                svg = ET.fromstring(extract_graphics((output / "document.html").read_text(), request, "origin")["graphic-1"])
                layout = json.loads(svg.attrib["data-flow-graphic-layout"])
                self.assertEqual(layout["fontSize"], 30)
                self.assertEqual(float(svg.attrib["width"]), layout["width"])
                self.assertEqual(float(svg.attrib["height"]), layout["height"])
                layouts.append(layout)
            self.assertAlmostEqual(layouts[0]["left"], -96 / 2.54)
            self.assertAlmostEqual(layouts[0]["top"], -96 / 2.54)
            self.assertAlmostEqual(layouts[0]["width"], 100 + 96 / 2.54)
            self.assertAlmostEqual(layouts[0]["height"], 80 + 96 / 2.54)
            self.assertEqual((layouts[1]["left"], layouts[1]["top"]), (0, 0))
            self.assertEqual((layouts[1]["width"], layouts[1]["height"]), (100, 80))


if __name__ == "__main__":
    unittest.main()
