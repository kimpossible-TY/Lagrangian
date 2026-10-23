"""Read-only package overlay preparation."""
from pathlib import Path
import os
import sys
import shutil
from flow_reader.resources import READER_ROOT as HERE


def package_cache_root() -> Path:
    """The CLI's cache root; only already discovered dependencies are captured."""
    if override := os.environ.get("TYPST_PACKAGE_CACHE_PATH"):
        return Path(override).resolve()
    if sys.platform == "darwin":
        base = Path.home() / "Library/Caches"
    elif sys.platform == "win32":
        base = Path(os.environ.get("LOCALAPPDATA", Path.home() / "AppData/Local"))
    else:
        base = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache"))
    return (base / "typst/packages").resolve()

def prepare_packages(original: Path, destination: Path) -> None:
    """Overlay package versions, with untouched packages linked read-only by convention.

    The destination must be new: never remove an arbitrary path or write through
    a link into an installed package. Typst only reads these source packages.
    """
    destination.mkdir()
    overlay = HERE / "packages"
    for source in (original, overlay):
        if not source.is_dir():
            raise ValueError(f"Package directory does not exist: {source}")
    versions: dict[Path, Path] = {}
    for source in (original, overlay):
        for manifest in source.glob("*/*/*/typst.toml"):
            versions[manifest.parent.relative_to(source)] = manifest.parent
    for relative, source in sorted(versions.items()):
        target = destination / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        if source.is_relative_to(overlay):
            shutil.copytree(source, target)
        else:
            target.symlink_to(source.resolve(), target_is_directory=True)
