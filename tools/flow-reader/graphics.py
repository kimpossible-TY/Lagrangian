"""Render original CeTZ annotation programs against measured browser geometry."""

import json
import math
from xml.etree import ElementTree as ET

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
            fragments = bounds.get("fragments", [bounds])
            if not isinstance(fragments, list) or not 1 <= len(fragments) <= 256:
                raise ValueError("Expected between 1 and 256 marker fragments")
            rectangles = []
            for fragment in fragments:
                if not isinstance(fragment, dict):
                    raise ValueError("Expected marker fragment bounds")
                x = number(fragment.get("x"), 0, width)
                y = number(fragment.get("y"), 0, height)
                w = number(fragment.get("width"), 0.01, width)
                h = number(fragment.get("height"), 0.01, height)
                if x + w > width + 1 or y + h > height + 1:
                    raise ValueError("Marker extends beyond its scene")
                rectangles.append({"x": x, "y": y, "width": w, "height": h})
            clean[tag] = {"fragments": rectangles} if "fragments" in bounds else rectangles[0]
        result[identifier] = {"width": width, "height": height, "markers": clean}
        if "fontSize" in geometry:
            result[identifier]["fontSize"] = number(geometry["fontSize"], 13, 30)
        if "routes" in geometry:
            routes = geometry["routes"]
            if not isinstance(routes, dict) or not 1 <= len(routes) <= 64:
                raise ValueError("Expected between 1 and 64 connector routes")
            clean_routes = {}
            outset = geometry.get("fontSize", 18) * 6
            for connector, points in routes.items():
                if (not isinstance(connector, str) or not connector.startswith("connector-")
                        or not connector[10:].isdigit() or not 1 <= int(connector[10:]) <= 64):
                    raise ValueError("Unknown connector route identifier")
                if not isinstance(points, list) or not 2 <= len(points) <= 64:
                    raise ValueError("Expected between 2 and 64 route points")
                clean_routes[connector] = []
                for point in points:
                    if not isinstance(point, dict):
                        raise ValueError("Expected a numeric route point")
                    clean_routes[connector].append({"x": number(point.get("x"), 0, width),
                                                    "y": number(point.get("y"), -outset, height + outset)})
            result[identifier]["routes"] = clean_routes
    return result


class GraphicSvgExtractor(SvgRanges):
    def __init__(self, source):
        super().__init__(source)
        self.stack = []
        self.graphic = None
        self.graphics = {}
        self.layouts = {}

    def handle_starttag(self, tag, attrs):
        attributes = dict(attrs)
        graphic = attributes.get("data-flow-graphic")
        if graphic and attributes.get("data-flow-rendered") == "true":
            self.graphic = graphic
            self.layouts[graphic] = json.loads(attributes["data-flow-graphic-layout"])
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
    result = {}
    for identifier, source_svg in parser.graphics.items():
        svg = ET.fromstring(namespace_svg_ids(source_svg, f"flow-{namespace}-{identifier}"))
        layout = parser.layouts[identifier]
        svg.set("data-flow-graphic-layout", json.dumps(layout, separators=(",", ":")))
        svg.set("width", str(layout["width"]))
        svg.set("height", str(layout["height"]))
        svg.set("style", f'width:{layout["width"]}px;height:{layout["height"]}px;overflow:visible')
        result[identifier] = ET.tostring(svg, encoding="unicode")
    return result
