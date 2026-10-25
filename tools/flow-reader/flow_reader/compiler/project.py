"""Validated project compilation inputs."""
from dataclasses import dataclass, field
import hashlib
import json
from pathlib import Path
from flow_reader.compiler.execution import CompileExecutor, local_compile


def document_identity(root, entry):
    root = Path(root).resolve()
    relative = _relative_entry(root, entry)
    return hashlib.sha256(json.dumps([str(root), relative]).encode()).hexdigest()[:24]


def _relative_entry(root, entry):
    entry = (root / entry).resolve()
    if not entry.is_file():
        raise ValueError(f"Missing entrypoint: {entry}")
    return entry.relative_to(root.resolve()).as_posix()

@dataclass(frozen=True)
class Project:
    root: Path
    entry: Path
    packages: Path
    fonts: tuple[Path, ...] = ()
    compiler: str = "typst"
    semantic_canvases: bool = False
    execute: CompileExecutor = field(default=local_compile, compare=False, repr=False)

    def relative_entry(self) -> str:
        return _relative_entry(self.root, self.entry)
