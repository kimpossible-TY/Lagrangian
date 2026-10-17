"""Run the normal Reader with browser integration checks attached only for tests.

Use normal serve.py arguments and tests/fixtures/responsive-math.typ as main.typ
in a disposable project directory. The report appears after the reading body.
"""

from pathlib import Path
import sys
from urllib.parse import parse_qs, urlsplit

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
import serve

normal_handler = serve.handler_for


def handler_for(state):
    class Handler(normal_handler(state)):
        def do_GET(self):
            path = urlsplit(self.path).path
            if path == "/":
                module = "routing-browser.js" if parse_qs(urlsplit(self.path).query).get("check") == ["routing"] else "runtime-browser.js"
                source = (ROOT / "web/index.html").read_text().replace(
                    "</body>", f'<script type="module" src="/{module}"></script></body>')
                return self.respond(source.encode(), "text/html; charset=utf-8")
            if path == "/runtime-browser.js":
                return self.respond((ROOT / "tests/runtime-browser.js").read_bytes(),
                                    "text/javascript; charset=utf-8")
            if path == "/routing-browser.js":
                return self.respond((ROOT / "tests/routing-browser.js").read_bytes(),
                                    "text/javascript; charset=utf-8")
            super().do_GET()
    return Handler


if __name__ == "__main__":
    serve.handler_for = handler_for
    serve.main()
