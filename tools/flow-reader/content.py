"""Normalize embedded SVG assets without altering the document's anchor names."""

from html.parser import HTMLParser
import re
from xml.etree import ElementTree as ET


ET.register_namespace("", "http://www.w3.org/2000/svg")
ET.register_namespace("xlink", "http://www.w3.org/1999/xlink")


class MathHtmlEmbedding(HTMLParser):
    """Place HTML phrasing content in MathML token integration points.

    Typst currently emits footnote `sup` nodes directly into MathML rows. An
    HTML5 browser then exits the math namespace, turning subsequent fractions
    and scripts into plain text. Repair the boundary before HTML parsing.
    """

    TOKENS = {"mi", "mo", "mn", "ms", "mtext"}
    MATH = TOKENS | {"math", "mrow", "mfrac", "msqrt", "mroot", "mstyle", "merror",
                     "mpadded", "mphantom", "mfenced", "menclose", "msub", "msup",
                     "msubsup", "munder", "mover", "munderover", "mmultiscripts",
                     "mprescripts", "none", "mtable", "mtr", "mlabeledtr", "mtd",
                     "maligngroup", "malignmark", "mspace", "semantics", "annotation",
                     "annotation-xml"}
    VOID = {"area", "base", "br", "col", "embed", "hr", "img", "input", "link",
            "meta", "param", "source", "track", "wbr"}
    PHRASING = {"a", "span", "sup", "sub", "em", "strong", "mark", "code", "br",
                "img", "svg", "i", "b", "small", "s", "u", "q", "abbr", "time"}

    def __init__(self):
        super().__init__(convert_charrefs=False)
        self.stack = []
        self.output = []

    def start(self, tag, self_closing):
        parent, namespace, _ = self.stack[-1][:3] if self.stack else (None, "html", False)
        in_math = namespace == "math" and parent not in self.TOKENS
        wrapped = in_math and tag not in self.MATH
        if wrapped and tag not in self.PHRASING:
            raise ValueError(f"Non-phrasing <{tag}> inside MathML requires a reader adapter")
        child_namespace = "math" if tag == "math" or (in_math and not wrapped) else "html"
        if namespace == "svg" or tag == "svg":
            child_namespace = "svg"
        if wrapped:
            self.output.append("<mtext>")
        self.output.append(self.get_starttag_text())
        if self_closing or tag in self.VOID:
            if wrapped:
                self.output.append("</mtext>")
        else:
            # HTMLParser lowercases tag names, but a later SVG extraction is
            # parsed as XML. Keep the source spelling for clipPath, gradients,
            # filters, and other case-sensitive SVG closing tags.
            spelling = re.match(r"<\s*([^\s/>]+)", self.get_starttag_text())[1]
            self.stack.append((tag, child_namespace, wrapped, spelling))

    def handle_starttag(self, tag, attrs):
        self.start(tag, False)

    def handle_startendtag(self, tag, attrs):
        self.start(tag, True)

    def handle_endtag(self, tag):
        if self.stack and self.stack[-1][0] == tag:
            _, namespace, wrapped, spelling = self.stack.pop()
            self.output.append(f"</{spelling if namespace == 'svg' else tag}>")
            if wrapped:
                self.output.append("</mtext>")
        else:
            self.output.append(f"</{tag}>")

    def handle_data(self, data):
        self.output.append(data)

    def handle_entityref(self, name):
        self.output.append(f"&{name};")

    def handle_charref(self, name):
        self.output.append(f"&#{name};")

    def handle_comment(self, data):
        self.output.append(f"<!--{data}-->")

    def handle_decl(self, decl):
        self.output.append(f"<!{decl}>")


def normalize_math_html(source: str) -> str:
    parser = MathHtmlEmbedding()
    parser.feed(source)
    return "".join(parser.output)


class SvgRanges(HTMLParser):
    def __init__(self, source: str) -> None:
        super().__init__()
        self.source = source
        self.offsets = [0]
        self.offsets.extend(match.end() for match in re.finditer("\n", source))
        self.depth = 0
        self.start = 0
        self.ranges: list[tuple[int, int]] = []

    def source_offset(self) -> int:
        row, column = self.getpos()
        return self.offsets[row - 1] + column

    def handle_starttag(self, tag, attrs):
        if tag == "svg":
            if self.depth == 0:
                self.start = self.source_offset()
            self.depth += 1

    def handle_endtag(self, tag):
        if tag == "svg":
            self.depth -= 1
            if self.depth == 0:
                self.ranges.append((self.start, self.source.index(">", self.source_offset()) + 1))

    def handle_startendtag(self, tag, attrs):
        if tag == "svg" and self.depth == 0:
            self.ranges.append((self.source_offset(), self.source_offset() + len(self.get_starttag_text())))


def namespace_svg_ids(source: str, prefix: str = "flow-svg") -> str:
    """Scope repeated glyph and clip definitions to their containing SVG.

    Typst emits self-contained SVG islands whose internal IDs can repeat in an
    HTML document. Prefix both definitions and references; leave links to
    external document anchors alone. SVG parsing retains case-sensitive names.
    """
    parser = SvgRanges(source)
    parser.feed(source)
    pieces = []
    previous = 0
    for number, (start, end) in enumerate(parser.ranges):
        pieces.append(source[previous:start])
        root = ET.fromstring(source[start:end])
        ids = {node.attrib["id"]: f"{prefix}-{number}-{node.attrib['id']}"
               for node in root.iter() if "id" in node.attrib}
        for node in root.iter():
            for key, value in list(node.attrib.items()):
                if key == "id":
                    node.set(key, ids[value])
                elif key in ("href", "{http://www.w3.org/1999/xlink}href"):
                    if value.startswith("#") and value[1:] in ids:
                        node.set(key, "#" + ids[value[1:]])
                else:
                    node.set(key, re.sub(
                        r"url\(\s*(['\"]?)#([^)'\"\s]+)\1\s*\)",
                        lambda match: f"url(#{ids[match[2]]})" if match[2] in ids else match[0],
                        value,
                    ))
        pieces.append(ET.tostring(root, encoding="unicode"))
        previous = end
    pieces.append(source[previous:])
    return "".join(pieces)
