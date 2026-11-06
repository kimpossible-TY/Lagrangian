"""One-origin composition of existing Homepage and document HTTP handlers."""
from http.server import BaseHTTPRequestHandler
from urllib.parse import unquote, urlsplit

from flow_reader.server.home import handler_for_home
from flow_reader.server.http import handler_for
from flow_reader.services.homepage import document_prefix, reader_url


def redirect(handler, destination):
    handler.send_response(307)
    handler.send_header("Location", destination)
    handler.send_header("Cache-Control", "no-store")
    handler.send_header("Content-Length", "0")
    handler.end_headers()


def handler_for_reader(documents, inventory, account, *, capability, ingress="admin", public_origin=None):
    """Documents map stable manager IDs to ReaderStates, never filesystem paths."""
    home = handler_for_home(inventory, account, capability=capability,
                            ingress=ingress, public_origin=public_origin)
    handlers = {document_prefix(key): handler_for(state, public_url=public_origin, homepage_url="/")
                for key, state in documents.items()}
    paged = {document_prefix(key): reader_url(state.original_url) for key, state in documents.items()}

    class Handler(home):
        def dispatch(self, method):
            if not self.trusted():
                return self.respond({"error": "Unrecognized host"}, 421)
            url = urlsplit(self.path)
            path = url.path
            decoded = unquote(path)
            if (url.scheme or url.netloc or "\\" in decoded or
                    any(part in {".", ".."} for part in decoded.split("/"))):
                return self.respond({"error": "Invalid route"}, 404)
            if path.startswith("/d/"):
                for prefix, document_handler in handlers.items():
                    if path == prefix[:-1]:
                        if method != "GET":
                            return self.respond({"error": "Trailing slash required"}, 404)
                        return redirect(self, prefix + ("?" + url.query if url.query else ""))
                    if not path.startswith(prefix):
                        continue
                    local = path[len(prefix) - 1:]
                    if local == "/paged/" and method == "GET" and paged[prefix]:
                        return redirect(self, paged[prefix])
                    if unquote(local).startswith("/api/home/"):
                        return self.respond({"error": "Not found"}, 404)
                    # Reuse the handler without constructing another socket reader or
                    # parsing the request twice. Its response writes to this connection.
                    child = document_handler.__new__(document_handler)
                    child.__dict__ = dict(self.__dict__)
                    child.path = local + ("?" + url.query if url.query else "")
                    return getattr(child, "do_" + method)()
                return self.respond({"error": "Unknown document"}, 404)
            return getattr(super(), "do_" + method)()

        def do_GET(self):
            return self.dispatch("GET")

        def do_POST(self):
            return self.dispatch("POST")

    return Handler


# An old root worker must retire when it next checks for an update. Cache keys
# include its exact scope; leave every other document's cache intact.
RETIRE_WORKER = b'''self.addEventListener("install", () => self.skipWaiting());
self.addEventListener("activate", event => event.waitUntil((async () => {
  const prefix = `flow-offline-v1:${self.registration.scope}:`;
  for (const key of await caches.keys()) if (key.startsWith(prefix)) await caches.delete(key);
  await self.registration.unregister();
})()));
'''


def handler_for_legacy(identifier, destination, *, public_origin=None):
    """Redirect-only compatibility ingress. It never delegates to Homepage."""
    origin = reader_url(destination)
    public = reader_url(public_origin) if public_origin else None
    if not origin or (public_origin and not public):
        raise ValueError("Invalid compatibility origin")
    prefix = document_prefix(identifier)

    class Handler(BaseHTTPRequestHandler):
        def dispatch(self):
            hosts = {f"127.0.0.1:{self.server.server_port}", f"localhost:{self.server.server_port}"}
            if public:
                hosts.add(urlsplit(public).netloc)
            if len(self.headers.get_all("Host", [])) != 1 or self.headers["Host"] not in hosts:
                return self.reply(b"Unrecognized host", 421)
            url = urlsplit(self.path)
            decoded = unquote(url.path)
            if (url.scheme or url.netloc or "\\" in decoded or
                    any(part in {".", ".."} for part in decoded.split("/"))):
                return self.reply(b"Invalid route", 404)
            if decoded.startswith("/api/home/"):
                return self.reply(b"No administration on compatibility ingress", 403)
            if url.path == "/service-worker.js" and self.command == "GET":
                return self.reply(RETIRE_WORKER, 200, "text/javascript")
            return redirect(self, origin + prefix.lstrip("/") + url.path.lstrip("/")
                            + ("?" + url.query if url.query else ""))

        def reply(self, body, status, mime="text/plain"):
            self.send_response(status)
            self.send_header("Content-Type", mime)
            self.send_header("Cache-Control", "no-store")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        do_GET = dispatch
        do_POST = dispatch

        def log_message(self, *_args):
            pass

    return Handler
