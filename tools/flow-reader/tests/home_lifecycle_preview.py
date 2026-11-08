"""Synthetic event-observation fixture; no production component is patched."""
import argparse
from http.server import ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit

from home_preview import ASSETS, CSP, Handler, file_inventory

HERE = Path(__file__).resolve().parent


class LifecycleHandler(Handler):
    def do_GET(self):
        route = urlsplit(self.path).path
        if route in ("/slow/", "/normal/"):
            source = ASSETS["/"].read_text()
            extras = '<script defer src="/fixture-observe.js"></script>'
            if route == "/slow/":
                extras += '<link rel="stylesheet" href="/fixture-slow.css" />'
            data = source.replace("</head>", extras + "</head>").encode()
            content_type = "text/html; charset=utf-8"
        elif route in ("/fixture-observe.js", "/fixture-slow.css"):
            filename = "home_lifecycle_observe.js" if route.endswith(".js") else "home_lifecycle_slow.css"
            data = (HERE / filename).read_bytes()
            content_type = "text/javascript; charset=utf-8" if route.endswith(".js") else "text/css; charset=utf-8"
        else:
            return super().do_GET()
        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Content-Security-Policy", CSP)
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=8875)
    parser.add_argument("--inventory-file", type=Path, required=True)
    args = parser.parse_args()
    file_inventory(args.inventory_file, args.port)
    server = ThreadingHTTPServer(("127.0.0.1", args.port), LifecycleHandler)
    server.mode = "documents"
    server.inventory_file = args.inventory_file
    server.serve_forever()


if __name__ == "__main__":
    main()
