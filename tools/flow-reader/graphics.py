"""Render original CeTZ annotation programs against measured browser geometry."""

import math

from content import SvgRanges, namespace_svg_ids


def validate_geometry(graphs: dict, known: dict) -> dict:
    """Accept only finite layout data for graphics in the published revision."""
    if not isinstance(graphs, dict) or not 1 <= len(graphs) <= 32:
        raise ValueError("Expected between 1 and 32 graphical annotations")

    def number(value, minimum, maximum):
        if isinstance(value, bool) or not isinstance(value, (int, float)):
            raise ValueError("Geometry values must be numbers")
        if not math.isfinite(value) or not minimum <= value <= maximum:
            raise ValueError("Geometry value is outside the supported range")
        return round(value, 3)

    result = {}
    for identifier, geometry in graphs.items():
        if identifier not in known or not isinstance(geometry, dict):
            raise ValueError("Unknown graphical annotation")
        width = number(geometry.get("width"), 1, 30000)
        height = number(geometry.get("height"), 1, 30000)
        markers = geometry.get("markers")
        if not isinstance(markers, dict) or set(markers) != set(known[identifier]):
            raise ValueError("Marker set differs from the compiled annotation")
        clean = {}
        for tag, bounds in markers.items():
            if not isinstance(bounds, dict):
                raise ValueError("Expected marker bounds")
            x = number(bounds.get("x"), 0, width)
            y = number(bounds.get("y"), 0, height)
            w = number(bounds.get("width"), 0.01, width)
            h = number(bounds.get("height"), 0.01, height)
            if x + w > width + 1 or y + h > height + 1:
                raise ValueError("Marker extends beyond its scene")
            clean[tag] = {"x": x, "y": y, "width": w, "height": h}
        result[identifier] = {"width": width, "height": height, "markers": clean}
    return result


class GraphicSvgExtractor(SvgRanges):
    def __init__(self, source):
        super().__init__(source)
        self.stack = []
        self.graphic = None
        self.graphics = {}

    def handle_starttag(self, tag, attrs):
        attributes = dict(attrs)
        graphic = attributes.get("data-flow-graphic")
        if graphic and attributes.get("data-flow-rendered") == "true":
            self.graphic = graphic
        if tag not in {"area", "base", "br", "col", "embed", "hr", "img", "input",
                       "link", "meta", "param", "source", "track", "wbr"}:
            self.stack.append((tag, graphic))
        super().handle_starttag(tag, attrs)

    def handle_endtag(self, tag):
        super().handle_endtag(tag)
        if tag == "svg" and self.depth == 0 and self.graphic:
            start, end = self.ranges[-1]
            self.graphics[self.graphic] = self.source[start:end]
        if self.stack and self.stack[-1][0] == tag:
            _, graphic = self.stack.pop()
            if graphic:
                self.graphic = None


def extract_graphics(source: str, requested: dict, namespace: str) -> dict:
    parser = GraphicSvgExtractor(source)
    parser.feed(source)
    if set(parser.graphics) != set(requested):
        raise ValueError("The compiler did not produce every requested graphical annotation")
    return {identifier: namespace_svg_ids(svg, f"flow-{namespace}-{identifier}")
            for identifier, svg in parser.graphics.items()}
