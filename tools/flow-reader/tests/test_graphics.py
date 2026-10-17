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


class GraphicCompilerTests(unittest.TestCase):
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


if __name__ == "__main__":
    unittest.main()
