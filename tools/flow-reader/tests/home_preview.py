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
    "/example-paged-a": "합성 Paged A 목적지",
    "/example-paged-b": "합성 Paged B 목적지",
}


def inventory(mode, port=8873):
    documents = [{**doc, "variants": [
        {**variant, "url": variant["url"].replace("127.0.0.1:8873", f"127.0.0.1:{port}")}
        for variant in doc["variants"]]} for doc in DOCUMENTS] if mode == "documents" else []
    return {"documents": documents,
            "loading": mode == "loading",
            "error": "합성 오류: 문서 목록을 확인하지 못했습니다." if mode == "error" else ""}


def file_inventory(path, port):
    # Only an explicitly named temporary synthetic fixture is read on each poll.
    path = Path(path).resolve(strict=True)
    if not path.is_relative_to(Path("/private/tmp")):
        raise ValueError("Inventory fixture must be under /private/tmp")
    data = json.loads(path.read_text())
    if not isinstance(data, list):
        raise ValueError("Inventory fixture must be a document list")
    documents = []
    for doc in data:
        if not isinstance(doc, dict) or set(doc) != {"id", "name", "state", "variants"}:
            raise ValueError("Invalid synthetic document")
        if not all(isinstance(doc[key], str) for key in ("id", "name", "state")):
            raise ValueError("Invalid synthetic document fields")
        if not isinstance(doc["variants"], list):
            raise ValueError("Invalid synthetic variants")
        variants = []
        for variant in doc["variants"]:
            if (not isinstance(variant, dict) or set(variant) != {"kind", "path"}
                    or variant["kind"] not in ("html", "paged")
                    or variant["path"] not in DESTINATIONS):
                raise ValueError("Invalid synthetic destination")
            variants.append({"kind": variant["kind"],
                             "url": f"http://127.0.0.1:{port}{variant['path']}"})
        documents.append({**doc, "variants": variants})
    return {"documents": documents, "loading": False, "error": ""}


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
            try:
                fixture = getattr(self.server, "inventory_file", None)
                result = file_inventory(fixture, self.server.server_port) if fixture else inventory(mode, self.server.server_port)
            except (OSError, ValueError, TypeError, json.JSONDecodeError):
                result = {"documents": [], "loading": False, "error": "합성 목록 파일을 읽지 못했습니다."}
            data = json.dumps(result, ensure_ascii=False).encode()
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
    parser.add_argument("--port", type=int, default=8873)
    parser.add_argument("--inventory-file", type=Path, help="Synthetic JSON document list under /private/tmp")
    args = parser.parse_args()
    if args.inventory_file:
        file_inventory(args.inventory_file, args.port)
    server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    server.mode = args.mode
    server.inventory_file = args.inventory_file
    server.serve_forever()


if __name__ == "__main__":
    main()
