#!/usr/bin/env python3
"""Serve a saved-document reader on loopback independently of the paged preview."""

import argparse
from collections import OrderedDict
import gzip
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import shutil
import threading
import tempfile
import time
from urllib.parse import parse_qs, urlsplit

from build import HERE, Project, compile_project
from graphics import extract_graphics, validate_geometry
from canvases import extract_canvases, validate_canvases
from sections import split_document
from passages import locate_passages


class ReaderState:
    def __init__(self, project, output, original_url, allow_incomplete):
        self.project = project
        self.output = output
        self.original_url = original_url
        self.allow_incomplete = allow_incomplete
        self.document_id = hashlib.sha256(
            json.dumps([str(project.root), str(project.relative_entry())]).encode()).hexdigest()[:24]
        self.lock = threading.RLock()
        self.report = {}
        self.document = None
        self.compressed = None
        self.revision = None
        self.compiling = False
        self.source_stamp = None
        self.graphic_cache = OrderedDict()
        self.canvas_cache = OrderedDict()
        self.graphic_lock = threading.Lock()
        self.graphics = {}
        self.canvases = []
        self.bundle = None
        self.section_compressed = {}
        self.asset_snapshots = OrderedDict()
        self.manifest_json = None
        self.manifest_compressed = None
        self.dependencies = set()
        self.accepted_dependencies = set()
        self.watch_stamp = None
        try:
            self.dependencies.update(json.loads((output / "report.json").read_text()).get("dependencies", []))
        except (OSError, ValueError):
            pass

    def load_result(self, source_stamp):
        report = json.loads((self.output / "report.json").read_text())
        accepted = report["exitCode"] == 0 and (report["contentGatePassed"] or self.allow_incomplete)
        if accepted:
            # Dynamic CeTZ programs can change without changing placeholder HTML.
            # The served revision therefore includes the accepted input snapshot.
            report["contentRevision"] = report["revision"]
            report["revision"] = hashlib.sha256(
                (report["revision"] + json.dumps(source_stamp)).encode()).hexdigest()
            document = (self.output / "document.html").read_bytes()
            bundle = split_document(document.decode(), report["revision"])
            bundle.manifest["documentID"] = self.document_id
            compressed = gzip.compress(document)
            section_compressed = {key: gzip.compress(value) for key, value in bundle.documents.items()}
            manifest_json = json.dumps(bundle.manifest, ensure_ascii=False).encode()
            manifest_compressed = gzip.compress(manifest_json)
        with self.lock:
            self.report = report
            if accepted:
                self.document = document
                self.compressed = compressed
                self.bundle = bundle
                self.section_compressed = section_compressed
                self.manifest_json = manifest_json
                self.manifest_compressed = manifest_compressed
                self.asset_snapshots[report["revision"]] = bundle.assets
                while len(self.asset_snapshots) > 3:
                    self.asset_snapshots.popitem(last=False)
                self.revision = report["revision"]
                self.source_stamp = source_stamp
                self.accepted_dependencies = set(self.dependencies)
                self.graphics = report.get("graphics", {})
                self.canvases = report.get("canvases", [])
                self.graphic_cache.clear()
                self.canvas_cache.clear()

    def compile(self):
        with self.lock:
            self.compiling = True
        try:
            for attempt in range(3):
                before = source_signature(self.project, self.dependencies)
                report = compile_project(self.project, self.output)
                discovered = set(report.get("dependencies", []))
                new_dependencies = discovered - self.dependencies
                self.dependencies.update(discovered)
                if new_dependencies and report["exitCode"] == 0:
                    # Discover the dependency graph once, then compile against a
                    # measured before/after snapshot of every newly found input.
                    continue
                after = source_signature(self.project, self.dependencies)
                self.watch_stamp = before
                if before != after:
                    raise ValueError("Sources changed during compilation; waiting for a stable save")
                self.load_result(after)
                self.watch_stamp = after
                break
            else:
                raise ValueError("The source dependency graph did not stabilize")
        except Exception as error:
            with self.lock:
                self.report = {"exitCode": 1, "contentGatePassed": False, "error": str(error),
                               "compiledAt": time.time()}
        finally:
            with self.lock:
                self.compiling = False

    def public(self):
        with self.lock:
            return {key: self.report.get(key) for key in (
                "exitCode", "contentGatePassed", "unsupported", "compilerLossWarnings",
                "elapsedSeconds", "compiledAt",
            )} | {"revision": self.revision, "compiling": self.compiling,
                  "documentID": self.document_id,
                  "originalURL": self.original_url, "development": self.allow_incomplete,
                  "graphics": self.graphics, "canvases": self.canvases}

    def locate(self, revision, fragments):
        with self.lock:
            if not self.bundle or revision != self.revision:
                raise RevisionChanged("The document revision has changed")
            bundle = self.bundle
        results = locate_passages(bundle.passages, fragments)
        with self.lock:
            if revision != self.revision:
                raise RevisionChanged("The document revision has changed")
        return {"revision": revision, "locations": results}

    def render_graphics(self, revision, graphs):
        return self.render_dynamic(revision, graphs, "graphics")

    def render_canvases(self, revision, canvases):
        return self.render_dynamic(revision, canvases, "canvases")

    def render_dynamic(self, revision, requests, kind):
        with self.lock:
            if not self.revision or revision != self.revision:
                raise RevisionChanged("The document revision has changed")
            geometry = (validate_geometry(requests, self.graphics) if kind == "graphics"
                        else validate_canvases(requests, self.canvases))
            stamp = self.source_stamp
            dependencies = set(self.accepted_dependencies)
        key = hashlib.sha256(json.dumps([kind, revision, geometry], sort_keys=True).encode()).hexdigest()
        canvas_keys = {identifier: json.dumps([revision, identifier, layout], sort_keys=True)
                       for identifier, layout in geometry.items()} if kind == "canvases" else {}
        cached = {}
        with self.graphic_lock:
            with self.lock:
                if self.revision != revision:
                    raise RevisionChanged("The document revision has changed")
                if key in self.graphic_cache:
                    self.graphic_cache.move_to_end(key)
                    return self.graphic_cache[key]
                for identifier, canvas_key in canvas_keys.items():
                    if canvas_key in self.canvas_cache:
                        cached[identifier] = self.canvas_cache[canvas_key]
                        self.canvas_cache.move_to_end(canvas_key)
                if cached:
                    geometry = {identifier: layout for identifier, layout in geometry.items()
                                if identifier not in cached}
                    if not geometry:
                        return {"revision": revision, kind: cached}
            if stamp != source_signature(self.project, dependencies):
                raise RevisionChanged("Saved sources have changed")
            with tempfile.TemporaryDirectory(prefix=f"{kind}-", dir=self.output) as temporary:
                work = Path(temporary)
                arguments = {"geometry" if kind == "graphics" else "canvases": geometry}
                report = compile_project(self.project, work, **arguments)
                if not report["contentGatePassed"]:
                    raise ValueError(f"{kind.capitalize()} compilation failed")
                extract = extract_graphics if kind == "graphics" else extract_canvases
                drawings = extract((work / "document.html").read_text(), geometry, key[:16])
            if stamp != source_signature(self.project, dependencies):
                raise RevisionChanged("Saved sources changed during graphical rendering")
            result = {"revision": revision, kind: cached | drawings}
            with self.lock:
                if self.revision != revision:
                    raise RevisionChanged("The document revision has changed")
                for identifier, drawing in drawings.items():
                    if identifier in canvas_keys:
                        self.canvas_cache[canvas_keys[identifier]] = drawing
                while len(self.canvas_cache) > 256:
                    self.canvas_cache.popitem(last=False)
                self.graphic_cache[key] = result
                while len(self.graphic_cache) > 48:
                    self.graphic_cache.popitem(last=False)
            return result


class RevisionChanged(ValueError):
    """A view request must be retried against the latest compiled snapshot."""


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
    # Parent directory timestamps also detect creation of a previously missing
    # import. Stat does not open or materialize unrelated cloud directories.
    paths.update(path.parent for path in list(paths))
    for path in paths:
        try:
            stat = path.stat()
            result.append((str(path), stat.st_mtime_ns, stat.st_size))
        except FileNotFoundError:
            result.append((str(path), None, None))
    return tuple(sorted(result))


def watch(state, stopped):
    previous = state.watch_stamp
    while not stopped.wait(1):
        current = source_signature(state.project, state.dependencies)
        if current == previous:
            continue
        # Coalesce saves; a change made during compilation is picked up next time.
        if stopped.wait(.5):
            return
        stable = source_signature(state.project, state.dependencies)
        if stable != current:
            continue
        state.compile()
        previous = state.watch_stamp or stable


def handler_for(state):
    class Handler(BaseHTTPRequestHandler):
        def do_POST(self):
            path = urlsplit(self.path).path
            if path not in {"/api/graphics", "/api/locate", "/api/canvases"}:
                return self.respond(b"Not found", "text/plain", 404)
            origin = self.headers.get("Origin")
            if origin and (urlsplit(origin).scheme not in {"http", "https"}
                           or urlsplit(origin).netloc != self.headers.get("Host")):
                return self.respond(b"Origin does not match the reader", "text/plain", 403)
            if self.headers.get("Content-Type", "").split(";")[0] != "application/json":
                return self.respond(b"Expected application/json", "text/plain", 415)
            try:
                length = int(self.headers.get("Content-Length", "0"))
                if not 0 < length <= 262144:
                    return self.respond(b"Invalid request size", "text/plain", 413)
                request = json.loads(self.rfile.read(length))
                if not isinstance(request, dict):
                    raise ValueError("Expected a JSON object")
                if path == "/api/locate":
                    result = state.locate(request.get("revision"), request.get("fragments"))
                elif path == "/api/canvases":
                    result = state.render_canvases(request.get("revision"), request.get("canvases"))
                else:
                    result = state.render_graphics(request.get("revision"), request.get("graphs"))
                self.respond(json.dumps(result).encode(), "application/json")
            except RevisionChanged as error:
                self.respond(json.dumps({"error": str(error)}).encode(), "application/json", 409)
            except (ValueError, TypeError) as error:
                self.respond(json.dumps({"error": str(error)}).encode(), "application/json", 400)

        def do_GET(self):
            url = urlsplit(self.path)
            path = url.path.rstrip("/") or "/"
            if path == "/api/state":
                return self.respond(json.dumps(state.public()).encode(), "application/json")
            if path == "/health":
                return self.respond(json.dumps({"ready": state.revision is not None}).encode(),
                                    "application/json", 200 if state.revision else 503)
            if path == "/api/manifest" or path.startswith("/api/sections/"):
                with state.lock:
                    if not state.bundle:
                        return self.respond(b"No accepted document is available", "text/plain", 503)
                    requested = parse_qs(url.query).get("revision", [state.revision])[0]
                    if requested != state.revision:
                        return self.respond(b"Document revision changed; refresh state", "text/plain", 409)
                    if path == "/api/manifest":
                        compressed = "gzip" in self.headers.get("Accept-Encoding", "")
                        return self.respond(state.manifest_compressed if compressed else state.manifest_json,
                                            "application/json", compressed=compressed)
                    identifier = path.removeprefix("/api/sections/")
                    if identifier not in state.bundle.documents:
                        return self.respond(b"Unknown section", "text/plain", 404)
                    compressed = "gzip" in self.headers.get("Accept-Encoding", "")
                    payload = (state.section_compressed if compressed else state.bundle.documents)[identifier]
                    return self.respond(payload, "text/html; charset=utf-8", compressed=compressed)
            if path.startswith("/api/assets/"):
                identifier = path.removeprefix("/api/assets/")
                with state.lock:
                    asset = next((assets[identifier] for assets in state.asset_snapshots.values()
                                  if identifier in assets), None)
                    if asset is not None:
                        content_type = {"svg": "image/svg+xml", "png": "image/png", "jpg": "image/jpeg",
                                        "webp": "image/webp", "gif": "image/gif"}[identifier.rsplit(".", 1)[-1]]
                        return self.respond(asset, content_type)
                return self.respond(b"Unknown asset", "text/plain", 404)
            if path == "/document.html":
                with state.lock:
                    requested = parse_qs(url.query).get("revision", [state.revision])[0]
                    if not state.document:
                        return self.respond(b"No accepted document is available", "text/plain", 503)
                    if requested != state.revision:
                        return self.respond(b"Document revision changed; refresh state", "text/plain", 409)
                    compressed = "gzip" in self.headers.get("Accept-Encoding", "")
                    payload = state.compressed if compressed else state.document
                    return self.respond(payload, "text/html; charset=utf-8", compressed=compressed)
            assets = {"/": ("index.html", "text/html; charset=utf-8"),
                      "/reader.js": ("reader.js", "text/javascript; charset=utf-8"),
                      "/graphics.js": ("graphics.js", "text/javascript; charset=utf-8"),
                      "/canvases.js": ("canvases.js", "text/javascript; charset=utf-8"),
                      "/highlights.js": ("highlights.js", "text/javascript; charset=utf-8"),
                      "/reader.css": ("reader.css", "text/css; charset=utf-8")}
            if path in assets:
                filename, content_type = assets[path]
                return self.respond((HERE / "web" / filename).read_bytes(), content_type)
            self.respond(b"Not found", "text/plain", 404)

        def respond(self, content, content_type, code=200, compressed=False):
            self.send_response(code)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(content)))
            self.send_header("Cache-Control", "no-store")
            self.send_header("X-Content-Type-Options", "nosniff")
            self.send_header("Referrer-Policy", "same-origin")
            if compressed:
                self.send_header("Content-Encoding", "gzip")
                self.send_header("Vary", "Accept-Encoding")
            self.end_headers()
            self.wfile.write(content)

        def log_message(self, format, *args):
            if len(args) > 1 and str(args[1]) not in {"200", "304"}:
                super().log_message(format, *args)

    return Handler


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--entry", type=Path, default=Path("main.typ"))
    parser.add_argument("--package-path", type=Path, required=True)
    parser.add_argument("--font-path", type=Path, action="append", default=[])
    parser.add_argument("--compiler", default="typst")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--original-url", required=True)
    parser.add_argument("--port", type=int, default=0)
    parser.add_argument("--watch", action="store_true")
    parser.add_argument("--allow-incomplete", action="store_true",
                        help="Local development only: show explicit fidelity diagnostics")
    args = parser.parse_args()
    project = Project(args.root.resolve(), args.entry, args.package_path.resolve(),
                      tuple(args.font_path), args.compiler)
    project.relative_entry()
    state = ReaderState(project, args.output.resolve(), args.original_url, args.allow_incomplete)
    server = ThreadingHTTPServer(("127.0.0.1", args.port), handler_for(state))
    stopped = threading.Event()
    def compile_and_watch():
        state.compile()
        if args.watch:
            watch(state, stopped)
    state.compiling = True
    threading.Thread(target=compile_and_watch, daemon=True).start()
    print(json.dumps({"url": f"http://127.0.0.1:{server.server_port}/", **state.public()}), flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        stopped.set()
        server.server_close()


if __name__ == "__main__":
    main()
