"""Loss-aware translation of an already accepted SectionBundle; no I/O or authority.

NA01 owns schema 1. The caller retains publication locks and accepted-input checks.
Assets are returned separately for the existing revision-bound asset delivery owner.
"""
from __future__ import annotations

from dataclasses import dataclass
import base64
import binascii
import hashlib
from html import escape
from html.parser import HTMLParser
import json
import math
import re
from urllib.parse import urlsplit

from flow_reader.document.sections import heading_level


SUPPORTED_CAPABILITIES = frozenset({"semantic-tree-v1", "image-layout-v1"})
IMAGE_LAYOUT_CAPABILITY = "image-layout-v1"


class NativeImportError(ValueError):
    """A bounded code only: never echo source, private paths or exception details."""


@dataclass(frozen=True)
class ImportedNativeDocument:
    document: dict
    assets: dict[str, bytes]


class _Element:
    def __init__(self, tag, attrs=()):
        self.tag, self.attrs, self.children = tag, dict(attrs), []

    def text(self):
        if self.tag == "br":
            return "\n"
        return "".join(c if isinstance(c, str) else c.text() for c in self.children)


class _Tree(HTMLParser):
    VOID = {"area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param", "source", "track", "wbr"}

    def __init__(self, html):
        super().__init__(convert_charrefs=True)
        self.root = _Element("root")
        self.stack = [self.root]
        self.feed(html)
        self.close()
        if len(self.stack) != 1:
            raise NativeImportError("malformed-html")

    def handle_starttag(self, tag, attrs):
        if len(self.stack) > 128 or len(dict(attrs)) != len(attrs):
            raise NativeImportError("invalid-html-structure")
        n = _Element(tag, attrs)
        self.stack[-1].children.append(n)
        if tag not in self.VOID:
            self.stack.append(n)

    def handle_startendtag(self, tag, attrs):
        self.handle_starttag(tag, attrs)
        if tag not in self.VOID:
            self.handle_endtag(tag)

    def handle_endtag(self, tag):
        if len(self.stack) < 2 or self.stack[-1].tag != tag:
            raise NativeImportError("malformed-html")
        self.stack.pop()

    def handle_decl(self, decl):
        if decl.lower() != "doctype html" or len(self.stack) != 1:
            raise NativeImportError("unsupported-declaration")

    def unknown_decl(self, data):
        raise NativeImportError("unsupported-declaration")

    def handle_data(self, value):
        self.stack[-1].children.append(value)


def _walk(n):
    yield n
    for child in n.children:
        if isinstance(child, _Element):
            yield from _walk(child)


def _offsets(text):
    u8, u16 = [0], [0]
    for c in text:
        u8.append(u8[-1] + len(c.encode("utf-8")))
        u16.append(u16[-1] + len(c.encode("utf-16-le")) // 2)
    return {"scalars": [ord(c) for c in text], "cpToUTF8": u8, "cpToUTF16": u16}


def _token(value):
    if not isinstance(value, str) or not re.fullmatch(r"[A-Za-z0-9_.:-]{1,128}", value):
        raise NativeImportError("invalid-identity")
    return value


# Serialized MathML remains semantic input for NA03, never executable HTML.
_MATH_TAGS = set("math mrow mi mn mo ms mtext mspace msup msub msubsup mfrac msqrt mroot mover munder munderover mtable mtr mtd menclose mpadded mphantom semantics annotation".split())
_MATH_ATTRS = set("xmlns display mathvariant mathsize mathcolor mathbackground scriptlevel displaystyle lspace rspace form stretchy symmetric fence separator accent accentunder notation columnalign rowalign columnspacing rowspacing rowspan columnspan width height depth voffset linethickness class data-flow-math-kind encoding".split())


def _mathml(n):
    if n.tag not in _MATH_TAGS or set(n.attrs) - _MATH_ATTRS:
        raise NativeImportError("unsupported-mathml")
    attrs = "".join(' ' + k + '="' + escape(v or "", quote=True) + '"' for k, v in n.attrs.items())
    return "<" + n.tag + attrs + ">" + "".join(escape(c) if isinstance(c, str) else _mathml(c) for c in n.children) + "</" + n.tag + ">"


def _svg(n):
    tags = {t.lower(): t for t in "svg g path defs symbol use rect circle ellipse line polyline polygon clipPath linearGradient radialGradient stop".split()}
    names = {a.lower(): a for a in "xmlns xmlns:xlink aria-label viewBox preserveAspectRatio width height x y x1 y1 x2 y2 cx cy r rx ry d points transform id fill fill-rule fill-opacity stroke stroke-width stroke-linecap stroke-linejoin stroke-miterlimit stroke-dasharray stroke-dashoffset stroke-opacity opacity clip-path clip-rule clipPathUnits gradientUnits gradientTransform offset stop-color stop-opacity href xlink:href style class overflow".split()}
    elements = list(_walk(n))
    if len(elements) > 20000:
        raise NativeImportError("svg-budget")
    ids = {}
    for e in elements:
        if "id" in e.attrs:
            identifier = _token(e.attrs["id"])
            if identifier in ids:
                raise NativeImportError("duplicate-svg-id")
            ids[identifier] = e
    references = {}
    for e in elements:
        refs = []
        for k, v in e.attrs.items():
            if k == "overflow" and (e.tag != "symbol" or v not in {"visible", "hidden"}):
                raise NativeImportError("unsupported-svg-overflow")
            if k == "style":
                # Geometry/paint validation remains with the existing native SVG
                # owner. The wire subset never accepts arbitrary CSS.
                allowed = {"fill", "stroke", "fill-opacity", "stroke-opacity", "opacity", "stroke-width", "clip-path", "fill-rule", "clip-rule"}
                for declaration in (v or "").split(";"):
                    if not declaration.strip():
                        continue
                    parts = declaration.split(":")
                    if len(parts) != 2:
                        raise NativeImportError("unsupported-svg-style")
                    key, value = (p.strip() for p in parts)
                    if key in {"width", "height"} and e.tag == "svg" and re.fullmatch(r"[0-9]+(?:\.[0-9]+)?(?:em|pt|px)", value):
                        continue
                    if key == "display" and e.tag == "svg" and value == "block":
                        continue
                    if key == "overflow" and e.tag == "svg" and value == "visible":
                        continue
                    if key not in allowed:
                        raise NativeImportError("unsupported-svg-style")
            if k in {"href", "xlink:href"} or "url(" in (v or "").lower():
                match = re.fullmatch(r"#([A-Za-z0-9_.:-]{1,128})" if k in {"href", "xlink:href"} else r"url\(#([A-Za-z0-9_.:-]{1,128})\)", v or "")
                if not match or match[1] not in ids:
                    raise NativeImportError("unresolved-or-external-svg-reference")
                refs.append(ids[match[1]])
        references[e] = refs
    work = 0
    def check(e, active, depth):
        nonlocal work
        work += 1
        if e in active or depth > 128:
            raise NativeImportError("svg-reference-cycle-or-depth")
        if work > 300000:
            raise NativeImportError("svg-budget")
        for child in [c for c in e.children if isinstance(c, _Element)] + references[e]:
            check(child, active | {e}, depth + 1)
    check(n, set(), 0)
    def xml(e):
        if e.tag not in tags or set(e.attrs) - names.keys():
            raise NativeImportError("unsupported-svg-primitive")
        for k, v in e.attrs.items():
            if k in {"href", "xlink:href"} and not (v or "").startswith("#"):
                raise NativeImportError("external-svg-reference")
            if k == "style" and ("url(" in (v or "").lower() or "@" in (v or "")):
                raise NativeImportError("external-svg-style")
            if "url(" in (v or "").lower() and not re.fullmatch(r"url\(#[A-Za-z0-9_.:-]+\)", v):
                raise NativeImportError("external-svg-reference")
        tag = tags[e.tag]
        return "<" + tag + "".join(' ' + names[k] + '="' + escape(v or "", quote=True) + '"' for k, v in e.attrs.items()) + ">" + "".join(escape(c) if isinstance(c, str) else xml(c) for c in e.children) + "</" + tag + ">"
    return xml(n)



def _image_layout(attrs, *, natural_unit, svg_overflow=False, svg=False):
    """HTML pixels are CSS px (96/in); compiler style pt is logical 72/in.

    Two explicit dimensions use HTML's default object-fit:fill. One dimension
    derives the other from the intrinsic ratio. No implicit responsive shrinking.
    Scheduling hints survive; bytes are eagerly prepared before native adoption.
    """
    if not svg_overflow and not set(attrs) & {"width", "height", "style", "loading", "decoding"}:
        return None
    if any(attrs[key] is None for key in {"width", "height", "style", "loading", "decoding"} & attrs.keys()):
        raise NativeImportError("invalid-image-attribute")
    def length(raw, css=False):
        if raw is None:
            return None
        match = re.fullmatch(r"([0-9]+(?:\.[0-9]+)?)(px|pt|em)" if css else r"([0-9]+(?:\.[0-9]+)?)", raw)
        if not match:
            raise NativeImportError("unsupported-image-length")
        value = float(match[1])
        if not math.isfinite(value) or not 0 < value <= 4096:
            raise NativeImportError("image-layout-budget")
        return {"value": value, "unit": match[2] if css else "px"}
    layout = {"naturalUnit": natural_unit, "placement": "inline", "fit": "fill"}
    for key in ["width", "height"]:
        if key in attrs:
            layout[key] = length(attrs[key], css=svg and bool(re.search(r"[a-z]$", attrs[key])))
    seen = set()
    for declaration in attrs.get("style", "").split(";"):
        if not declaration.strip():
            continue
        parts = [p.strip() for p in declaration.split(":")]
        if len(parts) != 2 or parts[0] in seen:
            raise NativeImportError("unsupported-image-style")
        key, value = parts
        seen.add(key)
        if key == "display" and value in {"inline", "block"}:
            layout["placement"] = value
        elif key in {"width", "height"}:
            layout[key] = length(value, css=True)
        elif svg and key == "overflow" and value == "visible":
            pass  # Preserved by the SVG scene, not a layout property.
        else:
            raise NativeImportError("unsupported-image-style")
    for key, allowed in [("loading", {"lazy", "eager"}), ("decoding", {"async", "sync", "auto"})]:
        if key in attrs:
            if attrs[key] not in allowed:
                raise NativeImportError("unsupported-image-" + key)
            layout[key] = attrs[key]
    return layout

def import_accepted_document(bundle, *, document_id: str, service_id: str,
                             generation: int, identity_scope: str = "service",
                             required_capabilities=("semantic-tree-v1",)) -> ImportedNativeDocument:
    """Translate manifest section order, not dictionary order or passage order.

    identity_scope='fixture' must be used without an observed service. This function
    does not establish server freshness. Unknown meaning fails the whole candidate.
    All ranges are block-local, half-open UTF16 over exact accepted HTML scalars.
    """
    revision = _token(bundle.manifest["revision"])
    if type(generation) is not int or generation < 0 or identity_scope not in {"fixture", "service"}:
        raise NativeImportError("invalid-generation-or-scope")
    if set(required_capabilities) - SUPPORTED_CAPABILITIES:
        raise NativeImportError("unsupported-required-capability")
    identity = {"documentID": _token(document_id), "serviceID": _token(service_id),
                "revision": revision, "scope": identity_scope}
    blocks, assets, descriptors, diagnostics, seen_anchors = [], {}, {}, [], set()
    counter = 0
    required = set(required_capabilities) | {"semantic-tree-v1"}

    def asset(data, mime):
        if mime == "image/svg+xml":
            if b"<!" in data:
                raise NativeImportError("unsupported-declaration")
            try:
                tree = _Tree(data.decode("utf-8"))
            except UnicodeError:
                raise NativeImportError("invalid-svg-encoding") from None
            roots = [e for e in tree.root.children if isinstance(e, _Element)]
            if len(roots) != 1 or roots[0].tag != "svg":
                raise NativeImportError("invalid-svg")
            _svg(roots[0])  # Validate, retain original digest-bound bytes.
        digest = hashlib.sha256(data).hexdigest()
        extension = {"image/svg+xml": "svg", "image/png": "png", "image/jpeg": "jpg", "image/webp": "webp", "image/gif": "gif"}.get(mime)
        if not extension:
            raise NativeImportError("unsupported-asset-type")
        key = digest + "." + extension
        assets[key] = data
        descriptors[key] = {"id": key, "sha256": digest, "mime": mime, "byteCount": len(data)}
        return key

    def emit(n, section, base):
        nonlocal counter
        counter += 1
        if counter > 100000:
            raise NativeImportError("node-limit")
        nid = "n" + str(counter)
        text = n if isinstance(n, str) else n.text()
        value = {"id": nid, "sectionID": section, "kind": "text", "canonicalText": text,
                 "displayText": text, "rangeUTF16": [base, base + len(text.encode("utf-16-le")) // 2],
                 "offsets": _offsets(text), "children": [], "anchors": [], "annotationTargets": [],
                 "visible": True, "mapping": "unmapped"}
        if isinstance(n, str):
            return value
        attrs = n.attrs
        common = {"id", "data-reader-key", "class", "role", "aria-level", "lang", "dir"}
        allowed = common | {"a": {"href", "data-project-ref-project", "data-project-ref-label",
                                  "data-project-ref-title", "data-project-ref-page", "data-project-ref-text"},
                            "td": {"colspan", "rowspan"},
                            "th": {"colspan", "rowspan", "scope"},
                            "span": {"data-flow-mark", "data-flow-targets"},
                            "mrow": {"data-flow-mark"},
                            "img": {"src", "alt", "width", "height", "style", "loading", "decoding"}}.get(n.tag, set())
        if n.tag not in {"math", "svg"} and set(attrs) - allowed:
            raise NativeImportError("unsupported-attribute")
        if attrs.get("role") not in {None, "heading"} or (attrs.get("role") == "heading" and heading_level(n.tag, attrs) is None):
            raise NativeImportError("unsupported-role")
        if attrs.get("lang"):
            if not re.fullmatch(r"[A-Za-z]{2,8}(?:-[A-Za-z0-9]{1,8})*", attrs["lang"]):
                raise NativeImportError("unsupported-language")
            value["language"] = attrs["lang"]
        if attrs.get("dir") not in {None, "auto", "ltr", "rtl"}:
            raise NativeImportError("unsupported-direction")
        if attrs.get("dir"):
            value["direction"] = attrs["dir"]
        classes = set(attrs.get("class", "").split())
        known_classes = {"flow-equation", "flow-equation-number", "flow-mark", "flow-annotation", "flow-annotation-body", "flow-drawing"}
        if classes - known_classes and n.tag not in {"math", "svg"}:
            raise NativeImportError("unsupported-class")
        if attrs.get("id"):
            anchor = _token(attrs["id"])
            if anchor in seen_anchors:
                raise NativeImportError("duplicate-anchor")
            seen_anchors.add(anchor)
            value["anchors"].append(anchor)
        if attrs.get("data-flow-mark"):
            value["anchors"].append("mark:" + _token(attrs["data-flow-mark"]))
        if attrs.get("data-flow-targets"):
            try:
                targets = json.loads(attrs["data-flow-targets"])
                if not isinstance(targets, list) or not targets or len(targets) > 32:
                    raise ValueError()
                value["annotationTargets"] = ["mark:" + _token(t) for t in targets]
            except (ValueError, TypeError):
                raise NativeImportError("invalid-annotation") from None
        if attrs.get("data-reader-key"):
            value["passageKey"] = _token(attrs["data-reader-key"])
        kinds = {"p": "paragraph", "strong": "strong", "em": "emphasis", "a": "link", "span": "group",
                 "div": "group", "mrow": "group", "mtext": "group", "table": "table", "thead": "tableHead", "tbody": "tableBody", "tfoot": "tableBody",
                 "tr": "row", "th": "cell", "td": "cell", "figure": "figure", "figcaption": "caption", "br": "break"}
        level = heading_level(n.tag, attrs)
        if level is not None:
            value.update(kind="heading", headingLevel=level)
        elif n.tag in kinds:
            value["kind"] = kinds[n.tag]
        elif n.tag == "math":
            value.update(kind="math", math={"mathML": _mathml(n), "normalizedText": " ".join(text.split()),
                                           "display": attrs.get("display") == "block"})
        elif n.tag == "svg":
            # Preserve compiler vector bytes; do not claim general native SVG support.
            value.update(kind="image", assetID=asset(_svg(n).encode(), "image/svg+xml"), alt=attrs.get("aria-label", ""))
            layout = _image_layout({k: v for k, v in attrs.items() if k in {"style", "width", "height"}},
                natural_unit="pt", svg=True, svg_overflow=any("overflow" in e.attrs for e in _walk(n)))
            if layout is not None:
                value["imageLayout"] = layout
        elif n.tag == "img":
            source = attrs.get("src", "")
            prefix = "data:image/svg+xml;base64,"
            if source.startswith(prefix):
                # SectionBundle already separates raster data images. The native
                # SVG owner validates the same digest-bound bytes for either a
                # compiler SVG data URI or an existing revision asset reference.
                if len(source) > len(prefix) + 4 * ((8 * 1024 * 1024 + 2) // 3):
                    raise NativeImportError("asset-limit")
                try:
                    original = base64.b64decode(source[len(prefix):], validate=True)
                except (binascii.Error, ValueError):
                    raise NativeImportError("invalid-svg-data-image") from None
                if not original or len(original) > 8 * 1024 * 1024:
                    raise NativeImportError("asset-limit")
                mime = "image/svg+xml"
            else:
                match = re.fullmatch(r"api/assets/([0-9a-f]{64}\.(svg|png|jpg|webp|gif))", source)
                if not match or match[1] not in bundle.assets:
                    raise NativeImportError("unresolved-asset")
                mime = {"svg": "image/svg+xml", "png": "image/png", "jpg": "image/jpeg", "webp": "image/webp", "gif": "image/gif"}[match[2]]
                original = bundle.assets[match[1]]
                if hashlib.sha256(original).hexdigest() != match[1].split(".")[0]:
                    raise NativeImportError("asset-digest-mismatch")
            key = asset(original, mime)
            value.update(kind="image", assetID=key, alt=attrs.get("alt", ""))
            overflow = mime == "image/svg+xml" and any("overflow" in e.attrs for e in _walk(_Tree(original.decode("utf-8")).root))
            layout = _image_layout(attrs, natural_unit="pt" if mime == "image/svg+xml" else "px", svg_overflow=overflow)
            if layout is not None:
                value["imageLayout"] = layout
        else:
            raise NativeImportError("unsupported-element")
        if "imageLayout" in value:
            required.add(IMAGE_LAYOUT_CAPABILITY)
        if "flow-equation" in classes:
            value["kind"] = "equation"
        if "flow-equation-number" in classes:
            value["kind"] = "equationNumber"
        if "flow-annotation" in classes:
            value["kind"] = "annotation"
        if n.tag == "a":
            href = attrs.get("href", "")
            url = urlsplit(href)
            if not (href.startswith("#") and len(href) > 1) and not (url.scheme in {"https", "http", "mailto"} and not url.username and not url.password):
                raise NativeImportError("unsafe-link")
            value["link"] = href
            if any(key.startswith("data-project-ref-") for key in attrs):
                project = (attrs.get("data-project-ref-project") or "").strip()
                label = (attrs.get("data-project-ref-label") or "").strip()
                if not project or not label:
                    raise NativeImportError("invalid-project-ref")
                project_ref = {"project": project, "label": label}
                for field in ("title", "text"):
                    optional = (attrs.get("data-project-ref-" + field) or "").strip()
                    if optional:
                        project_ref[field] = optional
                if "data-project-ref-page" in attrs:
                    page = (attrs["data-project-ref-page"] or "").strip()
                    if not re.fullmatch(r"[1-9][0-9]*", page):
                        raise NativeImportError("invalid-project-ref")
                    try:
                        project_ref["page"] = int(page)
                    except ValueError:
                        raise NativeImportError("invalid-project-ref") from None
                value["projectRef"] = project_ref
        if n.tag in {"td", "th"}:
            try:
                row, col = int(attrs.get("rowspan", "1")), int(attrs.get("colspan", "1"))
            except ValueError:
                raise NativeImportError("invalid-cell-span") from None
            if not 1 <= row <= 1000 or not 1 <= col <= 1000:
                raise NativeImportError("invalid-cell-span")
            value["cell"] = {"rowSpan": row, "columnSpan": col, "header": n.tag == "th", "scope": attrs.get("scope")}
        if n.tag not in {"math", "svg", "img", "br"}:
            offset = base
            for c in n.children:
                child = emit(c, section, offset)
                value["children"].append(child)
                offset = child["rangeUTF16"][1]
        if value["kind"] in {"math", "table", "figure", "image"}:
            diagnostics.append({"code": "native-paint-required", "nodeID": nid})
        return value

    sections = bundle.manifest["sections"]
    if len({s["id"] for s in sections}) != len(sections) or set(bundle.documents) != {s["id"] for s in sections}:
        raise NativeImportError("invalid-section-order")
    for section in sections:
        key = _token(section["id"])
        raw = bundle.documents[key]
        if len(raw) > 16 * 1024 * 1024:
            raise NativeImportError("section-limit")
        tree = _Tree(raw.decode("utf-8"))
        bodies = [n for n in _walk(tree.root) if n.tag == "body"]
        if len(bodies) != 1:
            raise NativeImportError("invalid-body")
        for n in bodies[0].children:
            if isinstance(n, str) and not n.strip():
                continue
            if isinstance(n, str):
                raise NativeImportError("unwrapped-body-text")
            blocks.append(emit(n, key, 0))
    all_nodes = []
    def collect(n):
        all_nodes.append(n)
        for c in n["children"]:
            collect(c)
    for b in blocks:
        collect(b)
    anchors = [a for n in all_nodes for a in n["anchors"]]
    if len(set(anchors)) != len(anchors) or any(t not in anchors for n in all_nodes for t in n["annotationTargets"]):
        raise NativeImportError("invalid-anchor-target")
    if not blocks:
        raise NativeImportError("empty-document")
    if IMAGE_LAYOUT_CAPABILITY in required:
        # A supplemented snapshot is complete: a missing per-image supplement
        # cannot look like successful legacy decoding after a lossy DTO copy.
        for n in all_nodes:
            if n["kind"] == "image" and "imageLayout" not in n:
                n["imageLayout"] = {"naturalUnit": "pt", "placement": "inline", "fit": "fill"}
    return ImportedNativeDocument({"schemaVersion": 1, "identity": identity, "generation": generation,
        "requiredCapabilities": sorted(required), "blocks": blocks,
        "assets": list(descriptors.values()), "diagnostics": diagnostics}, assets)
