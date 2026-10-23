"""Validate and expose only the two generated, content-identified compiler files."""
import hashlib
import json
from pathlib import Path


class CompilerAssets:
    def __init__(self, directory):
        directory = Path(directory).resolve()
        manifest = json.loads((directory / "manifest.json").read_text())
        files = manifest.get("files", {})
        if manifest.get("schemaVersion") != 1 or set(files) != {"compiler.js", "compiler_bg.wasm"}:
            raise ValueError("Invalid browser compiler manifest")
        for name, expected in files.items():
            path = directory / name
            if not path.resolve().is_relative_to(directory) or hashlib.sha256(path.read_bytes()).hexdigest() != expected:
                raise ValueError("Browser compiler assets do not match their manifest")
        self.engine = hashlib.sha256(json.dumps(files, sort_keys=True).encode()).hexdigest()
        if manifest.get("engine") != self.engine:
            raise ValueError("Invalid browser compiler identity")
        self.routes = {"/compiler-assets/" + name: (directory / name,
                       "application/wasm" if name.endswith(".wasm") else "text/javascript; charset=utf-8")
                       for name in files}

    def config(self):
        return {"enabled": True, "engine": self.engine, "moduleURL": "compiler-assets/compiler.js",
                "wasmURL": "compiler_bg.wasm"}
