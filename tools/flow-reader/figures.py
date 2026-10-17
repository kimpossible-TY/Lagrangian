"""Identify native figures independently of generated counters and SVG IDs."""

import hashlib
import json
import re
from xml.etree import ElementTree as ET

from content import MathHtmlEmbedding, SvgRanges


def geometry_identity(source):
    root = ET.fromstring(source)
    identifiers = {node.get("id"): f"node-{i}" for i, node in enumerate(root.iter())
                   if node.get("id")}

    def value(key, text):
        if key == "id":
            return identifiers[text]
        if key in {"href", "{http://www.w3.org/1999/xlink}href"} and text.startswith("#"):
            return "#" + identifiers.get(text[1:], text[1:])
        return re.sub(r"url\(\s*(['\"]?)#([^)'\"\s]+)\1\s*\)",
                      lambda match: f"url(#{identifiers.get(match[2], match[2])})", text)

    def canonical(node):
        return (node.tag, sorted((key, value(key, text)) for key, text in node.attrib.items()),
                node.text if node.text and node.text.strip() else "",
                [canonical(child) for child in node])

    data = json.dumps(canonical(root), ensure_ascii=False, separators=(",", ":"))
    return hashlib.sha256(data.encode()).hexdigest()


class NativeGeometry(SvgRanges):
    def __init__(self, source):
        super().__init__(source)
        self.stack = []
        self.figures = []
        self.owner = None

    def handle_starttag(self, tag, attrs):
        attributes = dict(attrs)
        canvas = self.stack[-1][1] if self.stack else None
        stage = self.stack[-1][2] if self.stack else None
        if "data-flow-canvas-model" in attributes:
            canvas = {"start": self.source_offset(), "tag": self.get_starttag_text()}
            self.figures.append(canvas)
        if "flow-canvas-stage" in attributes.get("class", "").split():
            stage = canvas
        if tag == "svg" and self.depth == 0:
            self.owner = stage
        super().handle_starttag(tag, attrs)
        if tag not in MathHtmlEmbedding.VOID:
            self.stack.append((tag, canvas, stage))

    def handle_endtag(self, tag):
        super().handle_endtag(tag)
        if tag == "svg" and self.depth == 0 and self.owner is not None:
            start, end = self.ranges[-1]
            if "identity" in self.owner:
                raise ValueError("Native figure has multiple geometry roots")
            self.owner["identity"] = geometry_identity(self.source[start:end])
            self.owner = None
        if self.stack and self.stack[-1][0] == tag:
            self.stack.pop()

    def handle_startendtag(self, tag, attrs):
        self.handle_starttag(tag, attrs)
        if tag not in MathHtmlEmbedding.VOID:
            self.handle_endtag(tag)


def stamp_canvas_identities(source):
    parser = NativeGeometry(source)
    parser.feed(source)
    pieces, previous = [], 0
    for figure in parser.figures:
        if "identity" not in figure:
            raise ValueError("Native figure is missing its geometry")
        tag = re.sub(r"\sdata-flow-canvas-identity=(?:\"[^\"]*\"|'[^']*')", "", figure["tag"])
        tag = tag[:-1] + f' data-flow-canvas-identity="{figure["identity"]}">'
        start = figure["start"]
        pieces.extend((source[previous:start], tag))
        previous = start + len(figure["tag"])
    pieces.append(source[previous:])
    return "".join(pieces)
