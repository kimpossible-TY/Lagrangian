"""Persistent visual edit targets, following the paged preview's change tracker."""

from difflib import SequenceMatcher
import hashlib
from html.parser import HTMLParser
import json
import logging
import os
from pathlib import Path
import re
import tempfile
import uuid


MAX_RECORD_BYTES = 4 * 1024 * 1024
MAX_BLOCKS = 50000
VOID = {"area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta",
        "param", "source", "track", "wbr"}


def digest(value):
    return hashlib.sha256(value.encode()).hexdigest()


class VisualBlocks(HTMLParser):
    """Fingerprint authored body units without generated IDs or navigation copies."""

    def __init__(self, source, section):
        super().__init__(convert_charrefs=True)
        self.section = section
        self.stack = []
        self.active = []
        self.blocks = []
        self.feed(source)

    def append(self, value, linked=False):
        in_link = linked or any(tag == "a" for tag, _, _ in self.stack)
        for block in self.active:
            block["all"].append(value)
            if not in_link:
                block["body"].append(value)

    def handle_starttag(self, tag, attrs):
        attributes = dict(attrs)
        excluded = (bool(self.stack and self.stack[-1][1]) or
                    tag in {"nav", "script", "style", "head"} or
                    "data-flow-targets" in attributes)
        block = None
        in_body = any(parent == "body" for parent, _, _ in self.stack)
        target = attributes.get("id")
        key = attributes.get("data-reader-key")
        figure = tag == "figure" or "data-flow-canvas" in attributes
        if in_body and not excluded and target and (key or figure):
            # The native canvas owns its geometry and label changes as one unit.
            if not any(item["figure"] for item in self.active):
                block = {"key": key, "target": target, "section": self.section,
                         "figure": figure, "all": [], "body": []}
                self.active.append(block)
                self.blocks.append(block)
        if not excluded:
            # Generated references/keys and responsive numbering are identities,
            # not paint. Internal SVG resources are normalized below as well.
            paint = [(name, value) for name, value in attrs
                     if name not in {"id", "data-reader-key", "data-flow-canvas-identity"}
                     and name not in {"data-flow-canvas", "data-flow-mark", "data-flow-graphic",
                                      "data-flow-decoration", "data-flow-decoration-layers"}
                     and not (name in {"href", "xlink:href"} and
                              (value or "").startswith("#") and
                              not any(parent == "svg" for parent, _, _ in self.stack))]
            paint = [(name, re.sub(r"(?:flow-svg|loc|canvas|graphic|decoration)-\d+", "generated", value or ""))
                     for name, value in paint]
            self.append(json.dumps([tag, sorted(paint)], ensure_ascii=False), linked=tag == "a")
        if tag not in VOID:
            self.stack.append((tag, excluded, block))

    def handle_startendtag(self, tag, attrs):
        self.handle_starttag(tag, attrs)
        if tag not in VOID:
            self.handle_endtag(tag)

    def handle_endtag(self, tag):
        if not self.stack or self.stack[-1][0] != tag:
            return
        _, excluded, block = self.stack.pop()
        if not excluded:
            self.append("/" + tag, linked=tag == "a")
        if block:
            self.active.remove(block)

    def handle_data(self, data):
        if self.stack and not self.stack[-1][1] and (value := " ".join(data.split())):
            self.append(value)

    def snapshot(self):
        return [{"key": block["key"], "target": block["target"], "section": block["section"],
                 "hash": digest("\n".join(block["all"])),
                 "bodyHash": digest("\n".join(block["body"]))} for block in self.blocks]


def input_fingerprint(project, dependencies):
    """Content changes count as edits; compiler binaries and mtimes do not."""
    files = {project.root / project.entry} | {Path(path) for path in dependencies}
    result = hashlib.sha256()
    for path in sorted(files):
        if not path.is_file():
            continue
        result.update(str(path).encode())
        with path.open("rb") as source:
            while chunk := source.read(65536):
                result.update(chunk)
    return result.hexdigest()


class ChangeTracker:
    def __init__(self, path, document_id):
        self.path = path
        self.document_id = document_id
        self.record = None
        try:
            with path.open("rb") as source:
                content = source.read(MAX_RECORD_BYTES + 1)
            if len(content) > MAX_RECORD_BYTES:
                return
            record = json.loads(content)
            blocks = record["blocks"]
            if (record["schema"] == 1 and record["documentID"] == document_id and
                    isinstance(record["inputs"], str) and isinstance(blocks, list) and
                    len(blocks) <= MAX_BLOCKS and all(self.valid_block(block) for block in blocks) and
                    (record["last"] is None or (self.valid_block(record["last"]) and
                     isinstance(record["last"].get("token"), str)))):
                self.record = record
        except (OSError, ValueError, KeyError, TypeError, RecursionError):
            pass

    @staticmethod
    def valid_block(block):
        return isinstance(block, dict) and all(
            isinstance(block.get(name), str) and 0 < len(block[name]) <= 1024
            for name in ("target", "section", "hash", "bodyHash")) and (
                block.get("key") is None or
                isinstance(block["key"], str) and len(block["key"]) <= 128)

    def observe(self, bundle, inputs):
        blocks = [block for section, source in bundle.documents.items()
                  for block in VisualBlocks(source.decode(), section).snapshot()]
        if not blocks or len(blocks) > MAX_BLOCKS:
            return None
        previous = self.record
        last = previous["last"] if previous else None
        if previous and previous["inputs"] != inputs:
            # Prefer authored text/paint over earlier generated reference copies.
            for field in ("bodyHash", "hash"):
                old = [block[field] for block in previous["blocks"]]
                new = [block[field] for block in blocks]
                edits = [entry for entry in SequenceMatcher(None, old, new, autojunk=False).get_opcodes()
                         if entry[0] != "equal"]
                if edits:
                    _, _, _, first, _ = edits[0]
                    last = {**blocks[min(first, len(blocks) - 1)], "token": uuid.uuid4().hex}
                    break
        if last:
            # Relocate across numbering/section changes without inventing an edit.
            matches = [block for block in blocks if block["hash"] == last["hash"]]
            keyed = [block for block in blocks if last["key"] and block["key"] == last["key"]]
            match = keyed[0] if len(keyed) == 1 else matches[0] if len(matches) == 1 else None
            last = {**match, "token": last["token"]} if match else None
        self.record = {"schema": 1, "documentID": self.document_id, "inputs": inputs,
                       "blocks": blocks, "last": last}
        try:
            self.persist()
        except OSError as error:
            logging.getLogger(__name__).warning("Could not persist Reader edit history: %s", error)
        return ({key: last[key] for key in ("token", "key", "target", "section")} |
                {"revision": bundle.manifest["revision"]}) if last else None

    def persist(self):
        content = json.dumps(self.record, ensure_ascii=False).encode()
        if len(content) > MAX_RECORD_BYTES:
            return
        self.path.parent.mkdir(parents=True, exist_ok=True)
        temporary = None
        try:
            with tempfile.NamedTemporaryFile(dir=self.path.parent, delete=False) as output:
                temporary = Path(output.name)
                output.write(content)
                output.flush()
                os.fsync(output.fileno())
            temporary.replace(self.path)
        finally:
            if temporary:
                temporary.unlink(missing_ok=True)
