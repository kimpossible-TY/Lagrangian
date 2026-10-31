#!/usr/bin/env python3
"""Hash the inputs that change the macOS flow-release engine binary.

Stdout is one lowercase SHA-256. The digest covers Rust sources, every
Cargo.toml and Cargo.lock, the Rust toolchain file, the scripts the
flow-engine workflow runs, the sources those scripts embed into the binary,
and the other crate and vendor inputs compiled into that binary. Runner OS
and architecture are part of the digest. Documentation, OpenSpec, and
Markdown are not: those changes must not look like a new engine.
"""

import argparse
import hashlib
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

# Scripts the workflow invokes, plus the scripts those entry points execute.
BUILD_SCRIPTS = (
    Path('scripts/flow-app.py'),
    Path('scripts/stage-tinymist-assets.mjs'),
    Path('scripts/build.mjs'),
    Path('scripts/builders.mjs'),
)

# stage-tinymist-assets.mjs compiles these into include_str! inputs.
EMBEDDED_ROOTS = (
    Path('tools/typst-preview-frontend'),
    Path('tools/typst-dom'),
    Path('tools/reader-common'),
)

# Non-Rust files under these trees are compiled into the engine (include_str!,
# include_bytes!, and the Typst library sources). Markdown stays out.
COMPILED_TREES = (
    Path('crates'),
    Path('vendor'),
    Path('benches'),
)

# Gitignored outputs of stage-tinymist-assets.mjs. Hashing them would make the
# digest depend on a previous local staging run.
GENERATED = {
    Path('crates/tinymist-assets/src/typst-preview.html'),
    Path('crates/tinymist-assets/src/tinymist-rt.toml'),
}

SKIP_DIRS = {
    '.git',
    'target',
    'node_modules',
    'dist',
    'build',
    'coverage',
    '__pycache__',
    '.venv',
    'out',
}


def include(rel: Path) -> bool:
    """Return whether a repo-relative path is an engine input."""
    if rel in GENERATED or rel.suffix in ('.md', '.log'):
        return False
    parts = rel.parts
    if not parts or parts[0] in ('docs', 'openspec'):
        return False
    if any(part in SKIP_DIRS for part in parts):
        return False
    if rel.suffix == '.rs' or rel.name in ('Cargo.toml', 'Cargo.lock'):
        return True
    if rel.name in ('rust-toolchain.toml', 'rust-toolchain') or parts[0] == '.cargo':
        return True
    if rel in BUILD_SCRIPTS or rel in (Path('package.json'), Path('yarn.lock'), Path('locales/tinymist-rt.toml')):
        return True
    if any(rel == root or root in rel.parents for root in COMPILED_TREES):
        return True
    if _embedded_source(rel):
        return True
    return False


def _embedded_source(rel: Path) -> bool:
    if not any(rel == root or root in rel.parents for root in EMBEDDED_ROOTS):
        return False
    if 'tests' in rel.parts:
        return False
    name = rel.name
    return '.test.' not in name and '.spec.' not in name


def iter_files(root: Path):
    for dirpath, dirnames, filenames in os.walk(root, followlinks=False):
        dirnames[:] = sorted(name for name in dirnames if name not in SKIP_DIRS)
        for name in sorted(filenames):
            path = Path(dirpath) / name
            if path.is_file():
                yield path


def digest(root: Path, system: str, machine: str) -> tuple[str, int]:
    """Return the engine-input digest and the number of hashed files."""
    hasher = hashlib.sha256()
    count = 0
    paths = []
    for path in iter_files(root):
        rel = path.relative_to(root)
        if include(rel):
            paths.append((rel.as_posix(), path))
    for rel, path in sorted(paths, key=lambda item: item[0]):
        hasher.update(rel.encode())
        hasher.update(b'\0')
        with path.open('rb') as handle:
            while True:
                chunk = handle.read(1024 * 1024)
                if not chunk:
                    break
                hasher.update(chunk)
        hasher.update(b'\0')
        count += 1
    hasher.update(b'os\0')
    hasher.update(system.encode())
    hasher.update(b'\0arch\0')
    hasher.update(machine.encode())
    hasher.update(b'\0')
    return hasher.hexdigest(), count


def main(argv=None):
    parser = argparse.ArgumentParser(description='Print the flow engine input hash')
    parser.add_argument('--root', type=Path, default=ROOT)
    parser.add_argument('--os', dest='system', default=None)
    parser.add_argument('--arch', default=None)
    args = parser.parse_args(argv)
    system = args.system
    machine = args.arch
    if system is None or machine is None:
        uname = os.uname()
        system = system or uname.sysname
        machine = machine or uname.machine
    if not system or not machine or any(char.isspace() for char in system + machine):
        raise SystemExit('Runner OS and architecture must be single tokens')
    value, count = digest(args.root.resolve(), system, machine)
    print(f'{count} files, {system} {machine}', file=sys.stderr)
    print(value)


if __name__ == '__main__':
    main()
