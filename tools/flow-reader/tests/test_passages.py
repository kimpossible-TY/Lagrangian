"""Saved quotations survive edits and section changes, with explicit uncertainty."""

from http.server import ThreadingHTTPServer
import json
import re
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
from flow_reader.compiler.source_map import CarrierPassages, SourceCarriers
from flow_reader.document.passages import PassageIndex, locate_passages
from flow_reader.document.sections import split_document
from flow_reader.server.state import ReaderState
from flow_reader.server.http import handler_for
from flow_reader.services.source_highlight import MarkedPassages, MAX_SELECTION_SEGMENTS


class PassageTests(unittest.TestCase):
    def test_browser_and_service_selection_segment_cap_match(self):
        controller = (ROOT / 'web/features/selection/controller.js').read_text()
        match = re.search(r'const MAX_SELECTION_SEGMENTS = (\d+);', controller)
        self.assertIsNotNone(match, 'browser selection cap declaration missing')
        self.assertEqual(int(match[1]), MAX_SELECTION_SEGMENTS)

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

    def test_equation_number_guards_shared_across_passage_index_carrier_and_marked_parsers(self):
        class RecordingPassageIndex(PassageIndex):
            def __init__(self, source, block_sections):
                self.trace = []
                super().__init__(source, block_sections)

            def handle_data(self, data):
                if data.strip():
                    self.trace.append((data, self.in_equation_number))
                super().handle_data(data)

        carriers = SourceCarriers()
        carriers.ranges = {
            "0": {"path": "main.typ", "source_hash": "0" * 64, "start": 0, "end": 5, "kind": "math"},
            "1": {"path": "main.typ", "source_hash": "0" * 64, "start": 6, "end": 12, "kind": "text"},
        }
        token = "edit-token"
        c_start = f'<span {carriers.attribute}="0" data-flow-source-edge="start"></span>'
        c_end = f'<span {carriers.attribute}="0" data-flow-source-edge="end"></span>'
        t_start = f'<span {carriers.attribute}="1" data-flow-source-edge="start"></span>'
        t_end = f'<span {carriers.attribute}="1" data-flow-source-edge="end"></span>'
        m_start = f'<span data-flow-source-edit="{token}" data-flow-source-edit-edge="start"></span>'
        m_end = f'<span data-flow-source-edit="{token}" data-flow-source-edit-edge="end"></span>'

        def build_html(start_tag, end_tag):
            return (
                '<html><body>'
                '<div class="flow-equation" data-reader-key="normal">'
                f'{start_tag}<math>u=0</math>'
                '<div class="flow-equation-number">(1)</div>'
                f'{end_tag}</div>'
                '<div class="flow-equation" data-reader-key="nested">'
                f'{start_tag}<math>v=1</math>'
                '<div class="flow-equation-number">(<span class="flow-equation-number">2</span>.3)</div>'
                f'{end_tag}</div>'
                '<div class="flow-equation" data-reader-key="excluded">'
                f'{start_tag}<nav><span class="flow-equation-number">nav</span></nav>'
                '<svg><span class="flow-equation-number">svg</span></svg>'
                '<math>w=2</math>'
                '<div class="flow-equation-number">(4)</div>'
                f'{end_tag}</div>'
                '</body></html>'
            )

        blocks = {"normal": "section-0", "nested": "section-0", "excluded": "section-0"}
        plain_html = build_html("", "")
        carried_html = build_html(c_start, c_end)
        marked_html = build_html(m_start, m_end)

        plain = RecordingPassageIndex(plain_html, blocks)
        with self.assertRaises(AttributeError):
            plain.in_equation_number = True
        self.assertFalse(plain.in_equation_number)
        self.assertEqual(plain.trace, [
            ("u=0", False), ("(1)", True),
            ("v=1", False), ("(", True), ("2", True), (".3)", True),
            ("nav", False), ("svg", False), ("w=2", False), ("(4)", True),
        ])

        plain_by_key = {p["key"]: p for p in plain.passages}
        self.assertEqual(plain_by_key["normal"]["text"], "u=0(1)")
        self.assertEqual(plain_by_key["normal"]["equation_number_ranges"], [(3, 6)])
        self.assertEqual(plain_by_key["nested"]["text"], "v=1(2.3)")
        self.assertEqual(plain_by_key["nested"]["equation_number_ranges"], [(3, 8)])
        self.assertEqual(plain_by_key["excluded"]["text"], "w=2(4)")
        self.assertEqual(plain_by_key["excluded"]["equation_number_ranges"], [(3, 6)])

        carrier_index = CarrierPassages(carried_html, blocks, carriers)
        self.assertTrue(carrier_index.valid)
        self.assertFalse(hasattr(carrier_index, "number_depth"))
        carrier_by_key = {p["key"]: p for p in carrier_index.passages}
        self.assertEqual(
            [(r["text_start"], r["text_end"]) for r in carrier_by_key["normal"]["source_ranges"]],
            [(0, 3)],
        )
        self.assertEqual(
            [(r["text_start"], r["text_end"]) for r in carrier_by_key["nested"]["source_ranges"]],
            [(0, 3)],
        )
        self.assertEqual(
            [(r["text_start"], r["text_end"]) for r in carrier_by_key["excluded"]["source_ranges"]],
            [(0, 3)],
        )

        marked_index = MarkedPassages(marked_html, blocks, token)
        self.assertTrue(marked_index.valid)
        self.assertFalse(hasattr(marked_index, "number_depth"))
        self.assertEqual(marked_index.intervals(), [(0, 0, 3), (1, 0, 3), (2, 0, 3)])

        # Void tags with flow-equation-number must not leak equation-number state.
        void_blocks = {"void": "section-0"}
        void_plain = PassageIndex('<html><body><p data-reader-key="void"><br class="flow-equation-number">after</p></body></html>', void_blocks)
        void_carried = CarrierPassages(
            f'<html><body><p data-reader-key="void">{t_start}<br class="flow-equation-number">after{t_end}</p></body></html>',
            void_blocks, carriers,
        )
        void_marked = MarkedPassages(
            f'<html><body><p data-reader-key="void">{m_start}<br class="flow-equation-number">after{m_end}</p></body></html>',
            void_blocks, token,
        )
        self.assertFalse(void_plain.in_equation_number)
        self.assertEqual(void_plain.passages[0]["equation_number_ranges"], [])
        self.assertEqual(
            [(r["text_start"], r["text_end"]) for r in void_carried.passages[0]["source_ranges"]],
            [(0, 5)],
        )
        self.assertEqual(void_marked.intervals(), [(0, 0, 5)])


if __name__ == "__main__":
    unittest.main()
