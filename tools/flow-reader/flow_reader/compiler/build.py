"""Isolated HTML compilation with shared content acceptance."""
from __future__ import annotations
import argparse
from collections import Counter
from contextlib import contextmanager
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
import time
from flow_reader.compiler.audit import audit_compiled_html
from flow_reader.compiler.project import Project
from flow_reader.compiler.execution import CompileRequest
from flow_reader.compiler.packages import prepare_packages
from flow_reader.compiler.source_map import compile_source_map
from flow_reader.resources import READER_ROOT as HERE


@contextmanager
def document_request(project: Project, output: Path, *, geometry=None, canvases=None,
                     decorations=None, timestamp=None, system_fonts=None):
    """Own the prepared HTML request and its temporary package overlay lifetime."""
    root = project.root.resolve()
    entry = project.relative_entry()
    output.mkdir(parents=True, exist_ok=True)
    wrapper = ('#import "@local/flow-reader:0.1.0": apply-reader\n'
               '#show: apply-reader\n'
               f'#include {json.dumps("/" + entry, ensure_ascii=False)}\n')
    # The temporary package overlay lives beside the result, outside the source.
    with tempfile.TemporaryDirectory(prefix="compile-", dir=output) as temporary:
        work = Path(temporary)
        prepare_packages(project.packages.resolve(), work / "packages")
        inputs = [("flow-reader", "true")]
        if project.semantic_canvases:
            inputs.append(("flow-native-labels", "true"))
        for key, value in (("flow-geometry", geometry), ("flow-decorations", decorations),
                           ("flow-canvases", canvases)):
            if value is not None:
                inputs.append((key, json.dumps(value, separators=(",", ":"))))
        purpose = ("graphics" if geometry is not None else "canvases" if canvases is not None
                   else "decorations" if decorations is not None else "document")
        request = CompileRequest(
            compiler=project.compiler, root=root, packages=work / "packages", target="html",
            source=wrapper, fonts=tuple((root / font).resolve() for font in project.fonts),
            timestamp=timestamp if timestamp is not None else int(time.time()),
            system_fonts=True if system_fonts is None else system_fonts,
            inputs=tuple(inputs), purpose=purpose, timeout=180 if purpose == "document" else 90)
        prepare_request = getattr(project.execute, "prepare_request", None)
        if timestamp is None and system_fonts is None and callable(prepare_request):
            request = prepare_request(request)
        yield request, work


def compile_document_source_map(project: Project, output: Path, dependencies, baseline: str, *,
                                request=None, work=None, timestamp=None, system_fonts=None) -> dict:
    """Compile optional correspondence with the same inputs as an ordinary document."""
    try:
        if request is not None:
            if work is None:
                raise ValueError("A prepared request needs its live work directory")
            return compile_source_map(project, dependencies, request, baseline, work)
        with document_request(project, output, timestamp=timestamp,
                              system_fonts=system_fonts) as (request, work):
            return compile_source_map(project, dependencies, request, baseline, work)
    except (OSError, ValueError, RecursionError, subprocess.TimeoutExpired):
        return {"sourceMap": {}, "sourceMapStatus": "unavailable"}


def compile_project(project: Project, output: Path, *, geometry: dict | None = None,
                    canvases: dict | None = None, decorations: dict | None = None,
                    map_sources: bool = True) -> dict:
    root = project.root.resolve()
    entry = project.relative_entry()
    started = time.monotonic()
    with document_request(project, output, geometry=geometry, canvases=canvases,
                          decorations=decorations) as (request, work):
        result = project.execute(request)
        if result.returncode == 0 and result.executor == "browser":
            retry = getattr(project.execute, "fallback_after_rejection", None)
            if callable(retry):
                try:
                    _, candidate = audit_compiled_html(result.artifact.decode("utf-8"), result.stderr)
                    accepted = candidate["contentGatePassed"]
                except (AttributeError, UnicodeDecodeError, ValueError, RecursionError):
                    accepted = False
                if not accepted:
                    result = retry(request)
        (output / "compile.log").write_text(result.stderr)
        report = {
            "schemaVersion": 1,
            "root": str(root),
            "entry": entry,
            "compiler": project.compiler,
            "compileInputs": {"timestamp": request.timestamp, "systemFonts": request.system_fonts},
            "exitCode": result.returncode,
            "elapsedSeconds": round(time.monotonic() - started, 3),
            "compiledAt": time.time(),
            "warnings": dict(Counter(line for line in result.stderr.splitlines()
                                     if line.startswith("warning:"))),
        }
        dependencies = {str((root / entry).resolve())}
        for filename in result.dependencies:
            path = Path(filename)
            if path.name == "<stdin>":
                continue
            if not path.is_absolute():
                path = root / path
            # Map the temporary overlay back to the maintained package files.
            path = path.resolve()
            overlay_root = (work / "packages").resolve()
            if path.is_relative_to(overlay_root):
                relative = path.relative_to(overlay_root)
                adapter = HERE / "packages" / relative
                adapter_manifest = HERE / "packages" / Path(*relative.parts[:3]) / "typst.toml"
                path = adapter if adapter_manifest.exists() else project.packages / relative
            dependencies.add(str(path.resolve()))
        report["dependencies"] = sorted(dependencies)
        if result.returncode == 0:
            content, audit = audit_compiled_html(result.artifact.decode("utf-8"), result.stderr)
            (work / "document.html").write_text(content)
            report.update(audit)
            if map_sources and report["contentGatePassed"] and all(
                    value is None for value in (geometry, canvases, decorations)):
                report.update(compile_document_source_map(project, output, dependencies, content,
                                                          request=request, work=work))
            report["revision"] = hashlib.sha256(content.encode()).hexdigest()
            (work / "document.html").replace(output / "document.html")
        else:
            report["contentGatePassed"] = False
        report.update(elapsedSeconds=round(time.monotonic() - started, 3), compiledAt=time.time())
        (output / "report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
        return report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--entry", type=Path, default=Path("main.typ"))
    parser.add_argument("--package-path", type=Path, required=True)
    parser.add_argument("--font-path", type=Path, action="append", default=[])
    parser.add_argument("--compiler", default="typst")
    parser.add_argument("--semantic-canvases", action="store_true",
                        help="Evaluate native figure labels independently of vector geometry")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    project = Project(args.root, args.entry, args.package_path, tuple(args.font_path), args.compiler,
                      args.semantic_canvases)
    report = compile_project(project, args.output.resolve())
    print(json.dumps(report, ensure_ascii=False, indent=2))
    # Compiling alone is not proof of faithful output; callers must check the gate.
    return 0 if report["contentGatePassed"] else 1
