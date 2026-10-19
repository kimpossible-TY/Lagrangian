"""Shared content transformation and acceptance policy for every compiler."""
from collections import Counter
from html.parser import HTMLParser
import json
import re
from urllib.parse import unquote
from flow_reader.document.content import namespace_svg_ids, normalize_math_html
from flow_reader.document.figures import stamp_canvas_identities

ALLOWED_WARNINGS = frozenset({
    "html export is under active development and incomplete",
    "page set rule was ignored during HTML export",
    "pdf-marker-tag was ignored during HTML export",
})


def diagnostic_warnings(diagnostic):
    """Read warnings from both verbose compile and short watch diagnostics."""
    return re.findall(r"(?:^|\n).*?warning: (.*)", diagnostic)


def unhandled_warnings(warnings):
    return sorted(set(warnings) - ALLOWED_WARNINGS)


def normalize_content(content):
    return stamp_canvas_identities(normalize_math_html(namespace_svg_ids(content)))


def audit_content(content):
    audit = ContentAudit()
    audit.feed(content)
    return audit.report()


def validate_content(content, diagnostic):
    if (unhandled_warnings(diagnostic_warnings(diagnostic))
            or re.search(r"(?:^|\n).*?error: ", diagnostic)):
        raise ValueError("Incremental compilation has unhandled diagnostics")
    content = normalize_content(content)
    if not audit_content(content)["contentGatePassed"]:
        raise ValueError("Incremental compilation failed the content gate")
    return content


class ContentAudit(HTMLParser):
    """Check content delivery invariants; visual validation is a separate gate."""

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.elements: Counter[str] = Counter()
        self.ids: Counter[str] = Counter()
        self.links: list[str] = []
        self.diagnostics: Counter[str] = Counter()
        self.marks: Counter[str] = Counter()
        self.annotation_targets: list[list[str]] = []
        self.graphics: dict[str, list[str]] = {}
        self.canvases: list[str] = []
        self.decorations: dict[str, list[str]] = {}

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        attributes = dict(attrs)
        self.elements[tag] += 1
        if identifier := attributes.get("id"):
            self.ids[identifier] += 1
        if (href := attributes.get("href")) and href.startswith("#"):
            self.links.append(unquote(href[1:]))
        if diagnostic := attributes.get("data-flow-diagnostic"):
            self.diagnostics[diagnostic] += 1
        if mark := attributes.get("data-flow-mark"):
            self.marks[mark] += 1
        if canvas := attributes.get("data-flow-canvas"):
            self.canvases.append(canvas)
        if decoration := attributes.get("data-flow-decoration"):
            self.decorations[decoration] = json.loads(attributes["data-flow-decoration-layers"])
        if targets := attributes.get("data-flow-targets"):
            self.annotation_targets.append(json.loads(targets))
            if graphic := attributes.get("data-flow-graphic"):
                self.graphics[graphic] = json.loads(targets)

    def report(self) -> dict:
        missing_links = sorted(set(self.links) - self.ids.keys())
        missing_marks = sorted({target for targets in self.annotation_targets
                                for target in targets} - self.marks.keys())
        duplicate_ids = sorted(key for key, count in self.ids.items() if count > 1)
        return {
            "elements": dict(self.elements),
            "missingLinkTargets": missing_links,
            "duplicateIds": duplicate_ids,
            "annotations": len(self.annotation_targets),
            "unresolvedAnnotationTargets": missing_marks,
            "unsupported": dict(self.diagnostics),
            "graphics": self.graphics,
            "canvases": self.canvases,
            "decorations": self.decorations,
            "contentGatePassed": not (
                missing_links or duplicate_ids or missing_marks or self.diagnostics
            ),
        }
