"""Snapshot isolation across source edits, temporary candidates and package overlays."""
from dataclasses import replace
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from flow_reader.compiler.execution import CompileRequest
from flow_reader.compiler.project import Project
from flow_reader.compiler.snapshot import capture_snapshot, SnapshotUnavailable, WRAPPER


class SnapshotTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.work = Path(self.temp.name).resolve()
        self.root = self.work / "source"
        self.root.mkdir()
        self.entry = self.root / "main.typ"
        self.entry.write_text('Original #include "chapter.typ"')
        self.chapter = self.root / "chapter.typ"
        self.chapter.write_text("Chapter")
        self.packages = self.work / "packages"
        self.packages.mkdir()
        self.project = Project(self.root, Path("main.typ"), self.packages)
        self.request = CompileRequest("typst", self.root, self.packages, "html",
                                      entry=self.entry, system_fonts=False, timestamp=1760000000)

    def capture(self, request=None, dependencies=None):
        return capture_snapshot(request or self.request, self.project,
                                dependencies or [self.entry, self.chapter], "engine-build-digest")

    def test_snapshot_bytes_and_identity_survive_later_workspace_edits(self):
        snapshot = self.capture()
        self.chapter.write_text("Changed")
        self.assertIn(b"Chapter", [file.content for file in snapshot.files])
        self.assertNotEqual(snapshot.identity, self.capture().identity)
        self.assertNotIn(str(self.root), json.dumps(snapshot.wire()))
        with self.assertRaises(SnapshotUnavailable):
            snapshot.dependencies(["/workspace/newer-file.typ"])
        self.assertEqual(snapshot.dependencies(["/workspace/chapter.typ"]), (str(self.chapter),))

    def test_candidate_uses_changed_shadow_bytes_without_reading_unrelated_files(self):
        shadow = self.work / "candidate"
        shadow.mkdir()
        (shadow / "main.typ").write_text("Candidate")
        (shadow / "chapter.typ").symlink_to(self.chapter)
        (self.root / "unrelated-secret").write_text("not an input")
        request = replace(self.request, root=shadow, entry=shadow / "main.typ")
        snapshot = self.capture(request)
        self.assertEqual({file.path: file.content for file in snapshot.files}, {
            "/workspace/main.typ": b"Candidate", "/workspace/chapter.typ": b"Chapter"})

    def test_current_package_overlay_and_manifest_are_captured(self):
        version = Path("local/example/0.1.0")
        original = self.packages / version
        original.mkdir(parents=True)
        (original / "lib.typ").write_text("Original package")
        overlay = self.work / "overlay"
        (overlay / version).mkdir(parents=True)
        (overlay / version / "lib.typ").write_text("HTML adapter")
        (overlay / version / "typst.toml").write_text("manifest")
        snapshot = self.capture(replace(self.request, packages=overlay), [self.entry, original / "lib.typ"])
        files = {file.path: file.content for file in snapshot.files}
        self.assertEqual(files["/packages/local/example/0.1.0/lib.typ"], b"HTML adapter")
        self.assertEqual(files["/packages/local/example/0.1.0/typst.toml"], b"manifest")

    def test_font_and_settings_changes_invalidate_identity(self):
        fonts = self.work / "fonts"
        fonts.mkdir()
        font = fonts / "body.ttf"
        font.write_bytes(b"font-one")
        request = replace(self.request, fonts=(fonts,))
        before = self.capture(request)
        font.write_bytes(b"font-two")
        self.assertNotEqual(before.identity, self.capture(request).identity)
        self.assertNotEqual(before.identity, self.capture(replace(request, inputs=(("theme", "dark"),))).identity)
        self.assertNotEqual(before.identity, self.capture(replace(request, target="pdf")).identity)

    def test_discovered_preview_cache_is_captured_without_scanning_other_packages(self):
        cache = self.work / "cache"
        version = cache / "preview/example/0.1.0"
        version.mkdir(parents=True)
        library = version / "lib.typ"
        library.write_text("Cached dependency")
        (version / "typst.toml").write_text("Manifest")
        (version / "unused.typ").write_text("Must not be sent")
        with patch("flow_reader.compiler.snapshot.package_cache_root", return_value=cache):
            snapshot = self.capture(dependencies=[self.entry, library])
        files = {file.path: file.content for file in snapshot.files}
        self.assertEqual(files["/packages/preview/example/0.1.0/lib.typ"], b"Cached dependency")
        self.assertEqual(files["/packages/preview/example/0.1.0/typst.toml"], b"Manifest")
        self.assertEqual(len(files), 3)
        self.assertEqual(snapshot.dependencies(["/packages/preview/example/0.1.0/lib.typ"]), (str(library),))

    def test_read_set_changed_during_capture_is_rejected(self):
        original = Path.open
        # Sorted chapter precedes main, so mutate the earlier chapter when main is read.
        def racing_main(path, *args, **kwargs):
            if path == self.entry and args == ("rb",):
                self.chapter.write_text("Concurrent save")
            return original(path, *args, **kwargs)
        with patch.object(Path, "open", racing_main), self.assertRaises(SnapshotUnavailable):
            self.capture()

    def test_missing_inputs_limits_implicit_fonts_and_reserved_entry_fail_closed(self):
        with self.assertRaises(SnapshotUnavailable):
            self.capture(replace(self.request, system_fonts=True))
        with patch("flow_reader.compiler.snapshot.MAX_BYTES", 2), self.assertRaises(SnapshotUnavailable):
            self.capture()
        outside = self.work / "private"
        outside.write_text("unrepresentable")
        with self.assertRaises(SnapshotUnavailable):
            self.capture(dependencies=[outside])
        wrapper = replace(self.request, entry=None, source="#include \"/main.typ\"")
        self.assertEqual(self.capture(wrapper).entry, WRAPPER)
        (self.root / Path(WRAPPER).name).write_text("authored file")
        with self.assertRaises(SnapshotUnavailable):
            self.capture(wrapper)


if __name__ == "__main__":
    unittest.main()
