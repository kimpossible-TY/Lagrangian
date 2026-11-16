"""Shared Reader service entrypoint: Homepage and independent document states."""
import argparse
from contextlib import ExitStack
from http.server import ThreadingHTTPServer
import json
from pathlib import Path
import secrets
import signal
import threading
from flow_reader.compiler.project import Project
from flow_reader.server.state import ReaderState
from flow_reader.server.http import handler_for
from flow_reader.server.watch import watch
from flow_reader.server.home import claim_host
from flow_reader.server.routing import handler_for_reader, handler_for_legacy
from flow_reader.server.preview_proxy import PreviewProxy
from flow_reader.services.source_history import SourceHistoryClient
from flow_reader.services.manager import ReaderManager
from flow_reader.services.homepage import HomeInventory, LOOPBACK_HOST, document_prefix
from flow_reader.services.home_account import HomeAccount
from flow_reader.services.chat_auth import ChatAuth
from flow_reader.services.chat_provider import ResponsesProvider
from flow_reader.services.chat_storage import DEFAULT_CHAT_DATA, inside_source, private_directory, write_json
from flow_reader.resources import READER_ROOT


def argument_parser():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path)
    parser.add_argument("--entry", type=Path, default=Path("main.typ"))
    parser.add_argument("--package-path", type=Path)
    parser.add_argument("--font-path", type=Path, action="append", default=[])
    parser.add_argument("--compiler", default="typst")
    parser.add_argument("--browser-compiler", type=Path,
                        help="Generated WASM compiler directory; uses explicit and bundled fonts for all executors")
    parser.add_argument("--engine", help="Flow engine supporting shared source history (FLOW_ENGINE_PATH or installed engine)")
    parser.add_argument("--semantic-canvases", action="store_true")
    parser.add_argument("--output", type=Path)
    parser.add_argument("--original-url")
    parser.add_argument("--public-url", help="Configured HTTPS Reader origin allowed by the HTTP Host guard")
    parser.add_argument("--homepage-url", help="Legacy option; shared Reader account entry is at its root")
    parser.add_argument("--managed", action="store_true", help="Serve all ReaderManager documents in one process")
    parser.add_argument("--data", type=Path, help="ReaderManager configuration directory")
    parser.add_argument("--chat-data", type=Path, default=DEFAULT_CHAT_DATA)
    parser.add_argument("--public-origin", help="Shared HTTPS origin on a separately provisioned proxy")
    parser.add_argument("--proxy-port", type=int, help="Read-only loopback ingress for that HTTPS proxy")
    parser.add_argument("--port", type=int, default=0)
    parser.add_argument("--watch", action="store_true")
    parser.add_argument("--focus-file", type=Path, help="Absolute Codex context file (default OUTPUT/focus.json)")
    parser.add_argument("--editor-server", help="Neovim server owning final verified source edits")
    parser.add_argument("--nvim", default="nvim", help="Neovim executable used for editor RPC")
    parser.add_argument("--change-file", type=Path, help="Common project edit history (otherwise match a Flow profile or project identity)")
    parser.add_argument("--allow-incomplete", action="store_true",
                        help="Local development only: show explicit fidelity diagnostics")
    return parser


def create_state(args, provider, directory):
    project = Project(args.root.resolve(), args.entry, args.package_path.resolve(),
                      tuple(args.font_path), args.compiler, args.semantic_canvases)
    project.relative_entry()
    source_history = SourceHistoryClient(project, engine=args.engine, change_file=args.change_file)
    try:
        state = ReaderState(project, args.output.resolve(), args.original_url, args.allow_incomplete,
                            focus_file=args.focus_file, editor_server=args.editor_server, nvim=args.nvim,
                            change_file=args.change_file, source_history=source_history,
                            browser_compiler=args.browser_compiler, chat_provider=provider, chat_data=directory)
    except BaseException:
        source_history.close()
        raise
    state.prewarm = True
    return state


class ReaderRuntime:
    """Own listeners, workers and one auth lease; construction never compiles."""
    def __init__(self, options, manager, *, state_factory=create_state):
        self.options, self.manager = options, manager
        self.stack = ExitStack()
        self.servers, self.threads, self.documents = [], [], {}
        self.workers = []
        self.stopped = threading.Event()
        try:
            self.configure(state_factory)
        except BaseException:
            self.close()
            raise

    def configure(self, state_factory):
        args, manager = self.options, self.manager
        # Shared mode is opt-in; never take over legacy document ports implicitly.
        shared = manager.shared_settings()
        if shared is None:
            raise ValueError('--managed requires ReaderManager config shared: {"port": ...}; configure shared before starting the Reader')
        profiles = manager.profiles()
        parents = manager.parent_profiles()
        port = args.port or shared.get("port", 8769)
        public = args.public_origin or shared.get("publicURL") or None
        proxy_port = args.proxy_port if args.proxy_port is not None else shared.get("proxyPort")
        self.previews = PreviewProxy(parents, reserved_ports={port, proxy_port,
            *(p.get("legacyPort", p["port"]) for p in profiles)})
        self.stack.callback(self.previews.close)
        plans = {p["id"]: argument_parser().parse_args(manager.document_arguments(p)[2:]) for p in profiles}
        if bool(public) != (proxy_port is not None):
            raise ValueError("Shared public origin and read-only proxy port must be configured together")
        # Check every source before mkdir/chmod, including non-Git projects.
        target = args.chat_data.expanduser().resolve()
        if any(inside_source(target, plan.root) for plan in plans.values()):
            raise ValueError("Chat storage must be outside the source project")
        self.directory = private_directory(args.chat_data, READER_ROOT.parents[1])
        self.stack.enter_context(claim_host(self.directory))
        self.auth = ChatAuth(self.directory)
        self.stack.callback(self.auth.close)
        provider = ResponsesProvider(self.auth)
        account = HomeAccount(self.auth, provider)
        for key, plan in plans.items():
            document_prefix(key)
            state = state_factory(plan, provider, self.directory)
            self.stack.callback(state.close)
            self.documents[key] = state
        capability = secrets.token_urlsafe(32)
        self.capability_path = self.directory / ("home-capability-" + secrets.token_hex(8) + ".json")
        write_json(self.capability_path, {"capability": capability})
        self.stack.callback(self.capability_path.unlink, missing_ok=True)
        # Bind all listeners before starting workers; a port conflict leaves no
        # partially running compiler, host or credential owner.
        inventory = self.inventory = HomeInventory(manager, loaded=(parents, profiles, self.documents))
        self.stack.callback(inventory.close)
        self.admin = self.bind(port, handler_for_reader(self.documents, inventory, account,
                               capability=capability, previews=self.previews,
                               preview_parents={p["id"]: p["parentID"] for p in profiles}))
        self.origin = f"http://{LOOPBACK_HOST}:{self.admin.server_port}/"
        inventory.preview_origins = (public, self.origin)
        for profile in profiles:
            profile.update(port=self.admin.server_port, publicURL=public or "")
        if proxy_port is not None:
            self.bind(proxy_port, handler_for_reader(self.documents, inventory, account,
                      capability=capability, ingress="proxy", public_origin=public, previews=self.previews,
                      preview_parents={p["id"]: p["parentID"] for p in profiles}))
        for profile in profiles:
            legacy_port = profile.get("legacyPort", plans[profile["id"]].port)
            if legacy_port in {self.admin.server_port, proxy_port}:
                raise ValueError("Shared ports must differ from old document ports")
            self.bind(legacy_port, handler_for_legacy(profile["id"], public or self.origin,
                      public_origin=profile.get("legacyPublicURL", plans[profile["id"]].public_url)))
        self.plans = plans

    def bind(self, port, handler):
        server = ThreadingHTTPServer((LOOPBACK_HOST, port), handler)
        self.servers.append(server)
        self.stack.callback(server.server_close)
        return server

    def start(self):
        for server in self.servers:
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            self.threads.append((server, thread))
        for key, state in self.documents.items():
            state.compiling = True
            def compile_and_watch(state=state, plan=self.plans[key]):
                state.compile()
                if plan.watch and not self.stopped.is_set():
                    watch(state, self.stopped)
            thread = threading.Thread(target=compile_and_watch, daemon=True)
            thread.start()
            self.workers.append(thread)
        return {"url": self.origin, "documents": {key: self.origin + document_prefix(key).lstrip("/")
                for key in self.documents}, "capabilityFile": str(self.capability_path)}

    def close(self):
        self.stopped.set()
        if getattr(self, "previews", None) is not None:
            self.previews.close()
        for server, thread in self.threads:
            server.shutdown()
            thread.join(timeout=2)
        self.threads.clear()
        self.stack.close()
        for worker in self.workers:
            worker.join(timeout=2)
        self.workers.clear()


def main(argv=None):
    parser = argument_parser()
    args = parser.parse_args(argv)
    if not args.managed and any(getattr(args, field) is None for field in
                                ("root", "package_path", "output", "original_url")):
        parser.error("Document mode requires --root, --package-path, --output and --original-url")
    def terminate(_signum, _frame):
        raise KeyboardInterrupt
    signal.signal(signal.SIGTERM, terminate)
    if not args.managed:
        return run_document(args)
    runtime = None
    try:
        runtime = ReaderRuntime(args, ReaderManager(data=args.data))
        print(json.dumps(runtime.start()), flush=True)
        runtime.stopped.wait()
    except KeyboardInterrupt:
        pass
    except (OSError, ValueError) as error:
        parser.error(str(error))
    finally:
        if runtime is not None:
            runtime.close()


def run_document(args):
    """Legacy direct CLI retained until its manager configuration migrates."""
    try:
        state = create_state(args, None, None)
    except KeyboardInterrupt:
        return
    except ValueError as error:
        raise SystemExit(str(error)) from error
    server = ThreadingHTTPServer(("127.0.0.1", args.port), handler_for(
        state, public_url=args.public_url, homepage_url=args.homepage_url))
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
