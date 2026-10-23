"""Lost acknowledgments and interrupted writes never apply an intent twice."""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import sys
import tempfile
import threading
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from flow_reader.services.highlight_receipts import HighlightReceipts
from flow_reader.compiler.project import Project
from flow_reader.compiler.inputs import input_fingerprint, source_signature
from flow_reader.document.sections import split_document
from flow_reader.server.state import ReaderState


class HighlightReceiptTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name).resolve()
        self.source = root / "main.typ"
        self.source.write_text("Original text.")
        project = Project(root, Path("main.typ"), root / "packages")
        self.state = ReaderState(project, root / "output", "", False)
        self.addCleanup(self.state.close)
        self.state.bundle = split_document("<html><body><p>Original text.</p></body></html>", "accepted")
        self.state.revision = "accepted"
        self.state.source_stamp = source_signature(project, [])
        self.state.accepted_inputs = input_fingerprint(project, [])
        self.request = {"requestID": "request-1234567890", "documentID": self.state.document_id,
                        "service": dict(self.state.focus.service), "revision": "accepted",
                        "fragments": [{"key": self.state.bundle.passages[0]["key"], "exact": "Original"}]}

    def test_lost_ack_replays_saved_result_even_after_source_and_service_change(self):
        def write(*args, **kwargs):
            self.source.write_text("#highlight[Original] text.")
            return "highlighted"
        with patch("flow_reader.services.selection.apply_highlight", side_effect=write) as apply:
            first = self.state.highlight_intent(self.request)
            self.state.focus.service = {"pid": 1, "startedAt": 0}
            self.state.selection.receipts = HighlightReceipts(self.state.output / "highlight-receipts.sqlite3")
            self.assertEqual(self.state.highlight_intent(self.request), first)
            self.assertEqual(first["status"], "highlighted")
            self.assertEqual(apply.call_count, 1)

    def test_same_identity_different_content_cannot_reuse_success(self):
        with patch("flow_reader.services.selection.apply_highlight", return_value="highlighted"):
            self.state.highlight_intent(self.request)
        with self.assertRaisesRegex(ValueError, "reused"):
            self.state.highlight_intent(self.request | {"revision": "other"})

    def test_interruption_after_write_leaves_uncertain_receipt_and_never_reexecutes(self):
        def interrupted(*args, **kwargs):
            self.source.write_text("#highlight[Original] text.")
            raise RuntimeError("Process stopped after source replacement")
        with patch("flow_reader.services.selection.apply_highlight", side_effect=interrupted) as apply:
            with self.assertRaises(RuntimeError):
                self.state.highlight_intent(self.request)
            self.assertEqual(self.state.highlight_intent(self.request)["status"], "uncertain")
            self.assertEqual(apply.call_count, 1)

    def test_revision_service_document_and_content_conflicts_never_write(self):
        for field, value in (("revision", "old"), ("service", {}), ("documentID", "other")):
            request = self.request | {"requestID": "different-identity-" + field, field: value}
            with patch("flow_reader.services.selection.apply_highlight") as apply:
                self.assertEqual(self.state.highlight_intent(request)["status"], "stale")
                apply.assert_not_called()
        self.source.write_text("External edit.")
        with patch("flow_reader.services.selection.apply_highlight") as apply:
            self.assertEqual(self.state.highlight_intent(self.request)["status"], "stale")
            apply.assert_not_called()

    def test_concurrent_duplicate_waits_for_one_authoritative_write(self):
        entered, release = threading.Event(), threading.Event()
        def write(*args, **kwargs):
            entered.set()
            self.assertTrue(release.wait(5))
            return "highlighted"
        with patch("flow_reader.services.selection.apply_highlight", side_effect=write) as apply:
            with ThreadPoolExecutor(max_workers=2) as workers:
                first = workers.submit(self.state.highlight_intent, self.request)
                self.assertTrue(entered.wait(5))
                duplicate = workers.submit(self.state.highlight_intent, self.request)
                release.set()
                self.assertEqual(first.result(5), duplicate.result(5))
                self.assertEqual(apply.call_count, 1)

    def test_editor_ownership_is_retained_for_replayed_requests(self):
        request = self.request | {"editorServer": "unrelated-editor"}
        with patch("flow_reader.services.selection.apply_highlight") as apply:
            self.assertEqual(self.state.highlight_intent(request)["status"], "editor-mismatch")
            apply.assert_not_called()


if __name__ == "__main__":
    unittest.main()
