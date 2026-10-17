#!/usr/bin/env python3
"""Install an immutable Reader release without replacing the existing Flow app."""

import argparse
import hashlib
import io
import json
from pathlib import Path
import shlex
import shutil
import subprocess
import tarfile
import tempfile

from manage import DEFAULT_DATA, ReaderManager, atomic_write, run


def install(args):
    source = Path(__file__).resolve().parents[2]
    if run(["git", "-C", source, "status", "--porcelain"]).strip():
        raise ValueError("Install Reader from a clean commit")
    revision = run(["git", "-C", source, "rev-parse", "HEAD"]).strip()
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
        services = [service for service in config["services"] if service["id"] != identifier]
        services.append({"id": identifier, "parentID": args.profile, "port": args.port,
                         "publicURL": args.public_url, "development": args.development})
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
        release = releases / revision
        with tempfile.TemporaryDirectory(prefix=".install-", dir=releases) as temporary:
            staging = Path(temporary) / "release"
            staging.mkdir()
            archive = subprocess.run(["git", "-C", str(source), "archive", revision, "tools/flow-reader"],
                                     capture_output=True, check=True).stdout
            with tarfile.open(fileobj=io.BytesIO(archive)) as tar:
                tar.extractall(staging, filter="data")
            files = {str(path.relative_to(staging)): hashlib.sha256(path.read_bytes()).hexdigest()
                     for path in staging.rglob("*") if path.is_file()}
            release_manifest = {"revision": revision, "files": files,
                                "compilerVersion": run([args.compiler, "--version"]).strip()}
            if release.exists():
                for filename, expected in files.items():
                    if hashlib.sha256((release / filename).read_bytes()).hexdigest() != expected:
                        raise ValueError("An installed immutable release was modified")
            else:
                atomic_write(staging / "release.json", json.dumps(release_manifest, indent=2).encode())
                staging.replace(release)
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
    return {"revision": revision, "manager": str(manager.launcher), "id": identifier,
            "publicURL": args.public_url, "port": args.port, "started": args.start}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--profile", required=True, help="Existing Flow parent profile ID")
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--public-url", default="")
    parser.add_argument("--data", type=Path, default=DEFAULT_DATA)
    parser.add_argument("--flow-manager", type=Path, default=Path.home() / "Applications/tinymist-flow.app/Contents/MacOS/tinymist-flow")
    parser.add_argument("--python", type=Path, default=Path(shutil.which("python3") or "/missing/python3"))
    parser.add_argument("--compiler", type=Path, default=Path(shutil.which("typst") or "/missing/typst"))
    parser.add_argument("--development", action="store_true", help="Retain the visible development notice; do not use as the mobile default")
    parser.add_argument("--start", action="store_true")
    args = parser.parse_args()
    print(json.dumps(install(args), indent=2))


if __name__ == "__main__":
    main()
