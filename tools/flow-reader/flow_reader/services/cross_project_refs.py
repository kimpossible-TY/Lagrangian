"""Resolve cross-project references and extract native reader previews."""

from dataclasses import dataclass
import json
import math
import os
import stat
from urllib.parse import parse_qs, urldefrag

from flow_reader.document.passages import normalized


class CatalogError(ValueError):
    """The catalog cannot be read or does not satisfy its schema."""


@dataclass(frozen=True)
class CrossProjectRefEntry:
    label: str
    page: int
    text: str
    x: float | None = None
    y: float | None = None


@dataclass(frozen=True)
class CrossProjectEntry:
    key: str
    title: str
    pdf_url: str
    references: dict[str, CrossProjectRefEntry]
    ambiguous_labels: tuple[str, ...]


@dataclass(frozen=True)
class CrossProjectCatalog:
    schema: int
    projects: dict[str, CrossProjectEntry]


def _nonempty(value):
    return isinstance(value, str) and bool(value.strip())


def _reject_json_constant(value):
    raise CatalogError(f'invalid JSON constant: {value}')


def load_project_catalog(path, *, max_bytes=16777216):
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK)
        with os.fdopen(fd, 'rb') as source:
            if not stat.S_ISREG(os.fstat(source.fileno()).st_mode):
                raise CatalogError('catalog must be a regular file')
            raw = source.read(max_bytes + 1)
        if len(raw) > max_bytes:
            raise CatalogError('catalog exceeds size limit')
        data = json.loads(raw.decode('utf-8'), parse_constant=_reject_json_constant)
    except (OSError, UnicodeError, ValueError, OverflowError) as exc:
        if isinstance(exc, CatalogError):
            raise
        raise CatalogError('invalid catalog') from exc
    if (not isinstance(data, dict) or type(data.get('schema')) is not int
            or data['schema'] != 1 or not isinstance(data.get('projects'), dict)):
        raise CatalogError('invalid catalog schema')
    projects = {}
    for key, project in data['projects'].items():
        if (not _nonempty(key) or not isinstance(project, dict)
                or not _nonempty(project.get('title')) or not _nonempty(project.get('pdf_url'))
                or not isinstance(project.get('references'), dict)):
            raise CatalogError('invalid project')
        ambiguous = project.get('ambiguous_labels', [])
        if not isinstance(ambiguous, list) or any(not isinstance(v, str) for v in ambiguous):
            raise CatalogError('invalid ambiguous labels')
        refs = {}
        for label, ref in project['references'].items():
            if (not _nonempty(label) or not isinstance(ref, dict)
                    or type(ref.get('page')) is not int or ref['page'] <= 0
                    or not _nonempty(ref.get('text'))):
                raise CatalogError('invalid reference')
            coords = []
            for name in ('x', 'y'):
                value = ref.get(name)
                if name in ref and (isinstance(value, bool) or not isinstance(value, (int, float))
                                    or (isinstance(value, float) and not math.isfinite(value))):
                    raise CatalogError('invalid coordinate')
                coords.append(value)
            refs[label] = CrossProjectRefEntry(label, ref['page'], ref['text'], *coords)
        projects[key] = CrossProjectEntry(key, project['title'], project['pdf_url'], refs, tuple(ambiguous))
    return CrossProjectCatalog(1, projects)


@dataclass(frozen=True)
class CrossProjectRefResolution:
    status: str
    resolution_mode: str | None
    project_key: str | None
    project_title: str | None
    label: str | None
    reference_text: str | None
    page: int | None
    pdf_url: str | None
    candidate_labels: tuple[str, ...] = ()

    def to_dict(self):
        return dict(status=self.status, resolutionMode=self.resolution_mode, projectKey=self.project_key,
                    projectTitle=self.project_title, label=self.label, referenceText=self.reference_text,
                    page=self.page, pdfUrl=self.pdf_url, candidateLabels=list(self.candidate_labels))


def _resolution(status, mode=None, project=None, label=None, ref=None, candidates=()):
    if status == 'unresolved' and mode is None:
        mode = 'unresolved'
    return CrossProjectRefResolution(status, mode, project.key if project else None,
        project.title if project else None, label, ref.text if ref else None,
        ref.page if ref else None, project.pdf_url if project else None, tuple(sorted(candidates)))


def resolve_cross_project_ref(catalog, *, href=None, link_text=None, data_attrs=None):
    attrs = data_attrs if isinstance(data_attrs, dict) else {}
    key = attrs.get('data-project-ref-project')
    label = attrs.get('data-project-ref-label')
    if key is not None or label is not None:
        project = catalog.projects.get(key) if isinstance(key, str) else None
        if project and label in project.ambiguous_labels:
            return _resolution('ambiguous', 'ambiguous', project, label, candidates=(label,))
        ref = project.references.get(label) if project and isinstance(label, str) else None
        if ref:
            return _resolution('resolved', 'explicit_metadata', project, label, ref)
        return _resolution('unresolved', project=project, label=label if isinstance(label, str) else None)
    if not isinstance(href, str):
        return _resolution('unresolved')
    try:
        base, fragment = urldefrag(href)
    except ValueError:
        return _resolution('unresolved')
    pages = parse_qs(fragment).get('page', [])
    if len(pages) != 1 or not pages[0].isascii() or not pages[0].isdigit():
        return _resolution('unresolved')
    try:
        page = int(pages[0])
    except ValueError:
        return _resolution('unresolved')
    if page <= 0:
        return _resolution('unresolved')
    matches = [(p, r) for p in catalog.projects.values() if p.pdf_url == base
               for r in p.references.values() if r.page == page]
    normalized_text = normalized(link_text if isinstance(link_text, str) else '')
    text_matches = [(p, r) for p, r in matches if normalized_text and normalized_text in
                    (normalized(r.text), normalized(f'{r.text} of {p.title}'))]
    selected = text_matches or matches
    if len(selected) == 1:
        project, ref = selected[0]
        if ref.label in project.ambiguous_labels:
            return _resolution('ambiguous', 'ambiguous', project, ref.label, candidates=(ref.label,))
        return _resolution('resolved', 'url_text_fallback' if text_matches else 'url_page_fallback', project, ref.label, ref)
    if len(selected) > 1:
        project = selected[0][0] if all(p.key == selected[0][0].key for p, _ in selected) else None
        return _resolution('ambiguous', 'ambiguous', project, candidates={r.label for _, r in selected})
    return _resolution('unresolved')


@dataclass(frozen=True)
class BlockSnippet:
    matched: bool
    match_mode: str | None
    anchor: str | None
    block_id: str | None
    section_id: str | None
    text: str
    blocks: tuple
    truncated: bool

    def to_dict(self):
        return dict(matched=self.matched, matchMode=self.match_mode, anchor=self.anchor,
                    blockID=self.block_id, sectionID=self.section_id, text=self.text,
                    blocks=list(self.blocks), truncated=self.truncated)


def _has_anchor(node, label):
    return label in node.get('anchors', []) or any(_has_anchor(child, label) for child in node.get('children', []))


def extract_block_snippet(document, *, label=None, reference_text=None, max_chars=1200, max_blocks=6):
    empty = BlockSnippet(False, None, None, None, None, '', (), False)
    if not isinstance(document, dict) or type(document.get('schemaVersion')) is not int or document['schemaVersion'] != 1:
        return empty
    blocks = document.get('blocks', [])
    if not isinstance(blocks, list) or max_blocks <= 0 or max_chars < 0:
        return empty
    index = next((i for i, b in enumerate(blocks) if label and _has_anchor(b, label)), None)
    mode = 'anchor'
    if index is None:
        needle = normalized(reference_text if isinstance(reference_text, str) else '')
        index = next((i for i, b in enumerate(blocks) if needle and any(
            needle in normalized(b.get(field) if isinstance(b.get(field), str) else '')
            for field in ('displayText', 'canonicalText'))), None)
        mode = 'reference_text'
    if index is None:
        return empty
    first = blocks[index]
    selected = []
    for block in blocks[index:]:
        if block.get('sectionID') != first.get('sectionID') or (selected and block.get('kind') == 'heading'):
            break
        if len(selected) == max_blocks:
            break
        selected.append(block)
    text = '\n\n'.join(b.get('displayText') or b.get('canonicalText', '') for b in selected)
    truncated = len(text) > max_chars
    if truncated:
        text = text[:max(0, max_chars - 3)] + '.' * min(3, max_chars)
    return BlockSnippet(True, mode, label if mode == 'anchor' else None, first.get('id'),
                        first.get('sectionID'), text, tuple(selected), truncated)


def build_preview_payload(catalog, target_document, *, href=None, link_text=None, data_attrs=None,
                          max_chars=1200, max_blocks=6):
    resolution = resolve_cross_project_ref(catalog, href=href, link_text=link_text, data_attrs=data_attrs)
    snippet = extract_block_snippet(target_document if resolution.status == 'resolved' else None,
                                    label=resolution.label, reference_text=resolution.reference_text,
                                    max_chars=max_chars, max_blocks=max_blocks)
    return {'resolution': resolution.to_dict(), 'snippet': snippet.to_dict()}
