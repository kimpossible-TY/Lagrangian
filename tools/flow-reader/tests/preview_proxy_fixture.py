"""Browser-only fake engine fixture; never invokes a compiler or live manager."""
from http.server import ThreadingHTTPServer
import json
from pathlib import Path
import secrets
import signal
import tempfile

from test_preview_proxy import Backend
from test_homepage import FakeAuth, FakeProvider, FakeManager
from flow_reader.server.preview_proxy import PreviewProxy
from flow_reader.server.routing import handler_for_reader
from flow_reader.services.home_account import HomeAccount
from flow_reader.services.homepage import HomeInventory


def main():
    signal.signal(signal.SIGTERM, lambda *_: (_ for _ in ()).throw(KeyboardInterrupt()))
    with tempfile.TemporaryDirectory(prefix="preview-proxy-browser-") as directory:
        backend = Backend()
        port = backend.port
        owner = PreviewProxy([{"id": "alpha", "port": port}])
        inventory = HomeInventory(FakeManager(), loaded=([{"id": "alpha", "name": "Fixture preview", "port": port}], [], {}))
        token = secrets.token_hex(16)
        base = handler_for_reader({}, inventory, HomeAccount(FakeAuth(Path(directory)), FakeProvider()),
                                  capability="fixture-proof", previews=owner)
        class Handler(base):
            def do_POST(self):
                nonlocal backend
                if self.path != "/fixture-control":
                    return super().do_POST()
                if self.headers.get("X-Fixture-Token") != token:
                    return self.respond({}, 403)
                request = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
                if request.get("operation") == "stop":
                    backend.stop()
                elif request.get("operation") == "restart":
                    backend.stop()
                    backend = Backend(port)
                return self.respond({})
        server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        url = f"http://127.0.0.1:{server.server_port}/"
        inventory.preview_origins = (None, url)
        inventory.observe()
        print(json.dumps({"url": url, "token": token, "backendURL": f"http://127.0.0.1:{port}/"}), flush=True)
        try:
            server.serve_forever()
        except KeyboardInterrupt:
            pass
        finally:
            owner.close()
            server.server_close()
            backend.stop()
            inventory.close()


if __name__ == "__main__":
    main()
