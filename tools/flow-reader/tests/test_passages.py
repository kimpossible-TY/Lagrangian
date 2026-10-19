"""Saved quotations survive edits and section changes, with explicit uncertainty."""

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
from flow_reader.document.passages import locate_passages
from flow_reader.document.sections import split_document
from flow_reader.server.state import ReaderState
from flow_reader.server.http import handler_for


class PassageTests(unittest.TestCase):
    def test_quotes_relocate_after_paragraph_edit_and_section_move(self):
        original = '<html><body><h2>Topic</h2><p>First. A saved quotation. Last.</p></body></html>'
        before = split_document(original, "before", max_blocks=2)
        key = before.passages[-1]["key"]
        changed = original.replace('<p>First.', '<p>New content.</p><p>Another paragraph.</p><p>Edited first.')
        after = split_document(changed, "after", max_blocks=2)
        result = locate_passages(after.passages, [{"key": key, "exact": "A saved quotation.",
                                                  "prefix": "First.", "suffix": "Last."}])[0]
        self.assertEqual(result["state"], "located")
        self.assertNotEqual(result["key"], key)
        self.assertNotEqual(result["section"], before.passages[-1]["section"])
        self.assertIn(b"A saved quotation.", after.documents[result["section"]])

    def test_duplicate_quotes_require_context_and_removed_quotes_are_retained_as_missing(self):
        bundle = split_document('<html><body><p>Left. Same quote. End.</p><p>Right. Same quote. End.</p></body></html>', "rev")
        fragments = [{"key": "old", "exact": "Same quote."},
                     {"key": "old", "exact": "Same quote.", "prefix": "Right."},
                     {"exact": "No longer present."}]
        found = locate_passages(bundle.passages, fragments)
        self.assertEqual(found[0], {"state": "ambiguous"})
        self.assertEqual(found[1]["key"], bundle.passages[1]["key"])
        self.assertEqual(found[2], {"state": "missing"})
        # A few coincidentally matching letters are not reliable context.
        self.assertEqual(locate_passages(bundle.passages, [{"exact": "Same quote.",
                                                          "prefix": "Completely different."}]),
                         [{"state": "ambiguous"}])

    def test_repeated_quote_within_math_block_and_text_entities(self):
        bundle = split_document('''<html><body><div class="flow-equation" id="eq">
<math><mi>𝑥</mi><mo>+</mo><mi>𝑥</mi><mtext><span data-flow-targets='[]'>hidden annotation</span></mtext></math>
</div><p>A &amp; B <em>with\n  whitespace</em></p></body></html>''', "rev")
        self.assertEqual(bundle.passages[0]["text"], "𝑥+𝑥")
        self.assertEqual(bundle.passages[1]["text"], "A & B with whitespace")
        found = locate_passages(bundle.passages, [{"key": bundle.passages[0]["key"], "exact": "𝑥", "prefix": "𝑥+"}])[0]
        self.assertEqual(found["occurrence"], 1)

    def test_locate_endpoint_uses_accepted_snapshot_and_rejects_stale_or_invalid_requests(self):
        with tempfile.TemporaryDirectory() as temporary:
            work = Path(temporary)
            (work / "main.typ").write_text("Fixture")
            state = ReaderState(Project(work, Path("main.typ"), work), work, "https://example.test/paged", False)
            state.revision = "accepted"
            state.bundle = split_document('<html><body><p>Accepted quotation.</p></body></html>', state.revision)
            state.report = {"exitCode": 1, "contentGatePassed": False}
            server = ThreadingHTTPServer(("127.0.0.1", 0), handler_for(state))
            worker = threading.Thread(target=server.serve_forever, daemon=True)
            worker.start()
            endpoint = f"http://127.0.0.1:{server.server_port}/api/locate"
            def request(payload):
                return Request(endpoint, json.dumps(payload).encode(), {"Content-Type": "application/json"})
            try:
                with urlopen(request({"revision": "accepted", "fragments": [{"exact": "Accepted quotation."}]})) as response:
                    result = json.load(response)
                self.assertEqual(result["revision"], "accepted")
                self.assertEqual(result["locations"][0]["state"], "located")
                for revision, fragments, status in (("old", [{"exact": "quote"}], 409),
                                                     ("accepted", [{"exact": ""}], 400),
                                                     ("accepted", [{}] * 33, 400)):
                    with self.assertRaises(HTTPError) as caught:
                        urlopen(request({"revision": revision, "fragments": fragments}))
                    self.assertEqual(caught.exception.code, status)
                    caught.exception.close()
            finally:
                server.shutdown()
                server.server_close()
                worker.join()


if __name__ == "__main__":
    unittest.main()
