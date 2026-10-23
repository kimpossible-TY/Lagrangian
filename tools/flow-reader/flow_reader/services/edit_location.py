"""Read the paged engine's saved source edit without becoming another writer."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess

from flow_reader.services.source_mapping import source_position

MAX_RECORD_BYTES = 16 * 1024 * 1024
MAX_SOURCE_BYTES = 2 * 1024 * 1024


def resolve_engine(requested=None):
    """Resolve the source-history executable separately from the HTML compiler."""
    selected = requested or os.environ.get("FLOW_ENGINE_PATH")
    candidates = ([selected] if selected else [
        Path.home() / "Applications/tinymist-flow.app/Contents/MacOS/flow-engine", "tinymist"])
    for candidate in candidates:
        executable = shutil.which(str(Path(candidate).expanduser()))
        if executable:
            return str(Path(executable).resolve())
    raise ValueError("A source-history capable Flow engine is required; pass --engine PATH "
                     "or set FLOW_ENGINE_PATH to the newly built flow-engine executable")


def read_json(path):
    with path.open("rb") as stream:
        content = stream.read(MAX_RECORD_BYTES + 1)
    if len(content) > MAX_RECORD_BYTES:
        raise ValueError("Edit history is oversized")
    return json.loads(content)


class SharedEditLocation:
    """One exact root/entry selects one source history, never the newest profile."""

    def __init__(self, root, entry, change_file=None, data=None):
        self.root = Path(root).resolve()
        self.entry = (self.root / entry).resolve()
        self.path = Path(change_file).resolve() if change_file else None
        self.discovery = "unavailable"
        if not self.entry.is_relative_to(self.root):
            self.discovery = "invalid"
        elif self.path is None:
            support = Path(data or os.environ.get("FLOW_DATA_DIR") or
                           Path.home() / "Library/Application Support/tinymist-flow")
            try:
                settings = read_json(support / "profiles.json")
                if settings.get("schemaVersion") != 1 or not isinstance(settings.get("profiles"), list):
                    raise ValueError("Invalid Flow profiles")
                matches = []
                for profile in settings["profiles"]:
                    root = Path(profile["root"]).resolve()
                    entry = (root / profile["entry"]).resolve()
                    if root == self.root and entry == self.entry:
                        identifier = profile["id"]
                        if not re.fullmatch(r"[a-z0-9][a-z0-9-]{0,63}", identifier):
                            raise ValueError("Invalid Flow profile ID")
                        matches.append(support / "changes" / (identifier + ".json"))
                if len(matches) == 1:
                    self.path = matches[0].resolve()
                elif matches:
                    self.discovery = "ambiguous"
            except FileNotFoundError:
                pass
            except (OSError, ValueError, KeyError, TypeError, AttributeError, RecursionError):
                self.discovery = "invalid"

    def stamp(self):
        try:
            stat = self.path.stat() if self.path else None
            return (stat.st_mtime_ns, stat.st_size, stat.st_ino) if stat else self.discovery
        except OSError:
            return "missing"

    @property
    def configured(self):
        return self.path is not None or self.discovery != "unavailable"

    def discover_engine_record(self, engine=None):
        """Find the engine's default path without observing or writing history."""
        if self.path is not None or self.discovery != "unavailable":
            return
        try:
            executable = resolve_engine(engine)
            result = subprocess.run([executable, "source-history", "--path-only",
                                     "--root", str(self.root), "--entry", str(self.entry)],
                                    text=True, capture_output=True, timeout=20)
            if result.returncode:
                return
            value = json.loads(result.stdout)
            path = Path(value["path"])
            if path.is_absolute():
                self.path = path.resolve()
        except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError):
            pass

    def read(self):
        if not self.entry.is_relative_to(self.root):
            return {"status": "invalid"}
        if self.path is None:
            return {"status": self.discovery}
        try:
            record = read_json(self.path)
            identity = json.loads(record["project"])
            if (record["schema_version"] != 2 or not isinstance(identity, list) or len(identity) != 2
                    or [str(Path(value).resolve()) for value in identity] !=
                    [str(self.root), str(self.entry)]):
                return {"status": "wrong-project"}
            history = record["source_history"]
            edit = history["latest"]
            if edit is None:
                return {"status": "empty"}
            sequence = history["sequence"]
            sources = history["sources"]
            if (type(sequence) is not int or not 0 < sequence <= 2**64 - 1
                    or not isinstance(sources, dict) or len(sources) > 256
                    or any(not isinstance(value, str) for value in sources.values())
                    or sum(len(value.encode("utf-8")) for value in sources.values()) > MAX_SOURCE_BYTES):
                raise ValueError("Invalid source history")
            path = Path(edit["filepath"])
            if not path.is_absolute() or not path.resolve().is_relative_to(self.root):
                raise ValueError("Source is outside the project")
            source = sources[str(path)]
            saved = source.encode("utf-8")
            start, end = edit["range"]["start"], edit["range"]["end"]
            if (type(start) is not int or type(end) is not int or not 0 <= start <= end <= len(saved)
                    or not re.fullmatch(r"[0-9a-fA-F]{32}", edit["source_hash"])):
                raise ValueError("Invalid source range")
            prefix = saved[:start].decode("utf-8")
            selected = saved[start:end].decode("utf-8")
            with path.open("rb") as stream:
                current = stream.read(MAX_SOURCE_BYTES + 1)
            # Comparing exact source bytes also avoids depending on Rust's private hash algorithm.
            if current != saved:
                return {"status": "stale"}
            token = hashlib.sha256(json.dumps([identity, sequence]).encode()).hexdigest()
            return {"status": "located", "path": str(path.resolve()),
                    "source_hash": hashlib.sha256(saved).hexdigest(), "token": token,
                    "start": len(prefix), "end": len(prefix) + len(selected),
                    **source_position(source, len(prefix))}
        except FileNotFoundError:
            return {"status": "missing"}
        except (OSError, ValueError, KeyError, TypeError, AttributeError, RecursionError):
            return {"status": "invalid"}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--entry", type=Path, default=Path("main.typ"))
    parser.add_argument("--change-file", type=Path)
    parser.add_argument("--engine", help="Flow engine used only to discover the shared record path")
    args = parser.parse_args()
    location = SharedEditLocation(args.root, args.entry, args.change_file)
    location.discover_engine_record(args.engine)
    print(json.dumps(location.read(), ensure_ascii=False))
