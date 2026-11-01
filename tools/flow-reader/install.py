#!/usr/bin/env python3
"""Install an immutable Reader release without replacing the existing Flow app."""

import argparse
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
import tarfile
import tempfile

# The staged tree is hashed before install. Importing flow_reader must not write
# __pycache__ into that tree, or verification refuses every bundle install.
sys.dont_write_bytecode = True

from flow_reader.services.manager import DEFAULT_DATA, ReaderManager, atomic_write, run
from flow_reader.server.compiler_assets import CompilerAssets


def reader_revision(source):
    """Return the commit from a clean checkout, or the headSha of a verified bundle."""
    source = Path(source)
    if (source / "reader-bundle.json").is_file():
        return _verify_reader_bundle(source)["headSha"]
    if run(["git", "-C", str(source), "status", "--porcelain"]).strip():
        raise ValueError("Install Reader from a clean commit")
    return run(["git", "-C", str(source), "rev-parse", "HEAD"]).strip()


def stage_reader_sources(source, staging):
    """Place the Reader trees in ``staging`` and return the revision those bytes belong to."""
    source = Path(source)
    staging = Path(staging)
    if (source / "reader-bundle.json").is_file():
        module = _reader_bundle_module(source)
        manifest = module.verify_unpacked_tree(source)
        for relative in ("tools/flow-reader", "tools/reader-common"):
            shutil.copytree(source / relative, staging / relative, symlinks=True)
        module.verify_copied_trees(staging, manifest)
        return manifest["headSha"]
    revision = reader_revision(source)
    archive = subprocess.run(
        ["git", "-C", str(source), "archive", revision, "tools/flow-reader", "tools/reader-common"],
        capture_output=True, check=True).stdout
    with tarfile.open(fileobj=io.BytesIO(archive)) as tar:
        tar.extractall(staging, filter="data")
    return revision


def _reader_bundle_module(source):
    module_path = Path(source) / "scripts" / "reader_bundle.py"
    if not module_path.is_file():
        raise ValueError("Reader bundle is missing scripts/reader_bundle.py")
    spec = importlib.util.spec_from_file_location("reader_bundle_install", module_path)
    if spec is None or spec.loader is None:
        raise ValueError("Reader bundle verifier could not be loaded")
    module = importlib.util.module_from_spec(spec)
    # Importing the verifier must not drop a .pyc into the tree before the hash check.
    previous = sys.dont_write_bytecode
    sys.dont_write_bytecode = True
    try:
        spec.loader.exec_module(module)
    finally:
        sys.dont_write_bytecode = previous
    return module


def _verify_reader_bundle(source):
    return _reader_bundle_module(source).verify_unpacked_tree(Path(source))


def install(args):
    source = Path(__file__).resolve().parents[2]
    revision = reader_revision(source)
    manager = ReaderManager(args.data)
    config_path = manager.data / "config.json"
    identifier = args.profile + "-reader"
    with manager.locked():
        config = json.loads(config_path.read_text()) if config_path.exists() else {"schemaVersion": 1, "services": []}
        if config.get("schemaVersion") != 1:
            raise ValueError("Unsupported existing reader configuration")
        if config_path.exists():
            for profile in manager.profiles():
                if manager.job_pid(profile):
                    raise ValueError("Stop the Reader services before updating their installed release")
        config.update(flowManager=str(args.flow_manager), python=str(args.python), compiler=str(args.compiler))
        browser_path = getattr(args, "browser_compiler", None) or config.get("browserCompiler")
        if getattr(args, "no_browser_compiler", False):
            browser_path = None
            config.pop("browserCompiler", None)
        browser_assets = CompilerAssets(browser_path) if browser_path else None
        if browser_assets:
            config["browserCompiler"] = str(Path(browser_path).resolve())
        if getattr(args, "engine", None):
            config["engine"] = str(args.engine.expanduser().resolve())
        previous = next((service for service in config["services"] if service["id"] == identifier), {})
        semantic_canvases = getattr(args, "semantic_canvases", None)
        if semantic_canvases is None:
            semantic_canvases = previous.get("semanticCanvases", False)
        extra_fonts = getattr(args, "extra_fonts", None)
        if extra_fonts is None:
            extra_fonts = previous.get("extraFonts", [])
        else:
            extra_fonts = [str(Path(path).expanduser().resolve()) for path in extra_fonts]
        services = [service for service in config["services"] if service["id"] != identifier]
        services.append({"id": identifier, "parentID": args.profile, "port": args.port,
                         "publicURL": args.public_url, "development": args.development,
                         "semanticCanvases": semantic_canvases,
                         **({"extraFonts": extra_fonts} if extra_fonts else {}),
                         **({"focusFile": previous["focusFile"]} if "focusFile" in previous else {})})
        config["services"] = services
        # Resolve the live parent profile and validate its inputs before touching
        # either the existing Reader configuration or its stable launcher.
        with tempfile.TemporaryDirectory(prefix="flow-reader-config-") as temporary:
            candidate = ReaderManager(temporary)
            atomic_write(candidate.data / "config.json", json.dumps(config).encode())
            for profile in candidate.profiles():
                candidate.arguments(profile)
        releases = manager.data / "releases"
        releases.mkdir(parents=True, exist_ok=True)
        release_id = revision + ("-wasm-" + browser_assets.engine[:16] if browser_assets else "")
        release = releases / release_id
        with tempfile.TemporaryDirectory(prefix=".install-", dir=releases) as temporary:
            staging = Path(temporary) / "release"
            staging.mkdir()
            staged_revision = stage_reader_sources(source, staging)
            if staged_revision != revision:
                raise ValueError("Reader revision changed during installation")
            if browser_assets:
                destination = staging / "tools/flow-reader/compiler-assets"
                destination.mkdir()
                for name in ("compiler.js", "compiler_bg.wasm", "manifest.json"):
                    shutil.copyfile(Path(browser_path) / name, destination / name)
                # Recheck copied bytes, including a build racing the copy operation.
                if CompilerAssets(destination).engine != browser_assets.engine:
                    raise ValueError("Browser compiler changed during installation")
            files = {str(path.relative_to(staging)): hashlib.sha256(path.read_bytes()).hexdigest()
                     for path in staging.rglob("*") if path.is_file()}
            release_manifest = {"revision": revision, "files": files,
                                "compilerVersion": run([args.compiler, "--version"]).strip()}
            if browser_assets:
                release_manifest["browserCompiler"] = browser_assets.engine
            if release.exists():
                for filename, expected in files.items():
                    if hashlib.sha256((release / filename).read_bytes()).hexdigest() != expected:
                        raise ValueError("An installed immutable release was modified")
            else:
                atomic_write(staging / "release.json", json.dumps(release_manifest, indent=2).encode())
                staging.replace(release)
        if browser_assets:
            config["browserCompiler"] = str(release / "tools/flow-reader/compiler-assets")
        marker = "# Flow Reader managed launcher\n"
        if manager.launcher.exists() and marker not in manager.launcher.read_text():
            raise ValueError("The installer will not replace an unrelated launcher")
        launcher = ("#!/bin/sh\n" + marker
                    + f"export FLOW_READER_DATA_DIR={shlex.quote(str(manager.data))}\n"
                    + "exec " + shlex.quote(str(args.python)) + " "
                    + shlex.quote(str(release / "tools/flow-reader/manage.py")) + ' "$@"\n')
        if config_path.exists():
            atomic_write(manager.data / "config.previous.json", config_path.read_bytes())
        atomic_write(config_path, json.dumps(config, ensure_ascii=False, indent=2).encode())
        atomic_write(manager.launcher, launcher.encode(), 0o755)
    run([manager.launcher, "--launch-plan", identifier])
    if args.start:
        run([manager.launcher, "--control", "start", identifier])
    return {"revision": revision, "release": release_id, "manager": str(manager.launcher), "id": identifier,
            "publicURL": args.public_url, "port": args.port, "started": args.start}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--profile", required=True, help="Existing Flow parent profile ID")
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--public-url", default="")
    parser.add_argument("--data", type=Path, default=DEFAULT_DATA)
    parser.add_argument("--flow-manager", type=Path, default=Path.home() / "Applications/Lagrangian.app/Contents/MacOS/Lagrangian")
    parser.add_argument("--python", type=Path, default=Path(shutil.which("python3") or "/missing/python3"))
    parser.add_argument("--compiler", type=Path, default=Path(shutil.which("typst") or "/missing/typst"))
    parser.add_argument("--engine", type=Path, help="Flow engine supporting shared source history (otherwise use the Flow app engine)")
    parser.add_argument("--font-path", dest="extra_fonts", type=Path, action="append",
                        help="Add a Reader-only font file or directory; repeat as needed (omission preserves installed paths)")
    browser = parser.add_mutually_exclusive_group()
    browser.add_argument("--browser-compiler", type=Path, help="Package generated WASM compiler assets in this immutable release")
    browser.add_argument("--no-browser-compiler", action="store_true", help="Disable browser compilation; omission preserves the setting")
    parser.add_argument("--development", action="store_true", help="Retain the visible development notice; do not use as the mobile default")
    parser.add_argument("--semantic-canvases", action=argparse.BooleanOptionalAction, default=None,
                        help="Enable native figure labels; omission preserves the installed setting")
    parser.add_argument("--start", action="store_true")
    args = parser.parse_args()
    print(json.dumps(install(args), indent=2))


if __name__ == "__main__":
    main()
