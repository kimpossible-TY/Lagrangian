#!/usr/bin/env python3
"""Serve a saved-document reader on loopback independently of the paged preview."""

import argparse
import gzip
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import threading
import time
from urllib.parse import parse_qs, urlsplit

from build import HERE, Project, compile_project


class ReaderState:
    def __init__(self, project, output, original_url, allow_incomplete):
        self.project = project
        self.output = output
        self.original_url = original_url
        self.allow_incomplete = allow_incomplete
        self.lock = threading.RLock()
        self.report = {}
        self.document = None
        self.compressed = None
        self.revision = None
        self.compiling = False

    def load_result(self):
        report = json.loads((self.output / "report.json").read_text())
        with self.lock:
            self.report = report
            if report["exitCode"] == 0 and (report["contentGatePassed"] or self.allow_incomplete):
                self.document = (self.output / "document.html").read_bytes()
                self.compressed = gzip.compress(self.document)
                self.revision = report["revision"]

    def compile(self):
        with self.lock:
            self.compiling = True
        try:
            compile_project(self.project, self.output)
            self.load_result()
        except Exception as error:
            with self.lock:
                self.report = {"exitCode": 1, "contentGatePassed": False, "error": str(error)}
        finally:
            with self.lock:
                self.compiling = False

    def public(self):
        with self.lock:
            return {key: self.report.get(key) for key in (
                "exitCode", "contentGatePassed", "unsupported", "compilerLossWarnings",
                "elapsedSeconds",
            )} | {"revision": self.revision, "compiling": self.compiling,
                  "originalURL": self.original_url, "development": self.allow_incomplete}


def source_signature(project):
    result = []
    # Watch document data and both original and reader-specific package sources.
    for root in (project.root, project.packages, HERE / "packages"):
        for path in root.rglob("*"):
            if any(part in {".git", "node_modules", "dist", ".runtime", "__pycache__"}
                   for part in path.relative_to(root).parts):
                continue
            if path.is_file() and path.suffix.lower() not in {".pdf", ".html", ".log"}:
                try:
                    stat = path.stat()
                    result.append((str(path), stat.st_mtime_ns, stat.st_size))
                except FileNotFoundError:
                    pass
    return tuple(sorted(result))


def watch(state, stopped):
    previous = source_signature(state.project)
    while not stopped.wait(1):
        current = source_signature(state.project)
        if current == previous:
            continue
        # Coalesce saves; a change made during compilation is picked up next time.
        if stopped.wait(.5):
            return
        stable = source_signature(state.project)
        if stable != current:
            continue
        previous = stable
        state.compile()


def handler_for(state):
    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            url = urlsplit(self.path)
            path = url.path.rstrip("/") or "/"
            if path == "/api/state":
                return self.respond(json.dumps(state.public()).encode(), "application/json")
            if path == "/health":
                return self.respond(json.dumps({"ready": state.revision is not None}).encode(),
                                    "application/json", 200 if state.revision else 503)
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
    state.compile()
    server = ThreadingHTTPServer(("127.0.0.1", args.port), handler_for(state))
    stopped = threading.Event()
    if args.watch:
        threading.Thread(target=watch, args=(state, stopped), daemon=True).start()
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
