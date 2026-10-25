"""Disposable real-compiler Reader for selection action browser checks."""

from http.server import ThreadingHTTPServer
import json
import os
from pathlib import Path
import signal
import shutil
import sys
import tempfile
import threading

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from flow_reader.compiler.build import Project
from flow_reader.server.state import ReaderState
from flow_reader.server.http import handler_for
from flow_reader.server.watch import watch


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
            '#let source-scope(body) = body(none)\n'
            '#let source-proof(body) = block(body)\n'
            '#source-scope(s => [\n#source-proof[\nWrapped proof 한글 with '
            '$alpha^2 + beta$ stays connected to its source.\n\n'
            'The next proof paragraph retains its own source range.\n]\n])\n\n'
            'Numbered example.\n\n$ alpha^2 + beta + 1 $\n\n'
            'Another independent selection remains available during a pending request.\n\n'
            '#let repeated() = [Shared macro words]\n'
            '#repeated()\n\n#repeated()\n\n' +
            ''.join(f'Trailing paragraph {i} permits ordinary vertical reading.\n\n'
                    for i in range(15)))
        project = Project(root, entry.resolve(), Path(os.environ["FLOW_READER_PACKAGES"]),
                          compiler=os.environ.get("FLOW_READER_TYPST", "typst"))
        managed = os.environ.get('FLOW_READER_MANAGED_FIXTURE') == '1'
        data = work / 'managed'
        output = data / 'documents' / 'fixture-reader' if managed else work / 'output'
        state = ReaderState(project, output, "https://example.test/paged/", False,
                            editor_server=os.environ.get("FLOW_READER_EDITOR_SERVER"),
                            change_file=os.environ.get("FLOW_READER_CHANGE_FILE"))
        state.compile()
        if not state.revision:
            raise RuntimeError(state.report)
        stopped = threading.Event()
        thread = threading.Thread(target=watch, args=(state, stopped), daemon=True)
        thread.start()
        server = ThreadingHTTPServer(("127.0.0.1", 0), handler_for(state))
        report = {"url": f"http://127.0.0.1:{server.server_port}/", "entry": str(entry),
                  "focusFile": str(state.focus.path)}
        if managed:
            # Only the platform launchd lookup is substituted. The actual manager,
            # profile matching, HTTP handshake, private registry and HTML service run.
            flow = work / 'flow-profile'
            parent = {'id': 'fixture', 'name': 'Fixture', 'root': str(root), 'entry': 'main.typ',
                      'fonts': [], 'packages': str(project.packages), 'port': 25001}
            flow.write_text(f'#!{sys.executable}\nimport json\nprint({json.dumps(json.dumps({"profiles": [parent]}))})\n')
            flow.chmod(0o700)
            (data / 'config.json').write_text(json.dumps({
                'schemaVersion': 1, 'flowManager': str(flow), 'python': sys.executable,
                'compiler': shutil.which(project.compiler), 'services': [{'id': 'fixture-reader', 'parentID': 'fixture',
                                                          'port': server.server_port}]}))
            interpreter = work / 'fixture-manager-python'
            interpreter.write_text(f'#!{sys.executable}\n' +
                'import os,sys\nfrom pathlib import Path\n' +
                'if Path(sys.argv[1]).name != "manage.py": os.execv(sys.executable, [sys.executable, *sys.argv[1:]])\n' +
                f'sys.path.insert(0, {str(ROOT)!r})\n' +
                'from flow_reader.services.manager import ReaderManager, cli\n' +
                f'ReaderManager.job_pid = lambda self, profile: {os.getpid()}\n' +
                'def unexpected(*args): raise AssertionError("Attachment tried to restart the running HTML service")\n' +
                'ReaderManager.control = unexpected\nsys.argv = sys.argv[1:]\nraise SystemExit(cli())\n')
            interpreter.chmod(0o700)
            report.update(managedData=str(data), managerPython=str(interpreter))
        print(json.dumps(report), flush=True)
        try:
            server.serve_forever()
        finally:
            stopped.set()
            server.server_close()
            state.close()


if __name__ == "__main__":
    main()
