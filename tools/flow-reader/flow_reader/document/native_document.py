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


def _mark(value):
    if not isinstance(value, str):
        raise NativeImportError("invalid-annotation")
    return "mark:" + (value if re.fullmatch(r"[A-Za-z0-9_.:-]{1,128}", value)
                      else "h-" + hashlib.sha256(value.encode("utf-8")).hexdigest()[:24])


def _targets(raw):
    try:
        targets = json.loads(raw) if raw.lstrip().startswith("[") else re.split(r"[\s,]+", raw.strip())
        if not isinstance(targets, list) or not 1 <= len(targets) <= 32 or any(not isinstance(t, str) or not t for t in targets):
            raise ValueError()
        return [_mark(t) for t in targets]
    except (ValueError, TypeError, AttributeError):
        raise NativeImportError("invalid-annotation") from None


def _link(href):
    url = urlsplit(href)
    if not (href.startswith("#") and len(href) > 1) and not (url.scheme in {"https", "http", "mailto"} and not url.username and not url.password):
        raise NativeImportError("unsafe-link")
    return href


# Serialized MathML remains semantic input for NA03, never executable HTML.
_MATH_TAGS = set("math mrow mi mn mo ms mtext mspace msup msub msubsup mfrac msqrt mroot mover munder munderover mtable mtr mtd menclose mpadded mphantom semantics annotation mmultiscripts mprescripts".split())
_MATH_ATTRS = set("xmlns display mathvariant mathsize mathcolor mathbackground scriptlevel displaystyle lspace rspace form stretchy symmetric fence separator accent accentunder notation columnalign rowalign columnspacing rowspacing rowspan columnspan width height depth voffset linethickness class data-flow-math-kind encoding".split())


def _mathml(n):
    if n.tag in {"sup", "a", "br", "code", "span"}:
        allowed = {"id", "class", "data-flow-mark", "data-flow-targets"} | {
            "sup": {"role"}, "a": {"href", "role"}, "br": set(),
            "code": {"data-lang"}, "span": {"style", "data-flow-graphic"}}[n.tag]
        if set(n.attrs) - allowed:
            raise NativeImportError("unsupported-mathml")
        if set(n.attrs.get("class", "").split()) - {"flow-annotation", "flow-graphic", "flow-mark", "flow-annotation-body"}:
            raise NativeImportError("unsupported-mathml")
        if "style" in n.attrs:
            _html_style("span", n.attrs["style"] or "")
        if n.tag == "a":
            _link(n.attrs.get("href", ""))
        if n.attrs.get("role") not in {None, "doc-noteref", "doc-biblioref", "doc-backlink", "mark"}:
            raise NativeImportError("unsupported-mathml")
        body = "".join("<mtext>" + escape(c) + "</mtext>" if isinstance(c, str) else _mathml(c) for c in n.children)
        if n.tag == "sup":
            return "<msup><mrow></mrow><mtext>" + escape(n.text()) + "</mtext></msup>"
        if n.tag == "br":
            return "<mtext>\n</mtext>"
        if n.tag == "code":
            return "<mtext mathvariant=\"monospace\">" + escape(n.text()) + "</mtext>"
        return "<mrow>" + body + "</mrow>"
    attrs = {k: v for k, v in n.attrs.items() if not k.startswith("data-flow-") and k not in {"style", "id"}}
    if n.tag not in _MATH_TAGS or set(attrs) - _MATH_ATTRS:
        raise NativeImportError("unsupported-mathml")
    encoded = "".join(' ' + k + '="' + escape(v or "", quote=True) + '"' for k, v in attrs.items())
    return "<" + n.tag + encoded + ">" + "".join(escape(c) if isinstance(c, str) else _mathml(c) for c in n.children) + "</" + n.tag + ">"


def _color(value):
    match = re.fullmatch(r"oklab\(\s*([+-]?(?:\d+(?:\.\d*)?|\.\d+))%\s+([+-]?(?:\d+(?:\.\d*)?|\.\d+))\s+([+-]?(?:\d+(?:\.\d*)?|\.\d+))\s*\)", value, re.I)
    if not match:
        return value
    light, a, b = (float(x) for x in match.groups())
    if not all(math.isfinite(x) and abs(x) <= 10000 for x in (light, a, b)):
        raise NativeImportError("unsupported-svg-color")
    light /= 100
    l = (light + 0.3963377774*a + 0.2158037573*b) ** 3
    m = (light - 0.1055613458*a - 0.0638541728*b) ** 3
    s = (light - 0.0894841775*a - 1.2914855480*b) ** 3
    rgb = (4.0767416621*l - 3.3077115913*m + 0.2309699292*s,
           -1.2684380046*l + 2.6097574011*m - 0.3413193965*s,
           -0.0041960863*l - 0.7034186147*m + 1.7076147010*s)
    def channel(c):
        c = max(0.0, min(1.0, c))
        return round(255 * (12.92*c if c <= 0.0031308 else 1.055*c**(1/2.4)-0.055))
    return "#%02x%02x%02x" % tuple(map(channel, rgb))


def _html_style(tag, raw):
    allowed = {"span": {"white-space", "display", "font-size", "font-weight", "font-style", "font-family", "text-decoration", "color"},
               "div": {"display", "flex-wrap", "flex-direction", "gap"},
               "ol": {"list-style-type"}, "ul": {"list-style-type"}}
    seen = set()
    for declaration in raw.split(";"):
        if not declaration.strip():
            continue
        parts = declaration.split(":")
        if len(parts) != 2:
            raise NativeImportError("unsupported-style")
        key, value = (part.strip().lower() for part in parts)
        if key not in allowed.get(tag, set()) or key in seen or not re.fullmatch(r"[a-z0-9#.,%() +\-]+", value) or any(x in value for x in ("url(", "expression(", "position", "behavior", "@import")):
            raise NativeImportError("unsupported-style")
        if tag == "div" and key == "display" and value != "flex":
            raise NativeImportError("unsupported-style")
        if key in {"font-family", "text-decoration"} and value not in {
                "font-family": {"sans-serif", "serif", "monospace"},
                "text-decoration": {"underline", "none", "line-through"}}[key]:
            raise NativeImportError("unsupported-style")
        seen.add(key)


def _svg(n):
    tags = {t.lower(): t for t in "svg g path defs symbol use rect circle ellipse line polyline polygon clipPath linearGradient radialGradient stop image".split()}
    names = {a.lower(): a for a in "xmlns xmlns:xlink aria-label viewBox preserveAspectRatio width height x y x1 y1 x2 y2 cx cy r rx ry d points transform id fill fill-rule fill-opacity stroke stroke-width stroke-linecap stroke-linejoin stroke-miterlimit stroke-dasharray stroke-dashoffset stroke-opacity opacity clip-path clip-rule clipPathUnits gradientUnits gradientTransform offset stop-color stop-opacity href xlink:href style class overflow".split()}
    elements = list(_walk(n))
    if len(elements) > 20000:
        raise NativeImportError("svg-budget")
    common = set("xmlns xmlns:xlink id aria-label class style transform fill fill-rule fill-opacity stroke stroke-width stroke-linecap stroke-linejoin stroke-miterlimit stroke-dasharray stroke-dashoffset stroke-opacity opacity clip-path clip-rule".split())
    viewport_attrs = {"viewbox", "x", "y", "width", "height", "preserveaspectratio"}
    def numbers(raw):
        if not isinstance(raw, str):
            raise NativeImportError("invalid-svg-geometry")
        pattern = r"[-+]?(?:[0-9]*\.[0-9]+|[0-9]+\.?[0-9]*)(?:[eE][-+]?[0-9]+)?"
        values, end = [], 0
        for match in re.finditer(pattern, raw):
            if raw[end:match.start()].strip(" \t\r\n,"):
                raise NativeImportError("invalid-svg-geometry")
            value = float(match[0])
            if not math.isfinite(value) or abs(value) > 1e8:
                raise NativeImportError("invalid-svg-geometry")
            values.append(value)
            end = match.end()
        if raw[end:].strip(" \t\r\n,"):
            raise NativeImportError("invalid-svg-geometry")
        return values

    ids = {}
    for element in elements:
        if "id" in element.attrs:
            identifier = _token(element.attrs["id"])
            if identifier in ids:
                raise NativeImportError("duplicate-svg-id")
            ids[identifier] = element

    def normalize_paints(e, inherited_opacity, inherited_alpha):
        declarations = {}
        if "style" in e.attrs:
            for declaration in (e.attrs["style"] or "").split(";"):
                if not declaration.strip():
                    continue
                parts = declaration.split(":")
                if len(parts) != 2:
                    raise NativeImportError("unsupported-svg-style")
                key, value = (part.strip() for part in parts)
                if key in declarations:
                    raise NativeImportError("unsupported-svg-style")
                declarations[key] = value
        explicit, paint_alpha = dict(inherited_opacity), dict(inherited_alpha)
        for key in ("fill", "stroke", "stop-color"):
            opacity = "stop-opacity" if key == "stop-color" else key + "-opacity"
            opacity_source = declarations if opacity in declarations else e.attrs
            try:
                previous = float(opacity_source.get(opacity, explicit.get(key, 1)))
                if not math.isfinite(previous) or not 0 <= previous <= 1:
                    raise ValueError()
            except (ValueError, TypeError):
                raise NativeImportError("unsupported-svg-opacity") from None
            explicit[key] = previous
            effective = declarations if key in declarations else e.attrs
            alpha = paint_alpha.get(key, 1) if key != "stop-color" else 1
            for source in (e.attrs, declarations):
                if key not in source:
                    continue
                value = source[key] or ""
                if re.fullmatch(r"#[0-9a-fA-F]{4}", value):
                    value = "#" + "".join(c * 2 for c in value[1:])
                match = re.fullmatch(r"#([0-9a-fA-F]{6})([0-9a-fA-F]{2})", value)
                if source is effective:
                    alpha = int(match[2], 16) / 255 if match else 1
                source[key] = _color("#" + match[1] if match else value)
            paint_alpha[key] = alpha
            # Paint alpha inherits with the paint, while explicit opacity has
            # its own cascade. Materialize their product so opaque overrides
            # cannot inherit an ancestor's extracted paint alpha.
            if alpha != 1 or inherited_alpha.get(key, 1) != 1:
                opacity_source[opacity] = str(previous * alpha)
        if "style" in e.attrs:
            e.attrs["style"] = ";".join(key + ":" + value for key, value in declarations.items())
        for child in e.children:
            if isinstance(child, _Element):
                normalize_paints(child, explicit, paint_alpha)

    for e in elements:
        e.attrs.pop("data-flow-raster-layer", None)
        if e.attrs.get("xmlns:h5") == "http://www.w3.org/1999/xhtml":
            del e.attrs["xmlns:h5"]
        if e.tag in {"svg", "image"}:
            local = viewport_attrs if e.tag == "svg" else (viewport_attrs - {"viewbox"}) | {"href", "xlink:href"}
            if set(e.attrs) - (common | local):
                raise NativeImportError("unsupported-svg-primitive")
            if e.attrs.get("class"):
                raise NativeImportError("unsupported-svg-class")
            for key, expected in (("xmlns", "http://www.w3.org/2000/svg"),
                                  ("xmlns:xlink", "http://www.w3.org/1999/xlink")):
                if key in e.attrs and e.attrs[key] != expected:
                    raise NativeImportError("unsupported-svg-namespace")
            if e.attrs.get("preserveaspectratio", "xMidYMid meet") not in {
                    "xMidYMid meet", "none", "xMinYMin meet", "xMaxYMax meet", "xMidYMid slice"}:
                raise NativeImportError("unsupported-svg-aspect")
        if any(isinstance(c, str) and c.strip() for c in e.children):
            raise NativeImportError("unsupported-svg-text")
        if e.tag in {"svg", "image"}:
            for key in ("x", "y"):
                if key in e.attrs:
                    values = numbers(e.attrs[key])
                    if len(values) != 1:
                        raise NativeImportError("invalid-svg-geometry")
                    # Serialize the validated scalar, never a numeric-list spelling
                    # that the native viewport mapper could interpret as zero.
                    e.attrs[key] = str(values[0])
            if "viewbox" in e.attrs:
                box = numbers(e.attrs["viewbox"])
                if len(box) != 4 or box[2] <= 0 or box[3] <= 0:
                    raise NativeImportError("invalid-svg-geometry")
            if e.tag == "svg":
                for key in ("width", "height"):
                    if key in e.attrs:
                        suffix = r"(?:pt|px|em|ex)$" if e is n else r"(?:pt|px)$"
                        raw = re.sub(suffix, "", e.attrs[key] or "")
                        if not re.fullmatch(r"\+?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][-+]?[0-9]+)?", raw):
                            raise NativeImportError("invalid-svg-geometry")
                        if not 0 < numbers(raw)[0]:
                            raise NativeImportError("invalid-svg-geometry")
            if "transform" in e.attrs:
                raw, end = e.attrs["transform"] or "", 0
                arities = {"matrix": {6}, "translate": {1, 2}, "scale": {1, 2}, "rotate": {1, 3}}
                for match in re.finditer(r"([a-zA-Z]+)\s*\(([^()]*)\)", raw):
                    if raw[end:match.start()].strip(" \t\r\n,") or len(numbers(match[2])) not in arities.get(match[1], set()):
                        raise NativeImportError("invalid-svg-geometry")
                    end = match.end()
                if raw[end:].strip():
                    raise NativeImportError("invalid-svg-geometry")
        if e.tag == "image":
            if "href" in e.attrs and "xlink:href" in e.attrs:
                raise NativeImportError("invalid-svg-image")
            href = e.attrs.get("href", e.attrs.get("xlink:href", "")) or ""
            prefix = "data:image/png;base64,"
            if not href.startswith(prefix) or len(href) > len(prefix) + 4 * ((8 * 1024 * 1024 + 2) // 3):
                raise NativeImportError("invalid-svg-image")
            try:
                data = base64.b64decode(href[len(prefix):], validate=True)
                if len(data) > 8 * 1024 * 1024 or base64.b64encode(data).decode() != href[len(prefix):] or not data.startswith(b"\x89PNG\r\n\x1a\n"):
                    raise ValueError()
                for dimension in ("width", "height"):
                    if not re.fullmatch(r"\+?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][-+]?[0-9]+)?", e.attrs[dimension] or ""):
                        raise ValueError()
                    values = numbers(e.attrs[dimension])
                    if len(values) != 1:
                        raise ValueError()
                    size = values[0]
                    if not math.isfinite(size) or not 0 < size <= 4096:
                        raise ValueError()
                if any(isinstance(c, _Element) for c in e.children):
                    raise ValueError()
            except (ValueError, KeyError, binascii.Error):
                raise NativeImportError("invalid-svg-image") from None
    references = {}
    for e in elements:
        refs = []
        for k, v in e.attrs.items():
            if k == "overflow" and (e.tag != "symbol" or v not in {"visible", "hidden"}):
                raise NativeImportError("unsupported-svg-overflow")
            if k == "style":
                # Geometry/paint validation remains with the existing native SVG
                # owner. The wire subset never accepts arbitrary CSS.
                allowed = {"fill", "stroke", "stop-color", "stop-opacity", "fill-opacity", "stroke-opacity", "opacity", "stroke-width", "clip-path", "fill-rule", "clip-rule"}
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
            if e.tag == "image" and k in {"href", "xlink:href"}:
                continue
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
    # Instance paint cascades must be resolved against the original definitions,
    # before their hex-alpha colors are converted to opaque colors and opacity.
    originals = {e: (dict(e.attrs), list(e.children)) for e in elements}
    generated = []
    generated_sources = {}
    serial = 0
    def instance(target):
        nonlocal serial
        mapping = {}
        def clone(e):
            nonlocal serial
            if len(elements) + len(generated) >= 20000:
                raise NativeImportError("svg-budget")
            attrs, children = originals[e]
            attrs = dict(attrs)
            if "id" in attrs:
                old = attrs["id"]
                while True:
                    serial += 1
                    new = "native-paint-instance-" + str(serial)
                    if new not in ids:
                        break
                mapping[old] = new
                attrs["id"] = new
            result = _Element(e.tag, attrs)
            generated.append(result)
            generated_sources[result] = e
            result.children = [clone(c) if isinstance(c, _Element) else c for c in children]
            return result
        result = clone(target)
        if "id" not in result.attrs:
            raise NativeImportError("unresolved-or-external-svg-reference")
        for element in list(_walk(result)):
            for key, value in element.attrs.items():
                if value and value.startswith("#") and key in {"href", "xlink:href"}:
                    element.attrs[key] = "#" + mapping.get(value[1:], value[1:])
                elif value and value.startswith("url(#") and value.endswith(")"):
                    identifier = value[5:-1]
                    element.attrs[key] = "url(#" + mapping.get(identifier, identifier) + ")"
            if "id" in element.attrs:
                ids[element.attrs["id"]] = element
        return result

    # Normalize referenced copies at their use sites, while keeping original
    # definitions available for independent uses with different cascades.
    normalized_instances = []
    def has_alpha(e, seen):
        if e in seen:
            return False
        attrs, children = originals[e]
        if any(re.search(r"#[0-9a-fA-F]{8}(?![0-9a-fA-F])|#[0-9a-fA-F]{4}(?![0-9a-fA-F])", value or "")
               for key, value in attrs.items() if key in {"fill", "stroke", "style"}):
            return True
        return any(has_alpha(child, seen | {e}) for child in children if isinstance(child, _Element)) or any(
            has_alpha(ref, seen | {e}) for ref in references[e])
    original_normalize = normalize_paints
    def normalize_paints(e, inherited_opacity, inherited_alpha):
        # The recursive implementation below calls this wrapper for children.
        if e.tag == "use":
            href_key = "href" if "href" in e.attrs else "xlink:href"
            href = e.attrs.get(href_key, "") or ""
            target = ids.get(href[1:]) if href.startswith("#") else None
            source = generated_sources.get(target, target) if target is not None else None
            use_has_alpha = any(re.search(r"#[0-9a-fA-F]{8}(?![0-9a-fA-F])|#[0-9a-fA-F]{4}(?![0-9a-fA-F])", value or "")
                                for key, value in e.attrs.items() if key in {"fill", "stroke", "style"})
            if source is not None and (has_alpha(source, set()) or use_has_alpha or
                                       any(value != 1 for value in inherited_alpha.values())):
                copy = instance(source)
                e.attrs[href_key] = "#" + copy.attrs["id"]
                # A synthetic child carries the exact inherited use cascade;
                # it is detached after normalization and stored in definitions.
                e.children.append(copy)
                original_normalize(e, inherited_opacity, inherited_alpha)
                e.children.pop()
                normalized_instances.append(copy)
                return
        original_normalize(e, inherited_opacity, inherited_alpha)
    # Definitions are normalized last so all references see authored paints.
    defs = [c for c in n.children if isinstance(c, _Element) and c.tag == "defs"]
    n.children = [c for c in n.children if c not in defs] + defs
    normalize_paints(n, {}, {})
    if normalized_instances:
        container = _Element("defs")
        container.children = normalized_instances
        n.children.append(container)
    def xml(e):
        if e.tag not in tags or set(e.attrs) - names.keys():
            raise NativeImportError("unsupported-svg-primitive")
        for k, v in e.attrs.items():
            if k in {"href", "xlink:href"} and e.tag != "image" and not (v or "").startswith("#"):
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
        match = re.fullmatch(r"([0-9]+(?:\.[0-9]+)?)(px|pt|em|%)" if css else r"([0-9]+(?:\.[0-9]+)?)(%?)", raw)
        if not match:
            raise NativeImportError("unsupported-image-length")
        value = float(match[1])
        unit = match[2] or "px"
        if not math.isfinite(value) or not 0 < value <= (100 if unit == "%" else 4096):
            raise NativeImportError("image-layout-budget")
        return {"value": value, "unit": unit}
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

    def annotations(element, value):
        for anchor in ([_token(element.attrs["id"])] if element.attrs.get("id") else []) + (
                [_mark(element.attrs["data-flow-mark"])] if element.attrs.get("data-flow-mark") else []):
            if anchor not in seen_anchors:
                seen_anchors.add(anchor)
                value["anchors"].append(anchor)
        if "data-flow-targets" in element.attrs:
            value["annotationTargets"].extend(_targets(element.attrs["data-flow-targets"]))

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
            normalized = _svg(roots[0])
            # Preserve existing byte identity unless compiler-only syntax needs normalization.
            if re.search(rb'xmlns:h5|data-flow-raster-layer|oklab\(|#(?:[0-9a-fA-F]{8}|[0-9a-fA-F]{4})(?![0-9a-fA-F])', data, re.I):
                data = normalized.encode("utf-8")
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
        allowed = common | {"a": {"href"}, "td": {"colspan", "rowspan"},
                            "th": {"colspan", "rowspan", "scope"},
                            "span": {"data-flow-mark", "data-flow-targets", "aria-hidden", "data-flow-request", "style"},
                            "div": {"style"}, "ol": {"style", "start"}, "ul": {"style"}, "li": {"value"},
                            "code": {"data-lang"},
                            "mrow": {"data-flow-mark"},
                            "img": {"src", "alt", "width", "height", "style", "loading", "decoding"}}.get(n.tag, set())
        allowed |= {"data-flow-graphic", "data-flow-canvas", "data-flow-canvas-package", "data-flow-canvas-model", "data-flow-canvas-label"}
        if n.tag not in {"math", "svg"} and set(attrs) - allowed:
            raise NativeImportError("unsupported-attribute")
        if attrs.get("role") not in {None, "heading", "doc-toc", "doc-noteref", "doc-biblioref", "doc-backlink", "doc-bibliography", "doc-endnotes", "mark"} or (attrs.get("role") == "heading" and heading_level(n.tag, attrs) is None):
            raise NativeImportError("unsupported-role")
        if attrs.get("lang"):
            if not re.fullmatch(r"[A-Za-z]{2,8}(?:-[A-Za-z0-9]{1,8})*", attrs["lang"]):
                raise NativeImportError("unsupported-language")
            value["language"] = attrs["lang"]
        if attrs.get("dir") not in {None, "auto", "ltr", "rtl"}:
            raise NativeImportError("unsupported-direction")
        if attrs.get("dir"):
            value["direction"] = attrs["dir"]
        if "style" in attrs and n.tag not in {"svg", "math", "img"}:
            _html_style(n.tag, attrs["style"] or "")
        for key in ({"li": ["value"], "ol": ["start"]}.get(n.tag, [])):
            if key in attrs and (not re.fullmatch(r"[+-]?[0-9]{1,10}", attrs[key] or "") or not -(2**31) <= int(attrs[key]) < 2**31):
                raise NativeImportError("invalid-list-value")
        classes = set(attrs.get("class", "").split())
        known_classes = {"flow-equation", "flow-equation-number", "flow-mark", "flow-annotation", "flow-annotation-body", "flow-drawing", *"flow-callout flow-callout-title flow-definition flow-note flow-lemma flow-proposition flow-emphasis flow-theorem flow-paragraph-tab flow-highlight flow-flowbox flow-aligned prefix flow-graphic flow-grid flow-book-cover flow-canvas flow-canvas-stage flow-canvas-labels flow-canvas-label flow-canvas-label-number flow-canvas-label-body flow-canvas-stack".split()}
        if classes - known_classes and n.tag not in {"math", "svg"}:
            raise NativeImportError("unsupported-class")
        annotations(n, value)
        if attrs.get("data-reader-key"):
            value["passageKey"] = _token(attrs["data-reader-key"])
        kinds = {"p": "paragraph", "strong": "strong", "em": "emphasis", "a": "link", "span": "group",
                 "div": "group", "ol": "group", "ul": "group", "li": "group", "sup": "group", "mark": "group", "code": "group", "section": "group", "header": "group", "nav": "group", "mrow": "group", "mtext": "group", "table": "table", "thead": "tableHead", "tbody": "tableBody", "tfoot": "tableBody",
                 "tr": "row", "th": "cell", "td": "cell", "figure": "figure", "figcaption": "caption", "br": "break"}
        level = heading_level(n.tag, attrs)
        if level is not None:
            value.update(kind="heading", headingLevel=level)
        elif n.tag in kinds:
            value["kind"] = kinds[n.tag]
        elif n.tag == "math":
            for descendant in list(_walk(n))[1:]:
                annotations(descendant, value)
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
            value["link"] = _link(attrs.get("href", ""))
        if n.tag == "li" and "value" in attrs:
            value["listItemNumber"] = int(attrs["value"])
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
            item_number = int(attrs.get("start", "1")) if n.tag == "ol" else None
            for c in n.children:
                child = emit(c, section, offset)
                if item_number is not None and isinstance(c, _Element) and c.tag == "li":
                    item_number = child.get("listItemNumber", item_number)
                    if not -(2**31) <= item_number < 2**31:
                        raise NativeImportError("invalid-list-value")
                    child["listItemNumber"] = item_number
                    item_number += 1
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
