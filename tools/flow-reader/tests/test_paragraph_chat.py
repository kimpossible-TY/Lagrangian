"""Host persistence, OAuth and genuine local HTTP/SSE tool-loop contracts."""
import concurrent.futures
import io
from http.server import ThreadingHTTPServer
import json
import os
from pathlib import Path
import stat
import tempfile
import threading
import time
import unittest
from urllib.error import HTTPError, URLError
from urllib.parse import parse_qs, urlencode, urlsplit
from urllib.request import Request, urlopen
from unittest.mock import patch

from chat_fixture import FakeOpenAI, SyntheticReader
from flow_reader.errors import RevisionChanged
from flow_reader.server.http import handler_for
from flow_reader.services.chat_auth import ChatProviderError, verify_identity
from flow_reader.services.chat_storage import read_json, write_json
from flow_reader.services.paragraph_chat import ParagraphChat, DocumentTools, attach


class ParagraphChatTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="paragraph-chat-test-")
        self.addCleanup(temporary.cleanup)
        self.work = Path(temporary.name)
        self.fake = FakeOpenAI()
        self.addCleanup(self.fake.close)
        self.reader = SyntheticReader(self.work, self.fake)
        self.addCleanup(self.reader.close)
        self.chat = self.reader.state.paragraph_chat

    def open(self, text="First paragraph"):
        return self.chat.open(self.reader.request(fragments=self.reader.fragments(text)))["conversations"][0]

    def send(self, record, question="Explain this", model="fixture-model", **extra):
        return self.chat.mutate(self.reader.request(conversationID=record["conversation_id"],
            version=record["version"], question=question, model=model, messageID=os.urandom(8).hex(), **extra), "send")

    def wait(self, identifier):
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            record = next(r for r in self.chat.list(self.reader.request())["conversations"] if r["conversation_id"] == identifier)
            if record["status"] != "streaming":
                return record
            time.sleep(0.02)
        self.fail("Host turn did not finish")

    def test_durable_independent_threads_restart_rename_and_unresolved(self):
        a, b = self.open(), self.open("second independent")
        self.assertNotEqual(a["conversation_id"], b["conversation_id"])
        reopened = self.open("keeps its own")
        self.assertEqual(reopened["conversation_id"], a["conversation_id"])
        a = reopened
        self.send(a)
        final = self.wait(a["conversation_id"])
        self.assertEqual(final["status"], "completed")
        self.assertEqual(final["draft"], "")
        self.assertEqual(len(self.chat.list(self.reader.request())["conversations"][1]["thread"]), 0)
        restored = ParagraphChat(self.reader.state, directory=self.work / "private", provider=self.chat.provider)
        self.assertEqual(restored.list(self.reader.request())["conversations"][0]["conversation_id"], a["conversation_id"])
        old_id = self.reader.state.document_id
        self.reader.state.document_id = "renamed-document"
        self.assertEqual(self.chat.list(self.reader.request())["conversations"], [])
        self.reader.state.document_id = old_id
        self.reader.html = self.reader.html.replace("First paragraph keeps its own question.", "Deleted paragraph replacement.")
        self.reader.publish("r2")
        missing = self.chat.list(self.reader.request())["conversations"][0]
        self.assertEqual(missing["attachment"]["state"], "unresolved")
        self.assertEqual(missing["thread"], final["thread"])

    def test_context_search_read_loop_only_explicit_bounded_tools_and_no_source_edits(self):
        before = self.reader.entry.read_bytes()
        # Real 8000-character passage pages, not an oversized fake tool result.
        self.reader.html = self.reader.html.replace("Additional context can be found by the model.",
                                                    "Additional context " + "x" * 8100)
        self.reader.publish("fixture-r1")
        for rounds, batch, fallback in ((9, 1, False), (9, 1, True), (1, 26, False), (14, 1, False)):
            with self.subTest(rounds=rounds, batch=batch, fallback=fallback):
                self.fake.tool_rounds, self.fake.calls_per_round = rounds, batch
                self.fake.fallback_text = fallback
                self.fake.requests.clear()
                self.fake.tool_outputs.clear()
                record = self.open()
                self.send(record, model="gpt-6-luna")
                final = self.wait(record["conversation_id"])
                self.assertEqual(final["status"], "completed")
                self.assertEqual(final["draft"], "")
                self.assertIn("accepted context", final["thread"][-1]["text"])
                requests = [body for path, body in self.fake.requests if path == "/responses"]
                self.assertEqual(len(requests), rounds + 1)
                continuation = []
                for index, body in enumerate(requests):
                    self.assertFalse(body["store"])
                    self.assertTrue(body["stream"])
                    self.assertEqual(body["model"], "gpt-6-luna")
                    self.assertEqual(body["reasoning"], {"effort": "xhigh"})
                    self.assertNotIn("previous_response_id", body)
                    namespace, = body["tools"]
                    self.assertEqual(namespace["name"], "current_document")
                    self.assertEqual([t["name"] for t in namespace["tools"]],
                                     ["search_current_document", "read_passage"])
                    self.assertTrue(all(t["strict"] and not t["parameters"]["additionalProperties"]
                                        for t in namespace["tools"]))
                    self.assertEqual(body["input"], requests[0]["input"] + continuation)
                    if index == rounds:
                        break
                    output = self.fake.tool_outputs[index]
                    continuation.extend(output)
                    calls = [item for item in output if item["type"] == "function_call"]
                    results = requests[index + 1]["input"][-batch:]
                    self.assertEqual([r["call_id"] for r in results], [c["call_id"] for c in calls])
                    for result, call in zip(results, calls):
                        self.assertEqual(result["type"], "function_call_output")
                        expected = DocumentTools(self.reader.state.document_id,
                            self.chat.snapshot(self.reader.request()), lambda: True)(
                                call["name"], json.loads(call["arguments"]))
                        self.assertEqual(json.loads(result["output"]), expected)
                        continuation.append(result)
                results = [i for i in continuation if i.get("type") == "function_call_output"]
                self.assertEqual([r["call_id"] for r in results], ["call-" + str(i) for i in range(rounds * batch)])
                if rounds == 14:
                    pages = [json.loads(r["output"])["text"] for r in results[1:]]
                    self.assertTrue(all(len(page) == 8000 for page in pages))
                    self.assertGreater(sum(map(len, pages)), 96000)
                    self.assertGreater(sum(len(r["output"]) for r in results), 96000)
                self.assertEqual(before, self.reader.entry.read_bytes())
        self.assertNotIn("fixture-access", (self.work / "private/history.sqlite3").read_bytes().decode(errors="ignore"))
        self.assertEqual(stat.S_IMODE((self.work / "private").stat().st_mode), 0o700)
        self.assertEqual(stat.S_IMODE((self.work / "private/history.sqlite3").stat().st_mode), 0o600)

    def test_timing_report_bounds_stages_and_never_includes_request_contents(self):
        self.fake.tool_rounds = 18
        record = self.open()
        original = self.chat.provider.run
        def run(**options):
            options["measure"]("timing-question-secret")
            options["measure"]("tool-start", "fixture-access")
            yield from original(**options)
        output = io.StringIO()
        with patch.object(self.chat.provider, "run", run), patch("sys.stderr", output):
            self.send(record, "timing-question-secret")
            result = self.wait(record["conversation_id"])
            # Completion is saved before the terminal report and job cleanup.
            deadline = time.monotonic() + 2
            while record["conversation_id"] in self.chat.jobs and time.monotonic() < deadline:
                time.sleep(0.01)
        self.assertEqual(result["status"], "completed")
        line, = output.getvalue().splitlines()
        self.assertTrue(line.startswith("reader-chat-timing "))
        report = json.loads(line.removeprefix("reader-chat-timing "))
        self.assertEqual(set(report), {"schemaVersion", "outcome", "durationMs", "sourceChecks",
                                     "sourceCheckMs", "storageWrites", "storageMs", "events"})
        self.assertEqual(report["outcome"], "completed")
        self.assertGreater(report["sourceChecks"], 0)
        self.assertGreater(report["storageWrites"], 0)
        self.assertEqual(len(report["events"]), 96)
        events = report["events"]
        rounds = [e["round"] for e in events if e["stage"] == "request-start"]
        self.assertIn(9, rounds)
        self.assertEqual(rounds, list(range(1, max(rounds) + 1)))
        self.assertEqual(len([b for path, b in self.fake.requests if path == "/responses"]), 19)
        self.assertEqual([e["atMs"] for e in events], sorted(e["atMs"] for e in events))
        for event in events:
            self.assertEqual(set(event), {"stage", "round", "atMs"})
        for secret in ("timing-question-secret", "fixture-access", "Additional context", "First paragraph",
                       record["conversation_id"], str(self.work)):
            self.assertNotIn(secret, line)
        self.assertNotIn("durationMs", json.dumps(result))
        for path, body in self.fake.requests:
            if path == "/responses":
                self.assertNotIn("timing", json.dumps({key: value for key, value in body.items() if key != "input"}))

    def test_unavailable_timing_log_does_not_keep_a_completed_job(self):
        output = io.StringIO()
        output.close()
        record = self.open()
        with patch("sys.stderr", output):
            self.send(record)
            result = self.wait(record["conversation_id"])
            deadline = time.monotonic() + 2
            while record["conversation_id"] in self.chat.jobs and time.monotonic() < deadline:
                time.sleep(0.01)
        self.assertEqual(result["status"], "completed")
        self.assertNotIn(record["conversation_id"], self.chat.jobs)

    def test_idle_cancellation_polls_do_not_repeat_full_validation_per_poll(self):
        record = self.open()
        def run(**options):
            before = fresh.call_count
            for _ in range(100):
                self.assertFalse(options["cancelled"]())
            self.assertLess(fresh.call_count - before, 10)
            yield {"type": "delta", "text": "Validated answer"}
        with patch.object(self.chat, "fresh", wraps=self.chat.fresh) as fresh, patch.object(self.chat.provider, "run", run):
            self.send(record)
            result = self.wait(record["conversation_id"])
        self.assertEqual(result["status"], "completed")
        self.assertEqual(result["thread"][-1]["text"], "Validated answer")

    def test_recent_idle_validation_cannot_admit_a_delta_after_source_change(self):
        record = self.open()
        sent = threading.Event()
        def run(**options):
            self.assertTrue(sent.wait(2))
            self.assertFalse(options["cancelled"]())
            self.reader.entry.write_text("changed immediately before the next delta")
            yield {"type": "delta", "text": "Must not be stored"}
        with patch.object(self.chat.provider, "run", run):
            self.send(record)
            sent.set()
            deadline = time.monotonic() + 2
            while record["conversation_id"] in self.chat.jobs and time.monotonic() < deadline:
                time.sleep(0.01)
        with self.chat.store.transaction() as db:
            result, = self.chat.store.read(db, self.reader.state.document_id, record["conversation_id"])
        self.assertEqual(result["status"], "interrupted")
        self.assertEqual(result["thread"][-1]["text"], "")

    def test_source_edit_revision_and_close_interrupt_late_idle_upstream(self):
        self.fake.tool_rounds, self.fake.defer_terminal = 9, True
        self.fake.mode = "stall"
        other = self.open("second independent")
        original_source = self.reader.entry.read_text()
        for action in ("source-edit", "revision", "close"):
            with self.subTest(action=action):
                self.reader.entry.write_text(original_source)
                self.reader.publish("fixture-" + action)
                self.fake.requests.clear()
                self.fake.stream_started.clear()
                self.fake.stream_closed.clear()
                record = self.open()
                sent = self.send(record, "Question before interruption")["conversations"][0]
                self.assertTrue(self.fake.stream_started.wait(3))
                job = self.chat.jobs[record["conversation_id"]]
                deadline = time.monotonic() + 2
                while time.monotonic() < deadline:
                    current = next(r for r in self.chat.list(self.reader.request())["conversations"]
                                   if r["conversation_id"] == record["conversation_id"])
                    if current["progress"] == "Thinking…":
                        break
                    time.sleep(0.01)
                self.assertEqual(current["thread"][-1]["text"], "Incomplete ")
                self.chat.mutate(self.reader.request(conversationID=record["conversation_id"],
                    version=sent["version"], draft="New follow-up draft"), "draft")
                if action == "source-edit":
                    self.reader.entry.write_text("changed while upstream is idle")
                elif action == "revision":
                    self.reader.publish("new-revision")
                else:
                    self.chat.close()
                self.assertTrue(self.fake.stream_closed.wait(2))
                job["thread"].join(2)
                self.assertFalse(job["thread"].is_alive())
                self.assertNotIn(record["conversation_id"], self.chat.jobs)
                with self.chat.store.transaction() as db:
                    result, = self.chat.store.read(db, self.reader.state.document_id, record["conversation_id"])
                    untouched, = self.chat.store.read(db, self.reader.state.document_id, other["conversation_id"])
                self.assertEqual(result["status"], "interrupted")
                self.assertEqual(result["draft"], "New follow-up draft")
                self.assertEqual(result["thread"][-2]["text"], "Question before interruption")
                self.assertEqual(result["thread"][-1]["text"], "Incomplete ")
                self.assertEqual(result["thread"][-1]["revision"], "fixture-" + action)
                self.assertEqual(untouched["thread"], [])
                self.assertEqual(len([b for path, b in self.fake.requests if path == "/responses"]), 10)

    def test_reselect_updates_composer_but_preserves_each_questions_original_context(self):
        first = self.open("First paragraph")
        self.send(first, "Explain the first selection")
        self.wait(first["conversation_id"])
        second = self.open("its own question.")
        self.assertEqual(second["conversation_id"], first["conversation_id"])
        self.assertEqual(second["quote"], "its own question.")
        self.assertEqual(second["thread"][0]["context"]["selection"], "First paragraph")
        self.send(second, "Explain the newer selection")
        final = self.wait(second["conversation_id"])
        users = [message for message in final["thread"] if message["role"] == "user"]
        self.assertEqual([m["context"]["selection"] for m in users], ["First paragraph", "its own question."])
        self.assertEqual([m["context"]["revision"] for m in users], ["fixture-r1", "fixture-r1"])
        latest = [body for path, body in self.fake.requests if path == "/responses"][-1]
        current = json.loads(latest["input"][0]["content"].split("\n", 1)[1])
        self.assertEqual(current["selection"], "its own question.")
        model_questions = [json.loads(item["content"]) for item in latest["input"] if item.get("role") == "user"]
        self.assertEqual([m["context"]["selection"] for m in model_questions], ["First paragraph", "its own question."])
        self.assertNotIn("filepath", json.dumps(model_questions))

    def test_reselection_is_rejected_while_a_run_owns_its_context(self):
        from unittest.mock import patch
        entered, release = threading.Event(), threading.Event()
        original = self.chat.provider.run
        def blocked(**kwargs):
            entered.set()
            if not release.wait(5):
                raise AssertionError("Fixture did not release the isolated provider")
            yield from original(**kwargs)
        first = self.open("First paragraph")
        with patch.object(self.chat.provider, "run", blocked):
            self.send(first)
            self.assertTrue(entered.wait(5))
            try:
                with self.assertRaisesRegex(ValueError, "Wait for the current response"):
                    self.open("its own question.")
                current = self.chat.list(self.reader.request())["conversations"][0]
                self.assertEqual(current["quote"], "First paragraph")
                self.assertEqual(current["thread"][0]["context"]["selection"], "First paragraph")
            finally:
                release.set()
            self.assertEqual(self.wait(first["conversation_id"])["status"], "completed")
        self.assertEqual(self.open("its own question.")["quote"], "its own question.")

    def test_completed_send_deduplicates_before_version_check_after_lost_ack(self):
        self.fake.tool_rounds = 9
        first = self.open()
        payload = self.reader.request(conversationID=first["conversation_id"], version=first["version"],
            question="A question with a lost acknowledgment", model="fixture-model", messageID="lost-ack-id")
        self.chat.mutate(payload, "send")
        final = self.wait(first["conversation_id"])
        requests = len(self.fake.requests)
        recovered = self.chat.mutate(payload, "send")["conversations"][0]
        self.assertEqual(recovered["thread"], final["thread"])
        self.assertEqual(len(recovered["thread"]), 2)
        self.assertEqual(len(self.fake.requests), requests)

    def test_failed_interrupted_retry_and_drafts_survive(self):
        self.fake.tool_rounds, self.fake.defer_terminal = 9, True
        self.fake.mode = "disconnect"
        record = self.open()
        self.send(record, "Draft question")
        failed = self.wait(record["conversation_id"])
        self.assertEqual(failed["status"], "failed")
        self.assertEqual(failed["draft"], "Draft question")
        self.assertEqual(failed["thread"][-1]["text"], "Incomplete ")
        self.fake.mode = "success"
        self.send(failed, failed["draft"])
        final = self.wait(record["conversation_id"])
        self.assertEqual(final["status"], "completed")
        self.assertEqual(final["thread"][1]["status"], "failed")
        self.fake.mode = "unsupported-tool"
        self.send(final, "Attempt disallowed tool")
        failed = self.wait(record["conversation_id"])
        self.assertEqual(failed["status"], "failed")
        self.assertIn("unsupported tool", failed["progress"])

    def test_upstream_failures_after_nine_tool_rounds_preserve_partial_and_draft(self):
        self.fake.tool_rounds, self.fake.defer_terminal = 9, True
        original_open = self.chat.provider.open_response
        for mode, error in (("http-failure", "HTTP 401"), ("failed", "Model request failed"),
                            ("incomplete", "Model request failed"), ("disconnect", "before completion"),
                            ("timeout", "connection interrupted")):
            with self.subTest(mode=mode):
                self.fake.mode = mode
                self.fake.tool_text_delta = "Earlier partial " if mode in {"http-failure", "timeout"} else ""
                self.fake.requests.clear()
                def open_response(request, **options):
                    body = json.loads(request.data)
                    if mode == "timeout" and len([i for i in body["input"]
                            if i.get("type") == "function_call_output"]) == 9:
                        raise URLError(TimeoutError("private transport detail"))
                    return original_open(request, **options)
                record = self.open()
                with patch.object(self.chat.provider, "open_response", open_response):
                    self.send(record, "Keep this question")
                    final = self.wait(record["conversation_id"])
                self.assertEqual(final["status"], "failed")
                self.assertIn(error, final["progress"])
                self.assertEqual(final["draft"], "Keep this question")
                self.assertEqual(final["thread"][-2]["text"], "Keep this question")
                self.assertEqual(final["thread"][-1]["text"],
                                 "Earlier partial " if mode in {"http-failure", "timeout"} else "Incomplete ")
                self.assertNotIn("private transport detail", json.dumps(final))
                self.assertEqual(len([b for path, b in self.fake.requests if path == "/responses"]),
                                 9 if mode == "timeout" else 10)

    def test_snapshot_source_service_and_tool_guards(self):
        request = self.reader.request()
        snapshot = self.chat.snapshot(request)
        tools = DocumentTools(self.reader.state.document_id, snapshot, lambda: self.chat.fresh(snapshot))
        args = {"documentID": request["documentID"], "revision": request["revision"], "key": "", "offset": 0, "limit": 2}
        self.assertEqual(len(tools("read_passage", args)["passages"]), 2)
        # Validation still applies after crossing the former call budget.
        for _ in range(26):
            tools("read_passage", args)
        for bad in (None, {**args, "documentID": "other"}, {**args, "revision": "old"}):
            with self.assertRaisesRegex(ValueError, "Document-tool identity mismatch"):
                tools("read_passage", bad)
        key = snapshot.bundle.passages[0]["key"]
        for bad in ({**args, "limit": 21}, {**args, "key": key, "limit": 8001},
                    {**args, "path": "/etc/passwd"}, {k: v for k, v in args.items() if k != "key"},
                    {**args, "key": "unknown"}, {**args, "offset": -1}, {**args, "offset": True},
                    {**args, "offset": 1.5}, {**args, "limit": 0}, {**args, "limit": False}):
            with self.assertRaises(ValueError):
                tools("read_passage", bad)
        query = {k: v for k, v in args.items() if k != "key"} | {"query": "context", "limit": 20}
        self.assertEqual(len(tools("search_current_document", query)["matches"]), 1)
        for bad in ({**query, "query": ""}, {**query, "query": "x" * 161},
                    {**query, "query": 1}, {**query, "limit": 21}, {**query, "path": "secret"}):
            with self.assertRaises(ValueError):
                tools("search_current_document", bad)
        self.assertEqual(tools("read_passage", {**args, "offset": 1000})["passages"], [])
        self.assertEqual(tools("read_passage", {**args, "key": key, "offset": 1000})["text"], "")
        with self.assertRaisesRegex(ValueError, "Unsupported document tool"):
            tools("exec_command", args)
        with self.assertRaises(RevisionChanged): self.chat.list({**request, "service": {"pid": 1}})
        with self.assertRaises(ValueError): self.chat.open(self.reader.request(fragments=[{**self.reader.fragments("First")[0], "exact": "fabricated"}]))
        self.reader.entry.write_text("Drift outside accepted snapshot")
        with self.assertRaises(RevisionChanged): self.chat.open(self.reader.request(fragments=self.reader.fragments("First")))
        with self.assertRaises(RevisionChanged): tools("read_passage", args)

    def test_ambiguous_anchor_does_not_choose_by_dom_key_after_revision(self):
        record = self.open()
        p = self.reader.state.bundle.passages
        candidate = next(part for part in p if part["text"].startswith("First"))
        evidence = record["anchor_evidence"]
        copies = [{"key": "x", "text": "same-before", "section": "s"}, candidate,
                  {"key": "z", "text": "same-after", "section": "s"}]
        from flow_reader.services.paragraph_chat import digest
        evidence.update(before=digest("same-before"), after=digest("same-after"))
        self.assertEqual(attach(record, copies + copies, "new")["reason"], "ambiguous")

    def test_lost_acknowledgment_cannot_run_a_turn_twice_and_cancel_is_durable(self):
        record = self.open()
        payload = self.reader.request(conversationID=record["conversation_id"], version=record["version"],
            question="One request", model="fixture-model", messageID="same-client-message")
        self.chat.mutate(payload, "send")
        duplicate = self.chat.mutate(payload, "send")["conversations"][0]
        self.assertEqual(len(duplicate["thread"]), 2)
        with self.assertRaises(ValueError):
            self.chat.mutate({**payload, "question": "A different request"}, "send")
        self.chat.mutate(self.reader.request(conversationID=record["conversation_id"], version=duplicate["version"]), "cancel")
        cancelled = self.wait(record["conversation_id"])
        self.assertEqual(cancelled["status"], "interrupted")
        self.assertEqual(cancelled["thread"][-1]["status"], "interrupted")
        self.assertEqual(cancelled["draft"], "One request")

    def test_http_origin_identity_stream_and_host_auth_boundary(self):
        server = ThreadingHTTPServer(("127.0.0.1", 0), handler_for(self.reader.state, public_url="https://reader.example"))
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        self.addCleanup(lambda: (server.shutdown(), server.server_close(), thread.join()))
        origin = f"http://127.0.0.1:{server.server_port}"
        def post(action, body, request_origin=origin, host=None):
            headers = {"Content-Type": "application/json"}
            if request_origin: headers["Origin"] = request_origin
            if host: headers["Host"] = host
            return urlopen(Request(origin + "/api/chat/" + action, json.dumps(body).encode(), headers), timeout=10)
        for bad_origin in (None, "https://attacker.invalid"):
            with self.assertRaises(HTTPError) as error: post("open", self.reader.request(fragments=self.reader.fragments("First")), bad_origin)
            self.assertEqual(error.exception.code, 403)
            self.addCleanup(error.exception.close)
        with self.assertRaises(HTTPError) as error:
            post("auth", self.reader.request(operation="login"), "https://reader.example", "reader.example")
        self.assertEqual(error.exception.code, 403)
        self.addCleanup(error.exception.close)
        with post("auth", self.reader.request(operation="status"), "https://reader.example", "reader.example") as response:
            status = json.load(response)
            self.assertTrue(status["signedIn"])
            self.assertNotIn("accounts", status)
            self.assertNotIn("hostCapabilityFile", status)
        with post("auth", self.reader.request(operation="models"), "https://reader.example", "reader.example") as response:
            self.assertEqual(json.load(response)["models"][0]["id"], "fixture-model")
        record = self.open()
        self.send(record)
        with post("events", self.reader.request()) as response:
            frames = response.read().decode()
            self.assertIn("text/event-stream", response.headers["Content-Type"])
            self.assertIn('"status": "completed"', frames)
            self.assertNotIn("fixture-access", frames)

    def serve(self, homepage_url="https://home.example/"):
        server = ThreadingHTTPServer(("127.0.0.1", 0), handler_for(self.reader.state,
            public_url="https://reader.example", homepage_url=homepage_url))
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        self.addCleanup(lambda: (server.shutdown(), server.server_close(), thread.join()))
        return f"http://127.0.0.1:{server.server_port}"

    def test_homepage_config_rejects_unsupported_loopback_and_returns_canonical_url(self):
        from flow_reader.services.homepage import LOOPBACK_HOST
        for configured in ("http://localhost:8769/", "http://[::1]:8769/"):
            with self.assertRaisesRegex(ValueError, "Invalid Homepage origin"):
                handler_for(self.reader.state, homepage_url=configured)
        configured = f"http://{LOOPBACK_HOST}:8769"
        origin = self.serve(homepage_url=configured)
        with urlopen(Request(origin + "/api/chat/auth",
                json.dumps(self.reader.request(operation="status")).encode(),
                {"Origin": origin, "Content-Type": "application/json"})) as response:
            self.assertEqual(json.load(response)["homepageURL"], configured + "/")

    def test_host_allowlist_blocks_rebinding_for_state_list_and_send(self):
        origin = self.serve()
        for host in ("attacker.invalid", "127.0.0.1:1", "localhost", "reader.example.attacker.invalid"):
            for action in ("state", "chat/list", "chat/send"):
                with self.subTest(host=host, action=action):
                    body = None if action == "state" else json.dumps(self.reader.request()).encode()
                    request = Request(origin + "/api/" + action, body,
                        {"Host": host, "Origin": "http://" + host, "Content-Type": "application/json"})
                    with self.assertRaises(HTTPError) as error:
                        urlopen(request)
                    self.assertEqual(error.exception.code, 421)
                    self.addCleanup(error.exception.close)
        for host in (urlsplit(origin).netloc, "localhost:" + str(urlsplit(origin).port), "reader.example"):
            with urlopen(Request(origin + "/api/state", headers={"Host": host})) as response:
                self.assertEqual(response.status, 200)

    def test_document_account_is_read_only_and_links_to_homepage(self):
        origin = self.serve()
        with urlopen(Request(origin + "/api/chat/auth",
                json.dumps(self.reader.request(operation="status")).encode(),
                {"Origin": origin, "Content-Type": "application/json"})) as response:
            status = json.load(response)
        self.assertEqual(status["homepageURL"], "https://home.example/")
        self.assertNotIn("accounts", status)
        for operation in ("login", "logout", "cancel"):
            method = "close" if operation == "cancel" else operation
            with patch.object(self.chat.auth, method) as action:
                with self.assertRaises(HTTPError) as error:
                    urlopen(Request(origin + "/api/chat/auth",
                        json.dumps(self.reader.request(operation=operation)).encode(),
                        {"Origin": origin, "Content-Type": "application/json", "X-Reader-Host-Capability": "anything"}))
                self.assertEqual(error.exception.code, 403)
                error.exception.close()
                action.assert_not_called()

    def test_invalid_request_does_not_echo_exception_secrets(self):
        origin = self.serve()
        with patch.object(self.chat, "list", side_effect=ValueError("secret-value")):
            with self.assertRaises(HTTPError) as error:
                urlopen(Request(origin + "/api/chat/list", json.dumps(self.reader.request()).encode(),
                    {"Origin": origin, "Content-Type": "application/json"}))
            self.assertEqual(error.exception.code, 400)
            self.addCleanup(error.exception.close)
            self.assertEqual(json.load(error.exception), {"error": "Invalid reader request"})

    def test_sse_client_cancel_closes_stalled_upstream_and_releases_host_job(self):
        self.fake.tool_rounds, self.fake.defer_terminal = 9, True
        origin = self.serve()
        self.fake.mode = "stall"
        record = self.open()
        sent = self.send(record)["conversations"][0]
        self.assertTrue(self.fake.stream_started.wait(3))
        deadline = time.monotonic() + 2
        while time.monotonic() < deadline:
            current = self.chat.list(self.reader.request())["conversations"][0]
            if current["thread"][-1]["text"] == "Incomplete ":
                break
            time.sleep(0.01)
        self.assertEqual(current["thread"][-1]["text"], "Incomplete ")
        job = self.chat.jobs[record["conversation_id"]]
        with urlopen(Request(origin + "/api/chat/cancel",
                json.dumps(self.reader.request(conversationID=record["conversation_id"], version=sent["version"])).encode(),
                {"Origin": origin, "Content-Type": "application/json"})) as response:
            self.assertEqual(response.status, 200)
        self.assertTrue(self.fake.stream_closed.wait(2), "Upstream SSE socket was not released")
        job["thread"].join(2)
        self.assertFalse(job["thread"].is_alive(), "Cancelled provider kept waiting for upstream bytes")
        final = self.wait(record["conversation_id"])
        self.assertEqual(final["status"], "interrupted")
        self.assertEqual(final["draft"], "Explain this")
        self.assertEqual(final["thread"][-1]["text"], "Incomplete ")
        self.assertEqual(len([b for path, b in self.fake.requests if path == "/responses"]), 10)


class ChatAuthTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="reader-oauth-test-")
        self.addCleanup(temporary.cleanup)
        self.directory = Path(temporary.name) / "credentials"
        self.fake = FakeOpenAI()
        self.addCleanup(self.fake.close)
        self.auth = self.fake.auth(self.directory)
        self.addCleanup(lambda: self.auth.close())

    def login(self):
        url = self.auth.login()["authUrl"]
        params = {k: v[0] for k, v in parse_qs(urlsplit(url).query).items()}
        self.fake.nonce = params["nonce"]
        callback = params["redirect_uri"] + "?" + urlencode({"state": params["state"], "code": "fixture-code", "client_id": "oaiapp_fixture"})
        return params, callback

    def test_pkce_loopback_signature_validation_refresh_serialization_and_revocation(self):
        params, callback = self.login()
        with urlopen(callback) as response: self.assertEqual(response.status, 200)
        self.assertTrue(self.auth.status()["planEnabled"])
        self.assertEqual(params["client_id"], "dynamic_agent_client")
        exchange = self.fake.requests[0][1]
        import base64, hashlib
        challenge = base64.urlsafe_b64encode(hashlib.sha256(exchange["code_verifier"].encode()).digest()).decode().rstrip("=")
        self.assertEqual(challenge, params["code_challenge"])
        self.assertEqual(exchange["redirect_uri"], params["redirect_uri"])
        self.assertEqual(exchange["client_id"], "oaiapp_fixture")
        self.assertEqual(stat.S_IMODE(self.auth.path.stat().st_mode), 0o600)
        self.assertNotIn("fixture-access", json.dumps(self.auth.status()))
        data = read_json(self.auth.path, {})
        data["registrations"]["oaiapp_fixture"]["expires_at"] = 0
        write_json(self.auth.path, data)
        other = self.fake.auth(self.directory)
        with concurrent.futures.ThreadPoolExecutor(2) as pool:
            self.assertEqual(list(pool.map(lambda auth: auth.access_token(), (self.auth, other))), ["fixture-access"] * 2)
        self.assertEqual(self.fake.refreshes, 1)
        self.assertTrue(self.auth.logout()["revocationConfirmed"])
        self.assertEqual(self.fake.revocations, 1)
        self.assertFalse(self.auth.status()["signedIn"])
        data = read_json(self.auth.path, {})
        self.assertNotIn("refresh_token", data["registrations"]["oaiapp_fixture"])
        self.assertEqual(data["hostID"], read_json(self.auth.path, {})["hostID"])

    def test_bad_state_invalid_identity_and_jwt_signature_do_not_save_tokens(self):
        params, callback = self.login()
        with self.assertRaises(HTTPError) as error: urlopen(callback.replace(params["state"], "bad-state"))
        self.addCleanup(error.exception.close)
        self.assertEqual(self.fake.requests, [])
        self.fake.nonce = "wrong-nonce"
        with self.assertRaises(HTTPError) as error: urlopen(callback)
        self.addCleanup(error.exception.close)
        self.assertFalse(self.auth.status()["signedIn"])
        token = self.fake.tokens()["id_token"]
        chunks = token.split(".")
        chunks[1] = chunks[1][:-2] + "AA"
        with self.assertRaises(ChatProviderError): verify_identity(".".join(chunks), [self.fake.keys["public"]])

    def test_terminal_refresh_failure_clears_tokens_and_revocation_failure_is_honest(self):
        self.auth = self.fake.auth(self.directory, signed_in=True)
        data = read_json(self.auth.path, {})
        data["registrations"]["oaiapp_fixture"]["expires_at"] = 0
        write_json(self.auth.path, data)
        self.fake.mode = "revoked"
        with self.assertRaises(ChatProviderError): self.auth.access_token()
        self.assertFalse(self.auth.status()["signedIn"])

        self.fake.mode = "success"
        self.auth = self.fake.auth(self.directory, signed_in=True)
        self.fake.mode = "revoke-failure"
        self.assertFalse(self.auth.logout()["revocationConfirmed"])
        self.assertIn("not confirmed", self.auth.status()["notice"])
        self.assertFalse(self.auth.status()["signedIn"])

    def test_refresh_retains_missing_or_empty_refresh_token_updates_expiry_and_drops_id_token(self):
        for replacement in (None, "", "omitted"):
            with self.subTest(replacement=replacement):
                self.auth = self.fake.auth(self.directory, signed_in=True)
                data = read_json(self.auth.path, {})
                record = data["registrations"]["oaiapp_fixture"]
                previous = record["refresh_token"]
                record.update(expires_at=0, id_token="old-id-token")
                write_json(self.auth.path, data)
                original = self.auth.request
                def request(url, fields=None, **kwargs):
                    tokens = original(url, fields, **kwargs)
                    if fields and fields.get("grant_type") == "refresh_token":
                        tokens.pop("refresh_token")
                        if replacement != "omitted":
                            tokens["refresh_token"] = replacement
                        tokens.update(expires_in=120, id_token="unverified-refreshed-id-token")
                    return tokens
                before = time.time()
                with patch.object(self.auth, "request", request):
                    self.assertEqual(self.auth.access_token(), "fixture-access")
                    refreshes = self.fake.refreshes
                    self.assertEqual(self.auth.access_token(), "fixture-access")
                    self.assertEqual(self.fake.refreshes, refreshes)
                saved = read_json(self.auth.path, {})["registrations"]["oaiapp_fixture"]
                self.assertEqual(saved["refresh_token"], previous)
                self.assertGreaterEqual(saved["expires_at"], before + 120)
                self.assertLessEqual(saved["expires_at"], time.time() + 120)
                self.assertNotIn("id_token", saved)
                for expiry in (0, -1, None):
                    tokens = {"access_token": "new", "token_type": "Bearer", "expires_in": expiry}
                    with self.assertRaises(ChatProviderError):
                        self.auth.update_tokens(saved, tokens)
                    self.assertEqual(saved["access_token"], "fixture-access")

    def test_callback_exchange_and_verification_release_state_lock_and_cancel_invalidates_result(self):
        for stage in ("request", "verify"):
            with self.subTest(stage=stage):
                entered, release = threading.Event(), threading.Event()
                _params, callback = self.login()
                original = getattr(self.auth, stage)
                def blocked(*args, **kwargs):
                    if stage == "verify" or args[0].endswith("/token"):
                        entered.set()
                        if not release.wait(5):
                            raise AssertionError("Callback fixture was not released")
                    return original(*args, **kwargs)
                with patch.object(self.auth, stage, blocked), concurrent.futures.ThreadPoolExecutor(3) as pool:
                    result = pool.submit(urlopen, callback)
                    try:
                        self.assertTrue(entered.wait(3))
                        self.assertFalse(pool.submit(self.auth.status).result(timeout=1)["signedIn"])
                        pool.submit(self.auth.close).result(timeout=1)
                    finally:
                        release.set()
                    with self.assertRaises(HTTPError) as error:
                        result.result(timeout=3)
                    self.assertEqual(error.exception.code, 400)
                    self.addCleanup(error.exception.close)
                self.assertFalse(self.auth.status()["signedIn"])

    def test_expired_oauth_attempt_does_not_exchange_or_save_credentials(self):
        _params, callback = self.login()
        self.auth.pending["expires"] = time.monotonic() - 1
        with self.assertRaises(HTTPError) as error:
            urlopen(callback)
        self.assertEqual(error.exception.code, 400)
        self.addCleanup(error.exception.close)
        self.assertEqual(self.fake.requests, [])
        self.assertFalse(self.auth.status()["signedIn"])


if __name__ == "__main__":
    unittest.main()
