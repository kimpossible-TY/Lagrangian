"""Compiler-carried ranges must agree for saved context and editor navigation."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from flow_reader.compiler.build import Project, compile_project
from flow_reader.compiler.source_map import SourceCarriers
from flow_reader.document.sections import split_document
from flow_reader.server.state import ReaderState


class CarrierAcceptanceTests(unittest.TestCase):
    def test_changed_html_and_unbalanced_carriers_never_authorize_a_map(self):
        carriers = SourceCarriers()
        carriers.ranges["0"] = {"path": "/unused.typ", "source_hash": "unused",
                                 "start": 0, "end": 4, "kind": "text"}
        attr = carriers.attribute
        marker = f'<span {attr}="0" data-flow-source-edge="start"></span>'
        baseline = '<html><body><p>Same</p></body></html>'
        self.assertEqual(carriers.extract(baseline, baseline.replace('Same', marker + 'Changed')), {})
        self.assertEqual(carriers.extract(baseline, baseline.replace('Same', marker + 'Same')), {})
        self.assertFalse(carriers.verified)

    def test_changed_block_order_cannot_shift_a_duplicate_to_another_source(self):
        carriers = SourceCarriers()
        carriers.ranges = {str(i): {"path": "/unused.typ", "source_hash": "unused",
                                    "start": i * 10, "end": i * 10 + 6, "kind": "text"}
                           for i in range(2)}
        def marked(identifier, text):
            return (f'<span {carriers.attribute}="{identifier}" data-flow-source-edge="start"></span>'
                    + text + f'<span {carriers.attribute}="{identifier}" data-flow-source-edge="end"></span>')
        baseline = '<html><body><p>Same</p><p>Same</p><p>Stable</p></body></html>'
        annotated = ('<html><body><p>Changed</p><p>' + marked("0", "Same")
                     + '</p><p>' + marked("1", "Stable") + '</p></body></html>')
        result = carriers.extract(baseline, annotated)
        self.assertEqual([part["text"] for part in result.values()], ["Stable"])
        self.assertFalse(carriers.complete)


class CompiledSourceMappingTests(unittest.TestCase):
    def setUp(self):
        packages = os.environ.get("FLOW_READER_PACKAGES")
        compiler = os.environ.get("FLOW_READER_TYPST") or shutil.which("typst")
        if not packages or not compiler:
            self.skipTest("Set FLOW_READER_PACKAGES and optionally FLOW_READER_TYPST")
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.work = Path(temporary.name).resolve()
        self.root = self.work / "project"
        self.root.mkdir()
        self.entry = self.root / "main.typ"
        self.project = Project(self.root, Path("main.typ"), Path(packages), compiler=compiler)

    def state(self, source):
        self.entry.write_text(source)
        state = ReaderState(self.project, self.work / "output", "", False)
        self.addCleanup(state.close)
        state.compile()
        self.assertTrue(state.report.get("contentGatePassed"), state.report)
        self.assertEqual(state.report.get("sourceMapStatus"), "verified", state.report.get("sourceMapStatus"))
        return state

    def fragment(self, state, exact, occurrence=0):
        passage = [part for part in state.bundle.passages if exact in part["text"]][occurrence]
        start = passage["text"].index(exact)
        return {"key": passage["key"], "exact": exact,
                "prefix": passage["text"][:start][-64:],
                "suffix": passage["text"][start + len(exact):][:64]}

    def test_nested_closure_proof_math_unicode_and_saved_range_share_one_mapping(self):
        chapter = self.root / "chapter.typ"
        source = ('#let scope(body) = body(none)\r\n'
                  '#let proof(body) = block(body)\r\n'
                  '#scope(s => [\r\n#proof[한글 before "quoted" words.\r\n\r\n'
                  'For $f in L^2$, the same kernel formula gives $u(t) arrow.r f$ after restriction.\r\n]\r\n])\r\n')
        chapter.write_bytes(source.encode())
        state = self.state('#include "chapter.typ"')
        passage = next(part for part in state.bundle.passages if "the same kernel formula" in part["text"])
        fragment = self.fragment(state, passage["text"])
        with patch("flow_reader.server.state.compile_project") as compile_again:
            location = state.source(state.revision, [fragment])
            saved = state.save_focus(state.revision, [fragment], state.focus.service, 42)
            compile_again.assert_not_called()
        self.assertEqual(location["status"], "located")
        self.assertEqual(location["path"], str(chapter))
        self.assertEqual((location["line"], location["column"]), (6, 0))
        self.assertEqual(location["end_column"], len(source.splitlines()[5].encode()))
        self.assertEqual(saved["status"], "selected")
        self.assertEqual(saved["source"]["filepath"], location["path"])
        self.assertEqual(saved["source"]["range"]["end"],
                         {"line": 6, "column": len(source.splitlines()[5]) + 1})
        self.assertTrue(state.read_focus()["source_excerpt_matches_disk"])
        self.assertFalse(state.read_focus()["needs_reselection"])
        quoted = state.source(state.revision, [self.fragment(state, "“quoted”")])
        self.assertEqual((quoted["line"], quoted["column"]), (4, len('#proof[한글 before '.encode())))
        cursor = state.cursor(state.revision, str(chapter), 6, len('For $f in '.encode()))
        self.assertEqual(cursor["key"], fragment["key"])
        self.assertEqual(chapter.read_bytes(), source.encode())
        self.assertNotIn(b"data-flow-source-", state.document)
        self.assertNotIn("source_ranges", json.dumps(state.bundle.manifest))

    def test_distinct_duplicate_paragraphs_and_repeated_includes_are_not_guessed(self):
        state = self.state('Same paragraph.\n\nSame paragraph.')
        first = state.source(state.revision, [self.fragment(state, "paragraph", 0)])
        second = state.source(state.revision, [self.fragment(state, "paragraph", 1)])
        self.assertEqual((first["line"], second["line"]), (1, 3))
        part = self.root / "part.typ"
        part.write_text("Repeated included text.")
        state = self.state('#include "part.typ"\n\n#include "part.typ"')
        self.assertEqual(state.cursor(state.revision, str(part), 1, 4)["status"], "ambiguous")
        self.assertEqual(state.source(state.revision, [self.fragment(state, "included", 1)])["path"], str(part))

    def test_multiblock_same_file_cross_file_partial_math_and_changed_sources(self):
        state = self.state('#let proof(body) = block(body)\n#proof[First paragraph.\n\nSecond $alpha^2$ paragraph.]')
        fragments = [self.fragment(state, "First paragraph."), self.fragment(state, "Second")]
        result = state.source(state.revision, fragments)
        self.assertEqual((result["status"], result["line"], result["end_line"]), ("located", 2, 4))
        formula = next(part for part in state.bundle.passages if "Second" in part["text"])
        math_span = next(span for span in formula["source_ranges"] if span["kind"] == "math")
        text = formula["text"][math_span["text_start"]:math_span["text_end"]]
        self.assertEqual(state.source(state.revision, [self.fragment(state, text)])["status"], "located")
        self.assertEqual(state.source(state.revision, [self.fragment(state, text[:1])])["status"], "unmapped")
        self.entry.write_text(self.entry.read_text().replace("First", "Other"))
        self.assertEqual(state.source(state.revision, fragments)["status"], "stale")
        part = self.root / "part.typ"
        part.write_text("From another file.")
        state = self.state('First file.\n\n#include "part.typ"')
        fragments = [self.fragment(state, "First file."), self.fragment(state, "From another file.")]
        self.assertEqual(state.source(state.revision, fragments)["status"], "unmapped")

    def test_lists_labels_nested_math_notes_and_unsupported_code_keep_original_html(self):
        source = ('#set math.equation(numbering: "(1)")\n'
                  '#set heading(numbering: "1.")\n'
                  '= Heading <heading>\n\n'
                  '#let scope(body) = block(body)\n'
                  '#scope[+ *First*: a whole-space argument (with parentheses).\n+ Second item.]\n\n'
                  'A whole-space argument (with parentheses).\n\n'
                  '$ alpha + #footnote[An inner $beta$ note.] beta $ <formula>\n\n'
                  'See @formula and @heading.\n\n'
                  '#let words = [Generated words.]\n#words\n\n```typ\nRaw words.\n```')
        state = self.state(source)
        plain = compile_project(self.project, self.work / "baseline", map_sources=False)
        self.assertTrue(plain["contentGatePassed"])
        self.assertEqual(state.document, (self.work / "baseline/document.html").read_bytes())
        fragment = self.fragment(state, "whole-space argument (with parentheses).")
        self.assertEqual(state.source(state.revision, [fragment])["status"], "located")
        self.assertEqual(state.source(state.revision, [self.fragment(state, "Generated words.")])["status"], "unmapped")

    def test_failed_or_changed_carrier_compile_keeps_original_accepted_output(self):
        self.entry.write_text("Ordinary paragraph.")
        for error in (ValueError("unsupported"), subprocess.TimeoutExpired("typst", 60)):
            with self.subTest(error=type(error).__name__), patch(
                    "flow_reader.compiler.build.compile_source_map", side_effect=error):
                report = compile_project(self.project, self.work / "failed-map")
            self.assertTrue(report["contentGatePassed"])
            self.assertEqual(report["sourceMap"], {})
            self.assertEqual(report["sourceMapStatus"], "unavailable")
            self.assertIn("Ordinary paragraph.", (self.work / "failed-map/document.html").read_text())

    def test_carried_paths_and_hashes_cannot_bypass_saved_source_checks(self):
        state = self.state("First literal paragraph.")
        fragment = self.fragment(state, "literal")
        span = state.bundle.passages[0]["source_ranges"][0]
        outside = self.work / "outside.typ"
        outside.write_text(self.entry.read_text())
        original_path = span["path"]
        span["path"] = str(outside)
        self.assertEqual(state.source(state.revision, [fragment])["status"], "unmapped")
        span["path"] = original_path
        span["source_hash"] = "0" * 64
        self.assertEqual(state.source(state.revision, [fragment])["status"], "stale")


if __name__ == "__main__":
    unittest.main()
