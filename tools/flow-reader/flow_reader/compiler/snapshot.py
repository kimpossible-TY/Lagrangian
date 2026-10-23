"""Bounded immutable input bundles for executors without filesystem access."""
from dataclasses import dataclass
import base64
import hashlib
import json
from pathlib import Path

from flow_reader.compiler.execution import CompileRequest
from flow_reader.compiler.packages import package_cache_root
from flow_reader.resources import READER_ROOT

MAX_FILES = 8192
MAX_BYTES = 128 * 1024 * 1024
FONT_SUFFIXES = {".ttf", ".otf", ".ttc", ".otc"}
WRAPPER = "/workspace/.flow-reader-entry.typ"


class SnapshotUnavailable(ValueError):
    """Inputs cannot safely be represented by this bounded snapshot."""


@dataclass(frozen=True)
class SnapshotFile:
    path: str
    digest: str
    content: bytes

    def wire(self):
        return {"path": self.path, "sha256": self.digest,
                "data": base64.b64encode(self.content).decode("ascii")}


@dataclass(frozen=True)
class CompileSnapshot:
    identity: str
    engine: str
    target: str
    entry: str
    inputs: tuple[tuple[str, str], ...]
    timestamp: int
    files: tuple[SnapshotFile, ...]
    fonts: tuple[SnapshotFile, ...]
    # Server-only reverse mapping; never transmit host filesystem paths.
    paths: tuple[tuple[str, str], ...]

    def wire(self):
        return {"schemaVersion": 1, "identity": self.identity, "engine": self.engine,
                "target": self.target, "entry": self.entry, "inputs": dict(self.inputs),
                "timestamp": self.timestamp, "files": [file.wire() for file in self.files],
                "fonts": [font.wire() for font in self.fonts]}

    def dependencies(self, names):
        mapping = dict(self.paths)
        if any(name not in mapping and name != WRAPPER for name in names):
            raise SnapshotUnavailable("Compiler requested inputs outside its captured bundle")
        return tuple(mapping[name] for name in names if name != WRAPPER)


def capture_snapshot(request: CompileRequest, project, dependencies, engine: str) -> CompileSnapshot:
    """Capture accepted dependencies using the candidate's root and package overlay.

    No recursive project scan and no lazy reads after capture. New imports require
    native discovery and a new snapshot; they cannot enrich an already leased job.
    """
    if request.system_fonts or request.timestamp is None:
        raise SnapshotUnavailable("Browser compilation needs explicit fonts and a fixed timestamp")
    cache = package_cache_root()
    roots = ((project.packages.resolve(), "/packages", request.packages),
             ((READER_ROOT / "packages").resolve(), "/packages", request.packages),
             (cache, "/packages", cache),
             (project.root.resolve(), "/workspace", request.root))
    paths = {}
    for filename in dependencies:
        path = Path(filename).resolve()
        for original, virtual, current in roots:
            if path.is_relative_to(original):
                relative = path.relative_to(original)
                if virtual == "/packages":
                    if len(relative.parts) < 4:
                        raise SnapshotUnavailable("Invalid package dependency")
                    version = Path(*relative.parts[:3])
                    # A maintained adapter replaces a complete package version.
                    # Never mix its files with the cached upstream version.
                    if (request.packages / version / "typst.toml").is_file():
                        current = request.packages
                paths[virtual + "/" + relative.as_posix()] = current / relative
                break
        else:
            raise SnapshotUnavailable(f"Unrepresentable dependency: {path.name}")
    for name in list(paths):
        if name.startswith("/packages/"):
            version = Path(*Path(name).parts[2:5])
            relative = Path(*Path(name).parts[2:])
            package_root = paths[name]
            for _ in relative.parts:
                package_root = package_root.parent
            paths["/packages/" + version.as_posix() + "/typst.toml"] = package_root / version / "typst.toml"
    if request.entry is not None:
        relative = request.entry.absolute().relative_to(request.root.absolute())
        entry = "/workspace/" + relative.as_posix()
        paths[entry] = request.entry
    else:
        entry = WRAPPER
        if WRAPPER in paths or (request.root / Path(WRAPPER).name).exists():
            raise SnapshotUnavailable("Reserved wrapper path already exists")

    font_paths = []
    for root in request.fonts:
        if root.is_file():
            font_paths.append(root)
        elif root.is_dir():
            font_paths.extend(sorted(path for path in root.rglob("*")
                                     if path.is_file() and path.suffix.lower() in FONT_SUFFIXES))
        else:
            raise SnapshotUnavailable("Configured font path is unavailable")
    if len(paths) + len(font_paths) + (request.source is not None) > MAX_FILES:
        raise SnapshotUnavailable("Compiler input file limit exceeded")

    captured = []
    total = 0
    def read(name, path):
        nonlocal total
        # Bound allocation before reading, then check again if a file grew.
        if path.stat().st_size > MAX_BYTES - total:
            raise SnapshotUnavailable("Compiler input byte limit exceeded")
        with path.open("rb") as source:
            content = source.read(MAX_BYTES - total + 1)
        total += len(content)
        if total > MAX_BYTES:
            raise SnapshotUnavailable("Compiler input byte limit exceeded")
        digest = hashlib.sha256(content).hexdigest()
        captured.append((path, digest))
        return SnapshotFile(name, digest, content)

    files = [read(name, path) for name, path in sorted(paths.items())]
    fonts = [read(f"font-{index}", path) for index, path in enumerate(font_paths)]
    if request.source is not None:
        content = request.source.encode("utf-8")
        total += len(content)
        if total > MAX_BYTES:
            raise SnapshotUnavailable("Compiler input byte limit exceeded")
        files.append(SnapshotFile(WRAPPER, hashlib.sha256(content).hexdigest(), content))
    # Verify the complete read set after capturing it, including package and font bytes.
    for path, digest in captured:
        with path.open("rb") as source:
            current = hashlib.file_digest(source, "sha256").hexdigest()
        if current != digest:
            raise SnapshotUnavailable("Compiler inputs changed during capture")
    inputs = tuple(sorted(dict(request.inputs).items()))
    identity = hashlib.sha256(json.dumps({
        "engine": engine, "target": request.target, "entry": entry, "inputs": inputs,
        "timestamp": request.timestamp,
        "files": [(file.path, file.digest) for file in files],
        "fonts": [(font.path, font.digest) for font in fonts],
    }, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
    return CompileSnapshot(identity, engine, request.target, entry, inputs, request.timestamp,
                           tuple(files), tuple(fonts),
                           tuple((name, str(path)) for name, path in paths.items()))
