"""Saved-source actions keep one accepted snapshot throughout their work."""

from concurrent.futures import ThreadPoolExecutor
import os
from pathlib import Path
import sys
import tempfile
import threading
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from flow_reader.compiler.inputs import input_fingerprint, source_signature
from flow_reader.compiler.project import Project
from flow_reader.document.sections import split_document
from flow_reader.server.state import ReaderState


class AcceptedSnapshotTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        work = Path(temporary.name).resolve()
        root = work / "project"
        root.mkdir()
        self.entry = root / "main.typ"
        self.entry.write_text("Original text.\n")
        self.imported = root / "part.typ"
        self.imported.write_text("Imported text.\n")
        project = Project(root, Path("main.typ"), work / "packages", compiler="missing")
        self.state = ReaderState(project, work / "output", "", False)
        self.state.bundle = split_document("<html><body><p>Original text.</p></body></html>", "accepted")
        self.state.revision = "accepted"
        self.state.accepted_dependencies = {str(self.imported)}
        self.state.source_stamp = source_signature(project, self.state.accepted_dependencies)
        self.state.accepted_inputs = input_fingerprint(project, self.state.accepted_dependencies)
        passage = self.state.bundle.passages[0]
        self.fragments = [{"key": passage["key"], "exact": "Original", "prefix": "", "suffix": " text."}]

    def save_focus(self):
        return self.state.save_focus("accepted", self.fragments, self.state.focus.service, 42)

    def edit_without_stat_change(self, path):
        before = path.stat()
        contents = path.read_bytes()
        path.write_bytes(b"X" + contents[1:])
        os.utime(path, ns=(before.st_atime_ns, before.st_mtime_ns))
        self.assertEqual(source_signature(self.state.project, self.state.accepted_dependencies),
                         self.state.source_stamp)

    def test_missing_snapshot_old_revision_and_compiling_never_start_source_work(self):
        original_bundle = self.state.bundle
        for revision, compiling, bundle in (
            ("old", False, original_bundle),
            ("accepted", True, original_bundle),
            ("accepted", False, None),
        ):
            with self.subTest(revision=revision, compiling=compiling, bundle=bool(bundle)):
                self.state.compiling, self.state.bundle = compiling, bundle
                with patch("flow_reader.services.navigation.source_location") as locate, patch(
                        "flow_reader.services.selection.apply_highlight") as highlight:
                    self.assertEqual(self.state.source(revision, self.fragments)["status"], "stale")
                    self.assertEqual(self.state.highlight(revision, self.fragments)["status"], "stale")
                    locate.assert_not_called()
                    highlight.assert_not_called()

    def test_content_drift_beyond_stat_signature_blocks_navigation_highlight_and_context(self):
        self.save_focus()
        self.edit_without_stat_change(self.imported)
        with patch("flow_reader.services.selection.apply_highlight") as highlight:
            self.assertEqual(self.state.source("accepted", self.fragments)["status"], "stale")
            self.assertEqual(self.state.highlight("accepted", self.fragments)["status"], "stale")
            highlight.assert_not_called()
        self.assertFalse(self.state.read_focus()["selection_usable"])
        self.assertEqual(self.save_focus()["status"], "stale")

    def test_concurrent_publication_does_not_retarget_an_inflight_navigation(self):
        entered, resume = threading.Event(), threading.Event()
        original_bundle = self.state.bundle
        original_dependencies = set(self.state.accepted_dependencies)

        def locate(project, dependencies, bundle, fragments):
            self.assertIs(bundle, original_bundle)
            self.assertEqual(dependencies, original_dependencies)
            entered.set()
            self.assertTrue(resume.wait(5), "Navigation fixture was not released")
            self.assertEqual(dependencies, original_dependencies)
            self.assertIs(bundle, original_bundle)
            return {"status": "located", "path": str(self.entry)}

        with patch("flow_reader.services.navigation.source_location", side_effect=locate):
            with ThreadPoolExecutor(max_workers=1) as worker:
                future = worker.submit(self.state.source, "accepted", self.fragments)
                try:
                    self.assertTrue(entered.wait(5), "Navigation did not capture its snapshot")
                    with self.state.lock:
                        self.state.accepted_dependencies.clear()
                        self.state.revision = "newer"
                        self.state.bundle = split_document("<html><body><p>Newer text.</p></body></html>", "newer")
                finally:
                    resume.set()
                self.assertEqual(future.result(timeout=5), {"status": "stale", "revision": "newer"})

    def test_highlight_rechecks_captured_inputs_during_candidate_verification(self):
        def verify(project, output, bundle, dependencies, fragments, fresh, writer=None):
            self.edit_without_stat_change(self.imported)
            fresh()
            self.fail("Changed source must stop the candidate before writing")

        with patch("flow_reader.services.selection.apply_highlight", side_effect=verify):
            self.assertEqual(self.state.highlight("accepted", self.fragments),
                             {"status": "stale", "revision": "accepted"})
        self.assertEqual(self.entry.read_text(), "Original text.\n")

    def test_filesystem_errors_preserve_each_action_failure_contract(self):
        with patch("flow_reader.services.accepted_snapshot.input_fingerprint", side_effect=OSError("unreadable")):
            self.assertEqual(self.state.source("accepted", self.fragments),
                             {"status": "stale", "revision": "accepted"})
            self.assertEqual(self.state.highlight("accepted", self.fragments),
                             {"status": "error", "revision": "accepted"})
            with self.assertRaisesRegex(OSError, "unreadable"):
                self.save_focus()

    def test_invalid_navigation_stays_an_error_instead_of_becoming_stale(self):
        with patch("flow_reader.services.navigation.source_location", side_effect=ValueError("invalid selection")):
            with self.assertRaisesRegex(ValueError, "invalid selection"):
                self.state.source("accepted", self.fragments)


if __name__ == "__main__":
    unittest.main()
