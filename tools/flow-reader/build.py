#!/usr/bin/env python3
"""Build the independent HTML reader without changing the paged installation."""

from __future__ import annotations

import argparse
from collections import Counter
from dataclasses import dataclass
import hashlib
from html.parser import HTMLParser
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
from urllib.parse import unquote

from content import namespace_svg_ids, normalize_math_html


HERE = Path(__file__).resolve().parent


@dataclass(frozen=True)
class Project:
    root: Path
    entry: Path
    packages: Path
    fonts: tuple[Path, ...] = ()
    compiler: str = "typst"

    def relative_entry(self) -> str:
        entry = (self.root / self.entry).resolve()
        if not entry.is_file():
            raise ValueError(f"Missing entrypoint: {entry}")
        return entry.relative_to(self.root.resolve()).as_posix()


def prepare_packages(original: Path, destination: Path) -> None:
    """Overlay package versions, with untouched packages linked read-only by convention.

    The destination must be new: never remove an arbitrary path or write through
    a link into an installed package. Typst only reads these source packages.
    """
    destination.mkdir()
    overlay = HERE / "packages"
    for source in (original, overlay):
        if not source.is_dir():
            raise ValueError(f"Package directory does not exist: {source}")
    versions: dict[Path, Path] = {}
    for source in (original, overlay):
        for manifest in source.glob("*/*/*/typst.toml"):
            versions[manifest.parent.relative_to(source)] = manifest.parent
    for relative, source in sorted(versions.items()):
        target = destination / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        if source.is_relative_to(overlay):
            shutil.copytree(source, target)
        else:
            target.symlink_to(source.resolve(), target_is_directory=True)


class ContentAudit(HTMLParser):
    """Check content delivery invariants; visual validation is a separate gate."""

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.elements: Counter[str] = Counter()
        self.ids: Counter[str] = Counter()
        self.links: list[str] = []
        self.diagnostics: Counter[str] = Counter()
        self.marks: Counter[str] = Counter()
        self.annotation_targets: list[list[str]] = []
        self.graphics: dict[str, list[str]] = {}
        self.canvases: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        attributes = dict(attrs)
        self.elements[tag] += 1
        if identifier := attributes.get("id"):
            self.ids[identifier] += 1
        if (href := attributes.get("href")) and href.startswith("#"):
            self.links.append(unquote(href[1:]))
        if diagnostic := attributes.get("data-flow-diagnostic"):
            self.diagnostics[diagnostic] += 1
        if mark := attributes.get("data-flow-mark"):
            self.marks[mark] += 1
        if canvas := attributes.get("data-flow-canvas"):
            self.canvases.append(canvas)
        if targets := attributes.get("data-flow-targets"):
            self.annotation_targets.append(json.loads(targets))
            if graphic := attributes.get("data-flow-graphic"):
                self.graphics[graphic] = json.loads(targets)

    def report(self) -> dict:
        missing_links = sorted(set(self.links) - self.ids.keys())
        missing_marks = sorted({target for targets in self.annotation_targets
                                for target in targets} - self.marks.keys())
        duplicate_ids = sorted(key for key, count in self.ids.items() if count > 1)
        return {
            "elements": dict(self.elements),
            "missingLinkTargets": missing_links,
            "duplicateIds": duplicate_ids,
            "annotations": len(self.annotation_targets),
            "unresolvedAnnotationTargets": missing_marks,
            "unsupported": dict(self.diagnostics),
            "graphics": self.graphics,
            "canvases": self.canvases,
            "contentGatePassed": not (
                missing_links or duplicate_ids or missing_marks or self.diagnostics
            ),
        }


def compile_project(project: Project, output: Path, *, geometry: dict | None = None,
                    canvases: dict | None = None) -> dict:
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
        for font in project.fonts:
            command.extend(["--font-path", str((root / font).resolve())])
        if geometry is not None:
            command.extend(["--input", "flow-geometry=" + json.dumps(geometry, separators=(",", ":"))])
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
            content = normalize_math_html(namespace_svg_ids((work / "document.html").read_text()))
            (work / "document.html").write_text(content)
            audit = ContentAudit()
            audit.feed(content)
            report.update(audit.report())
            # Typst can successfully exit after dropping unsupported elements.
            # Page furniture and PDF structure tags have no HTML representation;
            # all other warnings block promotion until reviewed or fixed.
            allowed_warnings = {
                "warning: html export is under active development and incomplete",
                "warning: page set rule was ignored during HTML export",
                "warning: pdf-marker-tag was ignored during HTML export",
            }
            report["compilerLossWarnings"] = sorted(set(report["warnings"]) - allowed_warnings)
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
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    project = Project(args.root, args.entry, args.package_path, tuple(args.font_path), args.compiler)
    report = compile_project(project, args.output.resolve())
    print(json.dumps(report, ensure_ascii=False, indent=2))
    # Compiling alone is not proof of faithful output; callers must check the gate.
    return 0 if report["contentGatePassed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
