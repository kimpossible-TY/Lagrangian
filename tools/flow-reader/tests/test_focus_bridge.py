"""Exercise the portable Tail Hosting adapter in an isolated copy, never live."""

import importlib.machinery
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch


class FocusBridgeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        source = os.environ.get("TAIL_HOSTING_SOURCE")
        if not source:
            raise unittest.SkipTest("Set TAIL_HOSTING_SOURCE to check the companion patch")
        cls.temporary = tempfile.TemporaryDirectory()
        cls.addClassCleanup(cls.temporary.cleanup)
        root = Path(cls.temporary.name)
        (root / "bin").mkdir()
        target = root / "bin/tail-hosting"
        target.write_bytes((Path(source) / "bin/tail-hosting").read_bytes())
        adapter = Path(__file__).resolve().parents[3] / "apps/macos/tail-hosting-reader-focus.patch"
        result = subprocess.run(["patch", "-p1", "--batch", "--forward", "-i", str(adapter)], cwd=root,
                                capture_output=True)
        if result.returncode:
            # A deployed source already includes this adapter. Reverse and
            # reapply it in the copy to verify both directions, never live.
            target.write_bytes((Path(source) / "bin/tail-hosting").read_bytes())
            subprocess.run(["patch", "-p1", "--batch", "--reverse", "-i", str(adapter)],
                           cwd=root, check=True, capture_output=True)
            subprocess.run(["patch", "-p1", "--batch", "--forward", "-i", str(adapter)],
                           cwd=root, check=True, capture_output=True)
        loader = importlib.machinery.SourceFileLoader("reader_hosting_fixture", str(target))
        spec = importlib.util.spec_from_loader(loader.name, loader)
        cls.hosting = importlib.util.module_from_spec(spec)
        loader.exec_module(cls.hosting)

    def setUp(self):
        self.paged = {"id": "doc", "name": "Paged", "kind": "typst-always-preview",
                      "projectRoot": "/projects/doc", "entrypoint": "main.typ",
                      "launchAgentLabel": "paged", "focusFile": "/runtime/paged.json"}
        self.reader = {**self.paged, "id": "doc-reader", "name": "Reader", "kind": "typst-reader",
                       "launchAgentLabel": "reader", "managerBinary": "/reader/manager",
                       "focusFile": "/runtime/reader.json",
                       "ingress": {"port": 23627, "path": "/"}}
        self.arguments = SimpleNamespace(list=False, preview=None, project=None, document=None, url=None)

    def test_listing_and_explicit_service_filters_keep_reader_and_paged_separate(self):
        h = self.hosting
        registry = {"services": [self.paged, self.reader]}
        self.arguments.list = True
        result = h.resolve_focus(registry, self.arguments)
        self.assertEqual([p["reader_kind"] for p in result["previews"]], ["paged", "html"])
        self.assertNotEqual(*[p["focus_file"] for p in result["previews"]])
        self.arguments.list = False
        self.arguments.project = "/projects/doc"
        with patch.object(h, "read_focus", return_value={"status": "waiting"}):
            result = h.resolve_focus(registry, self.arguments)
        self.assertEqual(result["status"], "waiting")
        self.assertFalse(result["needs_preview_selection"])
        self.arguments.preview = "doc-reader"
        with patch.object(h, "read_focus", return_value={"status": "selected"}) as read:
            result = h.resolve_focus(registry, self.arguments)
            read.assert_called_once_with(self.reader)
        self.assertEqual(result["preview"]["reader_kind"], "html")

    def context(self, timestamp, text=None, **overrides):
        return {"schema_version": 1, "status": "selected", "service_matches": True,
                "selected_at_unix_ms": timestamp, "needs_reselection": False,
                "selection": {"text": text} if text is not None else None, **overrides}

    def resolve(self, paged, reader):
        h = self.hosting
        records = {self.paged["id"]: paged, self.reader["id"]: reader}
        with patch.object(h, "read_focus", side_effect=lambda preview: records[preview["id"]]):
            return h.resolve_focus({"services": [self.paged, self.reader]}, self.arguments)

    def test_project_and_cwd_lookup_choose_saved_html_text_over_newer_paged_tap(self):
        for explicit in (False, True):
            with self.subTest(explicit=explicit), patch.object(Path, "cwd", return_value=Path("/projects/doc/chapter")):
                self.arguments.project = "/projects/doc" if explicit else None
                result = self.resolve(self.context(9000), self.context(1000, "α", status="unmapped",
                                      selection_usable=True, needs_reselection=True))
            self.assertEqual(result["preview"]["id"], "doc-reader")
            self.assertEqual(result["selection"]["text"], "α")
            self.assertEqual(result["resolution"], "latest_saved_text")
            self.assertTrue(result["selection_usable"])
            self.assertTrue(result["needs_reselection"])
            self.assertFalse(result["needs_preview_selection"])

    def test_latest_text_works_in_both_directions_and_retains_snapshot_failure(self):
        self.arguments.project = "/projects/doc"
        result = self.resolve(self.context(3000, "paged"), self.context(2000, "html"))
        self.assertEqual(result["selection"]["text"], "paged")
        result = self.resolve(self.context(1000, "old"), self.context(2000, "changed source",
                              revision_matches=False, selection_usable=False, needs_reselection=True))
        self.assertEqual(result["selection"]["text"], "changed source")
        self.assertFalse(result["revision_matches"])
        self.assertTrue(result["needs_reselection"])

    def test_only_locations_uses_latest_tap_and_no_context_waits_for_save(self):
        self.arguments.project = "/projects/doc"
        result = self.resolve(self.context(1000), self.context(2000))
        self.assertEqual(result["preview"]["id"], "doc-reader")
        self.assertEqual(result["resolution"], "latest_location")
        result = self.resolve({"status": "waiting"}, {"status": "waiting"})
        self.assertEqual(result["status"], "waiting")
        self.assertTrue(result["needs_reselection"])
        self.assertFalse(result["needs_preview_selection"])

    def test_other_documents_and_projects_never_resolve_by_global_recency(self):
        h = self.hosting
        for other in (self.reader | {"entrypoint": "other.typ"},
                      self.reader | {"projectRoot": "/projects/other"}):
            with self.subTest(other=other), patch.object(h, "read_focus") as read:
                result = h.resolve_focus({"services": [self.paged, other]}, self.arguments)
                read.assert_not_called()
            self.assertEqual(result["status"], "ambiguous")
            self.assertTrue(result["needs_preview_selection"])

    def test_unrelated_cwd_does_not_choose_a_project_with_multiple_readers(self):
        h = self.hosting
        with patch.object(Path, "cwd", return_value=Path("/unrelated")), patch.object(h, "read_focus") as read:
            result = h.resolve_focus({"services": [self.paged, self.reader]}, self.arguments)
        read.assert_not_called()
        self.assertEqual(result["status"], "ambiguous")

    def test_nearest_registered_project_is_resolved_before_reading_records(self):
        h = self.hosting
        other = self.paged | {"id": "parent", "projectRoot": "/projects"}
        with patch.object(Path, "cwd", return_value=Path("/projects/doc/chapter")), patch.object(
                h, "read_focus", return_value=self.context(1000, "html")) as read:
            result = h.resolve_focus({"services": [other, self.reader]}, self.arguments)
        read.assert_called_once_with(self.reader)
        self.assertEqual(result["preview"]["id"], "doc-reader")

    def test_exact_url_or_id_does_not_read_another_reader(self):
        h = self.hosting
        url = h.preview_info(self.reader)["url"]
        for target in ({"preview": "doc-reader"}, {"url": url}):
            for key in ("preview", "url"):
                setattr(self.arguments, key, target.get(key))
            with self.subTest(target=target), patch.object(h, "read_focus", return_value={"status": "waiting"}) as read:
                result = h.resolve_focus({"services": [self.paged, self.reader]}, self.arguments)
                read.assert_called_once_with(self.reader)
            self.assertEqual(result["status"], "waiting")
            self.assertEqual(result["preview"]["id"], "doc-reader")

    def test_ties_require_disambiguation_and_wrong_service_is_not_selected(self):
        self.arguments.project = "/projects/doc"
        result = self.resolve(self.context(1000, "paged"), self.context(1000, "html"))
        self.assertEqual(result["status"], "ambiguous")
        self.assertTrue(result["needs_preview_selection"])
        result = self.resolve(self.context(1000, "paged"), self.context(2000, "old process", service_matches=False))
        self.assertEqual(result["selection"]["text"], "paged")

    def test_unavailable_reader_is_reported_alongside_available_context(self):
        h = self.hosting
        self.arguments.project = "/projects/doc"
        def read(preview):
            if preview == self.paged:
                raise RuntimeError("unavailable")
            return self.context(1000, "html")
        with patch.object(h, "read_focus", side_effect=read):
            result = h.resolve_focus({"services": [self.paged, self.reader]}, self.arguments)
        self.assertEqual(result["selection"]["text"], "html")
        self.assertEqual(result["context_read_errors"], [{"id": "doc", "error": "unavailable"}])
        with patch.object(h, "read_focus", side_effect=ValueError("invalid record")):
            result = h.resolve_focus({"services": [self.paged, self.reader]}, self.arguments)
        self.assertEqual(result["status"], "not_ready")
        self.assertFalse(result["needs_preview_selection"])

    def test_paged_context_does_not_expire_and_still_checks_source_and_pid(self):
        h = self.hosting
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source, focus = root / "main.typ", root / "focus.json"
            source.write_text("saved text")
            focus.write_text(json.dumps({"schema_version": 1, "status": "selected", "server_pid": 123,
                "selected_at_unix_ms": 1000000,
                "source": {"filepath": str(source), "excerpt_start_line": 1, "excerpt": "saved text"}}))
            preview = self.paged | {"focusFile": str(focus)}
            with patch.object(h, "process_check", return_value={"pid": 123}), patch.object(h.time, "time", return_value=1000 + 86400 * 30):
                result = h.read_focus(preview)
                self.assertFalse(result["needs_reselection"])
                self.assertEqual(result["age_seconds"], 86400 * 30)
                source.write_text("changed text")
                self.assertTrue(h.read_focus(preview)["needs_reselection"])
                source.write_text("saved text")
                with patch.object(h, "process_check", return_value={"pid": 456}):
                    self.assertTrue(h.read_focus(preview)["needs_reselection"])

    def test_reader_uses_manager_validation_without_paged_record_fallback(self):
        h = self.hosting
        verified = {"status": "unmapped", "selection": {"text": "α"},
                    "selection_usable": True, "source": None}
        with patch.object(h, "require", return_value=json.dumps(verified)) as command:
            self.assertEqual(h.read_focus(self.reader), verified)
        command.assert_called_once_with(["/reader/manager", "--focus", "doc-reader"])
        with self.assertRaisesRegex(ValueError, "managerBinary"):
            h.read_focus(self.reader | {"managerBinary": None})


if __name__ == "__main__":
    unittest.main()
