"""Run the normal Reader with browser integration checks attached only for tests.

Use normal serve.py arguments and tests/fixtures/responsive-math.typ as main.typ
in a disposable project directory. The report appears after the reading body.
"""

from pathlib import Path
import json
import re
import sys
import threading
import time
from urllib.parse import parse_qs, urlsplit

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
import serve

normal_handler = serve.handler_for
report_lock = threading.Lock()


def save_browser_report(state, origin, expected_origin, payload):
    owned = (ROOT.parents[1] / "dist").resolve()
    if (not state.project.root.resolve().is_relative_to(owned)
            or not state.output.resolve().is_relative_to(owned)):
        raise PermissionError("Browser reports require an owned disposable fixture")
    if origin != expected_origin:
        raise PermissionError("Browser report origin does not match the fixture")
    run, kind = payload.get("run"), payload.get("kind")
    if (not isinstance(run, str) or not re.fullmatch(r"[a-zA-Z0-9][a-zA-Z0-9-]{0,63}", run)
            or kind not in {"body-math", "graphics", "native-canvases", "tables", "decorations"}):
        raise ValueError("Invalid browser report identity")
    sequence = payload.get("sequence")
    if type(sequence) is not int or sequence < 1 or payload.get("state") not in {"progress", "ready", "error"}:
        raise ValueError("Invalid browser report sequence or state")
    report = payload.get("report")
    with state.lock:
        revision = state.revision
    if not isinstance(report, dict) or not revision or report.get("revision") != revision:
        raise ValueError("Browser report does not describe the accepted fixture revision")
    directory = state.output / "browser-audits"
    path = directory / f"{kind}-{run}.json"
    with report_lock:
        if path.exists() and json.loads(path.read_text())["sequence"] >= sequence:
            return {"saved": False, "sequence": sequence}
        directory.mkdir(exist_ok=True)
        record = {**payload, "receivedAt": time.time(), "origin": origin}
        temporary = path.with_suffix(".tmp")
        temporary.write_text(json.dumps(record, ensure_ascii=False))
        temporary.replace(path)
    return {"saved": True, "sequence": sequence}


def handler_for(state):
    class Handler(normal_handler(state)):
        def do_POST(self):
            if urlsplit(self.path).path == "/api/test-report":
                try:
                    length = int(self.headers.get("Content-Length", "0"))
                    if not 0 < length <= 2 * 1024 * 1024:
                        raise ValueError("Invalid browser report size")
                    payload = json.loads(self.rfile.read(length))
                    if not isinstance(payload, dict):
                        raise ValueError("Invalid browser report")
                    result = save_browser_report(state, self.headers.get("Origin"),
                        f"http://127.0.0.1:{self.server.server_port}", payload)
                    return self.respond(json.dumps(result).encode(), "application/json")
                except PermissionError as error:
                    return self.respond(str(error).encode(), "text/plain", 403)
                except (ValueError, TypeError, KeyError):
                    return self.respond(b"Invalid owned browser report", "text/plain", 400)
            if urlsplit(self.path).path != "/api/test-edit":
                return super().do_POST()
            # This write protocol exists only in this test wrapper and only for
            # the explicitly owned PDE copy. The original project is excluded.
            expected = (ROOT.parents[1] / "dist/reader-label-checks/pde-update-source").resolve()
            if state.project.root.resolve() != expected:
                return self.respond(b"Not an owned update fixture", "text/plain", 403)
            try:
                length = int(self.headers.get("Content-Length", "0"))
                if not 0 < length <= 1000:
                    raise ValueError("Invalid test edit")
                step = json.loads(self.rfile.read(length))["step"]
                if type(step) is not int or step not in (1, 2):
                    raise ValueError("Unknown test edit")
                path = (expected / "chapter 3/figures/figures.typ").resolve()
                if not path.is_relative_to(expected):
                    raise ValueError("Test edit escaped its copy")
                source = path.read_text()
                marker = f"Source update fixture {step}"
                if marker not in source:
                    start = source.index("#let coordinate-averaging-surfaces()")
                    needle = "grid(columns: (1fr, 1fr), column-gutter: 12pt, row-gutter: 13pt,"
                    offset = source.index(needle, start) + len(needle)
                    function = "eta-profile(x + .65) * eta-profile(y)" if step == 1 else "eta-profile(x) * eta-profile(y)"
                    statement = f'\n    panel((x, y) => {function}, [{marker}], [Inserted in the isolated test copy], theme.callouts.tip.border),'
                    path.write_text(source[:offset] + statement + source[offset:])
                return self.respond(json.dumps({"edited": True, "step": step}).encode(), "application/json")
            except (ValueError, KeyError, OSError, json.JSONDecodeError):
                return self.respond(b"Invalid owned test edit", "text/plain", 400)

        def do_GET(self):
            path = urlsplit(self.path).path
            if path == "/":
                check = parse_qs(urlsplit(self.path).query).get("check", [""])[0]
                module = {"routing": "routing-browser.js", "native": "native-browser.js",
                          "highlighted": "highlighted-browser.js",
                          "equation-numbers": "equation-numbers-browser.js",
                          "inline": "inline-browser.js", "structure": "structure-browser.js",
                          "canvas-loading": "canvas-loading-browser.js",
                          "native-canvases": "native-canvases-browser.js",
                          "native-position": "native-position-browser.js",
                          "native-update": "native-update-browser.js",
                          "tables": "tables-browser.js",
                          "graphics": "graphics-browser.js",
                          "viewport": "viewport-browser.js",
                          "navigation": "navigation-browser.js",
                          "reading-navigation": "reading-navigation-browser.js",
                          "language": "language-browser.js",
                          "body-math": "body-math-browser.js",
                          "decoration-copy": "decoration-copy-browser.js",
                          "position": "position-browser.js", "entry": "entry-browser.js"}.get(check, "runtime-browser.js")
                source = (ROOT / "web/index.html").read_text().replace(
                    "</body>", f'<script type="module" src="/{module}"></script></body>')
                if check == "entry":
                    source = source.replace('<script type="module" src="reader.js">',
                                            '<script src="/entry-bootstrap.js"></script><script type="module" src="reader.js">')
                if check == "viewport":
                    source = source.replace('<script type="module" src="reader.js">',
                                            '<script src="/viewport-bootstrap.js"></script><script type="module" src="reader.js">')
                return self.respond(source.encode(), "text/html; charset=utf-8")
            if path == "/viewport-bootstrap.js":
                source = (ROOT / "tests/viewport-bootstrap.js").read_text().replace(
                    "__DOCUMENT_ID__", json.dumps(state.document_id))
                return self.respond(source.encode(), "text/javascript; charset=utf-8")
            if path == "/viewport-browser.js":
                return self.respond((ROOT / "tests/viewport-browser.js").read_bytes(),
                                    "text/javascript; charset=utf-8")
            if path == "/navigation-browser.js":
                return self.respond((ROOT / "tests/navigation-browser.js").read_bytes(),
                                    "text/javascript; charset=utf-8")
            if path == "/reading-navigation-browser.js":
                return self.respond((ROOT / "tests/reading-navigation-browser.js").read_bytes(),
                                    "text/javascript; charset=utf-8")
            if path == "/test-report.js":
                return self.respond((ROOT / "tests/test-report.js").read_bytes(),
                                    "text/javascript; charset=utf-8")
            if path == "/decoration-copy-browser.js":
                return self.respond((ROOT / "tests/decoration-copy-browser.js").read_bytes(),
                                    "text/javascript; charset=utf-8")
            if path == "/language-browser.js":
                return self.respond((ROOT / "tests/language-browser.js").read_bytes(),
                                    "text/javascript; charset=utf-8")
            if path == "/entry-bootstrap.js":
                with state.lock:
                    if not state.bundle:
                        return self.respond(b"Compile not ready", "text/plain", 503)
                    key, section = next(iter(state.bundle.manifest["blocks"].items()))
                    anchor = {"key": key, "text": "", "offset": 0, "section": section}
                source = (ROOT / "tests/entry-bootstrap.js").read_text().replace(
                    "__SEED_ANCHOR__", json.dumps(anchor)).replace("__DOCUMENT_ID__", json.dumps(state.document_id))
                return self.respond(source.encode(), "text/javascript; charset=utf-8")
            if path == "/entry-browser.js":
                return self.respond((ROOT / "tests/entry-browser.js").read_bytes(),
                                    "text/javascript; charset=utf-8")
            if path == "/native-canvases-browser.js":
                return self.respond((ROOT / "tests/native-canvases-browser.js").read_bytes(),
                                    "text/javascript; charset=utf-8")
            if path == "/native-position-browser.js":
                return self.respond((ROOT / "tests/native-position-browser.js").read_bytes(),
                                    "text/javascript; charset=utf-8")
            if path == "/native-update-browser.js":
                return self.respond((ROOT / "tests/native-update-browser.js").read_bytes(),
                                    "text/javascript; charset=utf-8")
            if path == "/tables-browser.js":
                return self.respond((ROOT / "tests/tables-browser.js").read_bytes(),
                                    "text/javascript; charset=utf-8")
            if path == "/graphics-browser.js":
                return self.respond((ROOT / "tests/graphics-browser.js").read_bytes(),
                                    "text/javascript; charset=utf-8")
            if path == "/body-math-browser.js":
                return self.respond((ROOT / "tests/body-math-browser.js").read_bytes(),
                                    "text/javascript; charset=utf-8")
            if path == "/runtime-browser.js":
                return self.respond((ROOT / "tests/runtime-browser.js").read_bytes(),
                                    "text/javascript; charset=utf-8")
            if path == "/highlighted-browser.js":
                return self.respond((ROOT / "tests/highlighted-browser.js").read_bytes(),
                                    "text/javascript; charset=utf-8")
            if path == "/equation-numbers-browser.js":
                return self.respond((ROOT / "tests/equation-numbers-browser.js").read_bytes(),
                                    "text/javascript; charset=utf-8")
            if path == "/routing-browser.js":
                return self.respond((ROOT / "tests/routing-browser.js").read_bytes(),
                                    "text/javascript; charset=utf-8")
            if path == "/native-browser.js":
                return self.respond((ROOT / "tests/native-browser.js").read_bytes(),
                                    "text/javascript; charset=utf-8")
            if path == "/inline-browser.js":
                return self.respond((ROOT / "tests/inline-browser.js").read_bytes(),
                                    "text/javascript; charset=utf-8")
            if path == "/structure-browser.js":
                return self.respond((ROOT / "tests/structure-browser.js").read_bytes(),
                                    "text/javascript; charset=utf-8")
            if path == "/canvas-loading-browser.js":
                return self.respond((ROOT / "tests/canvas-loading-browser.js").read_bytes(),
                                    "text/javascript; charset=utf-8")
            if path == "/position-browser.js":
                return self.respond((ROOT / "tests/position-browser.js").read_bytes(),
                                    "text/javascript; charset=utf-8")
            super().do_GET()
    return Handler


if __name__ == "__main__":
    serve.handler_for = handler_for
    serve.main()
