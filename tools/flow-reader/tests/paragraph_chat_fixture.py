"""Isolated browser fixture using real Reader HTTP and a local fake model only."""
from http.server import ThreadingHTTPServer
import json
from pathlib import Path
import secrets
import signal
import tempfile

from chat_fixture import FakeOpenAI, SyntheticReader
from flow_reader.server.http import handler_for


def main():
    def stop(*_args):
        raise SystemExit(0)
    signal.signal(signal.SIGTERM, stop)
    with tempfile.TemporaryDirectory(prefix="reader-chat-browser-") as directory:
        fake = FakeOpenAI()
        reader = SyntheticReader(Path(directory), fake)
        token = secrets.token_hex(16)
        base = handler_for(reader.state)
        class Handler(base):
            def do_POST(self):
                if self.path != "/fixture-control":
                    return super().do_POST()
                if self.headers.get("X-Fixture-Token") != token:
                    return self.respond(b"Forbidden", "text/plain", 403)
                request = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
                if request.get("mode"):
                    fake.mode = request["mode"]
                if request.get("delete"):
                    reader.html = reader.html.replace("First paragraph keeps its own question.", "Replacement paragraph.")
                    reader.publish("fixture-r2")
                if request.get("revision"):
                    reader.publish(request["revision"])
                return self.respond(b"{}", "application/json")
        server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        print(json.dumps({"url": f"http://127.0.0.1:{server.server_port}/", "token": token}), flush=True)
        try:
            server.serve_forever()
        finally:
            server.server_close()
            reader.close()
            fake.close()


if __name__ == "__main__":
    main()
