#!/usr/bin/env python3
"""Install an immutable Reader release without replacing the existing Flow app."""

import argparse
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import re
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

LAUNCHER_MARKER = "# Flow Reader managed launcher\n"
PREVIOUS_RELEASE_FILE = "previous-release.json"


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


def _is_valid_release_name(name):
    return (
        isinstance(name, str)
        and bool(name)
        and name not in {".", ".."}
        and not name.startswith(".")
        and "/" not in name
        and "\\" not in name
        and "\x00" not in name
    )


def _release_id_for_path(path_value, releases_resolved):
    """Return the direct release directory name under ``releases_resolved``, or None."""
    if not isinstance(path_value, (str, Path)):
        return None
    text = str(path_value)
    if not text or "\x00" in text:
        return None
    candidate = Path(text)
    if not candidate.is_absolute():
        return None
    try:
        resolved = candidate.resolve()
    except (OSError, RuntimeError, ValueError):
        return None
    if resolved == releases_resolved or not resolved.is_relative_to(releases_resolved):
        return None
    parts = resolved.relative_to(releases_resolved).parts
    if not parts or not _is_valid_release_name(parts[0]):
        return None
    return parts[0]


def _launcher_release_id(launcher_path, releases_resolved):
    """Extract the managed release ID from ``bin/flow-reader`` or raise ValueError."""
    launcher_path = Path(launcher_path)
    if launcher_path.is_symlink() or not launcher_path.is_file():
        raise ValueError("Active Reader launcher is missing or invalid")
    try:
        text = launcher_path.read_text(encoding="utf-8")
    except (OSError, UnicodeError) as error:
        raise ValueError(f"Active Reader launcher is unreadable: {error}") from error
    if LAUNCHER_MARKER not in text:
        raise ValueError("Active Reader launcher is not a managed Flow Reader launcher")
    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        try:
            tokens = shlex.split(line)
        except ValueError as error:
            raise ValueError(f"Active Reader launcher is malformed: {error}") from error
        if len(tokens) >= 3 and tokens[0] == "exec":
            for token in tokens[2:]:
                release_id = _release_id_for_path(token, releases_resolved)
                if release_id is not None:
                    return release_id
            raise ValueError("Active Reader launcher does not reference a managed release")
    raise ValueError("Active Reader launcher is missing an exec release target")


def _read_config_file(path, *, required):
    """Read and minimally validate a Reader config JSON file."""
    path = Path(path)
    if not path.exists() and not path.is_symlink():
        if required:
            raise ValueError(f"Missing Reader configuration: {path.name}")
        return None
    if path.is_symlink() or not path.is_file():
        raise ValueError(f"Invalid Reader configuration path: {path.name}")
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise ValueError(f"Malformed Reader configuration {path.name}: {error}") from error
    if not isinstance(payload, dict):
        raise ValueError(f"Reader configuration {path.name} must be a JSON object")
    if required:
        if payload.get("schemaVersion") != 1 or not isinstance(payload.get("services"), list):
            raise ValueError(f"Unsupported Reader configuration in {path.name}")
    browser = payload.get("browserCompiler")
    if browser is not None and not isinstance(browser, str):
        raise ValueError(f"Invalid browserCompiler path in {path.name}")
    return payload


def _read_previous_release_record(path):
    """Read optional ``previous-release.json`` rollback release ID."""
    path = Path(path)
    if not path.exists() and not path.is_symlink():
        return None
    if path.is_symlink() or not path.is_file():
        raise ValueError(f"Invalid previous release record: {path.name}")
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise ValueError(f"Malformed {path.name}: {error}") from error
    if not isinstance(payload, dict):
        raise ValueError(f"{path.name} must be a JSON object")
    release_id = payload.get("release")
    if release_id is None:
        return None
    if not _is_valid_release_name(release_id):
        raise ValueError(f"Invalid release ID in {path.name}")
    return release_id


def running_process_commands():
    """Return full command lines for running processes, or raise RuntimeError."""
    try:
        result = subprocess.run(
            ["ps", "-axww", "-o", "command="],
            text=True, capture_output=True, timeout=10, check=False,
        )
    except (OSError, subprocess.SubprocessError) as error:
        raise RuntimeError(f"Could not inspect running processes: {error}") from error
    if result.returncode != 0:
        detail = result.stderr.strip() or f"exit {result.returncode}"
        raise RuntimeError(f"Could not inspect running processes: {detail}")
    return result.stdout.splitlines()


def _running_release_ids(releases_dir, releases_resolved, process_commands):
    """Extract release IDs referenced by currently running process command lines."""
    lines = process_commands()
    if lines is None:
        raise RuntimeError("Process inspection returned no command list")
    prefixes = []
    for base in (str(releases_resolved), str(Path(releases_dir))):
        prefix = base.rstrip("/") + "/"
        if prefix not in prefixes:
            prefixes.append(prefix)
    referenced = set()
    for line in lines:
        if not isinstance(line, str):
            continue
        for prefix in prefixes:
            start = 0
            while True:
                index = line.find(prefix, start)
                if index < 0:
                    break
                after = line[index + len(prefix):]
                match = re.match(r"([^/\s'\"\\]+)", after)
                if match and _is_valid_release_name(match.group(1)):
                    referenced.add(match.group(1))
                start = index + len(prefix)
    return referenced


def _is_prunable_release(entry, releases_resolved):
    """Return True only for a real managed release directory strictly inside ``releases_resolved``."""
    if not _is_valid_release_name(entry.name):
        return False
    if entry.is_symlink():
        return False
    if not entry.is_dir():
        return False
    try:
        resolved = entry.resolve()
    except (OSError, RuntimeError):
        return False
    if resolved == releases_resolved or resolved.parent != releases_resolved or not resolved.is_relative_to(releases_resolved):
        return False
    manifest = resolved / "release.json"
    if manifest.is_symlink() or not manifest.is_file():
        return False
    return True


def prune_releases(data=DEFAULT_DATA, *, current_release=None, process_commands=None):
    """Remove obsolete managed Reader releases while preserving active, rollback, and live ones.

    Aborts safely without deleting anything if critical active metadata or process inspection
    fails. Individual deletion ``OSError``s warn to stderr and continue best-effort.
    """
    raw_data = Path(data or DEFAULT_DATA).expanduser()
    raw_releases = raw_data / "releases"
    manager = ReaderManager(data)
    releases = manager.data / "releases"
    if raw_releases.is_symlink() or releases.is_symlink() or not releases.is_dir():
        return {"pruned": [], "kept": [], "skipped": "releases directory is missing, non-directory, or symlink"}

    def _warn_skip(reason):
        print(f"Warning: skipping Reader release pruning: {reason}", file=sys.stderr)
        return {"pruned": [], "kept": [], "skipped": reason}

    try:
        with manager.locked(timeout=5):
            if raw_releases.is_symlink() or releases.is_symlink() or not releases.is_dir():
                return {"pruned": [], "kept": [], "skipped": "releases directory is missing, non-directory, or symlink"}
            releases_resolved = releases.resolve()
            active_config = _read_config_file(manager.data / "config.json", required=True)
            active_launcher_release = _launcher_release_id(manager.launcher, releases_resolved)
            previous_config = _read_config_file(manager.data / "config.previous.json", required=False)
            previous_record_release = _read_previous_release_record(manager.data / PREVIOUS_RELEASE_FILE)
            inspect_processes = running_process_commands if process_commands is None else process_commands
            running_releases = _running_release_ids(raw_releases, releases_resolved, inspect_processes)

            protected = {active_launcher_release}
            if current_release and _is_valid_release_name(current_release):
                protected.add(current_release)
            if active_config.get("browserCompiler"):
                browser_release = _release_id_for_path(active_config["browserCompiler"], releases_resolved)
                if browser_release:
                    protected.add(browser_release)
            if previous_config and previous_config.get("browserCompiler"):
                prev_browser_release = _release_id_for_path(previous_config["browserCompiler"], releases_resolved)
                if prev_browser_release:
                    protected.add(prev_browser_release)
            if previous_record_release:
                protected.add(previous_record_release)
            protected.update(running_releases)

            entries = sorted(releases.iterdir(), key=lambda item: item.name)
            pruned = []
            kept = []
            errors = []
            for entry in entries:
                if not _is_prunable_release(entry, releases_resolved):
                    continue
                if entry.name in protected:
                    kept.append(entry.name)
                    continue
                try:
                    shutil.rmtree(entry)
                    pruned.append(entry.name)
                except OSError as error:
                    print(f"Warning: could not prune obsolete Reader release {entry.name}: {error}", file=sys.stderr)
                    errors.append({"release": entry.name, "error": str(error)})
            result = {"pruned": pruned, "kept": kept}
            if errors:
                result["errors"] = errors
            return result
    except (ValueError, RuntimeError, OSError, BlockingIOError) as error:
        return _warn_skip(str(error))


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
        existing_browser_compiler = config.get("browserCompiler")
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
        if manager.launcher.exists() and LAUNCHER_MARKER not in manager.launcher.read_text():
            raise ValueError("The installer will not replace an unrelated launcher")
        launcher = ("#!/bin/sh\n" + LAUNCHER_MARKER
                    + f"export FLOW_READER_DATA_DIR={shlex.quote(str(manager.data))}\n"
                    + "exec " + shlex.quote(str(args.python)) + " "
                    + shlex.quote(str(release / "tools/flow-reader/manage.py")) + ' "$@"\n')
        releases_resolved = releases.resolve()
        pre_swap_release = None
        if manager.launcher.exists():
            try:
                pre_swap_release = _launcher_release_id(manager.launcher, releases_resolved)
            except ValueError:
                pre_swap_release = None
        if pre_swap_release is None and existing_browser_compiler:
            pre_swap_release = _release_id_for_path(existing_browser_compiler, releases_resolved)
        previous_record_path = manager.data / PREVIOUS_RELEASE_FILE
        if pre_swap_release and pre_swap_release != release_id:
            atomic_write(
                previous_record_path,
                json.dumps({"schemaVersion": 1, "release": pre_swap_release}, indent=2).encode(),
            )
        elif pre_swap_release == release_id and not previous_record_path.exists():
            try:
                prev_cfg = _read_config_file(manager.data / "config.previous.json", required=False)
            except ValueError:
                prev_cfg = None
            prev_cfg_release = (
                _release_id_for_path(prev_cfg.get("browserCompiler"), releases_resolved)
                if prev_cfg and prev_cfg.get("browserCompiler")
                else None
            )
            if prev_cfg_release and prev_cfg_release != release_id:
                atomic_write(
                    previous_record_path,
                    json.dumps({"schemaVersion": 1, "release": prev_cfg_release}, indent=2).encode(),
                )
        if config_path.exists():
            atomic_write(manager.data / "config.previous.json", config_path.read_bytes())
        atomic_write(config_path, json.dumps(config, ensure_ascii=False, indent=2).encode())
        atomic_write(manager.launcher, launcher.encode(), 0o755)
    run([manager.launcher, "--launch-plan", identifier])
    if args.start:
        run([manager.launcher, "--control", "start", identifier])
    if not getattr(args, "no_prune", False):
        prune_releases(args.data, current_release=release_id)
    return {"revision": revision, "release": release_id, "manager": str(manager.launcher), "id": identifier,
            "publicURL": args.public_url, "port": args.port, "started": args.start}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--profile", help="Existing Flow parent profile ID")
    parser.add_argument("--port", type=int)
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
    pruning = parser.add_mutually_exclusive_group()
    pruning.add_argument("--no-prune", action="store_true",
                         help="Defer pruning of obsolete managed releases after installation")
    pruning.add_argument("--prune-only", action="store_true",
                         help="Prune obsolete managed releases under --data without installing")
    args = parser.parse_args(argv)
    if args.prune_only:
        if args.profile is not None or args.port is not None or args.start:
            parser.error("--prune-only cannot be combined with --profile, --port, or --start")
        print(json.dumps(prune_releases(args.data), indent=2))
        return
    if not args.profile or args.port is None:
        parser.error("the following arguments are required: --profile, --port")
    print(json.dumps(install(args), indent=2))


if __name__ == "__main__":
    main()
