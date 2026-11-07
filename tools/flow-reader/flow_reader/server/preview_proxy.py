"""Registered loopback preview data planes; no lifecycle or arbitrary URL authority."""
import base64
import hashlib
from html.parser import HTMLParser
from http.client import HTTPConnection, HTTPException
import re
import select
import socket
import threading
from urllib.parse import unquote, urlsplit, urljoin

from flow_reader.resources import READER_ROOT
from flow_reader.services.homepage import LOOPBACK_HOST, preview_prefix

REQUEST_HEADERS = {"accept", "accept-language", "range", "if-range", "if-none-match", "if-modified-since"}
RESPONSE_HEADERS = {"content-type", "content-range", "accept-ranges", "content-encoding", "etag", "last-modified"}
WS_HEADERS = {"sec-websocket-key", "sec-websocket-version", "sec-websocket-protocol", "sec-websocket-extensions"}
MAX_TEXT = 32 * 1024 * 1024
MAX_BUFFER = 256 * 1024
BRIDGE = "__reader_preview_proxy__.js"
ROOT_ATTRIBUTE = re.compile(r'''(\b(?:src|href|action|poster)\s*=\s*)(["']?)(/(?!/)[^\s>"']*)(\2)''', re.I)
SPECIAL_ATTRIBUTE = re.compile(r'''(\b(style|srcset)\s*=\s*)(["'])(.*?)\3''', re.I | re.S)
CSS_ROOT = re.compile(r'''((?:url\(\s*|@import\s+)["']?)(/(?!/)[^\s)"';]+)''', re.I)


def scoped_url(value, prefix):
    return value if value.startswith(prefix) else prefix + value.lstrip("/")


class PreviewHTML(HTMLParser):
    def __init__(self, prefix, port):
        super().__init__(convert_charrefs=False)
        self.parts, self.inserted = [], False
        self.in_style = False
        self.prefix = prefix
        self.boot = (f'<base href="{prefix}"><script src="{prefix}{BRIDGE}" '
                     f'data-reader-preview-port="{port}"></script>')

    def handle_starttag(self, tag, attrs):
        if tag == "base":
            return
        raw = ROOT_ATTRIBUTE.sub(lambda m: m[1] + m[2] + scoped_url(m[3], self.prefix) + m[4], self.get_starttag_text())
        def special_attribute(match):
            value = match[4]
            if match[2].lower() == "style":
                value = CSS_ROOT.sub(lambda m: m[1] + scoped_url(m[2], self.prefix), value)
            elif "data:" not in value.lower():
                value = re.sub(r"(^|,\s*)(/(?!/)[^\s,]+)",
                               lambda m: m[1] + scoped_url(m[2], self.prefix), value)
            return match[1] + match[3] + value + match[3]
        self.parts.append(SPECIAL_ATTRIBUTE.sub(special_attribute, raw))
        if tag == "style":
            self.in_style = True
        if tag == "head" and not self.inserted:
            self.parts.append(self.boot)
            self.inserted = True

    def handle_startendtag(self, tag, attrs):
        self.handle_starttag(tag, attrs)

    def handle_endtag(self, tag):
        if tag == "style":
            self.in_style = False
        if tag != "base":
            self.parts.append(f"</{tag}>")

    def handle_data(self, data):
        if self.in_style:
            data = CSS_ROOT.sub(lambda m: m[1] + scoped_url(m[2], self.prefix), data)
        self.parts.append(data)

    def handle_entityref(self, name):
        self.parts.append("&" + name + ";")

    def handle_charref(self, name):
        self.parts.append("&#" + name + ";")

    def handle_comment(self, data):
        self.parts.append("<!--" + data + "-->")

    def handle_decl(self, decl):
        self.parts.append("<!" + decl + ">")

    def result(self):
        return ("" if self.inserted else self.boot) + "".join(self.parts)


class PreviewProxy:
    def __init__(self, profiles, *, reserved_ports=()):
        self.ports = {}
        occupied = set(reserved_ports)
        if len(profiles) > 128:
            raise ValueError("Preview inventory limit exceeded")
        for profile in profiles:
            identifier, port = profile.get("id"), profile.get("port")
            preview_prefix(identifier)
            if identifier in self.ports or type(port) is not int or not 1024 <= port <= 65535 or port in occupied:
                raise ValueError("Invalid or conflicting preview data-plane profile")
            self.ports[identifier] = port
            occupied.add(port)
        self.lock = threading.Lock()
        self.connections = set()
        self.closed = False
        self.slots = threading.BoundedSemaphore(32)

    def close(self):
        with self.lock:
            self.closed = True
            sockets = list(self.connections)
        for connection in sockets:
            try:
                connection.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
            connection.close()

    def track(self, *connections):
        with self.lock:
            if self.closed:
                raise OSError("Reader proxy is closed")
            self.connections.update(connections)

    def forget(self, *connections):
        with self.lock:
            self.connections.difference_update(connections)

    def reply(self, handler, status, body=b"", headers=()):
        handler.preview_response_started = True
        handler.send_response(status)
        for key, value in headers:
            handler.send_header(key, value)
        handler.send_header("Cache-Control", "no-store")
        handler.send_header("X-Content-Type-Options", "nosniff")
        handler.send_header("Referrer-Policy", "no-referrer")
        handler.send_header("Content-Length", str(len(body)))
        handler.end_headers()
        if handler.command != "HEAD":
            handler.wfile.write(body)

    def serve(self, handler, identifier, path):
        port = self.ports.get(identifier)
        if port is None:
            return self.reply(handler, 404)
        url = urlsplit(path)
        decoded = unquote(url.path)
        if (url.scheme or url.netloc or "\\" in decoded or "//" in decoded
                or any(p in {".", ".."} for p in decoded.split("/"))):
            return self.reply(handler, 404)
        if decoded.startswith(("/_editor", "/api/home", "/auth/")):
            return self.reply(handler, 403)
        if handler.command not in {"GET", "HEAD"}:
            return self.reply(handler, 405)
        upgrade = handler.headers.get("Upgrade", "").lower() == "websocket"
        origins = handler.headers.get_all("Origin", [])
        if (len(origins) > 1 or (origins and origins[0] != handler.origin()) or (upgrade and not origins)):
            return self.reply(handler, 403)
        if handler.headers.get("Transfer-Encoding") or handler.headers.get_all("Content-Length", []) not in ([], ["0"]):
            return self.reply(handler, 400)
        if not self.slots.acquire(blocking=False):
            return self.reply(handler, 503)
        try:
            with self.lock:
                closed = self.closed
            if closed:
                return self.reply(handler, 503)
            prefix = preview_prefix(identifier)
            # This exact preview-scoped bridge is the exception to web/assets.json.
            if url.path == "/" + BRIDGE and not upgrade:
                return self.reply(handler, 200, (READER_ROOT / "web" / "preview-proxy.js").read_bytes(),
                                  [("Content-Type", "text/javascript; charset=utf-8")])
            if upgrade:
                return self.websocket(handler, port, path)
            return self.http(handler, port, path, prefix, bool(origins))
        except (OSError, ValueError, UnicodeError, HTTPException):
            # Neither upstream errors nor source paths/headers enter the response.
            if not getattr(handler, "preview_response_started", False):
                return self.reply(handler, 503, b"Preview unavailable; retry after it is started.")
        finally:
            self.slots.release()

    def http(self, handler, port, path, prefix, has_origin):
        upstream = HTTPConnection(LOOPBACK_HOST, port, timeout=3)
        upstream_socket = None
        try:
            upstream.connect()
            upstream_socket = upstream.sock
            self.track(upstream_socket, handler.connection)
            headers = {key: value for key, value in handler.headers.items() if key.lower() in REQUEST_HEADERS}
            headers["Accept-Encoding"] = "identity"
            if has_origin:
                headers["Origin"] = f"http://{LOOPBACK_HOST}:{port}"
            upstream.request(handler.command, path, headers=headers)
            response = upstream.getresponse()
            fields = [(key, value) for key, value in response.getheaders() if key.lower() in RESPONSE_HEADERS]
            location = response.getheader("Location")
            if location:
                target = urlsplit(urljoin(f"http://{LOOPBACK_HOST}:{port}{path}", location))
                if target.scheme or target.netloc:
                    if target.scheme != "http" or target.netloc != f"{LOOPBACK_HOST}:{port}":
                        return self.reply(handler, 502)
                new_path = scoped_url(target.path or "/", prefix)
                fields.append(("Location", new_path + ("?" + target.query if target.query else "")
                               + ("#" + target.fragment if target.fragment else "")))
            mime = response.getheader("Content-Type", "").split(";")[0].strip().lower()
            if mime in {"text/html", "text/css"} and response.status == 200 and handler.command == "GET":
                if response.getheader("Content-Encoding", "identity") != "identity":
                    return self.reply(handler, 502)
                data = response.read(MAX_TEXT + 1)
                if len(data) > MAX_TEXT:
                    return self.reply(handler, 502)
                content = data.decode("utf-8")
                if mime == "text/html":
                    parser = PreviewHTML(prefix, port)
                    parser.feed(content)
                    parser.close()
                    content = parser.result()
                    fields.append(("Content-Security-Policy", "connect-src 'self' data:; base-uri 'self'; frame-ancestors 'none'"))
                else:
                    content = CSS_ROOT.sub(lambda m: m[1] + scoped_url(m[2], prefix), content)
                fields = [(k, v) for k, v in fields if k.lower() not in {"etag", "last-modified", "content-encoding"}]
                return self.reply(handler, response.status, content.encode(), fields)
            handler.send_response(response.status)
            for key, value in fields:
                handler.send_header(key, value)
            handler.send_header("Cache-Control", "no-store")
            handler.send_header("X-Content-Type-Options", "nosniff")
            # HTTP/1.0 close-delimited streaming avoids trusting upstream framing.
            handler.send_header("Connection", "close")
            handler.end_headers()
            handler.preview_response_started = True
            handler.close_connection = True
            if handler.command != "HEAD":
                while data := response.read(65536):
                    handler.wfile.write(data)
        finally:
            self.forget(upstream_socket, handler.connection)
            upstream.close()

    def websocket(self, handler, port, path):
        key = handler.headers.get("Sec-WebSocket-Key", "")
        try:
            valid_key = len(base64.b64decode(key, validate=True)) == 16
        except ValueError:
            valid_key = False
        if (handler.command != "GET" or not valid_key
                or len(handler.headers.get_all("Sec-WebSocket-Key", [])) != 1
                or handler.headers.get_all("Sec-WebSocket-Version", []) != ["13"]
                or "upgrade" not in [v.strip() for v in handler.headers.get("Connection", "").lower().split(",")]):
            return self.reply(handler, 400)
        upstream = socket.create_connection((LOOPBACK_HOST, port), timeout=3)
        try:
            self.track(upstream, handler.connection)
            fields = [(k, v) for k, v in handler.headers.items() if k.lower() in WS_HEADERS]
            request = (f"GET {path} HTTP/1.1\r\nHost: {LOOPBACK_HOST}:{port}\r\n"
                       f"Origin: http://{LOOPBACK_HOST}:{port}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
                       + "".join(f"{k}: {v}\r\n" for k, v in fields) + "\r\n")
            upstream.sendall(request.encode("latin-1"))
            data = bytearray()
            while b"\r\n\r\n" not in data:
                chunk = upstream.recv(4096)
                if not chunk or len(data) + len(chunk) > 65536:
                    raise ValueError("Invalid upgrade")
                data.extend(chunk)
            head, initial = bytes(data).split(b"\r\n\r\n", 1)
            lines = head.decode("latin-1").split("\r\n")
            headers = {}
            for line in lines[1:]:
                name, value = line.split(":", 1)
                name = name.lower()
                if name in headers:
                    raise ValueError("Duplicate upgrade header")
                headers[name] = value.strip()
            accept = base64.b64encode(hashlib.sha1((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode()).digest()).decode()
            if (len(lines[0].split()) < 2 or lines[0].split()[1] != "101" or headers.get("upgrade", "").lower() != "websocket"
                    or "upgrade" not in [v.strip() for v in headers.get("connection", "").lower().split(",")]
                    or headers.get("sec-websocket-accept") != accept):
                return self.reply(handler, 502)
            handler.protocol_version = "HTTP/1.1"
            handler.send_response(101)
            for name in ("upgrade", "connection", "sec-websocket-accept", "sec-websocket-protocol", "sec-websocket-extensions"):
                if name in headers:
                    handler.send_header(name, headers[name])
            handler.end_headers()
            handler.wfile.flush()
            handler.preview_response_started = True
            handler.close_connection = True
            # BaseHTTPRequestHandler may have buffered a frame sent alongside
            # the client's handshake. Drain only already available buffered data.
            initial_client = b""
            handler.connection.setblocking(False)
            try:
                pending = handler.rfile.peek(MAX_BUFFER)
                if pending:
                    initial_client = handler.rfile.read(len(pending))
            except BlockingIOError:
                pass
            self.tunnel(handler.connection, upstream, initial, initial_client)
        finally:
            self.forget(upstream, handler.connection)
            upstream.close()

    def tunnel(self, client, upstream, initial, initial_client=b""):
        client.setblocking(False)
        upstream.setblocking(False)
        buffers = {client: bytearray(initial), upstream: bytearray(initial_client)}
        peers = {client: upstream, upstream: client}
        reading = set(peers)
        half_closed = set()
        while reading or any(buffers.values()):
            for stream in peers:
                if stream not in reading and stream not in half_closed and not buffers[peers[stream]]:
                    peers[stream].shutdown(socket.SHUT_WR)
                    half_closed.add(stream)
            readable = [s for s in reading if len(buffers[peers[s]]) < MAX_BUFFER]
            writable = [s for s in peers if buffers[s]]
            ready, writes, _ = select.select(readable, writable, [], 1)
            for stream in writes:
                try:
                    size = stream.send(buffers[stream])
                except BlockingIOError:
                    continue
                del buffers[stream][:size]
            for stream in ready:
                try:
                    data = stream.recv(min(65536, MAX_BUFFER - len(buffers[peers[stream]])))
                except BlockingIOError:
                    continue
                if not data:
                    reading.remove(stream)
                else:
                    buffers[peers[stream]].extend(data)
        for stream in peers:
            if stream not in half_closed:
                peers[stream].shutdown(socket.SHUT_WR)
