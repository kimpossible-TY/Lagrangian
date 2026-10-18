"""Disposable real-compiler fixture for last-edit browser verification."""

from http.server import ThreadingHTTPServer
import json
import os
from pathlib import Path
import signal
import sys
import tempfile
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
import serve
from build import Project
from sections import split_document


def document(step):
    return ('#set heading(numbering: "1")\n'
            '= First chapter <first>\n\n'
            'Return to #link(<last>)[the last chapter].\n\n' +
            ''.join(f'Passage {number}: Ordinary reading keeps this sentence visible.\n\n'
                    for number in range(90)) +
            '= Last chapter <last>\n\n'
            'Return to #link(<first>)[the first chapter].\n\n'
            f'Edited passage version {step}.\n\n'
            '$ x^2 + y^2 = z^2 $\n\n' +
            ''.join(f'Final passage {number}: Trailing text permits target alignment.\n\n'
                    for number in range(15)))


def main():
    def stop(_signal, _frame):
        raise SystemExit(0)
    signal.signal(signal.SIGTERM, stop)
    with tempfile.TemporaryDirectory(prefix="reader-last-change-") as temporary:
        work = Path(temporary)
        entry = work / "main.typ"
        entry.write_text(document(0))
        project = Project(work, Path("main.typ"), Path(os.environ["FLOW_READER_PACKAGES"]),
                          compiler=os.environ.get("FLOW_READER_TYPST", "typst"))
        serve.split_document = lambda source, revision: split_document(source, revision, max_blocks=6)
        state = serve.ReaderState(project, work / "output", "https://example.test/paged/", False)
        state.compile()
        if state.revision is None:
            raise RuntimeError(state.report)

        class Handler(serve.handler_for(state)):
            def do_POST(self):
                if urlsplit(self.path).path != "/api/test-edit":
                    return super().do_POST()
                if self.headers.get("Origin") not in {None, f"http://127.0.0.1:{self.server.server_port}"}:
                    return self.respond(b"Wrong fixture origin", "text/plain", 403)
                request = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
                step = request["step"]
                if step == "failure":
                    entry.write_text("#unknown-fixture-function()")
                elif step == "comment":
                    entry.write_text(entry.read_text() + "\n// Comment without visible output\n")
                elif type(step) is int and 0 <= step <= 20:
                    entry.write_text(document(step))
                else:
                    return self.respond(b"Invalid fixture edit", "text/plain", 400)
                state.compile()
                return self.respond(json.dumps(state.public()).encode(), "application/json")

        server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        print(json.dumps({"url": f"http://127.0.0.1:{server.server_port}/"}), flush=True)
        try:
            server.serve_forever()
        finally:
            server.server_close()


if __name__ == "__main__":
    main()
