"""Bounded filesystem signatures for accepted compiler inputs."""
import hashlib
import json
import os
from pathlib import Path
import shutil

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
