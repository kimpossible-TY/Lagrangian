"""Explicit static asset registry shared by source and installed delivery."""
import json
from pathlib import Path
from flow_reader.resources import READER_ROOT, SHARED_ROOT

CONTENT_TYPES = {
    ".html": "text/html; charset=utf-8",
    ".js": "text/javascript; charset=utf-8",
    ".css": "text/css; charset=utf-8",
    ".ico": "image/vnd.microsoft.icon",
    ".png": "image/png",
    ".webmanifest": "application/manifest+json",
}


def reader_assets():
    """Only reviewed manifest entries can be served, including shared modules."""
    web = (READER_ROOT / "web").resolve()
    shared = SHARED_ROOT.resolve()
    manifest = json.loads((web / "assets.json").read_text())
    routes = {}
    for name, filename in manifest.items():
        route = "/" + name
        relative = Path(filename)
        path = (web / relative).resolve()
        if (name.startswith("/") or ".." in Path(name).parts or "?" in name or "#" in name
                or relative.is_absolute() or ".." in relative.parts
                or not (path.is_relative_to(web) or path.is_relative_to(shared))
                or path.suffix not in CONTENT_TYPES or not path.is_file()):
            raise ValueError(f"Invalid Reader asset: {route}")
        routes[route] = (path, CONTENT_TYPES[path.suffix])
    routes["/"] = routes["/index.html"]
    return routes
