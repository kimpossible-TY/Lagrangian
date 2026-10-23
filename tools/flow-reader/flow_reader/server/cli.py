"""Loopback Reader service entrypoint."""
import argparse
from http.server import ThreadingHTTPServer
import json
from pathlib import Path
import signal
import threading
from flow_reader.compiler.project import Project
from flow_reader.server.state import ReaderState
from flow_reader.server.http import handler_for
from flow_reader.server.watch import watch
from flow_reader.services.source_history import SourceHistoryClient


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--entry", type=Path, default=Path("main.typ"))
    parser.add_argument("--package-path", type=Path, required=True)
    parser.add_argument("--font-path", type=Path, action="append", default=[])
    parser.add_argument("--compiler", default="typst")
    parser.add_argument("--engine", help="Flow engine supporting shared source history (FLOW_ENGINE_PATH or installed engine)")
    parser.add_argument("--semantic-canvases", action="store_true")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--original-url", required=True)
    parser.add_argument("--port", type=int, default=0)
    parser.add_argument("--watch", action="store_true")
    parser.add_argument("--focus-file", type=Path, help="Absolute Codex context file (default OUTPUT/focus.json)")
    parser.add_argument("--editor-server", help="Neovim server owning final verified source edits")
    parser.add_argument("--nvim", default="nvim", help="Neovim executable used for editor RPC")
    parser.add_argument("--change-file", type=Path, help="Common project edit history (otherwise match a Flow profile or project identity)")
    parser.add_argument("--allow-incomplete", action="store_true",
                        help="Local development only: show explicit fidelity diagnostics")
    args = parser.parse_args()
    project = Project(args.root.resolve(), args.entry, args.package_path.resolve(),
                      tuple(args.font_path), args.compiler, args.semantic_canvases)
    project.relative_entry()
    def terminate(signum, frame):
        raise KeyboardInterrupt
    signal.signal(signal.SIGTERM, terminate)
    try:
        source_history = SourceHistoryClient(project, engine=args.engine, change_file=args.change_file)
    except KeyboardInterrupt:
        return
    except ValueError as error:
        parser.error(str(error))
    state = ReaderState(project, args.output.resolve(), args.original_url, args.allow_incomplete,
                        focus_file=args.focus_file, editor_server=args.editor_server, nvim=args.nvim,
                        change_file=args.change_file, source_history=source_history)
    server = ThreadingHTTPServer(("127.0.0.1", args.port), handler_for(state))
    state.prewarm = True
    stopped = threading.Event()
    def compile_and_watch():
        state.compile()
        if args.watch:
            watch(state, stopped)
    state.compiling = True
    try:
        threading.Thread(target=compile_and_watch, daemon=True).start()
        print(json.dumps({"url": f"http://127.0.0.1:{server.server_port}/", **state.public()}), flush=True)
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        stopped.set()
        server.server_close()
        state.close()
