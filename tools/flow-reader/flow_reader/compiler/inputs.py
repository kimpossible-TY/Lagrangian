"""Bounded filesystem signatures for accepted compiler inputs."""
import hashlib
import json
import os
from pathlib import Path
import shutil

MAX_SOURCE_BYTES = 2 * 1024 * 1024


def input_fingerprint(project, dependencies):
    """Content changes count as edits; compiler binaries and mtimes do not."""
    files = {project.root / project.entry} | {Path(path) for path in dependencies}
    result = hashlib.sha256()
    for path in sorted(files):
        if not path.is_file():
            continue
        result.update(str(path).encode())
        with path.open("rb") as source:
            while chunk := source.read(65536):
                result.update(chunk)
    return result.hexdigest()


def source_paths(project, dependencies):
    """Inspect only bounded, accepted Typst dependencies inside the workspace."""
    root, packages = project.root.resolve(), project.packages.resolve()
    names = {Path(name) for name in dependencies} | {root / project.entry}
    for path in sorted({name.resolve() for name in names}):
        if (path.suffix == ".typ" and path.is_relative_to(root)
                and not path.is_relative_to(packages) and path.is_file()
                and path.stat().st_size <= MAX_SOURCE_BYTES):
            yield path


def shadow_sources(root, destination, sources):
    """Copy changed sources only; other project inputs remain read-only links."""
    destination.mkdir()
    def populate(original, target, prefix=Path()):
        for child in original.iterdir():
            name = prefix / child.name
            if name in sources:
                (target / child.name).write_text(sources[name], encoding="utf-8")
            elif any(name in path.parents for path in sources):
                (target / child.name).mkdir()
                populate(child, target / child.name, name)
            else:
                (target / child.name).symlink_to(child, target_is_directory=child.is_dir())
    populate(root, destination)


def source_signature(project, dependencies=()):
    """Stat compiler inputs; never recursively enumerate the user's project."""
    result = []
    paths = {Path(path) for path in dependencies} | {project.root / project.entry}
    compiler = shutil.which(project.compiler)
    if compiler:
        paths.add(Path(compiler))
    # Fonts are not included in Typst's dependency JSON. Enumerate only the
    # explicitly configured font roots, pruning ignored folders before descent.
    for font in project.fonts:
        root = project.root / font
        paths.add(root)
        for folder, directories, files in os.walk(root):
            directories[:] = [name for name in directories if not name.startswith(".")]
            paths.update(Path(folder) / name for name in files
                         if Path(name).suffix.lower() in {".ttf", ".otf", ".ttc", ".otc"})
    # Directory entry names detect newly created imports. Metadata-only changes
    # (for example a File Provider timestamp update) are not new compiler input.
    # Enumerate only known parents, without opening their children's contents.
    paths.update(path.parent for path in list(paths))
    for path in paths:
        try:
            stat = path.stat()
            if path.is_dir():
                with os.scandir(path) as entries:
                    names = sorted(entry.name for entry in entries if entry.name != ".DS_Store")
                digest = hashlib.sha256(json.dumps(names).encode()).hexdigest()
                result.append((str(path), "directory", digest))
            else:
                result.append((str(path), stat.st_mtime_ns, stat.st_size))
        except FileNotFoundError:
            result.append((str(path), None, None))
    return tuple(sorted(result))
