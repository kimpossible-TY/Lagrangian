"""Codex context must be explicit, bounded and tied to a live saved snapshot."""

from http.server import ThreadingHTTPServer
import json
from pathlib import Path
import stat
import sys
import tempfile
import threading
import time
import unittest
from unittest.mock import patch
from urllib.error import HTTPError
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from flow_reader.compiler.build import Project
from flow_reader.services.change_history import input_fingerprint
from flow_reader.services.codex_context import read_reader, source_context
from flow_reader.document.sections import split_document
from flow_reader.server.state import ReaderState
from flow_reader.server.http import handler_for
from flow_reader.compiler.inputs import source_signature


class ReaderFocusTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.work = Path(temporary.name).resolve()
        self.root = self.work / "project"
        self.root.mkdir()
        self.entry = self.root / "main.typ"
        self.state = self.make_state("A selected 한글 passage.", "<p>A selected 한글 passage.</p>")

    def make_state(self, source, html):
        self.entry.write_text(source)
        project = Project(self.root, Path("main.typ"), self.work / "packages", compiler="missing")
        state = ReaderState(project, self.work / "output", "https://example.test/paged/", False)
        state.bundle = split_document(f"<html><body>{html}</body></html>", "accepted")
        state.revision = "accepted"
        state.source_stamp = source_signature(project, set())
        state.accepted_inputs = input_fingerprint(project, set())
        return state

    def fragment(self, text, index=0):
        passage = self.state.bundle.passages[index]
        return {"key": passage["key"], "exact": text, "prefix": "", "suffix": ""}

    def save(self, text="selected 한글", **overrides):
        payload = {"revision": self.state.revision, "fragments": [self.fragment(text)],
                   "service": self.state.focus.service, "viewer_id": 42}
        return self.state.save_focus(**(payload | overrides))

    def server(self):
        server = ThreadingHTTPServer(("127.0.0.1", 0), handler_for(self.state))
        worker = threading.Thread(target=server.serve_forever, daemon=True)
        worker.start()
        def close():
            server.shutdown()
            server.server_close()
            worker.join()
        self.addCleanup(close)
        return f"http://127.0.0.1:{server.server_port}/"

    def test_save_records_exact_text_source_identity_and_private_last_selection(self):
        before = self.entry.read_bytes()
        with patch("flow_reader.rendering.service.compile_project") as compile_document:
            result = self.save()
            compile_document.assert_not_called()
        self.assertEqual(result["selection"]["text"], "selected 한글")
        self.assertEqual(result["status"], "selected")
        self.assertEqual(result["source"]["filepath"], str(self.entry))
        self.assertEqual((result["source"]["line"], result["source"]["column"]), (1, 3))
        self.assertNotIn("page_no", result["position"])
        self.assertEqual(stat.S_IMODE(self.state.focus.path.stat().st_mode), 0o600)
        self.assertEqual(self.entry.read_bytes(), before)
        self.assertTrue(self.state.read_focus()["selection_usable"])
        self.assertFalse(self.state.read_focus()["needs_reselection"])
        newer = self.save("passage")
        self.assertGreater(newer["sequence"], result["sequence"])
        self.assertEqual(json.loads(self.state.focus.path.read_text())["selection"]["text"], "passage")
        self.assertEqual(list(self.state.focus.path.parent.glob(".focus-*")), [])

    def test_math_generated_and_multiblock_text_save_without_inventing_source(self):
        self.state = self.make_state('$ alpha $\n#let value = [Repeated]\n#value\n#value',
                                     '<p><math><mi>α</mi></math></p><p>Repeated</p><p>Repeated</p>')
        math = self.fragment("α") | {"segments": [{"math": True}]}
        result = self.save(fragments=[math])
        self.assertEqual(result["status"], "unmapped")
        self.assertIsNone(result["source"])
        self.assertTrue(self.state.read_focus()["selection_usable"])
        self.assertTrue(self.state.read_focus()["needs_reselection"])
        result = self.save(fragments=[self.fragment("Repeated", 1), self.fragment("Repeated", 2)])
        self.assertEqual(result["selection"]["text"], "Repeated\nRepeated")
        self.assertIsNone(result["source"])
        self.state = self.make_state("#let words = [Repeated Repeated]\n#words", "<p>Repeated Repeated</p>")
        ambiguous = self.save("Repeated")
        self.assertEqual(ambiguous["status"], "unmapped")
        self.assertEqual(ambiguous["selection"]["text"], "Repeated")
        self.assertIsNone(ambiguous["position"]["start"]["offset"])

    def test_source_change_revision_and_restart_invalidate_selection(self):
        self.save()
        self.entry.write_text("A modified 한글 passage.")
        read = self.state.read_focus()
        self.assertFalse(read["selection_usable"])
        self.assertFalse(read["source_excerpt_matches_disk"])
        result = self.save()
        self.assertEqual(result["status"], "stale")
        self.assertIsNone(result["selection"])
        self.state = self.make_state("A selected 한글 passage.", "<p>A selected 한글 passage.</p>")
        self.save()
        self.state.revision = "newer"
        self.assertFalse(self.state.read_focus()["revision_matches"])
        self.assertIsNone(self.save(revision="accepted")["selection"])
        self.assertEqual(self.save(service={"pid": 1, "startedAt": 1})["status"], "stale")
        restarted = ReaderState(self.state.project, self.state.output, "", False)
        self.assertEqual(restarted.read_focus()["status"], "waiting")
        self.assertIsNone(restarted.read_focus()["selection"])

    def test_saved_context_does_not_expire_but_snapshot_checks_still_apply(self):
        self.save()
        for elapsed in (301, 86400 * 30):
            with self.subTest(elapsed=elapsed), patch(
                    "flow_reader.services.codex_context.time.time", return_value=time.time() + elapsed):
                result = self.state.read_focus()
                self.assertTrue(result["selection_usable"])
                self.assertFalse(result["needs_reselection"])
                self.assertGreaterEqual(result["age_seconds"], elapsed)
        self.state.revision = "changed"
        self.assertFalse(self.state.read_focus()["selection_usable"])
        self.state.revision = "accepted"
        self.state.compiling = True
        self.assertEqual(self.save()["status"], "stale")

    def test_unmapped_saved_text_remains_usable_after_five_minutes(self):
        self.state = self.make_state('$ alpha $', '<p><math><mi>α</mi></math></p>')
        self.save(fragments=[self.fragment("α") | {"segments": [{"math": True}]}])
        with patch("flow_reader.services.codex_context.time.time", return_value=time.time() + 86400 * 30):
            result = self.state.read_focus()
        self.assertEqual(result["selection"]["text"], "α")
        self.assertTrue(result["selection_usable"])
        self.assertTrue(result["needs_reselection"])
        self.assertIsNone(result["source"])

    def test_invalid_oversized_and_injected_quotations_do_not_replace_context(self):
        original = self.save()
        for fragments in ([], [self.fragment("invented")],
                          [self.fragment("selected") | {"key": "unknown"}],
                          [self.fragment("x" * 8001)]):
            with self.subTest(fragments=fragments), self.assertRaises(ValueError):
                self.save(fragments=fragments)
        for viewer in (None, True, "42", -1):
            with self.assertRaises(ValueError):
                self.save(viewer_id=viewer)
        self.assertEqual(json.loads(self.state.focus.path.read_text()), original)

    def test_http_save_and_read_validate_service_identity_origin_and_source(self):
        base = self.server()
        payload = {"revision": self.state.revision, "fragments": [self.fragment("selected")],
                   "service": self.state.focus.service, "viewerID": 12}
        request = Request(base + "api/focus", json.dumps(payload).encode(),
                          {"Content-Type": "application/json", "Origin": base.rstrip("/")})
        with urlopen(request) as response:
            self.assertEqual(json.load(response)["status"], "selected")
        read = read_reader(base, expected_pid=self.state.focus.service["pid"],
                           project=self.root, document=self.entry)
        self.assertTrue(read["service_matches"])
        self.assertTrue(read["selection_usable"])
        for expected in ({"expected_pid": 1}, {"project": self.work}, {"document": self.root / "other.typ"}):
            self.assertFalse(read_reader(base, **expected)["selection_usable"])
        request.add_header("Origin", "https://other.test")
        with self.assertRaises(HTTPError) as wrong:
            urlopen(request)
        self.assertEqual(wrong.exception.code, 403)
        wrong.exception.close()
        self.state.focus.path.write_text("broken")
        with self.assertRaises(HTTPError) as broken:
            urlopen(base + "api/focus")
        self.assertEqual(broken.exception.code, 503)
        broken.exception.close()

    def test_context_files_are_separate_between_documents_and_absolute(self):
        other = self.root / "other.typ"
        other.write_text("Other.")
        project = Project(self.root, Path("other.typ"), self.work / "packages")
        second = ReaderState(project, self.work / "other-output", "", False)
        self.save()
        self.assertNotEqual(self.state.focus.path, second.focus.path)
        self.assertEqual(second.read_focus()["status"], "waiting")
        with self.assertRaisesRegex(ValueError, "absolute"):
            ReaderState(project, self.work / "other-output", "", False, focus_file=Path("relative.json"))

    def test_source_race_and_persistence_failure_never_acknowledge_success(self):
        def race(location):
            self.entry.write_text("Source changed during context resolution.")
            return source_context(location)
        with patch("flow_reader.services.selection.source_context", side_effect=race):
            self.assertEqual(self.save()["status"], "stale")
        self.state = self.make_state("A selected 한글 passage.", "<p>A selected 한글 passage.</p>")
        original = self.state.focus.path.read_bytes()
        base = self.server()
        request = Request(base + "api/focus", json.dumps({
            "revision": self.state.revision, "fragments": [self.fragment("selected")],
            "service": self.state.focus.service, "viewerID": 12,
        }).encode(), {"Content-Type": "application/json"})
        with patch.object(self.state.focus, "record", side_effect=OSError("storage unavailable")):
            with self.assertRaises(HTTPError) as failed:
                urlopen(request)
        self.assertEqual(failed.exception.code, 503)
        failed.exception.close()
        self.assertEqual(self.state.focus.path.read_bytes(), original)


if __name__ == "__main__":
    unittest.main()
