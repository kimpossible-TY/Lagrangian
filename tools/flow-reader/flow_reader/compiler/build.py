"""Isolated HTML compilation with shared content acceptance."""
from __future__ import annotations
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
import time
from flow_reader.compiler.audit import audit_content, normalize_content, unhandled_warnings
from flow_reader.compiler.project import Project
from flow_reader.compiler.packages import prepare_packages
from flow_reader.resources import READER_ROOT as HERE


def compile_project(project: Project, output: Path, *, geometry: dict | None = None,
                    canvases: dict | None = None, decorations: dict | None = None) -> dict:
    root = project.root.resolve()
    entry = project.relative_entry()
    output.mkdir(parents=True, exist_ok=True)
    wrapper = ('#import "@local/flow-reader:0.1.0": apply-reader\n'
               '#show: apply-reader\n'
               f'#include {json.dumps("/" + entry, ensure_ascii=False)}\n')
    started = time.monotonic()
    # The temporary package overlay lives beside the result, outside the source.
    with tempfile.TemporaryDirectory(prefix="compile-", dir=output) as temporary:
        work = Path(temporary)
        prepare_packages(project.packages.resolve(), work / "packages")
        command = [project.compiler, "compile", "--features", "html", "--root", str(root),
                   "--deps", str(work / "dependencies.json"),
                   "--package-path", str(work / "packages"), "--input", "flow-reader=true"]
        if project.semantic_canvases:
            command.extend(["--input", "flow-native-labels=true"])
        for font in project.fonts:
            command.extend(["--font-path", str((root / font).resolve())])
        if geometry is not None:
            command.extend(["--input", "flow-geometry=" + json.dumps(geometry, separators=(",", ":"))])
        if decorations is not None:
            command.extend(["--input", "flow-decorations=" + json.dumps(decorations, separators=(",", ":"))])
        if canvases is not None:
            command.extend(["--input", "flow-canvases=" + json.dumps(canvases, separators=(",", ":"))])
        command.extend(["-", str(work / "document.html")])
        result = subprocess.run(command, input=wrapper, text=True, capture_output=True, cwd=root)
        (output / "compile.log").write_text(result.stderr)
        report = {
            "schemaVersion": 1,
            "root": str(root),
            "entry": entry,
            "compiler": project.compiler,
            "exitCode": result.returncode,
            "elapsedSeconds": round(time.monotonic() - started, 3),
            "compiledAt": time.time(),
            "warnings": dict(Counter(line for line in result.stderr.splitlines()
                                     if line.startswith("warning:"))),
        }
        dependencies = {str((root / entry).resolve())}
        dependency_file = work / "dependencies.json"
        if dependency_file.exists():
            for filename in json.loads(dependency_file.read_text())["inputs"]:
                path = Path(filename)
                if path.name == "<stdin>":
                    continue
                if not path.is_absolute():
                    path = root / path
                # Map the temporary overlay back to the maintained package files.
                # Otherwise its deletion would look like a source edit every time.
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
            content = normalize_content((work / "document.html").read_text())
            (work / "document.html").write_text(content)
            report.update(audit_content(content))
            # Typst can successfully exit after dropping unsupported elements.
            # Page furniture and PDF structure tags have no HTML representation;
            # all other warnings block promotion until reviewed or fixed.
            report["compilerLossWarnings"] = [
                "warning: " + warning for warning in
                unhandled_warnings(line.removeprefix("warning: ") for line in report["warnings"])]
            report["contentGatePassed"] &= not report["compilerLossWarnings"]
            report["revision"] = hashlib.sha256(content.encode()).hexdigest()
            (work / "document.html").replace(output / "document.html")
        else:
            report["contentGatePassed"] = False
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
