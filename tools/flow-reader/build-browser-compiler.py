#!/usr/bin/env python3
"""Build a content-identified browser compiler from the locked workspace sources."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "dist/reader-compiler")
    parser.add_argument("--wasm-bindgen", default=shutil.which("wasm-bindgen") or
                        str(ROOT / "target/wasm-tools/bin/wasm-bindgen"))
    parser.add_argument("--jobs", type=int, default=2)
    args = parser.parse_args()
    lock = (ROOT / "Cargo.lock").read_text()
    import tomllib
    version = next(package["version"] for package in tomllib.loads(lock)["package"]
                   if package["name"] == "wasm-bindgen")
    actual = subprocess.check_output([args.wasm_bindgen, "--version"], text=True).strip()
    if actual != "wasm-bindgen " + version:
        raise ValueError(f"Build needs wasm-bindgen-cli {version}, got {actual}")
    environment = dict(os.environ, RUSTFLAGS="-Dwarnings")
    subprocess.run(["cargo", "build", "-p", "tinymist-web-compiler", "--release", "--locked",
                    "--target", "wasm32-unknown-unknown", "-j", str(args.jobs)],
                   cwd=ROOT, env=environment, check=True)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="flow-wasm-", dir=args.output.parent) as temporary:
        output = Path(temporary)
        subprocess.run([args.wasm_bindgen, "--target", "web", "--out-dir", str(output),
                        "--out-name", "compiler", str(ROOT / "target/wasm32-unknown-unknown/release/tinymist_web_compiler.wasm")],
                       check=True)
        files = {name: hashlib.sha256((output / name).read_bytes()).hexdigest()
                 for name in ("compiler.js", "compiler_bg.wasm")}
        typst_version = tomllib.loads((ROOT / "Cargo.toml").read_text())["workspace"]["dependencies"]["typst"]
        manifest = {"schemaVersion": 1, "files": files, "typstVersion": typst_version,
                    "wasmBindgenVersion": version,
                    "lockHash": hashlib.sha256(lock.encode()).hexdigest(),
                    "engine": hashlib.sha256(json.dumps(files, sort_keys=True).encode()).hexdigest()}
        (output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
        args.output.mkdir(parents=True, exist_ok=True)
        # Only generated files owned by this build are replaced.
        for name in (*files, "manifest.json"):
            (output / name).replace(args.output / name)
    print(json.dumps({"output": str(args.output), **manifest}, indent=2))


if __name__ == "__main__":
    main()
