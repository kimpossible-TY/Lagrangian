"""Actual CeTZ output must change geometry without scaling its label glyphs."""

import base64
import json
from html.parser import HTMLParser
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import threading
import unittest
from http.server import ThreadingHTTPServer
from urllib.error import HTTPError
from urllib.request import Request, urlopen
from unittest.mock import patch
from xml.etree import ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from build import Project, compile_project, prepare_packages
from canvases import extract_canvases, validate_canvases
from serve import ReaderState, handler_for
from content import SvgRanges


def request(width=280, font=18):
    return {"canvas-1": {"width": width, "fontSize": font}}


class CanvasValidationTests(unittest.TestCase):
    def test_only_known_canvases_and_finite_supported_sizes(self):
        self.assertEqual(validate_canvases(request(), ["canvas-1"]), request())
        for value in [request(float("nan")), request(0), request(True),
                      request(font=100), {"unknown": {"width": 280, "fontSize": 18}}]:
            with self.subTest(value=value), self.assertRaises(ValueError):
                validate_canvases(value, ["canvas-1"])


class CanvasCompilerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.compiler = os.environ.get("FLOW_READER_TYPST") or shutil.which("typst")
        packages = os.environ.get("FLOW_READER_PACKAGES")
        if not cls.compiler or not packages:
            raise unittest.SkipTest("Set FLOW_READER_PACKAGES and optionally FLOW_READER_TYPST")
        cls.packages = Path(packages)
        cls.project = Project(ROOT / "tests/fixtures", Path("canvases.typ"),
                              cls.packages, compiler=cls.compiler)

    def test_native_geometry_and_label_sources_are_exported_without_text_flattening(self):
        class NativeSources(HTMLParser):
            def __init__(self):
                super().__init__()
                self.models = {}
                self.styles = []
                self.math = 0
                self.math_depth = 0
                self.math_html = []

            def handle_starttag(self, tag, attrs):
                attributes = dict(attrs)
                if "data-flow-canvas-model" in attributes:
                    self.models[attributes["data-flow-canvas"]] = json.loads(attributes["data-flow-canvas-model"])
                if tag == "span" and "font-size:" in attributes.get("style", ""):
                    self.styles.append(attributes["style"])
                self.math += tag == "math"
                self.math_depth += tag == "math"
                if tag == "span" and self.math_depth:
                    self.math_html.append(attributes)

            def handle_endtag(self, tag):
                self.math_depth -= tag == "math"

        project = Project(self.project.root, Path("native-canvases.typ"), self.packages,
                          compiler=self.compiler, semantic_canvases=True)
        before = {path: path.read_bytes() for path in (project.root / project.entry,
                                                      self.project.root / self.project.entry)}
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary)
            report = compile_project(project, output)
            self.assertTrue(report["contentGatePassed"], (output / "compile.log").read_text())
            self.assertEqual(report["compilerLossWarnings"], [])
            source = (output / "document.html").read_text()
            parser = NativeSources()
            parser.feed(source)
            self.assertEqual(len(parser.models), 7)
            self.assertAlmostEqual(parser.models["canvas-2"]["width"], 500 / .75)
            self.assertEqual(len(parser.models["canvas-3"]["labels"]), 7)
            for model in parser.models.values():
                self.assertEqual(model["version"], 1)
                self.assertEqual(len({item["id"] for item in model["labels"]}), len(model["labels"]))
            self.assertTrue(any("font-size:1em" in style for style in parser.styles))
            self.assertTrue(any("font-size:2.545" in style and "color:#b5261e" in style
                                and "font-weight:700" in style for style in parser.styles))
            self.assertEqual(parser.math, 6)
            self.assertEqual(parser.math_html, [], "Mathematical glyphs must remain native MathML")
            self.assertIn("Original stacked label", source)
            self.assertIn("This fixed content box cannot shrink.", source)
            self.assertIn("Nested readable label", source)
            ranges = SvgRanges(source)
            ranges.feed(source)
            self.assertEqual(len(ranges.ranges), 7)
            for start, end in ranges.ranges:
                svg = ET.fromstring(source[start:end])
                self.assertFalse(list(svg.iter("{http://www.w3.org/2000/svg}symbol")))
        self.assertEqual({path: path.read_bytes() for path in before}, before)

    def test_coordinate_unit_adapts_but_glyphs_and_physical_strokes_do_not_shrink(self):
        before = (self.project.root / self.project.entry).read_bytes()
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary)
            rendered = []
            for width, font in [(560, 18), (280, 18), (280, 30)]:
                asks = request(width, font)
                report = compile_project(self.project, output, canvases=asks)
                self.assertTrue(report["contentGatePassed"], (output / "compile.log").read_text())
                result = extract_canvases((output / "document.html").read_text(), asks, "test")["canvas-1"]
                self.assertEqual(result["layout"]["status"], "width-fit")
                self.assertLessEqual(result["layout"]["width"], width + 1)
                root = ET.fromstring(result["svg"])
                ns = "{http://www.w3.org/2000/svg}"
                glyphs = [path.attrib["d"] for symbol in root.iter(ns + "symbol")
                          for path in symbol.iter(ns + "path")]
                self.assertGreater(len(glyphs), 5)
                self.assertTrue(all(path.attrib["stroke-width"] == "1" for path in root.iter(ns + "path")
                                    if "stroke-width" in path.attrib))
                rendered.append((result["layout"], glyphs))
            self.assertLess(rendered[1][0]["width"], rendered[0][0]["width"])
            self.assertEqual(rendered[0][1], rendered[1][1], "Fitting must not shrink label glyphs")
            self.assertNotEqual(rendered[1][1], rendered[2][1], "Larger reading size must affect labels")
        self.assertEqual((self.project.root / self.project.entry).read_bytes(), before)

    def test_fixed_physical_drawing_reports_overflow_without_clipping_or_scaling(self):
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary)
            asks = {"canvas-2": {"width": 280, "fontSize": 18}}
            report = compile_project(self.project, output, canvases=asks)
            self.assertTrue(report["contentGatePassed"], report)
            result = extract_canvases((output / "document.html").read_text(), asks, "test")["canvas-2"]
            self.assertEqual(result["layout"]["status"], "overflow")
            self.assertAlmostEqual(result["layout"]["width"], 500 / .75)
            self.assertEqual(result["layout"]["unitScale"], 1)

    def test_paged_fixture_is_byte_identical_with_canvas_adapter(self):
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary)
            prepare_packages(self.packages, output / "overlay")
            for name, packages in [("original", self.packages), ("reader", output / "overlay")]:
                result = subprocess.run([self.compiler, "compile", "--creation-timestamp", "1760000000",
                                         "--package-path", str(packages),
                                         str(self.project.root / self.project.entry), str(output / f"{name}.pdf")],
                                        text=True, capture_output=True)
                self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual((output / "original.pdf").read_bytes(), (output / "reader.pdf").read_bytes())

    def test_fletcher_and_older_cetz_export_native_labels_with_unchanged_pdf(self):
        project = Project(self.project.root, Path("legacy-canvases.typ"), self.packages,
                          compiler=self.compiler, semantic_canvases=True)
        before = (project.root / project.entry).read_bytes()
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary)
            report = compile_project(project, output)
            self.assertTrue(report["contentGatePassed"], (output / "compile.log").read_text())
            self.assertEqual(report["compilerLossWarnings"], [])
            self.assertEqual(len(report["canvases"]), 2)
            source = (output / "document.html").read_text()
            for phrase in ["Older readable source label", "Original node", "Target node", "Original edge"]:
                self.assertIn(phrase, source)
            parser = SvgRanges(source)
            parser.feed(source)
            self.assertEqual(len(parser.ranges), 2)
            for start, end in parser.ranges:
                svg = ET.fromstring(source[start:end])
                self.assertTrue(list(svg.iter("{http://www.w3.org/2000/svg}path")))
                self.assertFalse(list(svg.iter("{http://www.w3.org/2000/svg}symbol")))
            prepare_packages(self.packages, output / "overlay")
            for name, packages in [("original", self.packages), ("reader", output / "overlay")]:
                result = subprocess.run([self.compiler, "compile", "--creation-timestamp", "1760000000",
                                         "--package-path", str(packages), str(project.root / project.entry),
                                         str(output / f"{name}.pdf")], text=True, capture_output=True)
                self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual((output / "original.pdf").read_bytes(), (output / "reader.pdf").read_bytes())
        self.assertEqual((project.root / project.entry).read_bytes(), before)

    def test_surface_pixels_and_original_axis_anchors_survive_native_export(self):
        class Models(HTMLParser):
            def __init__(self):
                super().__init__()
                self.models = []

            def handle_starttag(self, tag, attrs):
                attributes = dict(attrs)
                if "data-flow-canvas-model" in attributes:
                    self.models.append(json.loads(attributes["data-flow-canvas-model"]))

        def images(source):
            parser = SvgRanges(source)
            parser.feed(source)
            pixels, anchors = [], []
            for start, end in parser.ranges:
                svg = ET.fromstring(source[start:end])
                for image in svg.iter("{http://www.w3.org/2000/svg}image"):
                    href = image.get("href", image.get("{http://www.w3.org/1999/xlink}href", ""))
                    if href.startswith("data:image/png;base64,"):
                        pixels.append(href)
                    elif href.startswith("data:image/svg+xml;base64,"):
                        overlay = ET.fromstring(base64.b64decode(href.split(",", 1)[1]))
                        anchors.extend((float(node.get("x")), float(node.get("y")),
                                        node.get("text-anchor"), "".join(node.itertext()))
                                       for node in overlay.iter("{http://www.w3.org/2000/svg}text"))
            return pixels, anchors

        entry = Path("surface-canvases.typ")
        before = (self.project.root / entry).read_bytes()
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary)
            variants = {}
            for enabled in [False, True]:
                folder = output / str(enabled)
                project = Project(self.project.root, entry, self.packages, compiler=self.compiler,
                                  semantic_canvases=enabled)
                report = compile_project(project, folder)
                self.assertTrue(report["contentGatePassed"], (folder / "compile.log").read_text())
                self.assertEqual(report["compilerLossWarnings"], [])
                variants[enabled] = (folder / "document.html").read_text()
            parser = Models()
            parser.feed(variants[True])
            self.assertEqual(len(parser.models), 2)
            original_pixels, original_anchors = images(variants[False])
            native_pixels, remaining_anchors = images(variants[True])
            self.assertEqual(len(original_pixels), 2)
            self.assertEqual(native_pixels, original_pixels, "Surface pixel data must stay byte-identical")
            self.assertEqual(remaining_anchors, [])
            native_anchors = [(label["left"], label["top"], label["align"])
                              for model in parser.models for label in model["labels"]]
            self.assertEqual(native_anchors, [anchor[:3] for anchor in original_anchors])
            self.assertTrue(all(label["baseline"] for model in parser.models for label in model["labels"]))
            for text in ["z₁", "z₂"]:
                self.assertEqual(variants[True].count(text), 2)
            prepare_packages(self.packages, output / "overlay")
            for name, packages in [("original", self.packages), ("reader", output / "overlay")]:
                result = subprocess.run([self.compiler, "compile", "--creation-timestamp", "1760000000",
                                         "--package-path", str(packages), str(self.project.root / entry),
                                         str(output / f"{name}.pdf")], text=True, capture_output=True)
                self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual((output / "original.pdf").read_bytes(), (output / "reader.pdf").read_bytes())
        self.assertEqual((self.project.root / entry).read_bytes(), before)

    def test_canvas_endpoint_caches_and_rejects_changed_sources_and_revisions(self):
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary)
            source = output / "source"
            source.mkdir()
            shutil.copyfile(self.project.root / self.project.entry, source / "main.typ")
            state = ReaderState(Project(source, Path("main.typ"), self.packages, compiler=self.compiler),
                                output / "build", "https://example.test/original", True)
            state.compile()
            revision = state.revision
            self.assertIsNotNone(revision, state.report)
            server = ThreadingHTTPServer(("127.0.0.1", 0), handler_for(state))
            worker = threading.Thread(target=server.serve_forever, daemon=True)
            worker.start()
            url = f"http://127.0.0.1:{server.server_port}/api/canvases"
            def post(width=280, rev=revision, drawings=None):
                return Request(url, json.dumps({"revision": rev, "canvases": drawings or request(width)}).encode(),
                               {"Content-Type": "application/json"})
            try:
                with urlopen(post(drawings=request() | {"canvas-2": {"width": 280, "fontSize": 18}})) as response:
                    result = json.load(response)
                self.assertEqual(result["canvases"]["canvas-1"]["layout"]["status"], "width-fit")
                # A canvas rendered in a larger batch must also be cached when
                # the viewport later requests it alone.
                result["canvases"].pop("canvas-2")
                with patch("serve.compile_project", side_effect=AssertionError("Cached canvas recompiled")):
                    with urlopen(post()) as response:
                        self.assertEqual(json.load(response), result)
                (source / "main.typ").write_text("#not-a-function()")
                state.compile()
                self.assertEqual(state.revision, revision)
                for bad in [post(300), post(rev="stale")]:
                    with self.assertRaises(HTTPError) as error:
                        urlopen(bad)
                    self.assertEqual(error.exception.code, 409)
                    error.exception.close()
                with urlopen(post()) as response:
                    self.assertEqual(json.load(response), result)
            finally:
                server.shutdown()
                server.server_close()
                worker.join()
