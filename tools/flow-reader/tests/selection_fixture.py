"""Disposable real-compiler Reader for selection action browser checks."""

from http.server import ThreadingHTTPServer
import json
import os
from pathlib import Path
import signal
import sys
import tempfile
import threading

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from build import Project
from serve import ReaderState, handler_for, watch


def main():
    def stop(_signal, _frame):
        raise SystemExit(0)
    signal.signal(signal.SIGTERM, stop)
    with tempfile.TemporaryDirectory(prefix="reader-selection-") as temporary:
        work = Path(temporary)
        root = work / "source"
        root.mkdir()
        entry = root / "main.typ"
        entry.write_text(
            '#import "@local/text-utils:0.1.2": highlighted\n'
            '#set math.equation(numbering: "(1)")\n'
            '= Selection actions\n\n'
            'A selected ordinary passage wraps across narrow reading lines and remains '
            'available for review, Codex context and source highlighting.\n\n'
            'Complete mathematics $alpha^2 + beta$ remains selectable.\n\n'
            'Numbered example.\n\n$ alpha^2 + beta + 1 $\n\n'
            'Another independent selection remains available during a pending request.\n\n'
            '#let repeated() = [Shared macro words]\n'
            '#repeated()\n\n#repeated()\n\n' +
            ''.join(f'Trailing paragraph {i} permits ordinary vertical reading.\n\n'
                    for i in range(15)))
        project = Project(root, Path("main.typ"), Path(os.environ["FLOW_READER_PACKAGES"]),
                          compiler=os.environ.get("FLOW_READER_TYPST", "typst"))
        state = ReaderState(project, work / "output", "https://example.test/paged/", False)
        state.compile()
        if not state.revision:
            raise RuntimeError(state.report)
        stopped = threading.Event()
        thread = threading.Thread(target=watch, args=(state, stopped), daemon=True)
        thread.start()
        server = ThreadingHTTPServer(("127.0.0.1", 0), handler_for(state))
        print(json.dumps({"url": f"http://127.0.0.1:{server.server_port}/", "entry": str(entry),
                          "focusFile": str(state.focus.path)}), flush=True)
        try:
            server.serve_forever()
        finally:
            stopped.set()
            server.server_close()


if __name__ == "__main__":
    main()
