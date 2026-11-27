"""Read-only cross-project catalog and previews of mounted accepted documents.

The Swift CrossProjectReference contract is retained at the language boundary.
No lookup starts a compiler, reads target source files or adopts an editor session.
"""
from contextlib import ExitStack, contextmanager
import fcntl
import json
from itertools import islice
import math
import os
from pathlib import Path
import re
import stat
import threading
import unicodedata
from urllib.parse import parse_qs, quote, unquote, urlsplit

from flow_reader.server.native_reader import import_bounded_document, service_id
from flow_reader.services.accepted_snapshot import AcceptedSnapshot
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


@contextmanager
def _open_catalog(package_path):
    root = Path(package_path).resolve(strict=True)
    root_info = root.stat()
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
        opened_root = os.fstat(directory)
        if ((opened_root.st_dev, opened_root.st_ino) != (root_info.st_dev, root_info.st_ino)
                or Path(os.fsdecode(fcntl.fcntl(directory, fcntl.F_GETPATH, bytes(1024)).split(b"\0", 1)[0])) != root):
            _invalid()
        for part in parts[:-1]:
            directory = opened(part, os.O_RDONLY | os.O_DIRECTORY, dir_fd=directory)
        fd = opened(parts[-1], os.O_RDONLY, dir_fd=directory)
        opened_path = Path(os.fsdecode(fcntl.fcntl(fd, fcntl.F_GETPATH, bytes(1024)).split(b"\0", 1)[0]))
        opened_path.relative_to(root)
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode):
            _invalid()
        yield fd, info


def _signature(info):
    return (info.st_dev, info.st_ino, info.st_mtime_ns, info.st_size)


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
            with _open_catalog(package_path) as (fd, info):
                if info.st_size > max_bytes:
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


def _contains_case_insensitive(text, query):
    """Approximate Foundation's canonical, case-insensitive substring search.

    Match complete case mappings: 'ss' may match 'ß', but 's' must not match
    half of it. NFC also preserves accents while matching equivalent spellings.
    Foundation/Unicode version differences remain a language-boundary limit.
    """
    text = unicodedata.normalize("NFC", " ".join(text.split()))
    query = unicodedata.normalize("NFC", query).casefold()
    forbidden, offset = set(), 0
    for char in text:
        size = len(char.casefold())
        forbidden.update(range(offset + 1, offset + size))
        offset += size
    folded = text.casefold()
    start = folded.find(query)
    while start >= 0:
        if start not in forbidden and start + len(query) not in forbidden:
            return True
        start = folded.find(query, start + 1)
    return False


def _graphemes(text):
    """Conservative stdlib clusters for common reader text and emoji.

    Keep marks, variation selectors, emoji modifiers/ZWJ sequences, flag pairs,
    CRLF and Hangul together. This is not a complete Unicode UAX #29 segmenter;
    uncommon Indic conjuncts/prepend rules can differ from Swift Character.
    """
    def hangul(char):
        code = ord(char)
        if 0x1100 <= code <= 0x115F or 0xA960 <= code <= 0xA97C:
            return "L"
        if 0x1160 <= code <= 0x11A7 or 0xD7B0 <= code <= 0xD7C6:
            return "V"
        if 0x11A8 <= code <= 0x11FF or 0xD7CB <= code <= 0xD7FB:
            return "T"
        if 0xAC00 <= code <= 0xD7A3:
            return "LV" if (code - 0xAC00) % 28 == 0 else "LVT"
        return ""
    cluster, regional = "", 0
    for char in text:
        code = ord(char)
        is_regional = 0x1F1E6 <= code <= 0x1F1FF
        previous = cluster[-1:] or "\0"
        joins = (unicodedata.category(char).startswith("M") or char in {"\u200c", "\u200d"}
                 or previous == "\u200d" or 0x1F3FB <= code <= 0x1F3FF
                 or 0xE0020 <= code <= 0xE007F or previous == "\r" and char == "\n"
                 or is_regional and regional % 2 == 1
                 or (hangul(previous), hangul(char)) in {
                     ("L", "L"), ("L", "V"), ("L", "LV"), ("L", "LVT"),
                     ("LV", "V"), ("V", "V"), ("LV", "T"), ("V", "T"), ("LVT", "T"), ("T", "T")})
        if cluster and not joins:
            yield cluster
            cluster = ""
        cluster += char
        regional = regional + 1 if is_regional else 0
    if cluster:
        yield cluster


def extract_snippet(native_document, label, reference_text=None, max_chars=600, max_blocks=4, *, manifest=None):
    """Use canonical plain text, never serialized HTML, MathML or asset payloads."""
    if max_chars <= 0 or max_blocks <= 0:
        return None
    blocks = native_document["blocks"]
    def nodes(block):
        yield block
        for child in block.get("children", []):
            yield from nodes(child)
    anchor = (label or "").strip()
    query = " ".join((reference_text or "").split())
    match = next(((i, n) for i, b in enumerate(blocks) for n in nodes(b) if anchor and
                  anchor in n.get("anchors", [])), None)
    if match is None and query:
        match = next(((i, b) for i, b in enumerate(blocks) if any(
            _contains_case_insensitive(b.get(k, ""), query)
            for k in ("displayText", "canonicalText"))), None)
    start = match[0] if match else None
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
    result = {"text": text, "truncated": more}
    characters = list(islice(_graphemes(text), max_chars + 1))
    if len(characters) > max_chars:
        result = {"text": "".join(characters[:max_chars - 3]) + "..." if max_chars >= 3
                  else "".join(characters[:max_chars]), "truncated": True}
    if manifest is not None:
        anchors = manifest.get("anchors", {})
        # The imported block carries DOM IDs and passage keys; only a reader ID
        # present in this section's manifest is a navigable compiled anchor.
        result["anchor"] = next((candidate for candidate in ([match[1].get("passageKey")] + match[1].get("anchors", []))
            if isinstance(candidate, str) and candidate.startswith("reader-")
            and anchors.get(candidate) == section), None)
    return result


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
        return route + ("#" + quote(anchor, safe="") if anchor else "")
    except (ValueError, TypeError):
        return None


class CatalogAvailability:
    """Share one parsed catalog between previews and capability discovery."""
    def __init__(self):
        self.lock = threading.Lock()
        self.signature = None
        self.path = None
        self.catalog = None

    def load(self, package_path):
        path = Path(package_path)
        with self.lock:
            try:
                with _open_catalog(package_path) as (_fd, info):
                    signature = _signature(info)
                    if path == self.path and signature == self.signature:
                        return self.catalog
                catalog = CrossProjectCatalog.load(package_path)
                with _open_catalog(package_path) as (_fd, info):
                    if signature != _signature(info):
                        raise ValueError("Catalog changed during validation")
            except (OSError, ValueError, RuntimeError):
                self.signature = None
                self.catalog = None
                raise ValueError("Project reference catalog unavailable or invalid") from None
            self.path = path
            self.signature = signature
            self.catalog = catalog
            return catalog

    def check(self, package_path):
        try:
            self.load(package_path)
            return True
        except ValueError:
            return False


class PreviewImportCache:
    """One bounded accepted import per target; concurrent requests share work.

    Waiters release the condition lock, and imports never hold either this lock
    or the target publication lock. Failed imports are cached as metadata-only.
    """
    def __init__(self):
        self.condition = threading.Condition()
        self.cached = None
        self.importing = False

    def get(self, snapshot, document_id, incarnation):
        key = (document_id, snapshot.revision, incarnation)
        with self.condition:
            while True:
                if self.cached is not None and self.cached[0] == key and self.cached[1] is snapshot.bundle:
                    return self.cached[2]
                if not self.importing:
                    self.importing = True
                    break
                self.condition.wait()
        try:
            try:
                result = import_bounded_document(snapshot.bundle, document_id=document_id, service_id=incarnation)
            except (ValueError, TypeError, KeyError, UnicodeError, RecursionError, OSError):
                result = None
            with self.condition:
                self.cached = (key, snapshot.bundle, result)
            return result
        finally:
            with self.condition:
                self.importing = False
                self.condition.notify_all()


class CrossProjectPreviewService:
    def __init__(self, state, peer_lookup=None, *, allowed_origin=None):
        self.state = state
        self.peer_lookup = peer_lookup or (lambda _key, _title: None)
        self.allowed_origin = allowed_origin

    def catalog(self):
        return self.state.catalog_availability.load(self.state.project.packages)

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
        peer = self.peer_lookup(resolved["projectKey"], resolved["projectTitle"])
        if peer is None:
            return result
        target, route = peer
        result["targetUrl"] = target_url(route, result["anchor"], self.allowed_origin)
        if result["targetUrl"] is None:
            return result
        # Capture only publication identity under the target lock. Import and
        # snippet work use the retained accepted bundle outside that lock.
        try:
            with target.lock:
                snapshot = AcceptedSnapshot.capture(target, target.revision)
                document_id = target.document_id
                incarnation = service_id(target.focus.service)
            if snapshot is None or not snapshot.revision or snapshot.bundle.manifest["revision"] != snapshot.revision:
                return result
            imported = target.cross_project_imports.get(snapshot, document_id, incarnation)
            if imported is not None:
                snippet = extract_snippet(imported.document, resolved["label"], resolved["refText"],
                                          manifest=snapshot.bundle.manifest)
                with target.lock:
                    current = AcceptedSnapshot.capture(target, target.revision)
                    current_identity = (target.document_id, service_id(target.focus.service))
                if (current is None or current.bundle is not snapshot.bundle or current.revision != snapshot.revision
                        or current_identity != (document_id, incarnation)):
                    return result
                if snippet is not None:
                    result.update(snippet=snippet["text"], truncated=snippet["truncated"],
                                  anchor=snippet["anchor"],
                                  targetUrl=target_url(route, snippet["anchor"], self.allowed_origin))
        except (ValueError, TypeError, KeyError, UnicodeError, RecursionError, OSError):
            pass  # Keep the unique catalog metadata and safe mounted route.
        return result
