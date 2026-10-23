"""Reader HTTP protocol and explicit immutable asset delivery."""
import gzip
from http.server import BaseHTTPRequestHandler
import json
from urllib.parse import parse_qs, urlsplit
from flow_reader.resources import READER_ROOT as HERE
from flow_reader.errors import RevisionChanged
from flow_reader.services.editor_sync import UNSPECIFIED_EDITOR
from flow_reader.server.assets import reader_assets
from flow_reader.server.offline import snapshot_inventory, worker_script


def handler_for(state):
    assets = reader_assets()
    vendor = HERE / "web/vendor/mathjax-4.1.3"
    vendor_files = json.loads((vendor / "manifest.json").read_text())["files"]
    vendor_routes = {"/vendor/mathjax-4.1.3/" + name: vendor / name for name in vendor_files}
    vendor_routes["/vendor/mathjax-4.1.3/manifest.json"] = vendor / "manifest.json"
    offline_worker = worker_script(assets, vendor_routes)

    class Handler(BaseHTTPRequestHandler):
        def do_POST(self):
            path = urlsplit(self.path).path
            if path not in {"/api/graphics", "/api/locate", "/api/canvases", "/api/decorations",
                            "/api/highlight", "/api/source", "/api/cursor", "/api/focus"}:
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
                if path == "/api/focus":
                    try:
                        result = state.save_focus(request.get("revision"), request.get("fragments"),
                                                  request.get("service"), request.get("viewerID"))
                    except OSError:
                        return self.respond(b"Could not save Codex context", "text/plain", 503)
                elif path == "/api/highlight":
                    result = state.highlight(request.get("revision"), request.get("fragments"),
                                             expected_editor=request.get("editorServer", UNSPECIFIED_EDITOR))
                elif path == "/api/source":
                    result = state.source(request.get("revision"), request.get("fragments"))
                elif path == "/api/cursor":
                    result = state.cursor(request.get("revision"), request.get("path"),
                                          request.get("line"), request.get("column"))
                elif path == "/api/locate":
                    result = state.locate(request.get("revision"), request.get("fragments"))
                elif path == "/api/decorations":
                    result = state.render_dynamic(request.get("revision"), request.get("decorations"), "decorations")
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
            if path == "/service-worker.js":
                return self.respond(offline_worker, "text/javascript; charset=utf-8")
            if path == "/api/offline":
                inventory = snapshot_inventory(state)
                if inventory is None:
                    return self.respond(b"No accepted document is available", "text/plain", 503)
                return self.respond(json.dumps(inventory).encode(), "application/json")
            if path == "/api/state":
                return self.respond(json.dumps(state.public()).encode(), "application/json")
            if path == "/api/focus":
                try:
                    return self.respond(json.dumps(state.read_focus(), ensure_ascii=False).encode(),
                                        "application/json")
                except (OSError, ValueError):
                    return self.respond(b"Focus record unavailable", "text/plain", 503)
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
            if path in assets:
                asset, content_type = assets[path]
                return self.respond(asset.read_bytes(), content_type)
            if path in vendor_routes:
                asset = vendor_routes[path]
                content_type = {".js": "text/javascript; charset=utf-8", ".woff2": "font/woff2",
                                ".json": "application/json"}.get(asset.suffix, "text/plain; charset=utf-8")
                compressed = asset.suffix == ".js" and "gzip" in self.headers.get("Accept-Encoding", "")
                content = asset.read_bytes()
                return self.respond(gzip.compress(content) if compressed else content, content_type,
                                    compressed=compressed, cache="public, max-age=31536000, immutable")
            self.respond(b"Not found", "text/plain", 404)

        def respond(self, content, content_type, code=200, compressed=False, cache="no-store"):
            self.send_response(code)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(content)))
            self.send_header("Cache-Control", cache)
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
