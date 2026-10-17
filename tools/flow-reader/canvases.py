"""Render existing CeTZ programs at a reader width without rewriting coordinates."""

import json
import math
from xml.etree import ElementTree as ET

from content import MathHtmlEmbedding, SvgRanges, namespace_svg_ids


def validate_canvases(requests, known):
    if not isinstance(requests, dict) or not 1 <= len(requests) <= 32:
        raise ValueError("Expected between 1 and 32 canvases")
    result = {}
    for identifier, request in requests.items():
        if identifier not in known or not isinstance(request, dict):
            raise ValueError("Unknown canvas")
        clean = {}
        for key, minimum, maximum in (("width", 32, 4096), ("fontSize", 13, 30)):
            value = request.get(key)
            if (isinstance(value, bool) or not isinstance(value, (int, float))
                    or not math.isfinite(value) or not minimum <= value <= maximum):
                raise ValueError(f"Unsupported canvas {key}")
            clean[key] = round(value, 3)
        result[identifier] = clean
    return result


class CanvasExtractor(SvgRanges):
    def __init__(self, source):
        super().__init__(source)
        self.stack = []
        self.active = None
        self.canvases = {}

    def handle_starttag(self, tag, attrs):
        attributes = dict(attrs)
        canvas = attributes.get("data-flow-canvas")
        if canvas and "data-flow-canvas-layout" in attributes:
            self.active = (canvas, json.loads(attributes["data-flow-canvas-layout"]))
        if tag not in MathHtmlEmbedding.VOID:
            self.stack.append((tag, canvas))
        super().handle_starttag(tag, attrs)

    def handle_endtag(self, tag):
        super().handle_endtag(tag)
        if tag == "svg" and self.depth == 0 and self.active:
            identifier, layout = self.active
            start, end = self.ranges[-1]
            self.canvases[identifier] = {"layout": layout, "svg": self.source[start:end]}
        if self.stack and self.stack[-1][0] == tag:
            _, canvas = self.stack.pop()
            if canvas:
                self.active = None


def extract_canvases(source, requested, namespace):
    parser = CanvasExtractor(source)
    parser.feed(source)
    if set(parser.canvases) != set(requested):
        raise ValueError("The compiler did not produce every requested canvas")
    result = {}
    for identifier, record in parser.canvases.items():
        svg = ET.fromstring(namespace_svg_ids(record["svg"], f"flow-{namespace}-{identifier}"))
        # html.frame emits em-based dimensions. Use the measured physical size
        # instead so the browser's inherited font cannot scale the baked glyphs.
        layout = record["layout"]
        svg.set("width", str(layout["width"]))
        svg.set("height", str(layout["height"]))
        svg.set("style", f'width:{layout["width"]}px;height:{layout["height"]}px;overflow:visible')
        result[identifier] = {"layout": layout, "svg": ET.tostring(svg, encoding="unicode")}
    return result
