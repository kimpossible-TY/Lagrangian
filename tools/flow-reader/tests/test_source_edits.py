"""Real compiler proof for explicit HTML source highlights."""

import os
from dataclasses import replace
from types import SimpleNamespace
from pathlib import Path
import shutil
import sys
import tempfile
import unittest
from unittest.mock import patch
from http.server import ThreadingHTTPServer
from urllib.error import HTTPError
from urllib.request import Request, urlopen
import json
import threading

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from flow_reader.compiler.build import Project
from flow_reader.server.state import ReaderState
from flow_reader.server.http import handler_for
from flow_reader.services.source_highlight import selection_pattern


class SourceHighlightTests(unittest.TestCase):
    def setUp(self):
        packages = os.environ.get("FLOW_READER_PACKAGES")
        compiler = os.environ.get("FLOW_READER_TYPST") or shutil.which("typst")
        if not packages or not compiler:
            self.skipTest("Set FLOW_READER_PACKAGES and optionally FLOW_READER_TYPST")
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.work = Path(self.temporary.name)
        self.root = self.work / "source"
        self.root.mkdir()
        self.entry = self.root / "main.typ"
        self.project = Project(self.root, Path("main.typ"), Path(packages), compiler=compiler)

    def compile(self, source):
        self.entry.write_text(source)
        state = ReaderState(self.project, self.work / "output", "https://example.test/paged/", False)
        state.compile()
        self.assertTrue(state.report["contentGatePassed"], state.report)
        return state

    def fragment(self, state, exact, occurrence=0):
        passage = [part for part in state.bundle.passages if exact in part["text"]][occurrence]
        start = passage["text"].index(exact)
        return {"key": passage["key"], "exact": exact,
                "prefix": passage["text"][:start][-64:],
                "suffix": passage["text"][start + len(exact):][:64]}

    def test_literal_highlight_changes_source_and_preserves_permissions(self):
        state = self.compile("Before selected ordinary text after.")
        self.entry.chmod(0o640)
        fragment = self.fragment(state, "selected ordinary text")
        self.assertEqual(state.highlight(state.revision, [fragment])["status"], "highlighted")
        self.assertEqual(self.entry.read_text(), "Before #highlight[selected ordinary text] after.")
        self.assertEqual(self.entry.stat().st_mode & 0o777, 0o640)

    def test_absolute_entry_and_absolute_font_directory_use_the_shadow_candidate(self):
        fonts = self.work / "external-fonts"
        fonts.mkdir()
        marker = fonts / "preserve.txt"
        marker.write_text("Original font directory contents")
        self.project = replace(self.project, entry=self.entry.resolve(), fonts=(fonts.resolve(),))
        state = self.compile("Before selected ordinary text after.")
        fragment = self.fragment(state, "selected ordinary text")
        self.assertEqual(state.highlight(state.revision, [fragment])["status"], "highlighted")
        self.assertEqual(self.entry.read_text(), "Before #highlight[selected ordinary text] after.")
        self.assertEqual(marker.read_text(), "Original font directory contents")
        state.compile()
        self.assertTrue(state.report["contentGatePassed"], state.report)

    def test_verified_highlight_refused_by_editor_never_falls_back_to_disk_write(self):
        source = "Before selected ordinary text after."
        state = self.compile(source)
        fragment = self.fragment(state, "selected ordinary text")
        edits = []
        def reject_dirty(path, original, updated):
            edits.append((path, original, updated))
            return "modified"
        state.editor = SimpleNamespace(write=reject_dirty)
        self.assertEqual(state.highlight(state.revision, [fragment])["status"], "modified")
        self.assertEqual(self.entry.read_text(), source)
        self.assertEqual(edits, [(self.entry.resolve(), source.encode(),
                                 b"Before #highlight[selected ordinary text] after.")])

    def test_navigation_survives_a_verified_partial_source_highlight(self):
        state = self.compile("한글 before selected ordinary text after.")
        fragment = self.fragment(state, "selected ordinary text")
        before = state.source(state.revision, [fragment])
        self.assertEqual(before["status"], "located")
        self.assertEqual(before["column"], len("한글 before ".encode()))
        self.assertEqual(state.highlight(state.revision, [fragment])["status"], "highlighted")
        state.compile()
        fragment = self.fragment(state, "selected ordinary text")
        after = state.source(state.revision, [fragment])
        self.assertEqual(after["status"], "located")
        self.assertEqual(after["column"], len("한글 before #highlight[".encode()))
        cursor = state.cursor(state.revision, str(self.entry), after["line"], after["column"])
        self.assertEqual(cursor["status"], "located")
        self.assertEqual(cursor["exact"], "한글 before selected ordinary text after.")

    def test_imported_source_and_smart_quotes_are_verified(self):
        part = self.root / "part.typ"
        part.write_text('Before "quoted text" after.')
        state = self.compile('#include "part.typ"')
        fragment = self.fragment(state, "“quoted text”")
        self.assertEqual(state.highlight(state.revision, [fragment])["status"], "highlighted")
        self.assertEqual(part.read_text(), 'Before #highlight["quoted text"] after.')
        self.assertEqual(self.entry.read_text(), '#include "part.typ"')

    def test_repeated_source_text_uses_the_actual_compiled_target(self):
        state = self.compile("First repeated words here.\n\nSecond repeated words there.")
        fragment = self.fragment(state, "repeated words", 1)
        self.assertEqual(state.highlight(state.revision, [fragment])["status"], "highlighted")
        self.assertEqual(self.entry.read_text(),
                         "First repeated words here.\n\nSecond #highlight[repeated words] there.")

    def test_common_words_use_context_before_compiler_verification(self):
        state = self.compile("\n\n".join(f"Paragraph {i}: common word in passage {i}." for i in range(40)))
        fragment = self.fragment(state, "common word", 27)
        self.assertEqual(state.highlight(state.revision, [fragment])["status"], "highlighted")
        self.assertEqual(self.entry.read_text().count("#highlight["), 1)
        self.assertIn("Paragraph 27: #highlight[common word]", self.entry.read_text())

    def test_a_complete_formula_is_ranked_among_many_other_equations(self):
        state = self.compile('#import "@local/text-utils:0.1.2": highlighted\n' +
                             "\n\n".join(f"$alpha^{i} + beta$" for i in range(40)))
        exact = state.bundle.passages[27]["text"]
        fragment = self.fragment(state, exact)
        fragment["segments"] = [{"text": exact, "math": True, "complete": True}]
        self.assertEqual(state.highlight(state.revision, [fragment])["status"], "highlighted")
        self.assertIn("#highlighted[$alpha^27 + beta$]", self.entry.read_text())

    def test_read_only_source_is_retained(self):
        state = self.compile("Before selected text after.")
        fragment = self.fragment(state, "selected text")
        self.entry.chmod(0o444)
        self.assertEqual(state.highlight(state.revision, [fragment])["status"], "unsupported")
        self.assertEqual(self.entry.read_text(), "Before selected text after.")

    def test_a_reused_macro_body_cannot_edit_only_one_visible_occurrence(self):
        source = "#let repeated() = [Shared literal words]\n#repeated()\n\n#repeated()"
        state = self.compile(source)
        fragment = self.fragment(state, "literal words")
        self.assertEqual(state.highlight(state.revision, [fragment])["status"], "unmapped")
        self.assertEqual(self.entry.read_text(), source)

    def test_a_highlight_that_breaks_paged_output_is_not_saved(self):
        state = self.compile("Before selected text after.")
        fragment = self.fragment(state, "selected text")
        with patch("flow_reader.services.source_highlight.paged_candidate_compiles", return_value=False):
            self.assertEqual(state.highlight(state.revision, [fragment])["status"], "unmapped")
        self.assertEqual(self.entry.read_text(), "Before selected text after.")

    def test_code_string_lookalikes_are_not_source_text(self):
        source = '#let value = "Selected words"\n#value'
        state = self.compile(source)
        fragment = self.fragment(state, "Selected words")
        self.assertEqual(state.highlight(state.revision, [fragment])["status"], "unmapped")
        self.assertEqual(self.entry.read_text(), source)

    def test_math_uses_the_document_helper_and_rejects_partial_formulas(self):
        source = ('#import "@local/text-utils:0.1.2": highlighted\n'
                  'Before $alpha^2 + beta$ after.')
        state = self.compile(source)
        text = state.bundle.passages[0]["text"]
        exact = text.removeprefix("Before ").removesuffix(" after.")
        fragment = self.fragment(state, exact)
        fragment["segments"] = [{"text": exact, "math": True, "complete": False}]
        self.assertEqual(state.highlight(state.revision, [fragment])["status"], "unsupported")
        fragment["segments"][0]["complete"] = True
        self.assertEqual(state.highlight(state.revision, [fragment])["status"], "highlighted")
        self.assertIn("#highlighted[$alpha^2 + beta$]", self.entry.read_text())

    def test_stale_revision_or_changed_disk_never_writes(self):
        state = self.compile("Before selected text after.")
        fragment = self.fragment(state, "selected text")
        self.assertEqual(state.highlight("old-revision", [fragment])["status"], "stale")
        self.entry.write_text("A newer editor save.")
        self.assertEqual(state.highlight(state.revision, [fragment])["status"], "stale")
        self.assertEqual(self.entry.read_text(), "A newer editor save.")

    def test_display_equation_does_not_require_its_generated_number(self):
        state = self.compile('#import "@local/text-utils:0.1.2": highlighted\n'
                             '#set math.equation(numbering: "(1)")\n$ alpha^2 + beta + 1 $')
        exact = state.bundle.passages[0]["text"].removesuffix("(1)")
        fragment = self.fragment(state, exact)
        fragment["segments"] = [{"text": exact, "math": True, "complete": True}]
        self.assertEqual(state.highlight(state.revision, [fragment])["status"], "highlighted")
        self.assertIn("#highlighted[$ alpha^2 + beta + 1 $]", self.entry.read_text())

    def test_a_save_during_candidate_compilation_is_not_overwritten(self):
        state = self.compile("Before selected text after.")
        fragment = self.fragment(state, "selected text")
        from flow_reader.services.source_highlight import compile_project
        def compile_and_edit(*args, **kwargs):
            result = compile_project(*args, **kwargs)
            self.entry.write_text("A concurrent editor save.")
            return result
        with patch("flow_reader.services.source_highlight.compile_project", side_effect=compile_and_edit):
            self.assertEqual(state.highlight(state.revision, [fragment])["status"], "stale")
        self.assertEqual(self.entry.read_text(), "A concurrent editor save.")

    def test_http_highlight_requires_matching_origin_and_current_revision(self):
        state = self.compile("Before selected text after.")
        fragment = self.fragment(state, "selected text")
        server = ThreadingHTTPServer(("127.0.0.1", 0), handler_for(state))
        worker = threading.Thread(target=server.serve_forever, daemon=True)
        worker.start()
        url = f"http://127.0.0.1:{server.server_port}/api/highlight"
        def request(revision, origin=None):
            headers = {"Content-Type": "application/json"}
            if origin:
                headers["Origin"] = origin
            return Request(url, json.dumps({"revision": revision, "fragments": [fragment]}).encode(), headers)
        try:
            with self.assertRaises(HTTPError) as wrong:
                urlopen(request(state.revision, "https://another-reader.test"))
            self.assertEqual(wrong.exception.code, 403)
            wrong.exception.close()
            with urlopen(request("obsolete")) as response:
                self.assertEqual(json.load(response)["status"], "stale")
            self.assertEqual(self.entry.read_text(), "Before selected text after.")
            with urlopen(request(state.revision)) as response:
                self.assertEqual(json.load(response)["status"], "highlighted")
            self.assertEqual(self.entry.read_text(), "Before #highlight[selected text] after.")
        finally:
            server.shutdown()
            server.server_close()
            worker.join()


class SourceSelectionValidationTests(unittest.TestCase):
    def test_malformed_or_inconsistent_segments_are_rejected(self):
        for segments in ([None], [{"text": "Different"}], []):
            with self.assertRaises(ValueError):
                selection_pattern([{"exact": "Selected", "segments": segments}])


if __name__ == "__main__":
    unittest.main()
