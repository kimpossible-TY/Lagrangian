"""Raw compiler execution; acceptance and source mutation belong to callers.

Requests describe one invocation, not an authorization to publish its output.
Browser executors must capture these filesystem inputs before offering a job.
"""
from dataclasses import dataclass
import json
from pathlib import Path
import subprocess
import tempfile
import time
from typing import Literal, Protocol


@dataclass(frozen=True)
class CompileRequest:
    compiler: str
    root: Path
    packages: Path
    target: Literal["html", "pdf"]
    entry: Path | None = None
    source: str | None = None
    fonts: tuple[Path, ...] = ()
    inputs: tuple[tuple[str, str], ...] = ()
    timeout: float = 90
    system_fonts: bool = True
    timestamp: int | None = None
    purpose: str = "compile"

    def __post_init__(self):
        if (self.entry is None) == (self.source is None):
            raise ValueError("Compile exactly one entry or stdin source")
        if self.target not in {"html", "pdf"}:
            raise ValueError("Unsupported compiler target")
        if self.timeout <= 0:
            raise ValueError("Compilation needs a positive timeout")


@dataclass(frozen=True)
class CompileResult:
    returncode: int
    stderr: str
    artifact: bytes | None
    dependencies: tuple[str, ...]
    elapsed_seconds: float


class CompileExecutor(Protocol):
    def __call__(self, request: CompileRequest) -> CompileResult: ...


def font_arguments(fonts, work):
    """Expose explicit font files to the directory-searching Typst CLI."""
    arguments = []
    for index, font in enumerate(fonts):
        if font.is_file():
            directory = work / f"font-{index}"
            directory.mkdir()
            (directory / font.name).symlink_to(font.resolve())
            font = directory
        arguments.extend(["--font-path", str(font)])
    return arguments


def local_compile(request: CompileRequest) -> CompileResult:
    """Run the existing CLI in an isolated output directory with bounded lifetime."""
    started = time.monotonic()
    with tempfile.TemporaryDirectory(prefix="flow-execute-") as temporary:
        work = Path(temporary)
        output = work / ("document." + request.target)
        dependencies = work / "dependencies.json"
        # Keep the Reader fallback within one CPU job alongside the native preview.
        command = [request.compiler, "compile", "--jobs", "1", "--root", str(request.root),
                   "--package-path", str(request.packages), "--deps", str(dependencies)]
        if request.target == "html":
            command.extend(["--features", "html"])
        if not request.system_fonts:
            command.append("--ignore-system-fonts")
        if request.timestamp is not None:
            command.extend(["--creation-timestamp", str(request.timestamp)])
        command.extend(font_arguments(request.fonts, work))
        for key, value in request.inputs:
            command.extend(["--input", key + "=" + value])
        command.extend([str(request.entry) if request.entry is not None else "-", str(output)])
        result = subprocess.run(command, input=request.source, text=True,
                                capture_output=True, cwd=request.root, timeout=request.timeout)
        inputs = tuple(json.loads(dependencies.read_text())["inputs"]) if dependencies.exists() else ()
        return CompileResult(result.returncode, result.stderr,
                             output.read_bytes() if result.returncode == 0 else None,
                             inputs, time.monotonic() - started)
