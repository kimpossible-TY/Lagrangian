"""Exercise reader serving across an actual successful and failed compilation."""

from http.server import ThreadingHTTPServer
import json
import os
from pathlib import Path
import shutil
import sys
import tempfile
import threading
import unittest
from urllib.error import HTTPError
from urllib.request import urlopen

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from build import Project
from serve import ReaderState, handler_for


class ReaderServingTests(unittest.TestCase):
    def test_compile_failure_keeps_the_previous_document_available(self):
        compiler = os.environ.get("FLOW_READER_TYPST") or shutil.which("typst")
        packages = os.environ.get("FLOW_READER_PACKAGES")
        if not compiler or not packages:
            self.skipTest("Set FLOW_READER_PACKAGES and optionally FLOW_READER_TYPST")
        with tempfile.TemporaryDirectory() as temporary:
            work = Path(temporary)
            source = work / "source"
            source.mkdir()
            shutil.copyfile(ROOT / "tests/fixtures/main.typ", source / "main.typ")
            project = Project(source, Path("main.typ"), Path(packages), compiler=compiler)
            state = ReaderState(project, work / "output", "https://example.test/paged/", False)
            state.compile()
            self.assertEqual(state.report["exitCode"], 0, state.report)
            self.assertTrue(state.report["contentGatePassed"], state.report)
            revision = state.revision
            server = ThreadingHTTPServer(("127.0.0.1", 0), handler_for(state))
            worker = threading.Thread(target=server.serve_forever, daemon=True)
            worker.start()
            base = f"http://127.0.0.1:{server.server_port}"
            try:
                original = urlopen(base + "/document.html").read()
                (source / "main.typ").write_text("#this-function-does-not-exist()")
                state.compile()
                public = json.load(urlopen(base + "/api/state"))
                self.assertEqual(public["exitCode"], 1)
                self.assertEqual(public["revision"], revision)
                self.assertEqual(urlopen(base + "/document.html").read(), original)
                self.assertTrue(json.load(urlopen(base + "/health"))["ready"])
                with self.assertRaises(HTTPError) as stale:
                    urlopen(base + "/document.html?revision=outdated")
                self.assertEqual(stale.exception.code, 409)
                stale.exception.close()
            finally:
                server.shutdown()
                server.server_close()
                worker.join()


if __name__ == "__main__":
    unittest.main()
