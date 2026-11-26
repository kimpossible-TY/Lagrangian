"""Read-only cross-project catalog and previews of mounted accepted documents.

The Swift CrossProjectReference contract is retained at the language boundary.
No lookup starts a compiler, reads target source files or adopts an editor session.
"""
from contextlib import ExitStack
import json
import math
import os
from pathlib import Path
import re
import stat
from urllib.parse import parse_qs, quote, unquote, urlsplit

from flow_reader.document.native_document import import_accepted_document
from flow_reader.services.homepage import reader_url

MAX_CATALOG_BYTES = 16 * 1024 * 1024
MAX_PARAM_CHARS = 1024
MAX_CANDIDATES = 32


def _invalid(*_args):
    raise ValueError("Invalid project reference catalog")


def _object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            _invalid()
        result[key] = value
    return result


def _string(value):
    if not isinstance(value, str):
        _invalid()
    # Reject lone surrogate scalars before publishing UTF-8 JSON.
    value.encode("utf-8")
    return value


def _metadata(target):
    return {key: value[:MAX_PARAM_CHARS] if isinstance(value, str) else value
            for key, value in target.items()}


def _pdf_url(value):
    """Catalog PDFs are metadata only; never expose local filesystem URLs."""
    try:
        url = urlsplit(value)
        return value[:MAX_PARAM_CHARS] if (len(value) <= MAX_PARAM_CHARS and url.scheme in {"http", "https"}
            and url.hostname and not url.username and not url.password
            and not any(c.isspace() or ord(c) < 32 for c in value) and "\\" not in value) else None
    except ValueError:
        return None


class CrossProjectCatalog:
    def __init__(self, projects):
        self.projects = projects

    @classmethod
    def load(cls, package_path, max_bytes=MAX_CATALOG_BYTES):
        """Resolve inside packages, open only regular files and bound the read.

        Walk the resolved relative path using directory FDs and O_NOFOLLOW so
        replacing a path component after the containment check cannot escape.
        All failures use a fixed message, including OS/JSON decoder failures.
        """
        try:
            if type(max_bytes) is not int or not 0 < max_bytes <= MAX_CATALOG_BYTES:
                _invalid()
            root = Path(package_path).resolve(strict=True)
            catalog = (root / "local/project-references/0.1.0/projects.json").resolve(strict=True)
            parts = catalog.relative_to(root).parts
            if not parts:
                _invalid()
            with ExitStack() as stack:
                def opened(path, flags, **kwargs):
                    fd = os.open(path, flags | os.O_NOFOLLOW | os.O_NONBLOCK, **kwargs)
                    stack.callback(os.close, fd)
                    return fd
                directory = opened(root, os.O_RDONLY | os.O_DIRECTORY)
                for part in parts[:-1]:
                    directory = opened(part, os.O_RDONLY | os.O_DIRECTORY, dir_fd=directory)
                fd = opened(parts[-1], os.O_RDONLY, dir_fd=directory)
                info = os.fstat(fd)
                if not stat.S_ISREG(info.st_mode) or info.st_size > max_bytes:
                    _invalid()
                with os.fdopen(os.dup(fd), "rb") as stream:
                    raw = stream.read(max_bytes + 1)
                if len(raw) > max_bytes:
                    _invalid()
            document = json.loads(raw.decode("utf-8"), object_pairs_hook=_object, parse_constant=_invalid)
            if (not isinstance(document, dict) or type(document.get("schema")) is not int
                    or document["schema"] != 1 or not isinstance(document.get("projects"), dict)):
                _invalid()
            for key, project in document["projects"].items():
                _string(key)
                if not isinstance(project, dict):
                    _invalid()
                _string(project["title"])
                _string(project["pdf_url"])
                if (not isinstance(project["references"], dict) or not isinstance(project["ambiguous_labels"], list)):
                    _invalid()
                for label in project["ambiguous_labels"]:
                    _string(label)
                for label, entry in project["references"].items():
                    _string(label)
                    if not isinstance(entry, dict) or type(entry.get("page")) is not int or not 0 < entry["page"] < 2**63:
                        _invalid()
                    _string(entry["text"])
                    for coordinate in (entry.get("x"), entry.get("y")):
                        if coordinate is not None and (type(coordinate) not in {int, float} or not math.isfinite(coordinate)):
                            _invalid()
            return cls(document["projects"])
        except (OSError, ValueError, TypeError, KeyError, OverflowError, RuntimeError):
            raise ValueError("Project reference catalog unavailable or invalid") from None

    def _target(self, key, label):
        project = self.projects[key]
        entry = project["references"][label]
        return {"projectKey": key, "projectTitle": project["title"], "label": label,
                "refText": entry["text"], "title": entry["text"], "pdfUrl": _pdf_url(project["pdf_url"])}

    def resolve(self, project_key=None, label=None, href=None, link_text=None):
        if project_key is not None or label is not None:
            project = self.projects.get(project_key)
            if project is None:
                return {"status": "unresolved"}
            if label in project["ambiguous_labels"]:
                return {"status": "ambiguous", "candidates": []}
            if label not in project["references"]:
                return {"status": "unresolved"}
            return {"status": "unique", **self._target(project_key, label)}
        try:
            url = urlsplit(href or "")
            fragment = unquote(url.fragment)
            if not re.fullmatch(r"page=[+]?[0-9]+", fragment):
                return {"status": "unresolved"}
            page = int(fragment[5:])
            if not 0 < page < 2**63:
                return {"status": "unresolved"}
            pdf = (href or "").split("#", 1)[0]
        except ValueError:
            return {"status": "unresolved"}
        candidates, count, ambiguous = [], 0, False
        for key, project in sorted(self.projects.items()):
            if project["pdf_url"] != pdf:
                continue
            for label, entry in sorted(project["references"].items()):
                if entry["page"] != page or (link_text is not None and link_text not in
                        {entry["text"], entry["text"] + " of " + project["title"]}):
                    continue
                count += 1
                ambiguous |= label in project["ambiguous_labels"]
                if len(candidates) < MAX_CANDIDATES:
                    candidates.append(self._target(key, label))
        if not count:
            return {"status": "unresolved"}
        if count == 1 and not ambiguous:
            return {"status": "unique", **candidates[0]}
        return {"status": "ambiguous", "candidates": [_metadata(c) for c in candidates]}


def extract_snippet(native_document, label, reference_text=None, max_chars=600, max_blocks=4):
    """Use canonical plain text, never serialized HTML, MathML or asset payloads."""
    if max_chars <= 0 or max_blocks <= 0:
        return None
    blocks = native_document["blocks"]
    def nodes(block):
        yield block
        for child in block.get("children", []):
            yield from nodes(child)
    anchor = (label or "").strip()
    query = " ".join((reference_text or "").split()).casefold()
    start = next((i for i, b in enumerate(blocks) if anchor and any(
        anchor in n.get("anchors", []) or anchor == n.get("id") for n in nodes(b))), None)
    if start is None and query:
        start = next((i for i, b in enumerate(blocks) if any(query in " ".join(b.get(k, "").split()).casefold()
                     for k in ("displayText", "canonicalText", "reference_text"))), None)
    if start is None:
        return None
    section, index, parts = blocks[start]["sectionID"], start, []
    while index < len(blocks) and index - start < max_blocks:
        block = blocks[index]
        if block["sectionID"] != section or (index != start and block["kind"] == "heading"):
            break
        text = block.get("displayText", "").strip() or block.get("canonicalText", "").strip()
        if text:
            parts.append(text)
        index += 1
    text = "\n\n".join(parts)
    more = (index - start == max_blocks and index < len(blocks) and blocks[index]["sectionID"] == section
            and blocks[index]["kind"] != "heading")
    if len(text) > max_chars:
        return {"text": text[:max_chars - 3] + "..." if max_chars >= 3 else text[:max_chars], "truncated": True}
    return {"text": text, "truncated": more}


def preview_query(query):
    """Two exclusive query forms, decoded once with strict UTF-8 and limits."""
    if len(query) > 3 * MAX_PARAM_CHARS * 12 + 64 or re.search(r"%(?![0-9a-fA-F]{2})", query):
        raise ValueError("Invalid cross-project query")
    fields = parse_qs(query, keep_blank_values=True, strict_parsing=True, errors="strict", max_num_fields=3)
    keys = set(fields)
    if keys != {"project", "label"} and keys not in ({"href"}, {"href", "text"}):
        raise ValueError("Invalid cross-project query")
    if any(len(v) != 1 or not v[0].strip() or len(v[0]) > MAX_PARAM_CHARS
           or any(ord(c) < 32 or ord(c) == 127 for c in v[0]) for v in fields.values()):
        raise ValueError("Invalid cross-project query")
    if "project" in fields:
        return {"project_key": fields["project"][0], "label": fields["label"][0]}
    return {"href": fields["href"][0], "link_text": fields.get("text", [None])[0]}


def target_url(route, anchor, allowed_origin=None):
    """Only a mounted document route, optionally on the configured origin."""
    try:
        if not isinstance(route, str) or len(route) > MAX_PARAM_CHARS or any(
                c.isspace() or ord(c) < 32 for c in route) or "\\" in route:
            return None
        url = urlsplit(route)
        if "?" in route or "#" in route or not re.fullmatch(r"/d/[a-z0-9][a-z0-9-]{0,63}/", url.path):
            return None
        if url.scheme or url.netloc:
            origin = reader_url(url._replace(path="/", query="", fragment="").geturl())
            if not origin or origin != reader_url(allowed_origin):
                return None
        elif route != url.path:
            # urlsplit collapses a leading triple slash; browsers may instead
            # treat it as a network-path reference and navigate off origin.
            return None
        return route + "#" + quote(anchor, safe="")
    except (ValueError, TypeError):
        return None


class CrossProjectPreviewService:
    def __init__(self, state, peer_lookup=None, *, allowed_origin=None):
        self.state = state
        self.peer_lookup = peer_lookup or (lambda _key, _title: None)
        self.allowed_origin = allowed_origin

    def catalog(self):
        return CrossProjectCatalog.load(self.state.project.packages)

    @property
    def available(self):
        try:
            self.catalog()
            return True
        except ValueError:
            return False

    def preview(self, **query):
        result = {"status": "unresolved", **dict.fromkeys(("projectKey", "projectTitle", "label", "refText",
                  "title", "snippet", "targetUrl", "anchor", "pdfUrl")), "truncated": False}
        try:
            resolved = self.catalog().resolve(**query)
            result.update(_metadata(resolved))
        except ValueError:
            return result
        if result["status"] != "unique":
            return result
        # Display bounds must never turn a long identity into a different key,
        # anchor or text match. Keep full catalog values for internal lookup.
        if len(resolved["label"]) > MAX_PARAM_CHARS:
            return result
        result["anchor"] = resolved["label"]
        peer = self.peer_lookup(resolved["projectKey"], resolved["projectTitle"])
        if peer is None:
            return result
        target, route = peer
        result["targetUrl"] = target_url(route, result["anchor"], self.allowed_origin)
        if result["targetUrl"] is None:
            return result
        # Publication lock binds the importer to the accepted bundle. No source
        # fingerprint I/O: preview intentionally reads the last accepted document.
        try:
            with target.lock:
                if (not target.bundle or not target.revision or target.compiling
                        or target.bundle.manifest["revision"] != target.revision):
                    return result
                service = target.focus.service
                imported = import_accepted_document(target.bundle, document_id=target.document_id,
                    service_id=f'reader:{service["pid"]}:{service["startedAt"]}', generation=0)
                snippet = extract_snippet(imported.document, resolved["label"], resolved["refText"])
                if snippet is not None:
                    result.update(snippet=snippet["text"], truncated=snippet["truncated"])
        except (ValueError, TypeError, KeyError, UnicodeError, RecursionError, OSError):
            pass  # Keep the unique catalog metadata and safe mounted route.
        return result
