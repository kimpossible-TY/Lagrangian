"""Keep browser audit evidence inside an explicitly owned disposable fixture."""

from http.server import ThreadingHTTPServer
import json
from pathlib import Path
import sys
import tempfile
import threading
import unittest
from urllib.error import HTTPError
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from flow_reader.compiler.build import Project
from flow_reader.server.state import ReaderState
from runtime_fixture import handler_for


class BrowserReportTests(unittest.TestCase):
    def setUp(self):
        directory = ROOT.parents[1] / "dist"
        directory.mkdir(exist_ok=True)
        self.temporary = tempfile.TemporaryDirectory(dir=directory)
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        source = self.root / "source"
        source.mkdir()
        (source / "main.typ").write_text("The original fixture source")
        output = self.root / "output"
        output.mkdir()
        self.state = ReaderState(Project(source, Path("main.typ"), ROOT / "packages"),
                                 output, "https://example.test/paged/", False)
        self.state.revision = "a" * 64
        self.server = ThreadingHTTPServer(("127.0.0.1", 0), handler_for(self.state))
        self.worker = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.worker.start()
        self.addCleanup(self.stop)
        self.origin = f"http://127.0.0.1:{self.server.server_port}"

    def stop(self):
        self.server.shutdown()
        self.server.server_close()
        self.worker.join()

    def payload(self, sequence=1, status="progress"):
        return {"run": "run-1", "kind": "body-math", "sequence": sequence,
                "state": status, "report": {"revision": self.state.revision,
                "width": 320, "checks": 12, "errors": []}}

    def post(self, payload, origin=None):
        request = Request(self.origin + "/api/test-report", json.dumps(payload).encode(),
                          {"Content-Type": "application/json", "Origin": origin or self.origin})
        return json.load(urlopen(request))

    def test_completed_evidence_survives_observation_and_late_progress_cannot_replace_it(self):
        self.assertTrue(self.post(self.payload())["saved"])
        self.assertTrue(self.post(self.payload(2, "ready"))["saved"])
        self.assertFalse(self.post(self.payload())["saved"])
        record = json.loads((self.state.output / "browser-audits/body-math-run-1.json").read_text())
        self.assertEqual(record["state"], "ready")
        self.assertEqual(record["sequence"], 2)
        self.assertEqual(record["origin"], self.origin)
        self.assertEqual(record["report"]["checks"], 12)
        with urlopen(self.origin + "/test-report.js") as response:
            self.assertIn("javascript", response.headers["Content-Type"])
            self.assertIn(b"MutationObserver", response.read())

    def test_unrelated_origins_revisions_and_paths_cannot_supply_evidence(self):
        for field, value, status in (("run", "../main.typ", 400),
                                     ("sequence", True, 400),
                                     ("kind", "../../main.typ", 400)):
            payload = self.payload()
            payload[field] = value
            with self.subTest(field=field), self.assertRaises(HTTPError) as error:
                self.post(payload)
            self.assertEqual(error.exception.code, status)
            error.exception.close()
        with self.assertRaises(HTTPError) as error:
            self.post(self.payload(), "https://unrelated.test")
        self.assertEqual(error.exception.code, 403)
        error.exception.close()
        payload = self.payload()
        payload["report"]["revision"] = "b" * 64
        with self.assertRaises(HTTPError) as error:
            self.post(payload)
        self.assertEqual(error.exception.code, 400)
        error.exception.close()
        self.assertFalse((self.state.output / "browser-audits").exists())
        self.assertEqual((self.state.project.root / "main.typ").read_text(), "The original fixture source")

    def test_reporting_is_not_enabled_for_a_non_owned_project(self):
        with tempfile.TemporaryDirectory() as unrelated:
            self.state.project = Project(Path(unrelated), Path("main.typ"), ROOT / "packages")
            with self.assertRaises(HTTPError) as error:
                self.post(self.payload())
            self.assertEqual(error.exception.code, 403)
            error.exception.close()
        self.assertFalse((self.state.output / "browser-audits").exists())


if __name__ == "__main__":
    unittest.main()
