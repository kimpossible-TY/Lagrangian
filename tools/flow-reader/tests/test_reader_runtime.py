"""Shared lifecycle contracts; fake states, isolated sockets/data, no compiler."""
from contextlib import redirect_stderr
from http.client import HTTPConnection
import io
import json
import os
from pathlib import Path
from types import SimpleNamespace
import tempfile
import unittest
from unittest.mock import Mock, patch

from test_homepage import FakeAuth
from flow_reader.server.cli import ReaderRuntime, argument_parser, create_state
from flow_reader.services.paragraph_chat import ParagraphChat
from flow_reader.services.chat_provider import ResponsesProvider
from flow_reader.services.chat_storage import read_json


class RuntimeTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="reader-runtime-test-")
        self.addCleanup(temporary.cleanup)
        self.work = Path(temporary.name)
        self.args = argument_parser().parse_args(["--managed", "--chat-data", str(self.work / "private")])
        self.manager = Mock()
        self.manager.shared_settings.return_value = {"port": 0}
        self.profiles = [{"id": key, "parentID": key, "name": key, "port": 0} for key in ("first", "second")]
        self.manager.profiles.side_effect = lambda: [dict(p) for p in self.profiles]
        self.manager.parent_profiles.return_value = [{"id": key, "name": key, "port": 0} for key in ("first", "second")]
        self.manager.document_arguments.side_effect = lambda p: ["python", "serve.py", "--root", str(self.work / p["id"]),
            "--original-url", "https://paged.example/", "--port", "0"]
        self.states, self.providers = {}, []
        for key in ("first", "second"):
            (self.work / key).mkdir()
        self.closed_auth = []

    def factory(self, plan, provider, directory):
        key = plan.root.name
        state = SimpleNamespace(original_url=plan.original_url, compile=Mock(), close=Mock(), compiling=False,
                                public=lambda: {"revision": key, "documentID": key, "pid": os.getpid()})
        self.states[key] = state
        self.providers.append(provider)
        return state

    def runtime(self):
        with patch("flow_reader.server.cli.ChatAuth", FakeAuth):
            runtime = ReaderRuntime(self.args, self.manager, state_factory=self.factory)
        self.addCleanup(runtime.close)
        return runtime

    def get(self, server, path):
        connection = HTTPConnection("127.0.0.1", server.server_port, timeout=3)
        connection.request("GET", path)
        response = connection.getresponse()
        result = response.status, response.read(), dict(response.getheaders())
        connection.close()
        return result

    def test_missing_shared_rejects_before_states_or_occupied_legacy_port_binds(self):
        from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
        occupied = ThreadingHTTPServer(("127.0.0.1", 0), BaseHTTPRequestHandler)
        self.addCleanup(occupied.server_close)
        self.profiles[0]["port"] = occupied.server_port
        self.args.port = occupied.server_port  # An explicit port does not opt into shared mode.
        self.manager.shared_settings.return_value = None
        factory = Mock(side_effect=AssertionError("Document state must not be created"))
        with patch("flow_reader.server.cli.ThreadingHTTPServer") as server, \
                patch("flow_reader.server.cli.ChatAuth") as auth:
            with self.assertRaisesRegex(ValueError, r'--managed requires.*shared:.*port'):
                ReaderRuntime(self.args, self.manager, state_factory=factory)
        factory.assert_not_called()
        server.assert_not_called()
        auth.assert_not_called()
        self.manager.profiles.assert_not_called()
        self.manager.parent_profiles.assert_not_called()
        self.manager.document_arguments.assert_not_called()
        self.assertFalse((self.work / "private").exists())

    def test_managed_and_home_cli_report_missing_shared_without_binding(self):
        from flow_reader.server.cli import main as reader_main
        from flow_reader.server.home import main as home_main
        self.manager.shared_settings.return_value = None
        for entrypoint in ("reader", "home"):
            with self.subTest(entrypoint=entrypoint), \
                    patch("flow_reader.server.cli.ReaderManager", return_value=self.manager), \
                    patch("flow_reader.server.cli.ThreadingHTTPServer") as server, \
                    patch("flow_reader.server.cli.create_state") as state, \
                    patch("flow_reader.server.cli.signal.signal"), \
                    patch("sys.argv", ["home.py", "--chat-data", str(self.args.chat_data)]), \
                    redirect_stderr(io.StringIO()) as errors:
                with self.assertRaises(SystemExit) as exited:
                    if entrypoint == "reader":
                        reader_main(["--managed", "--chat-data", str(self.args.chat_data)])
                    else:
                        home_main()
                self.assertEqual(exited.exception.code, 2)
                self.assertIn('shared: {"port": ...}', errors.getvalue())
                self.assertNotIn("Traceback", errors.getvalue())
                server.assert_not_called()
                state.assert_not_called()
        self.manager.profiles.assert_not_called()

    def test_one_auth_owner_all_documents_and_redirect_sockets_share_process(self):
        runtime = self.runtime()
        self.assertEqual(len(runtime.servers), 3)
        self.assertIs(self.providers[0], self.providers[1])
        self.assertIs(self.providers[0].auth, runtime.auth)
        self.assertFalse(any(s.compile.called for s in self.states.values()))
        result = runtime.start()
        self.assertEqual(set(result["documents"]), {"first", "second"})
        self.assertEqual(self.get(runtime.admin, "/")[0], 200)
        for key in self.states:
            status, raw, _ = self.get(runtime.admin, f"/d/{key}/api/state")
            self.assertEqual(status, 200)
            self.assertEqual(json.loads(raw)["pid"], os.getpid())
        for key, server in zip(self.states, runtime.servers[1:]):
            status, _, headers = self.get(server, "/?mode=terminal")
            self.assertEqual(status, 307)
            self.assertEqual(headers["Location"], result["documents"][key] + "?mode=terminal")
        capability_file = runtime.capability_path
        self.assertTrue(read_json(capability_file, {})["capability"])
        runtime.close()
        self.assertFalse(capability_file.exists())
        self.assertTrue(all(state.close.called for state in self.states.values()))
        self.assertEqual(runtime.auth.calls, ["cancel"])
        self.assertFalse(runtime.threads)

    def test_loaded_inventory_links_and_status_use_current_states_without_launchctl(self):
        runtime = self.runtime()
        runtime.start()
        runtime.inventory.observe()
        inventory = json.loads(self.get(runtime.admin, "/api/home/documents")[1])
        self.assertEqual(len(inventory["documents"]), 2)
        for item in inventory["documents"]:
            self.assertTrue(all(v["url"].startswith(runtime.origin + f"d/{item['id']}/") for v in item["variants"]))
        self.manager.control.assert_not_called()
        self.manager.job_pid.assert_not_called()
        self.manager.request.assert_not_called()

    def test_startup_failure_disposes_previous_states_lease_and_capability(self):
        self.manager.document_arguments.side_effect = [
            ["python", "serve.py", "--root", str(self.work / "first"), "--original-url", "https://paged.example/"],
            ["python", "serve.py", "--root", str(self.work / "second"), "--original-url", "https://paged.example/"]]
        count = 0
        def factory(*args):
            nonlocal count
            count += 1
            if count == 2:
                raise ValueError("fixture state failed")
            return self.factory(*args)
        with patch("flow_reader.server.cli.ChatAuth", FakeAuth):
            with self.assertRaisesRegex(ValueError, "fixture state failed"):
                ReaderRuntime(self.args, self.manager, state_factory=factory)
        self.assertTrue(self.states["first"].close.called)
        self.assertEqual(list((self.work / "private").glob("home-capability-*.json")), [])
        from flow_reader.server.home import claim_host
        with claim_host(self.work / "private"):
            pass

    def test_source_local_storage_is_rejected_before_creation(self):
        target = self.work / "second" / "private"
        self.args.chat_data = target
        with patch("flow_reader.server.cli.ChatAuth") as auth:
            with self.assertRaisesRegex(ValueError, "outside the source"):
                ReaderRuntime(self.args, self.manager, state_factory=self.factory)
        auth.assert_not_called()
        self.assertFalse(target.exists())

    def test_bind_failure_closes_all_states_without_compiling(self):
        from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
        occupied = ThreadingHTTPServer(("127.0.0.1", 0), BaseHTTPRequestHandler)
        self.addCleanup(occupied.server_close)
        self.manager.shared_settings.return_value = {"port": occupied.server_port}
        with patch("flow_reader.server.cli.ChatAuth", FakeAuth):
            with self.assertRaises(OSError):
                ReaderRuntime(self.args, self.manager, state_factory=self.factory)
        self.assertTrue(all(state.close.called for state in self.states.values()))
        self.assertFalse(any(state.compile.called for state in self.states.values()))
        self.assertEqual(list((self.work / "private").glob("home-capability-*.json")), [])

    def test_home_entrypoint_is_an_alias_for_the_managed_reader(self):
        from flow_reader.server.home import main
        with patch("sys.argv", ["home.py", "--port", "8769"]), \
                patch("flow_reader.server.cli.main") as reader_main:
            main()
        reader_main.assert_called_once_with(["--managed", "--port", "8769"])

    def test_real_state_creation_injects_one_provider_into_lazy_conversations(self):
        auth = FakeAuth(self.work)
        provider = ResponsesProvider(auth)
        states = []
        for key in ("first", "second"):
            (self.work / key / "main.typ").write_text("Fixture")
            plan = argument_parser().parse_args(["--root", str(self.work / key), "--package-path", str(self.work),
                "--output", str(self.work / (key + "-output")), "--original-url", "https://paged.example/"])
            with patch("flow_reader.server.cli.SourceHistoryClient", return_value=None):
                state = create_state(plan, provider, self.work / "private")
            states.append(state)
            self.addCleanup(state.close)
            self.assertIs(state.paragraph_chat.auth, auth)
            self.assertIs(state.paragraph_chat.provider, provider)
        states[0].close()
        self.assertEqual(auth.calls, [])
        self.assertFalse(states[1].paragraph_chat.closed)

    def test_document_disposal_does_not_close_injected_account_owner(self):
        state = SimpleNamespace(project=SimpleNamespace(root=self.work / "first"), document_id="first")
        auth = FakeAuth(self.work)
        chat = ParagraphChat(state, directory=self.work / "private", provider=ResponsesProvider(auth))
        chat.close()
        self.assertEqual(auth.calls, [])


if __name__ == "__main__":
    unittest.main()
