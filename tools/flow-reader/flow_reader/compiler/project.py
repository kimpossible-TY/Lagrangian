"""Validated project compilation inputs."""
from dataclasses import dataclass, field
from pathlib import Path
from flow_reader.compiler.execution import CompileExecutor, local_compile

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
        entry = (self.root / self.entry).resolve()
        if not entry.is_file():
            raise ValueError(f"Missing entrypoint: {entry}")
        return entry.relative_to(self.root.resolve()).as_posix()
