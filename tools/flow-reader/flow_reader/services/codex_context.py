"""Explicit, revision-bound Codex context for the HTML and terminal Reader."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import tempfile
import threading
import time
from urllib.parse import urlsplit
from urllib.request import urlopen

from flow_reader.document.passages import locate_passages, occurrences, validate_fragments


MAX_TEXT = 8000


def selected_text(bundle, fragments):
    """Accept only bounded quotations from the submitted accepted body blocks."""
    clean = validate_fragments(fragments)
    text = "\n".join(part["exact"] for part in fragments)
    if not text.strip() or len(text) > MAX_TEXT:
        raise ValueError("Select at most 8000 characters for Codex")
    by_key = {part["key"]: part for part in bundle.passages}
    if any(part["key"] not in by_key or part["exact"] not in by_key[part["key"]]["text"]
           for part in clean):
        raise ValueError("Selection does not identify the accepted body blocks")
    locations = locate_passages(bundle.passages, clean)
    for part, location in zip(clean, locations):
        if location["state"] == "located":
            start = list(occurrences(by_key[part["key"]]["text"], part["exact"]))[location["occurrence"]]
            location.update(start=start, end=start + len(part["exact"]))
        else:
            # Repeated accepted text is still usable context. Never invent an
            # occurrence or source offset when its local context cannot choose.
            location.update(key=part["key"], section=by_key[part["key"]]["section"],
                            start=None, end=None)
    return text, locations


def source_context(location):
    """Read one verified literal source position using the paged focus fields."""
    if location.get("status") != "located":
        return None
    path = Path(location["path"])
    data = path.read_bytes()
    if hashlib.sha256(data).hexdigest() != location["source_hash"]:
        raise ValueError("The selected source changed")
    lines = data.decode("utf-8").splitlines()
    line = location["line"]
    start = max(1, line - 8)
    excerpt = "\n".join(lines[start - 1:start + 16])
    column = len(lines[line - 1].encode("utf-8")[:location["column"]].decode("utf-8")) + 1
    return {"filepath": str(path), "line": line, "column": column,
            "excerpt_start_line": start, "excerpt": excerpt[:8000],
            "excerpt_truncated": len(excerpt) > 8000 or len(lines) > start + 16,
            "sha256": location["source_hash"]}


class FocusStore:
    """One private, atomic last-selection record per Reader service."""

    def __init__(self, path, project, document_id):
        self.path = Path(path)
        if not self.path.is_absolute():
            raise ValueError("Reader focus file must be absolute")
        self.service = {"pid": os.getpid(), "startedAt": time.time_ns() // 1000000}
        self.project = project
        self.document_id = document_id
        self.sequence = 0
        self.lock = threading.RLock()
        self.record("waiting", None, None)

    def record(self, status, rendered_revision, compiled_revision, *, selection=None,
               source=None, position=None, viewer_id=0):
        with self.lock:
            self.sequence += 1
            snapshot = {
                "schema_version": 1, "reader_kind": "html",
                "server_pid": self.service["pid"],
                "server_started_at_unix_ms": self.service["startedAt"],
                "sequence": self.sequence, "viewer_id": viewer_id,
                "selected_at_unix_ms": time.time_ns() // 1000000 if selection else 0,
                "status": status, "position": position,
                "rendered_revision": rendered_revision, "compiled_revision": compiled_revision,
                "source": source, "selection": selection,
                "document_id": self.document_id, "project_root": str(self.project.root.resolve()),
                "document": str((self.project.root / self.project.entry).resolve()),
            }
            self.path.parent.mkdir(parents=True, exist_ok=True)
            descriptor, temporary = tempfile.mkstemp(prefix=".focus-", dir=self.path.parent)
            try:
                with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
                    json.dump(snapshot, handle, ensure_ascii=False)
                    handle.flush()
                    os.fsync(handle.fileno())
                Path(temporary).replace(self.path)
            finally:
                Path(temporary).unlink(missing_ok=True)
            return snapshot

    def read(self, revision, inputs_current):
        """Check service, accepted revision, age and source drift on every read."""
        with self.lock:
            data = json.loads(self.path.read_text())
        if data.get("schema_version") != 1 or data.get("reader_kind") != "html":
            raise ValueError("Unsupported Reader focus record")
        service_matches = (data.get("server_pid") == self.service["pid"]
                           and data.get("server_started_at_unix_ms") == self.service["startedAt"]
                           and data.get("document_id") == self.document_id
                           and data.get("project_root") == str(self.project.root.resolve())
                           and data.get("document") == str((self.project.root / self.project.entry).resolve()))
        selected_at = data.get("selected_at_unix_ms", 0)
        age = max(0, time.time() - selected_at / 1000) if selected_at else None
        revision_matches = bool(revision and data.get("rendered_revision") == revision
                                and data.get("compiled_revision") == revision and inputs_current)
        source_matches = None
        source = data.get("source")
        if source:
            try:
                path = Path(source["filepath"]).resolve()
                # A record is context, never authority to read outside this project.
                if path.is_relative_to(self.project.root.resolve()):
                    raw = path.read_bytes()
                    start = source["excerpt_start_line"] - 1
                    excerpt = "\n".join(raw.decode("utf-8").splitlines()[start:start + 17])[:8000]
                    source_matches = (hashlib.sha256(raw).hexdigest() == source["sha256"]
                                      and excerpt == source["excerpt"])
            except (OSError, UnicodeError, KeyError, TypeError):
                source_matches = False
        usable = bool(service_matches and revision_matches and age is not None and age <= 300
                      and data.get("status") in {"selected", "unmapped"}
                      and data.get("selection") and (not source or source_matches is True))
        return {**data, "age_seconds": round(age, 1) if age is not None else None,
                "service_matches": service_matches, "revision_matches": revision_matches,
                "source_excerpt_matches_disk": source_matches, "selection_usable": usable,
                "needs_reselection": not (usable and source_matches is True)}


def read_reader(url, *, expected_pid=None, project=None, document=None):
    """Read a configured loopback Reader; never infer a service from recency."""
    parsed = urlsplit(url)
    if (parsed.scheme != "http" or parsed.hostname not in {"127.0.0.1", "localhost", "::1"}
            or parsed.username or parsed.password or parsed.query or parsed.fragment):
        raise ValueError("Expected a configured loopback Reader URL")
    with urlopen(url.rstrip("/") + "/api/focus", timeout=5) as response:
        data = json.load(response)
    if data.get("reader_kind") != "html" or data.get("schema_version") != 1:
        raise ValueError("Unsupported Reader focus response")
    if ((expected_pid is not None and data.get("server_pid") != expected_pid)
            or (project is not None and data.get("project_root") != str(Path(project).resolve()))
            or (document is not None and data.get("document") != str(Path(document).resolve()))):
        data.update(service_matches=False, selection_usable=False, needs_reselection=True)
    return data


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--url", required=True, help="Explicit local Reader origin, including its port")
    args = parser.parse_args()
    print(json.dumps(read_reader(args.url), ensure_ascii=False, indent=2))
