"""Real isolated HTTP/WS sockets; fake engines and accounts, no launchd/compiler."""
import base64
import hashlib
from http.client import HTTPConnection
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import socket
import tempfile
from types import SimpleNamespace
import threading
import unittest

from test_homepage import FakeAuth, FakeProvider, FakeManager
from flow_reader.server.preview_proxy import MAX_BUFFER, PreviewProxy
from flow_reader.server.routing import handler_for_reader
from flow_reader.services.home_account import HomeAccount
from flow_reader.services.homepage import HomeInventory


SHELL = b'''<!doctype html><html><head><link href="/assets/theme.css?x=1" rel="stylesheet">
<style>body { background: url(/images/paper.png) }</style>
<script>window.socket = new WebSocket(new URL("/", location.href));</script>
<script src='/assets/client.js'></script></head><body style="background:url(/images/paper.png)"><img src=/images/picture.png srcset="/images/picture.png 1x, /images/picture-2x.png 2x"><img srcset="data:image/jpeg;base64,/9j/4AAQ 1x"></body></html>'''


def exact(stream, size):
    data = bytearray()
    while len(data) < size:
        chunk = stream.recv(size - len(data))
        if not chunk:
            raise EOFError()
        data.extend(chunk)
    return bytes(data)


def client_frame(payload=b"fixture", opcode=2):
    mask = b"test"
    return bytes([0x80 | opcode, 0x80 | len(payload)]) + mask + bytes(b ^ mask[i % 4] for i, b in enumerate(payload))


def server_frame(stream):
    head = exact(stream, 2)
    return head[0] & 15, exact(stream, head[1] & 127)


class Backend:
    def __init__(self, port=0):
        self.requests, self.sockets = [], set()
        self.mode = "normal"
        owner = self
        class Handler(BaseHTTPRequestHandler):
            def do_HEAD(self):
                self.do_GET()

            def do_GET(self):
                owner.requests.append((self.path, dict(self.headers)))
                if self.headers.get("Upgrade", "").lower() == "websocket":
                    owner.sockets.add(self.connection)
                    key = self.headers["Sec-WebSocket-Key"]
                    accept = base64.b64encode(hashlib.sha1((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode()).digest()).decode()
                    if owner.mode == "bad-handshake":
                        accept = "invalid"
                    response = ("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
                                f"Sec-WebSocket-Accept: {accept}\r\n\r\n").encode()
                    # Headers and first frame intentionally share one write.
                    self.wfile.write(response + b"\x82\x05hello")
                    self.wfile.flush()
                    try:
                        while True:
                            head = exact(self.connection, 2)
                            mask = exact(self.connection, 4)
                            data = exact(self.connection, head[1] & 127)
                            data = bytes(b ^ mask[i % 4] for i, b in enumerate(data))
                            opcode = head[0] & 15
                            self.wfile.write(bytes([0x80 | (10 if opcode == 9 else opcode), len(data)]) + data)
                            self.wfile.flush()
                            if opcode == 8:
                                break
                    except (OSError, EOFError):
                        pass
                    finally:
                        owner.sockets.discard(self.connection)
                    return
                mime, body, status = "text/html", SHELL, 200
                if self.path.startswith("/assets/theme.css"):
                    mime, body = "text/css", b'@import "/other.css"; body { background: url(/images/paper.png) }'
                elif self.path.startswith("/assets/client.js"):
                    mime, body = "text/javascript", b"window.previewLoaded=true"
                elif self.path.startswith("/images/"):
                    mime, body = "image/png", b"fixture-image"
                elif self.path.startswith("/range"):
                    mime, body, status = "application/pdf", b"part", 206
                elif self.path.startswith("/redirect"):
                    self.send_response(302)
                    self.send_header("Location", "https://evil.example/" if owner.mode == "external-redirect" else "/?keep=1")
                    self.send_header("Content-Length", "0")
                    self.end_headers()
                    return
                self.send_response(status)
                self.send_header("Content-Type", mime)
                self.send_header("Content-Length", str(len(body)))
                self.send_header("ETag", "fixture")
                self.send_header("Set-Cookie", "ReaderHomeAdmin=must-not-adopt")
                self.send_header("Access-Control-Allow-Origin", "*")
                self.end_headers()
                if self.command != "HEAD":
                    self.wfile.write(body)

            def log_message(self, *_args):
                pass
        self.server = ThreadingHTTPServer(("127.0.0.1", port), Handler)
        self.port = self.server.server_port
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.stopped = False

    def stop(self):
        if self.stopped:
            return
        self.stopped = True
        for stream in list(self.sockets):
            try:
                stream.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
            stream.close()
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()


class PreviewProxyTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory(prefix="preview-proxy-test-")
        self.addCleanup(directory.cleanup)
        self.backend = Backend()
        self.addCleanup(self.backend.stop)
        self.proxy = PreviewProxy([{"id": "alpha", "port": self.backend.port, "publicURL": "https://ignored.example"}])
        self.inventory = HomeInventory(FakeManager())
        self.addCleanup(self.inventory.close)
        self.auth = FakeAuth(Path(directory.name))
        self.account = HomeAccount(self.auth, FakeProvider())
        self.admin = self.serve()
        self.remote = self.serve(public=True)
        self.addCleanup(self.proxy.close)

    def serve(self, public=False, owner=None):
        handler = handler_for_reader({}, self.inventory, self.account, capability="private-proof",
            previews=owner or self.proxy, ingress="proxy" if public else "admin",
            public_origin="https://reader.example" if public else None)
        server = ThreadingHTTPServer(("127.0.0.1", 0), handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        self.addCleanup(lambda: (server.shutdown(), server.server_close(), thread.join()))
        return server

    def origin(self, server):
        return "https://reader.example" if server is self.remote else f"http://127.0.0.1:{server.server_port}"

    def request(self, path="/p/alpha/", *, server=None, headers=None, method="GET"):
        server = server or self.admin
        origin = self.origin(server)
        fields = {"Host": origin.split("//")[1], **(headers or {})}
        connection = HTTPConnection("127.0.0.1", server.server_port, timeout=5)
        connection.request(method, path, headers=fields)
        result = connection.getresponse()
        response = result.status, result.read(), dict(result.getheaders())
        connection.close()
        return response

    def ws(self, path="/p/alpha/", *, server=None, origin=True, initial=b"", key="dGhlIHNhbXBsZSBub25jZQ=="):
        server = server or self.admin
        endpoint = self.origin(server)
        stream = socket.create_connection(("127.0.0.1", server.server_port), timeout=3)
        self.addCleanup(stream.close)
        headers = (f"GET {path} HTTP/1.1\r\nHost: {endpoint.split('//')[1]}\r\nUpgrade: websocket\r\n"
                   f"Connection: keep-alive,Upgrade\r\nSec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n")
        if origin:
            headers += "Origin: " + (endpoint if origin is True else origin) + "\r\n"
        stream.sendall((headers + "\r\n").encode() + initial)
        response = bytearray()
        while not response.endswith(b"\r\n\r\n"):
            response.extend(exact(stream, 1))
        return stream, bytes(response)

    def test_tunnel_drains_bounded_buffers_before_half_close(self):
        client_proxy, client = socket.socketpair()
        upstream_proxy, upstream = socket.socketpair()
        for stream in (client_proxy, client, upstream_proxy, upstream):
            self.addCleanup(stream.close)
        client_proxy.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, 4096)
        client.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 4096)
        client.settimeout(10)
        upstream.settimeout(10)
        sizes, errors = [], []

        class ObservedSocket:
            def __init__(self, stream):
                self.stream = stream
            def __getattr__(self, name):
                return getattr(self.stream, name)
            def send(self, data):
                sizes.append(len(data))
                return self.stream.send(data)

        payload = b"\x82\x7f" + (600000).to_bytes(8, "big") + b"x" * 600000 + b"\x88\x02\x03\xe8"
        def relay():
            try:
                self.proxy.tunnel(ObservedSocket(client_proxy), ObservedSocket(upstream_proxy), b"")
            except OSError as error:
                errors.append(error)
        thread = threading.Thread(target=relay, daemon=True)
        thread.start()
        def send():
            upstream.sendall(payload)
            upstream.shutdown(socket.SHUT_WR)
        writer = threading.Thread(target=send, daemon=True)
        writer.start()
        # The small socket buffers force backpressure before the reader drains.
        writer.join(0.1)
        self.assertTrue(writer.is_alive())
        received = bytearray()
        while chunk := client.recv(8192):
            received.extend(chunk)
        self.assertEqual(received, payload)
        self.assertTrue(received.endswith(b"\x88\x02\x03\xe8"))
        client.shutdown(socket.SHUT_WR)
        writer.join(10)
        thread.join(10)
        self.assertFalse(writer.is_alive())
        self.assertFalse(thread.is_alive())
        self.assertEqual(errors, [])
        self.assertTrue(sizes)
        self.assertLessEqual(max(sizes), MAX_BUFFER)

    def test_mapping_path_query_and_absolute_assets(self):
        status, body, headers = self.request("/p/alpha/?mode=doc&x=%2F")
        self.assertEqual(status, 200)
        self.assertEqual(self.backend.requests[0][0], "/?mode=doc&x=%2F")
        self.assertIn(b'<base href="/p/alpha/">', body)
        self.assertLess(body.index(b"__reader_preview_proxy__.js"), body.index(b"new WebSocket"))
        for value in (b'"/p/alpha/assets/theme.css?x=1"', b"'/p/alpha/assets/client.js'", b"url(/p/alpha/images/paper.png)", b"src=/p/alpha/images/picture.png", b'srcset="/p/alpha/images/picture.png 1x, /p/alpha/images/picture-2x.png 2x"'):
            self.assertIn(value, body)
        self.assertIn(b'srcset="data:image/jpeg;base64,/9j/4AAQ 1x"', body)
        self.assertNotIn("ETag", headers)
        self.assertNotIn("Set-Cookie", headers)
        self.assertEqual(int(headers["Content-Length"]), len(body))
        self.assertEqual(headers["Cache-Control"], "no-store")
        self.assertEqual(headers["Content-Security-Policy"],
                         "connect-src 'self' data:; base-uri 'self'; frame-ancestors 'none'")
        status, css, _ = self.request("/p/alpha/assets/theme.css?x=1")
        self.assertEqual(status, 200)
        self.assertIn(b'"/p/alpha/other.css"', css)
        self.assertIn(b"url(/p/alpha/images/paper.png)", css)
        self.assertEqual(self.request("/p/alpha/images/picture.png")[1], b"fixture-image")
        self.assertEqual(self.request("/p/alpha/__reader_preview_proxy__.js")[0], 200)
        self.assertEqual(self.request("/assets/client.js")[0], 404)
        self.assertEqual(self.request("/_theme/dark")[0], 404)

    def test_unregistered_ids_traversal_and_arbitrary_upstreams_rejected(self):
        for path in ("/p/nope/", "/p/%61lpha/", "/p/alpha/../api/home/account", "/p/alpha/%2e%2e/", "/p/http://evil.example/", "/p/alpha/%5capi/home/account"):
            self.assertEqual(self.request(path)[0], 404, path)
        self.assertEqual(self.backend.requests, [])
        self.assertEqual(self.request("/p/nope/", method="HEAD")[0], 404)
        self.assertEqual(self.request("/", method="HEAD")[0], 405)
        self.assertEqual(self.request("/p/alpha/?upstream=http://evil.example:80/")[0], 200)
        self.assertIn("upstream=http://evil.example:80/", self.backend.requests[-1][0])
        status, _, headers = self.request("/p/alpha?x=1")
        self.assertEqual(status, 307)
        self.assertEqual(headers["Location"], "/p/alpha/?x=1")

    def test_fixed_profile_validation(self):
        for profiles in ([{"id": "../a", "port": self.backend.port}], [{"id": "a", "port": 0}],
                         [{"id": "a", "port": True}], [{"id": "a", "port": 65536}],
                         [{"id": "a", "port": self.backend.port}, {"id": "b", "port": self.backend.port}]):
            with self.subTest(profiles=profiles), self.assertRaises(ValueError):
                PreviewProxy(profiles)
        with self.assertRaises(ValueError):
            PreviewProxy([{"id": "a", "port": self.backend.port}], reserved_ports={self.backend.port})

    def test_multiple_registered_previews_never_share_upstream_selection(self):
        other = Backend()
        self.addCleanup(other.stop)
        owner = PreviewProxy([{"id": "alpha", "port": self.backend.port}, {"id": "beta", "port": other.port}])
        server = self.serve(owner=owner)
        self.addCleanup(owner.close)
        self.assertEqual(self.request("/p/alpha/?a=1", server=server)[0], 200)
        self.assertEqual(self.request("/p/beta/?b=2", server=server)[0], 200)
        self.assertEqual([r[0] for r in self.backend.requests], ["/?a=1"])
        self.assertEqual([r[0] for r in other.requests], ["/?b=2"])

    def test_homepage_preview_only_profile_and_html_paged_alias(self):
        manager = FakeManager()
        parents, profiles = manager.parent_profiles(), manager.profiles()
        profiles[0].update(port=8769, publicURL="https://reader.example/")
        inventory = HomeInventory(manager, loaded=(parents, profiles, {"html1": SimpleNamespace(public=lambda: {"revision": "r1"})}),
            preview_origins=("https://reader.example/", "http://127.0.0.1:8769/"))
        self.addCleanup(inventory.close)
        inventory.observe()
        documents = {p["id"]: p for p in inventory.snapshot(local=False)["documents"]}
        self.assertEqual(documents["p2"]["variants"], [{"kind": "paged", "url": "https://reader.example/p/p2/"}])
        self.assertEqual(documents["p2"]["state"], "unknown")
        self.assertEqual(documents["p1"]["variants"][0]["url"], "https://reader.example/p/p1/")
        handler = handler_for_reader({"doc": SimpleNamespace(original_url="https://old.example/")},
            self.inventory, self.account, capability="proof", previews=self.proxy, preview_parents={"doc": "alpha"})
        server = ThreadingHTTPServer(("127.0.0.1", 0), handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        self.addCleanup(lambda: (server.shutdown(), server.server_close(), thread.join()))
        status, _, headers = self.request("/d/doc/paged/?theme=dark", server=server)
        self.assertEqual(status, 307)
        self.assertEqual(headers["Location"], "/p/alpha/?theme=dark")

    def test_duplicate_origin_framing_and_connection_limit(self):
        connection = HTTPConnection("127.0.0.1", self.admin.server_port, timeout=3)
        connection.putrequest("GET", "/p/alpha/")
        for _ in range(2):
            connection.putheader("Origin", self.origin(self.admin))
        connection.endheaders()
        response = connection.getresponse()
        self.assertEqual(response.status, 403)
        response.read(); connection.close()
        for headers in ({"Content-Length": "1"}, {"Transfer-Encoding": "chunked"}):
            self.assertEqual(self.request(headers=headers)[0], 400)
        for _ in range(32):
            self.proxy.slots.acquire()
        try:
            self.assertEqual(self.request()[0], 503)
        finally:
            for _ in range(32):
                self.proxy.slots.release()
        self.assertEqual(self.backend.requests, [])

    def test_origin_and_credential_filtering(self):
        headers = {"Origin": self.origin(self.admin), "Cookie": "ReaderHomeAdmin=private", "Authorization": "Bearer private",
                   "X-Reader-Host-Capability": "private-proof", "X-Reader-CSRF": "private", "X-Forwarded-For": "private"}
        self.assertEqual(self.request(headers=headers)[0], 200)
        fields = {k.lower(): v for k, v in self.backend.requests[-1][1].items()}
        self.assertEqual(fields["host"], f"127.0.0.1:{self.backend.port}")
        self.assertEqual(fields["origin"], f"http://127.0.0.1:{self.backend.port}")
        self.assertFalse({"cookie", "authorization", "x-reader-host-capability", "x-reader-csrf", "x-forwarded-for"} & fields.keys())
        before = len(self.backend.requests)
        self.assertEqual(self.request(headers={"Origin": "https://evil.example"})[0], 403)
        self.assertEqual(self.request(headers={"Host": "evil.example"})[0], 421)
        for path in ("/p/alpha/_editor/channel", "/p/alpha/api/home/account", "/p/alpha/auth/callback"):
            self.assertEqual(self.request(path)[0], 403)
        self.assertEqual(self.request(method="POST")[0], 405)
        self.assertEqual(len(self.backend.requests), before)

    def test_redirects_head_and_range(self):
        status, _, headers = self.request("/p/alpha/redirect")
        self.assertEqual(status, 302)
        self.assertEqual(headers["Location"], "/p/alpha/?keep=1")
        self.backend.mode = "external-redirect"
        self.assertEqual(self.request("/p/alpha/redirect")[0], 502)
        self.assertEqual(self.request(method="HEAD")[:2], (200, b""))
        status, body, headers = self.request("/p/alpha/range?part=1", headers={"Range": "bytes=1-4"})
        self.assertEqual((status, body), (206, b"part"))
        self.assertEqual(headers["ETag"], "fixture")
        self.assertEqual(self.backend.requests[-1][1]["Range"], "bytes=1-4")

    def test_ws_upgrade_frames_query_and_early_bytes(self):
        stream, headers = self.ws("/p/alpha/_theme/dark?keep=%2F", initial=client_frame(b"early"))
        self.assertIn(b"HTTP/1.1 101 ", headers)
        self.assertEqual(server_frame(stream), (2, b"hello"))
        self.assertEqual(server_frame(stream), (2, b"early"))
        self.assertEqual(self.backend.requests[-1][0], "/_theme/dark?keep=%2F")
        stream.sendall(client_frame(b"\x00\xff\x01"))
        self.assertEqual(server_frame(stream), (2, b"\x00\xff\x01"))
        stream.sendall(client_frame(b"text", opcode=1))
        self.assertEqual(server_frame(stream), (1, b"text"))
        stream.sendall(client_frame(b"ping", opcode=9))
        self.assertEqual(server_frame(stream), (10, b"ping"))
        stream.sendall(client_frame(b"", opcode=8))
        self.assertEqual(server_frame(stream), (8, b""))

    def test_ws_bad_origin_key_and_upstream_handshake(self):
        for origin in (False, "null", "https://evil.example"):
            _, headers = self.ws(origin=origin)
            self.assertIn(b" 403 ", headers)
        _, headers = self.ws(key="invalid")
        self.assertIn(b" 400 ", headers)
        self.assertEqual(self.backend.requests, [])
        self.backend.mode = "bad-handshake"
        _, headers = self.ws()
        self.assertIn(b" 502 ", headers)

    def test_proxy_ingress_ws_and_remote_account_mutation(self):
        stream, headers = self.ws(server=self.remote)
        self.assertIn(b"HTTP/1.1 101 ", headers)
        self.assertEqual(server_frame(stream), (2, b"hello"))
        fields = self.backend.requests[-1][1]
        self.assertEqual(fields["Origin"], f"http://127.0.0.1:{self.backend.port}")
        self.assertEqual(self.request(server=self.remote)[0], 200)
        self.assertEqual(self.request("/api/home/account", server=self.remote, method="POST")[0], 403)
        self.assertEqual(self.auth.calls, [])

    def test_upstream_stop_restart_keeps_mapping_and_direct_port(self):
        stream, headers = self.ws()
        self.assertEqual(server_frame(stream), (2, b"hello"))
        port = self.backend.port
        self.backend.stop()
        self.assertEqual(stream.recv(1), b"")
        self.assertEqual(self.request()[0], 503)
        restarted = Backend(port)
        self.addCleanup(restarted.stop)
        self.assertEqual(self.request()[0], 200)
        stream, headers = self.ws()
        self.assertIn(b"HTTP/1.1 101 ", headers)
        self.assertEqual(server_frame(stream), (2, b"hello"))
        connection = HTTPConnection("127.0.0.1", port, timeout=3)
        connection.request("GET", "/")
        response = connection.getresponse()
        self.assertEqual(response.read(), SHELL)
        connection.close()

    def test_reader_proxy_close_closes_relays_without_stopping_backend(self):
        stream, _ = self.ws()
        self.assertEqual(server_frame(stream), (2, b"hello"))
        self.proxy.close()
        self.assertEqual(stream.recv(1), b"")
        connection = HTTPConnection("127.0.0.1", self.backend.port, timeout=3)
        connection.request("GET", "/")
        response = connection.getresponse()
        self.assertEqual(response.status, 200)
        response.read(); connection.close()
        replacement = PreviewProxy([{"id": "alpha", "port": self.backend.port}])
        self.addCleanup(replacement.close)
        server = self.serve(owner=replacement)
        self.assertEqual(self.request(server=server)[0], 200)


if __name__ == "__main__":
    unittest.main()
