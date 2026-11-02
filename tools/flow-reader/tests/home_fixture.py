"""Fake-only Homepage fixture; never reads the user's configuration or credentials."""
from http.server import ThreadingHTTPServer
import json
from pathlib import Path
import secrets
import signal
import tempfile
import time
import threading

from test_homepage import FakeAuth, FakeManager, FakeProvider
from flow_reader.server.home import handler_for_home
from flow_reader.services.homepage import HomeInventory
from flow_reader.services.home_account import HomeAccount


def main():
    signal.signal(signal.SIGTERM, lambda *_: (_ for _ in ()).throw(SystemExit(0)))
    with tempfile.TemporaryDirectory(prefix="home-browser-") as directory:
        auth, manager, provider = FakeAuth(Path(directory)), FakeManager(), FakeProvider()
        inventory = HomeInventory(manager, interval=30)
        inventory.observe()
        inventory.started = time.time()
        account = HomeAccount(auth, provider)
        token = secrets.token_hex(16)
        base = handler_for_home(inventory, account, capability="fixture-host-proof")
        class Handler(base):
            def do_POST(self):
                if self.path != "/fixture-control":
                    return super().do_POST()
                if self.headers.get("X-Fixture-Token") != token:
                    return self.respond({}, 403)
                request = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
                if "mode" in request:
                    manager.mode = request["mode"]
                    inventory.observe()
                if request.get("signedIn"):
                    auth.signed_in, auth.pending = True, False
                if request.get("interrupted"):
                    auth.pending = False
                    auth.notice = "Sign-in expired. Try again."
                if request.get("catalogFailure"):
                    provider.fail = True
                return self.respond({"authCalls": auth.calls, "modelCalls": provider.calls})
        server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        proxy = ThreadingHTTPServer(("127.0.0.1", 0), handler_for_home(inventory, account,
            ingress="proxy", public_origin="https://home.example:8443"))
        threading.Thread(target=proxy.serve_forever, daemon=True).start()
        print(json.dumps({"proxyURL": f"http://127.0.0.1:{proxy.server_port}/", "url": f"http://127.0.0.1:{server.server_port}/", "token": token}), flush=True)
        try:
            server.serve_forever()
        finally:
            server.server_close()
            proxy.shutdown()
            proxy.server_close()
            inventory.close()


if __name__ == "__main__":
    main()
