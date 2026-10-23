#!/usr/bin/env python3
"""Compare every measured browser edit with native compilation of the same bytes."""
import argparse
import base64
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import time

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from flow_reader.compiler.audit import normalize_content, audit_content
from flow_reader.compiler.execution import CompileRequest, local_compile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("corpus", type=Path)
    parser.add_argument("--compiler", default="typst")
    args = parser.parse_args()
    snapshot = json.loads((args.corpus / "snapshot.json").read_text())
    metadata = json.loads((args.corpus / "corpus.json").read_text())
    measurements = {path.stem.removeprefix("measurements-"): json.loads(path.read_text())
                    for path in args.corpus.glob("measurements-*.json")}
    if not measurements:
        raise ValueError("No browser measurements")
    if any(result.get("error") for result in measurements.values()):
        raise ValueError("A browser benchmark failed; do not report sustained agreement")
    comparisons = []
    with tempfile.TemporaryDirectory(prefix="flow-wasm-agreement-") as temporary:
        root = Path(temporary)
        for file in snapshot["files"]:
            content = base64.b64decode(file["data"], validate=True)
            if hashlib.sha256(content).hexdigest() != file["sha256"]:
                raise ValueError("Corpus file changed")
            relative = Path(file["path"].lstrip("/"))
            if ".." in relative.parts or relative.parts[0] not in {"workspace", "packages"}:
                raise ValueError("Invalid corpus path")
            target = root / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(content)
        fonts = []
        for index, font in enumerate(snapshot["fonts"]):
            content = base64.b64decode(font["data"], validate=True)
            if hashlib.sha256(content).hexdigest() != font["sha256"]:
                raise ValueError("Corpus font changed")
            path = root / f"font-{index}.ttf"
            path.write_bytes(content)
            fonts.append(path)
        request = CompileRequest(args.compiler, root / "workspace", root / "packages", snapshot["target"],
                                 entry=root / snapshot["entry"].lstrip("/"), fonts=tuple(fonts),
                                 inputs=tuple(snapshot["inputs"].items()), system_fonts=False,
                                 timestamp=snapshot["timestamp"], timeout=300)
        entry = root / metadata["entry"].lstrip("/")
        original = entry.read_bytes()
        rounds = max(len(result["runs"]) for result in measurements.values())
        for run in range(rounds):
            entry.write_bytes(original + (f"\n\nBrowser benchmark edit {run}.\n".encode() if run else b""))
            native = local_compile(request)
            if native.returncode:
                raise ValueError(native.stderr)
            expected = normalize_content(native.artifact.decode())
            for engine, measured in measurements.items():
                if run >= len(measured["runs"]):
                    continue
                started = time.monotonic()
                content = normalize_content((args.corpus / f"result-{engine}-{run}.html").read_text())
                gate = audit_content(content)["contentGatePassed"]
                comparison = {"engine": engine, "run": run, "exactNormalizedHtml": content == expected,
                              "contentGatePassed": gate, "nativeCompileSeconds": native.elapsed_seconds,
                              "pythonPostprocessSeconds": time.monotonic() - started,
                              "normalizedHtmlHash": hashlib.sha256(content.encode()).hexdigest()}
                comparisons.append(comparison)
                (args.corpus / "agreement.json").write_text(json.dumps(comparisons, indent=2) + "\n")
                if not gate or content != expected:
                    raise ValueError(f"Output disagreement: {engine}, edit {run}")
            print(f"Edit {run}: complete normalized HTML matches native output", flush=True)


if __name__ == "__main__":
    main()
