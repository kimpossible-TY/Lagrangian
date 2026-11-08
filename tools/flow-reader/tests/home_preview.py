"""Read-only synthetic Homepage preview on an explicit loopback port.

Use --mode {documents,empty,loading,error} to inspect inventory states. The
fixture does not set cookies and never reads or changes real account data.
"""
import argparse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import sys
from urllib.parse import parse_qs, urlsplit

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from flow_reader.server.home import home_assets
from flow_reader.server.assets import CONTENT_TYPES

ASSETS = home_assets()
MODES = ("documents", "empty", "loading", "error")
CSP = ("default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self'; "
       "connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'")
DOCUMENTS = [
    {"id": "one", "name": "편미분방정식 — 합성 예제 문서", "state": "ready", "variants": [
        {"kind": "html", "url": "http://127.0.0.1:8873/example-html"},
        {"kind": "paged", "url": "http://127.0.0.1:8873/example-paged"}]},
    {"id": "two", "name": "긴 제목이 좁은 화면에서 여러 줄로 자연스럽게 표시되는 합성 문서 예제", "state": "compiling", "variants": [
        {"kind": "paged", "url": "http://127.0.0.1:8873/example-paged"}]},
    {"id": "three", "name": "공개 주소가 없는 합성 문서", "state": "stopped", "variants": []},
]
DESTINATIONS = {
    "/example-html": "합성 HTML 목적지",
    "/example-paged": "합성 Paged 목적지",
}


def inventory(mode):
    return {"documents": DOCUMENTS if mode == "documents" else [],
            "loading": mode == "loading",
            "error": "합성 오류: 문서 목록을 확인하지 못했습니다." if mode == "error" else ""}


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        request = urlsplit(self.path)
        path = request.path
        if path == "/api/home/documents":
            # The override permits read-only HTTP checks; normal Home uses server.mode.
            mode = parse_qs(request.query).get("mode", [self.server.mode])[-1]
            if mode not in MODES:
                self.send_error(400)
                return
            data = json.dumps(inventory(mode), ensure_ascii=False).encode()
            content_type = "application/json"
        elif path == "/api/home/account":
            data = json.dumps({"instance": "synthetic", "version": 1, "eligible": False}).encode()
            content_type = "application/json"
        elif path in DESTINATIONS:
            title = DESTINATIONS[path]
            data = (f'<!doctype html><html lang="ko"><meta charset="utf-8">'
                    f'<meta name="viewport" content="width=device-width, initial-scale=1">'
                    f'<title>{title}</title><body><main><h1>{title}</h1>'
                    '<p>검토용 합성 페이지입니다.</p><a href="/">홈으로 돌아가기</a>'
                    '</main></body></html>').encode()
            content_type = "text/html; charset=utf-8"
        elif path in ASSETS:
            asset = ASSETS[path]
            data = asset.read_bytes()
            content_type = CONTENT_TYPES[asset.suffix]
        else:
            self.send_error(404)
            return
        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Content-Security-Policy", CSP)
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mode", choices=MODES, default="documents")
    args = parser.parse_args()
    server = ThreadingHTTPServer(("127.0.0.1", 8873), Handler)
    server.mode = args.mode
    server.serve_forever()


if __name__ == "__main__":
    main()
