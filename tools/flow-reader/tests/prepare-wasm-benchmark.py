#!/usr/bin/env python3
"""Freeze an actual Reader corpus and its native output for the Worker benchmark."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from flow_reader.compiler.audit import normalize_content, audit_content, diagnostic_warnings, unhandled_warnings
from flow_reader.compiler.execution import CompileRequest, local_compile
from flow_reader.compiler.project import Project
from flow_reader.compiler.snapshot import capture_snapshot


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path, required=True, help="Accepted Reader dependency report")
    parser.add_argument("--packages", type=Path, required=True)
    parser.add_argument("--font", type=Path, action="append", default=[])
    parser.add_argument("--compiler", default="typst")
    parser.add_argument("--compiler-assets", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    report = json.loads(args.report.read_text())
    original = Path(report["root"]).resolve()
    if args.output.exists():
        raise ValueError("Use a new benchmark directory; previous evidence is immutable")
    source = args.output / "source"
    packages = args.output / "packages"
    source.mkdir(parents=True)
    packages.mkdir()
    versions = {}
    for filename in report["dependencies"]:
        path = Path(filename)
        if path.is_relative_to(original):
            target = source / path.relative_to(original)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(path, target)
        elif "/packages/" in filename:
            relative = filename.rsplit("/packages/", 1)[1]
            version = Path(*Path(relative).parts[:3])
            versions[version] = Path(filename.rsplit("/packages/", 1)[0]) / "packages" / version
        else:
            raise ValueError(f"Unrepresentable dependency: {path.name}")
    for version in sorted(versions):
        maintained = ROOT / "packages" / version
        configured = args.packages / version
        package = maintained if maintained.is_dir() else configured if configured.is_dir() else versions[version]
        shutil.copytree(package, packages / version)
    fonts = []
    for number, font in enumerate(args.font):
        destination = args.output / "fonts" / str(number)
        original_font = original / font
        if original_font.is_file():
            destination = destination.with_suffix(original_font.suffix)
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(original_font, destination)
        else:
            shutil.copytree(original_font, destination)
        fonts.append(destination.resolve())
    assets = json.loads((args.compiler_assets / "manifest.json").read_text())
    project = Project(source.resolve(), Path(report["entry"]), packages.resolve(), tuple(fonts))
    wrapper = ('#import "@local/flow-reader:0.1.0": apply-reader\n#show: apply-reader\n'
               f'#include {json.dumps("/" + report["entry"])}\n')
    request = CompileRequest(args.compiler, project.root, project.packages, "html", source=wrapper,
                             fonts=project.fonts, inputs=(("flow-reader", "true"), ("flow-native-labels", "true")),
                             timeout=300, system_fonts=False, timestamp=1760000000)
    result = local_compile(request)
    (args.output / "native.log").write_text(result.stderr)
    if result.returncode:
        raise ValueError(result.stderr)
    raw = result.artifact.decode("utf-8")
    started = time.monotonic()
    content = normalize_content(raw)
    audit = audit_content(content)
    audit["compilerLossWarnings"] = unhandled_warnings(diagnostic_warnings(result.stderr))
    if not audit["contentGatePassed"] or audit["compilerLossWarnings"]:
        raise ValueError(f"Native benchmark failed the content gate: {audit.get('compilerLossWarnings')}")
    postprocess = time.monotonic() - started
    (args.output / "native.html").write_text(raw)
    dependencies = [(request.root / path).resolve() for path in result.dependencies
                    if Path(path).name != "<stdin>"]
    snapshot = capture_snapshot(request, project, dependencies, assets["engine"])
    (args.output / "snapshot.json").write_text(json.dumps(snapshot.wire()))
    corpus = {file.path: file.digest for file in snapshot.files}
    (args.output / "corpus.json").write_text(json.dumps({
        "files": corpus, "identity": snapshot.identity,
        "engine": snapshot.engine, "entry": "/workspace/" + report["entry"],
        "fontHashes": [font.digest for font in snapshot.fonts],
        "inputBytes": sum(len(file.content) for file in (*snapshot.files, *snapshot.fonts)),
        "nativeCompileSeconds": result.elapsed_seconds, "pythonPostprocessSeconds": postprocess,
        "nativeHtmlHash": hashlib.sha256(result.artifact).hexdigest(),
        "contentGatePassed": True,
    }, indent=2) + "\n")
    print(json.dumps({"snapshot": str(args.output / "snapshot.json"), "files": len(snapshot.files),
                      "nativeSeconds": result.elapsed_seconds, "postprocessSeconds": postprocess}))


if __name__ == "__main__":
    main()
