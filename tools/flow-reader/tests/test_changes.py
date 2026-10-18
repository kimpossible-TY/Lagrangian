"""Last-edit history follows accepted visual output, independently of viewers."""

import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from build import Project
from changes import ChangeTracker, MAX_RECORD_BYTES, input_fingerprint
from sections import split_document
from serve import ReaderState, source_signature


def bundle(body, revision="r1", max_blocks=2):
    return split_document("<html><body>" + body + "</body></html>", revision,
                          max_blocks=max_blocks)


class ChangeTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.path = Path(self.directory.name) / "last-change.json"
        self.tracker = ChangeTracker(self.path, "project")

    def test_distant_heading_prefers_body_over_outline_and_reference_copies(self):
        def source(title):
            return ('<nav><p><a href="#distant">' + title + '</a></p></nav>'
                    '<p id="reference">See <a href="#distant">' + title + '</a>.</p>'
                    '<p id="first">First body passage</p><h2 id="distant">' + title + '</h2>')
        self.assertIsNone(self.tracker.observe(bundle(source("Old heading")), "inputs-1"))
        change = self.tracker.observe(bundle(source("Edited heading"), "r2"), "inputs-2")
        self.assertEqual(change["target"], "distant")
        self.assertEqual(change["section"], "section-1")
        self.assertEqual(change["revision"], "r2")
        self.assertEqual(self.path.stat().st_mode & 0o777, 0o600)

    def test_restart_comment_and_runtime_rebase_retain_the_same_edit(self):
        self.tracker.observe(bundle('<p id="a">Original</p>'), "a")
        change = self.tracker.observe(bundle('<p id="a">Changed</p>', "r2"), "b")
        tracker = ChangeTracker(self.path, "project")
        for body, inputs in (('<p id="a">Changed</p>', "b"),
                             ('<p id="a">Changed</p>', "comment"),
                             ('<p id="a" class="new-renderer">Changed</p>', "comment")):
            current = tracker.observe(bundle(body, "r3"), inputs)
            self.assertEqual(current["target"], "a")
            self.assertEqual(current["token"], change["token"])
        stopped_edit = ChangeTracker(self.path, "project").observe(
            bundle('<p id="a">Edited while stopped</p>', "r4"), "stopped")
        self.assertNotEqual(stopped_edit["token"], change["token"])

    def test_math_format_and_native_geometry_are_visual_changes(self):
        for before, after, target in (
            ('<div class="flow-equation" id="equation"><math><mi>x</mi></math></div>',
             '<div class="flow-equation" id="equation"><math><mi mathvariant="bold">x</mi></math></div>',
             "equation"),
            ('<div id="canvas" data-flow-canvas="canvas-1"><svg><path d="M0 0L1 1"/></svg></div>',
             '<div id="canvas" data-flow-canvas="canvas-1"><svg><path d="M0 0L2 2"/></svg></div>',
             "canvas"),
        ):
            with self.subTest(target=target):
                self.tracker = ChangeTracker(self.path, target)
                self.tracker.observe(bundle(before), "old")
                self.assertEqual(self.tracker.observe(bundle(after), "new")["target"], target)

    def test_deleted_passage_uses_surviving_neighbor_including_end_of_document(self):
        for remaining, target in (('<p id="b">B</p>', "b"), ('<p id="a">A</p>', "a")):
            self.tracker = ChangeTracker(self.path, target)
            self.tracker.observe(bundle('<p id="a">A</p><p id="b">B</p>'), "old")
            self.assertEqual(self.tracker.observe(bundle(remaining), "new")["target"], target)

    def test_generated_ids_and_section_boundaries_do_not_invent_edits(self):
        source = '<p id="loc-1">Before</p><p id="loc-2">After</p>'
        self.tracker.observe(bundle(source, max_blocks=2), "old")
        source = source.replace("After", "Edited")
        change = self.tracker.observe(bundle(source, "r2", 2), "new")
        source = source.replace("loc-1", "loc-7").replace("loc-2", "loc-8")
        rebased = self.tracker.observe(bundle(source, "r3", 1), "newer-comment")
        self.assertEqual(rebased["token"], change["token"])
        self.assertEqual(rebased["target"], "loc-8")
        self.assertEqual(rebased["section"], "section-1")

    def test_invalid_oversized_and_other_project_records_establish_baselines(self):
        self.tracker.observe(bundle('<p id="a">Initial</p>'), "a")
        self.tracker.observe(bundle('<p id="a">Edit</p>'), "b")
        original = self.path.read_bytes()
        for payload in (b"{broken", b"null", b"[]", b"[" * 2000 + b"]" * 2000,
                        b" " * (MAX_RECORD_BYTES + 1),
                        original.replace(b'"project"', b'"other-project"')):
            self.path.write_bytes(payload)
            self.assertIsNone(ChangeTracker(self.path, "project").observe(
                bundle('<p id="a">Edit</p>'), "b"))

    def test_content_fingerprint_ignores_touch_but_includes_import_edits(self):
        root = Path(self.directory.name)
        entry, imported = root / "main.typ", root / "part.typ"
        entry.write_text('#include "part.typ"')
        imported.write_text("Original")
        project = Project(root, Path("main.typ"), root / "packages")
        first = input_fingerprint(project, [str(imported)])
        os.utime(imported, (1, 1))
        self.assertEqual(input_fingerprint(project, [str(imported)]), first)
        imported.write_text("Imported edit")
        self.assertNotEqual(input_fingerprint(project, [str(imported)]), first)

    def test_failed_persistence_keeps_in_memory_navigation(self):
        self.tracker.observe(bundle('<p id="a">Initial</p>'), "a")
        with patch.object(self.tracker, "persist", side_effect=OSError("read only")):
            with self.assertLogs("changes", level="WARNING"):
                self.assertEqual(self.tracker.observe(bundle('<p id="a">Edit</p>'), "b")["target"], "a")

    def test_reader_publishes_history_only_from_successful_accepted_snapshots(self):
        root = Path(self.directory.name)
        entry = root / "main.typ"
        entry.write_text("Original")
        output = root / "output"
        output.mkdir()
        project = Project(root, Path("main.typ"), root / "packages", compiler="missing")
        state = ReaderState(project, output, "https://example.test/paged/", False)
        def publish(text, accepted=True):
            entry.write_text(text)
            (output / "report.json").write_text(json.dumps({
                "revision": text, "exitCode": 0 if accepted else 1,
                "contentGatePassed": accepted}))
            (output / "document.html").write_text(f'<html><body><p id="body">{text}</p></body></html>')
            state.load_result(source_signature(project))
        publish("Original")
        self.assertIsNone(state.bundle.manifest["lastChange"])
        publish("Accepted edit")
        manifest = json.loads(state.manifest_json)
        change = manifest["lastChange"]
        self.assertEqual(change["revision"], state.revision)
        self.assertEqual(change["target"], "body")
        saved = (output / "last-change.json").read_bytes()
        publish("Failed edit", accepted=False)
        self.assertEqual(state.bundle.manifest["lastChange"], change)
        self.assertEqual((output / "last-change.json").read_bytes(), saved)


if __name__ == "__main__":
    unittest.main()
