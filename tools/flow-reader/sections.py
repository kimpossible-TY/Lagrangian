"""Deliver bounded reading sections while retaining every document anchor."""

from dataclasses import dataclass
import base64
import hashlib
from html import escape
import json
import re
from xml.etree import ElementTree as ET

from content import MathHtmlEmbedding, SvgRanges
from passages import PassageIndex


class AssetSvgRanges(SvgRanges):
    """Native figure geometry must stay inspectable for label placement."""

    def __init__(self, source):
        super().__init__(source)
        self.stack = []
        self.inline = set()

    def handle_starttag(self, tag, attrs):
        native = (self.stack and self.stack[-1][1]) or (
            "flow-canvas-stage" in dict(attrs).get("class", "").split())
        if tag == "svg" and self.depth == 0 and native:
            self.inline.add(self.source_offset())
        if tag not in MathHtmlEmbedding.VOID:
            self.stack.append((tag, native))
        super().handle_starttag(tag, attrs)

    def handle_endtag(self, tag):
        super().handle_endtag(tag)
        if self.stack and self.stack[-1][0] == tag:
            self.stack.pop()

    def handle_startendtag(self, tag, attrs):
        if tag == "svg" and self.depth == 0 and self.stack and self.stack[-1][1]:
            self.inline.add(self.source_offset())
        super().handle_startendtag(tag, attrs)


def separate_assets(source):
    """Keep large vector drawings out of the reader DOM without rasterizing them."""
    parser = AssetSvgRanges(source)
    parser.feed(source)
    assets = {}
    pieces = []
    previous = 0
    for start, end in parser.ranges:
        svg = source[start:end]
        if len(svg) < 30000 or start in parser.inline:
            continue
        root = ET.fromstring(svg)
        ids = {node.get("id") for node in root.iter()}
        # Document links inside an image cannot navigate the surrounding reader.
        # Such islands must remain inline so the normal anchor handler sees them.
        links = [value for node in root.iter() for key, value in node.attrib.items()
                 if key in {"href", "{http://www.w3.org/1999/xlink}href"}]
        if any(node.tag == "{http://www.w3.org/2000/svg}a" for node in root.iter()) or any(
            value.startswith("#") and value[1:] not in ids for value in links
        ):
            continue
        identifier = hashlib.sha256(svg.encode()).hexdigest() + ".svg"
        assets[identifier] = svg.encode()
        attrs = {key: root.get(key) for key in ("width", "height", "style", "class") if root.get(key)}
        attrs.update(src=f"api/assets/{identifier}", loading="lazy", decoding="async",
                     alt=root.get("aria-label", "벡터 그림"))
        image = "<img " + " ".join(f'{key}="{escape(value, quote=True)}"' for key, value in attrs.items()) + ">"
        pieces.extend((source[previous:start], image))
        previous = end
    pieces.append(source[previous:])
    return separate_data_images("".join(pieces), assets), assets


class DataImages(SvgRanges):
    def __init__(self, source, assets):
        super().__init__(source)
        self.assets = assets
        self.replacements = []

    def handle_starttag(self, tag, attrs):
        if tag != "img":
            return
        attributes = dict(attrs)
        source = attributes.get("src", "")
        for mime, extension in (("image/png", "png"), ("image/jpeg", "jpg"),
                                ("image/webp", "webp"), ("image/gif", "gif")):
            prefix = f"data:{mime};base64,"
            if source.startswith(prefix):
                content = base64.b64decode(source[len(prefix):], validate=True)
                identifier = hashlib.sha256(content).hexdigest() + "." + extension
                self.assets[identifier] = content
                attributes.update(src=f"api/assets/{identifier}", loading="lazy", decoding="async")
                image = "<img " + " ".join(
                    f'{key}="{escape(value, quote=True)}"' if value is not None else key
                    for key, value in attributes.items()) + ">"
                offset = self.source_offset()
                self.replacements.append((offset, offset + len(self.get_starttag_text()), image))
                break

    handle_startendtag = handle_starttag


def separate_data_images(source, assets):
    parser = DataImages(source, assets)
    parser.feed(source)
    pieces, previous = [], 0
    for start, end, image in parser.replacements:
        pieces.extend((source[previous:start], image))
        previous = end
    pieces.append(source[previous:])
    return "".join(pieces)


def heading_level(tag, attributes):
    """Read native headings and Typst's deeper ARIA heading exports."""
    if tag in {"h1", "h2", "h3", "h4", "h5", "h6"}:
        return int(tag[1])
    if attributes.get("role") == "heading" and re.fullmatch(r"[1-9][0-9]*", attributes.get("aria-level", "")):
        return int(attributes["aria-level"])
    return None


class BlockIdentifiers(SvgRanges):
    """Assign reading keys before partitioning, independent of section numbers."""

    def __init__(self, source):
        super().__init__(source)
        self.stack = []
        self.active = []
        self.canvas_scopes = []
        self.heading = "document"
        self.counts = {}
        self.insertions = []

    def handle_starttag(self, tag, attrs):
        attributes = dict(attrs)
        classes = attributes.get("class", "").split()
        level = heading_level(tag, attributes)
        if "data-flow-canvas-identity" in attributes:
            self.canvas_scopes.append((len(self.stack), attributes["data-flow-canvas-identity"]))
        if "body" in self.stack and not {"math", "svg", "nav"}.intersection(self.stack) and (
            level or tag in {"p", "figcaption", "td", "th"}
            or (tag == "div" and {"flow-equation", "flow-canvas-label-body"}.intersection(classes))
        ):
            for parent in self.active:
                if parent.get("native_label") or parent.get("table_cell"):
                    parent["child_block"] = True
            self.active.append({"depth": len(self.stack), "tag": tag, "text": [],
                                "heading_level": level,
                                "id": attributes.get("id"), "heading": self.heading,
                                "canvas_scope": self.canvas_scopes[-1][1] if self.canvas_scopes else "",
                                "native_label": "flow-canvas-label-body" in classes,
                                "table_cell": tag in {"td", "th"},
                                "position": self.source_offset() + len(self.get_starttag_text()) - 1})
        if tag not in MathHtmlEmbedding.VOID:
            self.stack.append(tag)

    def handle_startendtag(self, tag, attrs):
        self.handle_starttag(tag, attrs)
        if tag not in MathHtmlEmbedding.VOID:
            self.handle_endtag(tag)

    def handle_endtag(self, tag):
        if not self.stack or self.stack[-1] != tag:
            return
        self.stack.pop()
        if self.canvas_scopes and self.canvas_scopes[-1][0] == len(self.stack):
            self.canvas_scopes.pop()
        if self.active and self.active[-1]["depth"] == len(self.stack):
            node = self.active.pop()
            if (node.get("native_label") or node.get("table_cell")) and node.get("child_block"):
                return
            text = " ".join("".join(node["text"]).split())
            # Named labels are explicit stable identities. Typst's generated
            # loc-N labels shift after edits, so use contextual text for those.
            label = node["id"]
            heading = node["heading"] + ("\nfigure:" + node["canvas_scope"] if node["canvas_scope"] else "")
            identity = f"label:{label}" if label and not re.fullmatch(r"loc-\d+", label) else (
                heading + "\n" + tag + "\n" + text)
            digest = hashlib.sha256(identity.encode()).hexdigest()[:20]
            count = self.counts.get(digest, 0) + 1
            self.counts[digest] = count
            key = f"reader-{digest}-{count}"
            attributes = f' data-reader-key="{key}"'
            if not label:
                attributes += f' id="{key}"'
            self.insertions.append((node["position"], attributes))
            if node["heading_level"]:
                self.heading = text

    def handle_data(self, data):
        for node in self.active:
            node["text"].append(data)


def assign_block_ids(source):
    parser = BlockIdentifiers(source)
    parser.feed(source)
    pieces, previous = [], 0
    for position, attributes in sorted(parser.insertions):
        pieces.extend((source[previous:position], attributes))
        previous = position
    pieces.append(source[previous:])
    return "".join(pieces)


class BodyIndex(SvgRanges):
    def __init__(self, source):
        super().__init__(source)
        self.stack = []
        self.starts = []
        self.anchors = {}
        self.blocks = {}
        self.marks = {}
        self.canvas_identities = {}
        self.unsplittable = set()
        self.headings = []
        self.heading = None
        self.body_start = self.body_end = None
        self.language = None

    def handle_starttag(self, tag, attrs):
        attributes = dict(attrs)
        offset = self.source_offset()
        if tag in {"html", "body"} and "lang" in attributes:
            self.language = attributes["lang"]
        if tag == "body":
            self.body_start = offset + len(self.get_starttag_text())
        elif self.stack == ["html", "body"] or self.stack == ["body"]:
            self.starts.append(offset)
        index = len(self.starts) - 1
        in_body = "body" in self.stack
        if in_body and index >= 0:
            if (identifier := attributes.get("id")) and "svg" not in self.stack:
                self.anchors[identifier] = index
            if key := attributes.get("data-reader-key"):
                self.blocks[key] = index
            if identity := attributes.get("data-flow-canvas-identity"):
                self.canvas_identities.setdefault(identity, set()).add(index)
            if mark := attributes.get("data-flow-mark"):
                self.marks[mark] = index
            if targets := attributes.get("data-flow-targets"):
                for target in json.loads(targets):
                    if target not in self.marks:
                        raise ValueError(f"Annotation precedes its marked term: {target}")
                    # A section cut cannot separate a note from a preceding term.
                    self.unsplittable.update(range(self.marks[target] + 1, index + 1))
            level = heading_level(tag, attributes)
            if level and not {"nav", "svg", "math"}.intersection(self.stack):
                self.heading = {"id": attributes.get("id"), "level": level, "tag": tag, "depth": len(self.stack),
                                "text": "", "block": index}
        if tag not in MathHtmlEmbedding.VOID:
            self.stack.append(tag)

    def handle_startendtag(self, tag, attrs):
        self.handle_starttag(tag, attrs)
        if tag not in MathHtmlEmbedding.VOID:
            self.handle_endtag(tag)

    def handle_endtag(self, tag):
        if tag == "body":
            self.body_end = self.source_offset()
        if self.heading and tag == self.heading["tag"] and len(self.stack) == self.heading["depth"] + 1:
            self.heading["text"] = " ".join(self.heading["text"].split())
            self.headings.append(self.heading)
            self.heading = None
        if self.stack and self.stack[-1] == tag:
            self.stack.pop()

    def handle_data(self, data):
        if self.heading:
            self.heading["text"] += data


@dataclass
class SectionBundle:
    manifest: dict
    documents: dict[str, bytes]
    assets: dict[str, bytes]
    passages: list[dict]


def split_document(source, revision, max_chars=180000, max_blocks=140):
    source, assets = separate_assets(source)
    source = assign_block_ids(source)
    index = BodyIndex(source)
    index.feed(source)
    if index.body_start is None or index.body_end is None or not index.starts:
        raise ValueError("The reader needs a non-empty HTML body")
    starts = [index.body_start, *index.starts[1:], index.body_end]
    heading_blocks = {heading["block"] for heading in index.headings}
    cuts = [0]
    for block in range(1, len(index.starts)):
        size = starts[block] - starts[cuts[-1]]
        if block not in index.unsplittable and (
            size >= max_chars or block - cuts[-1] >= max_blocks
            or (size >= 25000 and block in heading_blocks)
        ):
            cuts.append(block)
    cuts.append(len(index.starts))
    documents, block_sections, sections = {}, {}, []
    for number, (first, last) in enumerate(zip(cuts, cuts[1:])):
        identifier = f"section-{number}"
        body = source[starts[first]:starts[last]]
        documents[identifier] = (source[:index.body_start] + body + source[index.body_end:]).encode()
        for block in range(first, last):
            block_sections[block] = identifier
        headings = [heading for heading in index.headings if first <= heading["block"] < last]
        prior = [heading for heading in index.headings if heading["block"] <= first]
        title = (headings[0] if headings else prior[-1] if prior else {}).get("text", "처음")
        if body.lstrip().startswith('<section role="doc-endnotes"'):
            title = "각주"
        sections.append({"id": identifier, "title": title, "bytes": len(documents[identifier])})
    anchors = {anchor: block_sections[block] for anchor, block in index.anchors.items()}
    outline = [{"id": heading["id"], "title": heading["text"], "level": heading["level"],
                "section": block_sections[heading["block"]]}
               for heading in index.headings if heading["id"]]
    blocks = {key: block_sections[block] for key, block in index.blocks.items()}
    canvas_sections = {identity: {block_sections[block] for block in entries}
                       for identity, entries in index.canvas_identities.items()}
    canvas_sections = {identity: next(iter(entries)) for identity, entries in canvas_sections.items()
                       if len(entries) == 1}
    return SectionBundle({"revision": revision, "language": index.language,
                          "sections": sections, "anchors": anchors,
                          "blocks": blocks, "canvasIdentities": canvas_sections, "outline": outline}, documents, assets,
                         PassageIndex(source, blocks).passages)
