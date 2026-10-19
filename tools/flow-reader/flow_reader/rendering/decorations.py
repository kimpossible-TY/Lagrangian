"""Render only the authored decoration, keeping mathematical terms in MathML."""

import json
import math
import re
from xml.etree import ElementTree as ET

from flow_reader.document.content import MathHtmlEmbedding, SvgRanges, namespace_svg_ids


def validate_decorations(requests, known):
    if not isinstance(requests, dict) or not 1 <= len(requests) <= 32:
        raise ValueError("Expected between 1 and 32 decorations")

    def number(value, minimum, maximum):
        if (isinstance(value, bool) or not isinstance(value, (int, float))
                or not math.isfinite(value) or not minimum <= value <= maximum):
            raise ValueError("Invalid decoration geometry")
        return round(value, 3)

    result = {}
    for identifier, request in requests.items():
        if identifier not in known or not isinstance(request, dict):
            raise ValueError("Unknown decoration")
        fragments = request.get("fragments")
        if not isinstance(fragments, list) or not 1 <= len(fragments) <= 128:
            raise ValueError("Invalid decoration fragments")
        ink = request.get("ink")
        if not isinstance(ink, str) or not re.fullmatch(r"#[0-9a-fA-F]{6}", ink):
            raise ValueError("Invalid decoration ink")
        clean = []
        for fragment in fragments:
            if not isinstance(fragment, dict):
                raise ValueError("Invalid decoration fragment")
            clean.append({key: number(fragment.get(key), 0.01, 30000)
                          for key in ("width", "height")})
        result[identifier] = {"fontSize": number(request.get("fontSize"), 8, 60),
                              "ink": ink.lower(), "fragments": clean}
    return result


class DecorationExtractor(SvgRanges):
    def __init__(self, source):
        super().__init__(source)
        self.stack = []
        self.active = None
        self.decorations = {}
        self.layers = {}

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if term := attrs.get("data-flow-decoration"):
            self.layers[term] = json.loads(attrs["data-flow-decoration-layers"])
        identifier = attrs.get("data-flow-decoration-rendered")
        if identifier:
            self.active = (identifier, int(attrs["data-flow-decoration-fragment"]),
                           attrs["data-flow-decoration-layer"],
                           json.loads(attrs["data-flow-decoration-layout"]))
        if tag not in MathHtmlEmbedding.VOID:
            self.stack.append((tag, identifier))
        super().handle_starttag(tag, list(attrs.items()))

    def handle_endtag(self, tag):
        super().handle_endtag(tag)
        if tag == "svg" and self.depth == 0 and self.active:
            self.record_svg()
        if self.stack and self.stack[-1][0] == tag:
            _, identifier = self.stack.pop()
            if identifier:
                self.active = None

    def handle_startendtag(self, tag, attrs):
        super().handle_startendtag(tag, attrs)
        if tag == "svg" and self.depth == 0 and self.active:
            self.record_svg()

    def record_svg(self):
        identifier, fragment, layer, layout = self.active
        start, end = self.ranges[-1]
        self.decorations.setdefault(identifier, []).append({
            "fragment": fragment, "layer": layer, "layout": layout,
            "svg": self.source[start:end],
        })


def extract_decorations(source, requested, namespace):
    parser = DecorationExtractor(source)
    parser.feed(source)
    if set(parser.decorations) != set(requested):
        raise ValueError("The compiler did not produce every requested decoration")
    for identifier, drawings in parser.decorations.items():
        expected = {(index, layer) for index in range(len(requested[identifier]["fragments"]))
                    for layer in parser.layers[identifier]}
        actual = {(item["fragment"], item["layer"]) for item in drawings}
        if actual != expected or len(actual) != len(drawings):
            raise ValueError("The compiler omitted or repeated a decoration layer")
        for item in drawings:
            prefix = f'flow-{namespace}-{identifier}-{item["fragment"]}-{item["layer"]}'
            svg = ET.fromstring(namespace_svg_ids(item["svg"], prefix))
            layout = item["layout"]
            svg.set("style", f'width:{layout["width"]}px;height:{layout["height"]}px;overflow:visible')
            item["svg"] = ET.tostring(svg, encoding="unicode")
    return parser.decorations
