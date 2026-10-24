"""Lease ownership, reassignment and HTTP execution preserve server authority."""
import base64
from concurrent.futures import ThreadPoolExecutor
from http.server import ThreadingHTTPServer
import json
from pathlib import Path
import sys
import tempfile
import threading
from types import SimpleNamespace
import unittest
from urllib.error import HTTPError
from urllib.request import Request, urlopen

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from flow_reader.compiler.execution import CompileRequest, CompileResult
from flow_reader.compiler.diagnostics import CompilerDiagnostics
from flow_reader.compiler.pool import BrowserCompilePool
from flow_reader.compiler.project import Project
from flow_reader.compiler.snapshot import capture_snapshot
from flow_reader.server.http import handler_for


class PoolTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        self.entry = self.root / "main.typ"
        self.entry.write_text("Original")
        packages = self.root / "packages"
        packages.mkdir()
        self.project = Project(self.root, Path("main.typ"), packages)
        self.request = CompileRequest("typst", self.root, packages, "html", entry=self.entry,
                                      system_fonts=False, timestamp=1760000000)
        self.native = []
        def fallback(request):
            self.native.append(request)
            return CompileResult(0, "", b"native", (), 0)
        self.now = 10.0
        self.pool = BrowserCompilePool(self.project, lambda: [self.entry], "engine",
                                      clock=lambda: self.now, heartbeat_timeout=3, fallback=fallback)
        self.threads = ThreadPoolExecutor(max_workers=2)
        self.addCleanup(self.threads.shutdown)
        self.addCleanup(self.pool.close)
        self.snapshot = capture_snapshot(self.request, self.project, [self.entry], "engine")

    def worker(self):
        return self.pool.register("engine")["worker"]

    def start(self, call=None):
        future = self.threads.submit(call or (lambda: self.pool.execute(self.snapshot, 30)))
        with self.pool.condition:
            self.assertTrue(self.pool.condition.wait_for(lambda: bool(self.pool.jobs), 2))
        return future

    def result(self, worker, task, **overrides):
        payload = {"identity": self.snapshot.identity, "returncode": 0, "stderr": "",
                   "artifact": base64.b64encode(b"browser").decode(),
                   "dependencies": ["/workspace/main.typ"]} | overrides
        return self.pool.submit(worker, task["job"], task["lease"], payload)

    def test_exact_lease_delivers_once_and_keeps_captured_dependencies(self):
        worker = self.worker()
        future = self.start()
        task = self.pool.poll(worker)
        self.assertIsNone(self.pool.poll(worker))
        self.assertFalse(self.pool.submit(worker, task["job"], "wrong", {})["accepted"])
        self.entry.write_text("Concurrent edit")
        self.assertEqual(base64.b64decode(task["snapshot"]["files"][0]["data"]), b"Original")
        self.assertTrue(self.result(worker, task)["accepted"])
        self.assertFalse(self.result(worker, task)["accepted"])
        result = future.result(2)
        self.assertEqual(result.artifact, b"browser")
        self.assertEqual(result.dependencies, (str(self.entry),))
        self.assertEqual(self.pool.completed, 1)

    def test_lost_heartbeat_reassigns_same_snapshot_and_rejects_old_lease(self):
        first, second = self.worker(), self.worker()
        future = self.start()
        old = self.pool.poll(first)
        self.now += 2
        self.pool.heartbeat(second)
        self.now += 2
        new = self.pool.poll(second)
        self.assertEqual(old["job"], new["job"])
        self.assertEqual(old["snapshot"], new["snapshot"])
        self.assertNotEqual(old["lease"], new["lease"])
        self.assertFalse(self.result(first, old)["accepted"])
        self.assertTrue(self.result(second, new)["accepted"])
        self.assertEqual(future.result(2).artifact, b"browser")

    def test_release_reassigns_to_remaining_worker(self):
        first, second = self.worker(), self.worker()
        future = self.start()
        old = self.pool.poll(first)
        self.pool.release(first)
        new = self.pool.poll(second)
        self.assertFalse(self.result(first, old)["accepted"])
        self.result(second, new)
        self.assertEqual(future.result(2).artifact, b"browser")

    def test_deadline_discards_result_even_if_worker_still_heartbeats(self):
        worker = self.worker()
        future = self.start()
        task = self.pool.poll(worker)
        with self.pool.condition:
            self.now += 31
            self.pool.condition.notify_all()
        self.assertIsNone(future.result(2))
        self.assertFalse(self.result(worker, task)["accepted"])

    def test_malformed_failed_and_new_dependency_results_trigger_native_fallback(self):
        for override in ({"identity": "other"}, {"returncode": 1}, {"artifact": "!"},
                         {"dependencies": ["/workspace/new.typ"]}):
            with self.subTest(override=override):
                worker = self.worker()
                future = self.start(lambda: self.pool(self.request))
                task = self.pool.poll(worker)
                self.assertFalse(self.result(worker, task, **override)["accepted"])
                self.assertEqual(future.result(2).artifact, b"native")
                self.pool.release(worker)
        self.assertEqual(len(self.native), 4)
        self.assertTrue(all(not request.system_fonts for request in self.native))

    def test_no_workers_uses_native_without_wait_and_close_cancels_without_fallback(self):
        self.assertEqual(self.pool(self.request).artifact, b"native")
        self.worker()
        future = self.start(lambda: self.pool(self.request))
        self.pool.close()
        with self.assertRaises(OSError):
            future.result(2)
        self.assertEqual(len(self.native), 1)

    def test_last_worker_release_falls_back_and_unknown_inputs_are_not_lazy_loaded(self):
        worker = self.worker()
        future = self.start(lambda: self.pool(self.request))
        self.pool.release(worker)
        self.assertEqual(future.result(2).artifact, b"native")
        self.worker()
        self.pool.dependencies = lambda: [self.root.parent / "outside.typ"]
        self.assertEqual(self.pool(self.request).artifact, b"native")
        self.assertFalse(self.pool.jobs)

    def test_engine_and_capacity_are_bounded(self):
        with self.assertRaises(ValueError):
            self.pool.register("different")
        for _ in range(4):
            self.worker()
        with self.assertRaises(ValueError):
            self.worker()

    def test_pinned_check_cannot_reassign_or_fall_back(self):
        first, second = self.worker(), self.worker()
        future = self.start(lambda: self.pool.execute(self.snapshot, 30, worker=first, purpose="test-quick"))
        self.assertIsNone(self.pool.poll(second))
        task = self.pool.poll(first)
        self.pool.release(first)
        self.assertIsNone(future.result(2))
        self.assertFalse(self.result(first, task)["accepted"])
        self.assertEqual(self.native, [])
        self.assertEqual(self.pool.status()["history"][0]["status"], "disconnected")

    def test_status_has_bounded_history_and_no_worker_credentials(self):
        worker = self.pool.register("engine", "My iPhone")["worker"]
        future = self.start()
        task = self.pool.poll(worker)
        self.result(worker, task)
        future.result(2)
        status = self.pool.status()
        self.assertEqual(status["history"][0]["device"]["name"], "My iPhone")
        self.assertNotIn(worker, json.dumps(status))
        self.assertNotIn(task["lease"], json.dumps(status))
        for _ in range(100):
            self.pool.record(status="test")
        self.assertEqual(len(self.pool.status()["history"]), 64)

    def test_diagnostic_requires_matching_output_and_preserves_publication(self):
        for matching in (True, False):
            with self.subTest(matching=matching):
                worker = self.worker()
                state = SimpleNamespace(compiler_pool=self.pool, project=self.project,
                                        lock=threading.RLock(), accepted_dependencies=set(),
                                        revision="unchanged", source_stamp=None, compiling=False)
                reference = b"browser" if matching else b"different"
                diagnostic = CompilerDiagnostics(state, reference=lambda snapshot, compiler:
                                                  CompileResult(0, "", reference, (), 0))
                identifier = diagnostic.start(worker, "quick")["id"]
                with self.pool.condition:
                    self.assertTrue(self.pool.condition.wait_for(lambda: bool(self.pool.jobs), 2))
                with self.assertRaisesRegex(ValueError, "test-already-running"):
                    diagnostic.start(worker, "quick")
                task = self.pool.poll(worker)
                self.result(worker, task, identity=task["snapshot"]["identity"], dependencies=[])
                self.assertTrue(diagnostic.lock.acquire(timeout=2))
                diagnostic.lock.release()
                event = next(item for item in self.pool.status()["history"] if item["id"] == identifier)
                self.assertEqual(event["status"], "passed" if matching else "failed")
                if not matching:
                    self.assertEqual(event["reason"], "output-mismatch")
                self.assertEqual(state.revision, "unchanged")
                self.assertEqual(self.native, [])
                self.pool.release(worker)

    def test_http_registration_task_delivery_and_result_guards(self):
        state = SimpleNamespace(compiler_pool=self.pool, compiler_assets=None)
        server = ThreadingHTTPServer(("127.0.0.1", 0), handler_for(state))
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        def stop():
            server.shutdown()
            server.server_close()
            thread.join()
        self.addCleanup(stop)
        origin = f"http://127.0.0.1:{server.server_port}"
        def post(action, body, origin_header=origin):
            request = Request(origin + "/api/compiler/" + action, json.dumps(body).encode(),
                              {"Content-Type": "application/json", "Origin": origin_header})
            with urlopen(request, timeout=5) as response:
                return json.load(response)
        with self.assertRaises(HTTPError) as error:
            post("register", {"engine": "engine"}, "https://elsewhere.invalid")
        self.assertEqual(error.exception.code, 403)
        error.exception.close()
        worker = post("register", {"engine": "engine"})["worker"]
        future = self.start()
        task = post("poll", {"worker": worker})["task"]
        result = {"identity": task["snapshot"]["identity"], "returncode": 0, "stderr": "",
                  "artifact": base64.b64encode(b"HTTP browser").decode(), "dependencies": []}
        body = {"worker": worker, "job": task["job"], "lease": task["lease"], "result": result}
        self.assertTrue(post("result", body)["accepted"])
        self.assertEqual(future.result(2).artifact, b"HTTP browser")
        self.assertFalse(post("result", body)["accepted"])
        post("release", {"worker": worker})
        with self.assertRaises(HTTPError) as error:
            post("heartbeat", {"worker": worker})
        self.assertEqual(error.exception.code, 400)
        error.exception.close()


if __name__ == "__main__":
    unittest.main()
