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
    def test_routes_are_numeric_bounded_and_preserved_in_the_request(self):
        value = geometry()
        value["graphic-1"]["routes"] = {"connector-1": [{"x": 80, "y": 70}, {"x": 90, "y": -20}]}
        self.assertEqual(validate_geometry(value, {"graphic-1": ["left", "right"]}), value)
        for routes in ({}, {"unknown": []}, {"connector-1": []},
                       {"connector-1": [{"x": 80, "y": 70}, {"x": float("nan"), "y": 0}]},
                       {"connector-1": [{"x": 80, "y": 70}, {"x": 401, "y": 0}]},
                       {"connector-1": [{"x": 80, "y": 70}, {"x": 80, "y": -109}]}):
            value["graphic-1"]["routes"] = routes
            with self.assertRaises(ValueError):
                validate_geometry(value, {"graphic-1": ["left", "right"]})

    def test_fragment_geometry_preserves_gaps_and_checks_each_rectangle(self):
        known = {"graphic-1": ["left", "right"]}
        value = geometry()
        marker = value["graphic-1"]["markers"]["left"]
        fragments = [marker, {"x": 10, "y": 120, "width": 60, "height": 25}]
        value["graphic-1"]["markers"]["left"] = {"fragments": fragments}
        self.assertEqual(validate_geometry(value, known), value)
        for invalid in ([], fragments * 129, [marker, None],
                        [marker, {"x": 380, "y": 120, "width": 60, "height": 25}]):
            value["graphic-1"]["markers"]["left"]["fragments"] = invalid
            with self.assertRaises(ValueError):
                validate_geometry(value, known)

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
        value["graphic-1"]["fontSize"] = 13
        self.assertEqual(validate_geometry(value, known), value)
        for size in (True, 0, 12, 31, float("nan")):
            value["graphic-1"]["fontSize"] = size
            with self.assertRaises(ValueError):
                validate_geometry(value, known)


class GraphicCompilerTests(unittest.TestCase):
    def test_free_endpoints_can_adapt_while_named_endpoints_remain_exact(self):
        compiler = os.environ.get("FLOW_READER_TYPST") or shutil.which("typst")
        packages = os.environ.get("FLOW_READER_PACKAGES")
        if not compiler or not packages:
            self.skipTest("Set FLOW_READER_PACKAGES and optionally FLOW_READER_TYPST")
        project = Project(ROOT / "tests/fixtures", Path("graphics-free-endpoints.typ"), Path(packages), compiler=compiler)
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary)
            request = geometry()
            report = compile_project(project, output, geometry=request)
            self.assertTrue(report["contentGatePassed"], (output / "compile.log").read_text())
            def rendered():
                svg = ET.fromstring(extract_graphics((output / "document.html").read_text(), request, "free")["graphic-1"])
                return json.loads(svg.attrib["data-flow-graphic-layout"])
            before = rendered()["connectors"]
            self.assertEqual(len(before), 2)
            self.assertTrue(before[0]["end"]["free"])
            self.assertTrue(before[1]["start"]["free"])
            self.assertEqual(before[0]["start"], {"tag": "left", "anchor": "south"})
            self.assertEqual(before[1]["end"], {"tag": "right", "anchor": "south"})
            request["graphic-1"]["routes"] = {
                "connector-1": [before[0]["points"][0], {"x": 370, "y": 130}],
                "connector-2": [{"x": 20, "y": 140}, before[1]["points"][-1]],
            }
            report = compile_project(project, output, geometry=request)
            self.assertTrue(report["contentGatePassed"], (output / "compile.log").read_text())
            after = rendered()
            self.assertTrue(all(item["routed"] for item in after["connectors"]))
            self.assertLessEqual(after["width"], 400.01)
            request["graphic-1"]["routes"]["connector-1"][0] = {"x": 1, "y": 1}
            report = compile_project(project, output, geometry=request)
            self.assertEqual(report["exitCode"], 1)
            self.assertIn("changed its original endpoints", (output / "compile.log").read_text())

    def test_routing_keeps_original_named_endpoints_and_cetz_marks(self):
        compiler = os.environ.get("FLOW_READER_TYPST") or shutil.which("typst")
        packages = os.environ.get("FLOW_READER_PACKAGES")
        if not compiler or not packages:
            self.skipTest("Set FLOW_READER_PACKAGES and optionally FLOW_READER_TYPST")
        project = Project(ROOT / "tests/fixtures", Path("graphics-routed-anchors.typ"), Path(packages), compiler=compiler)
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary)
            request = geometry(220)
            report = compile_project(project, output, geometry=request)
            self.assertTrue(report["contentGatePassed"], (output / "compile.log").read_text())
            original = ET.fromstring(extract_graphics((output / "document.html").read_text(), request, "before")["graphic-1"])
            connector = json.loads(original.attrib["data-flow-graphic-layout"])["connectors"][0]
            self.assertEqual(connector["start"], {"tag": "left", "anchor": "south"})
            self.assertEqual(connector["end"], {"tag": "right", "anchor": "south"})
            self.assertEqual(connector["kind"], "cubic")
            self.assertFalse(connector["routed"])
            a, b = connector["points"][0], connector["points"][-1]
            request["graphic-1"]["routes"] = {"connector-1": [a, {"x": a["x"], "y": 170}, {"x": b["x"], "y": 170}, b]}
            report = compile_project(project, output, geometry=request)
            self.assertTrue(report["contentGatePassed"], (output / "compile.log").read_text())
            routed = ET.fromstring(extract_graphics((output / "document.html").read_text(), request, "after")["graphic-1"])
            revised = json.loads(routed.attrib["data-flow-graphic-layout"])["connectors"][0]
            self.assertTrue(revised["routed"])
            self.assertEqual(revised["points"], connector["points"])
            self.assertNotEqual(json.loads(original.attrib["data-flow-graphic-layout"])["labels"],
                                json.loads(routed.attrib["data-flow-graphic-layout"])["labels"])
            # The original arrowhead remains a separate CeTZ stroke; the route
            # is recomposed by CeTZ rather than replaced with a browser glyph.
            before = [p for p in original.iter("{http://www.w3.org/2000/svg}path") if p.get("stroke")]
            after = [p for p in routed.iter("{http://www.w3.org/2000/svg}path") if p.get("stroke")]
            self.assertEqual(len(after), len(before))
            self.assertEqual([p.get("stroke") for p in after], [p.get("stroke") for p in before])
            self.assertNotEqual(after[0].get("d"), before[0].get("d"))
            request["graphic-1"]["routes"]["connector-1"][0] = {"x": a["x"] + 2, "y": a["y"]}
            report = compile_project(project, output, geometry=request)
            self.assertEqual(report["exitCode"], 1)
            self.assertIn("changed its original endpoints", (output / "compile.log").read_text())

    def test_fragment_anchors_land_on_actual_terms_and_keep_the_first_origin(self):
        compiler = os.environ.get("FLOW_READER_TYPST") or shutil.which("typst")
        packages = os.environ.get("FLOW_READER_PACKAGES")
        if not compiler or not packages:
            self.skipTest("Set FLOW_READER_PACKAGES and optionally FLOW_READER_TYPST")
        project = Project(ROOT / "tests/fixtures", Path("graphics-fragments.typ"), Path(packages), compiler=compiler)
        request = geometry()
        request["graphic-1"]["markers"]["left"] = {"fragments": [
            {"x": 80, "y": 20, "width": 40, "height": 20},
            {"x": 10, "y": 60, "width": 70, "height": 20},
        ]}
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary)
            report = compile_project(project, output, geometry=request)
            self.assertTrue(report["contentGatePassed"], (output / "compile.log").read_text())
            # Assertions inside the original CeTZ callback check cardinal,
            # arbitrary-angle, center, and perimeter anchors against both lines.
            svg = extract_graphics((output / "document.html").read_text(), request, "fragments")["graphic-1"]
            self.assertGreater(len(list(ET.fromstring(svg).iter("{http://www.w3.org/2000/svg}path"))), 1)

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
