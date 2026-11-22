"""Compiler-carried ranges must agree for saved context and editor navigation."""

import hashlib
from http.server import ThreadingHTTPServer
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import threading
from types import SimpleNamespace
import unittest
from unittest.mock import patch
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from flow_reader.compiler.build import Project, compile_project
from flow_reader.compiler.source_map import SourceCarriers, markup_ranges
from flow_reader.document.passages import PassageIndex, validate_fragments
from flow_reader.document.sections import split_document
from flow_reader.server.state import ReaderState
from flow_reader.server.http import handler_for
from flow_reader.services.source_mapping import edit_location, mapped_source_range, source_excerpt


class CarrierAcceptanceTests(unittest.TestCase):
    def test_excerpt_scanning_excludes_literal_and_computed_labels(self):
        formula = '$alpha + #text("$") beta$'
        for suffix in ('', ' <literal>', ' #<literal>',
                       ' #(s.tag)("periodic-cell-solution")',
                       ' #tag("price-$", ("nested",))'):
            with self.subTest(suffix=suffix):
                source = formula + suffix
                carried = next(markup_ranges(source))
                expression = next(markup_ranges(source, include_labels=False))
                self.assertEqual(carried, (0, len(source), 'math'))
                self.assertEqual(expression, (0, len(formula), 'math'))

    def test_computed_reference_calls_are_one_source_range(self):
        source = 'See #(s.ref)("interval-images") now.'
        ranges = list(markup_ranges(source))
        self.assertIn(('#(s.ref)("interval-images")', 'reference'),
                      [(source[start:end], kind) for start, end, kind in ranges])

    def test_at_label_references_emit_reference_ranges_and_preserve_trailing_punctuation(self):
        source = (
            'By @Fourier, see (@Fourier) and @sec:1.2. Also @sec:1.2: and '
            '@Fourier[Theorem 1] end. Bare @ @. @: stay text.'
        )
        extracted = [(source[start:end], kind) for start, end, kind in markup_ranges(source)]
        references = [text for text, kind in extracted if kind == 'reference']
        self.assertEqual(
            references,
            ['@Fourier', '@Fourier', '@sec:1.2', '@sec:1.2', '@Fourier[Theorem 1]'],
        )
        self.assertIn(('. Also', 'text'), extracted)
        self.assertIn((': and', 'text'), extracted)
        self.assertIn((') and', 'text'), extracted)
        self.assertIn(('end. Bare', 'text'), extracted)
        self.assertIn(('.', 'text'), extracted)
        self.assertIn((': stay text.', 'text'), extracted)

    def navigation_for(self, body):
        carriers = SourceCarriers()
        carriers.navigation_sources['0'] = {'path': '/unused.typ', 'source_hash': 'unused',
                                             'start': 0, 'end': 20, 'kind': 'invocation'}
        start = f'<span {carriers.navigation_attribute}="0" data-flow-source-edge="start"></span>'
        end = f'<span {carriers.navigation_attribute}="0" data-flow-source-edge="end"></span>'
        document = lambda content: '<html><body>' + content + '</body></html>'
        carriers.extract(document(body), document(start + body + end))
        return carriers.navigation

    def test_sibling_callout_and_figure_are_independent_invocation_outputs(self):
        callout = '<figure><div class="flow-callout">Repeated output.</div></figure>'
        for figure in ('<figure><img src="picture.png"><figcaption>Repeated output.</figcaption></figure>',
                       '<figure style="border: 1px solid red"></figure>'):
            for body in (callout + figure, figure + callout):
                with self.subTest(body=body):
                    self.assertEqual(self.navigation_for(body), [])

    def test_content_outside_nested_callout_maps_to_its_whole_figure(self):
        callout = '<div class="flow-callout">Nested callout.</div>'
        for outside in ('<img src="picture.png">', '<p>Other figure content.</p>',
                        '<svg><rect width="20" height="10"/></svg>',
                        '<figure style="border: 1px solid red"></figure>'):
            for children in (outside + callout, callout + outside):
                with self.subTest(children=children):
                    navigation = self.navigation_for('<figure>' + children + '</figure>')
                    self.assertEqual(len(navigation), 1)
                    self.assertTrue(navigation[0]['target'].startswith('reader-figure-'))

    def test_navigation_containers_require_complete_compiler_agreement_and_unique_output(self):
        carriers = SourceCarriers()
        carriers.navigation_sources['0'] = {'path': '/unused.typ', 'source_hash': 'unused',
                                             'start': 0, 'end': 20, 'kind': 'invocation'}
        start = f'<span {carriers.navigation_attribute}="0" data-flow-source-edge="start"></span>'
        end = f'<span {carriers.navigation_attribute}="0" data-flow-source-edge="end"></span>'
        container = '<figure><div class="flow-callout">Unwrapped body.</div></figure>'
        document = lambda body: '<html><body>' + body + '</body></html>'
        carriers.extract(document(container), document(start + container + end))
        self.assertEqual(len(carriers.navigation), 1)
        self.assertTrue(carriers.navigation[0]['target'].startswith('reader-callout-'))
        for baseline, annotated in (
                (container, start + container.replace('body.', 'different.') + end),
                (container, start + container),
                (container * 2, (start + container + end) * 2),
                ('<p>Outside.</p>' + container, start + '<p>Outside.</p>' + container + end)):
            carriers.extract(document(baseline), document(annotated))
            self.assertEqual(carriers.navigation, [])

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

    def test_arguments_skip_code_keywords_and_frame_calls_while_preserving_markup(self):
        source = (
            '#figure(\n'
            '  context {\n'
            '    import "@preview/cetz:0.4.2": canvas, draw\n'
            '    canvas(length: 1cm, { content((0, 0), text(size: 9pt)[$xi_(1)$]) })\n'
            '  },\n'
            '  caption: [Context figure caption.],\n'
            ')\n'
            '#figure(\n'
            '  cetz.canvas(length: 1cm, { content((0, 0), [$eta$]) }),\n'
            '  caption: [Direct CeTZ caption.],\n'
            ')\n'
            '#figure(canvas(length: 1cm)[$zeta$], caption: [Trailing canvas caption.])\n'
            '#figure(html.frame[$omega$], caption: [Frame caption.])\n'
            '#figure(if true { [$a$] } else { [$b$] }, caption: [Conditional caption.])\n'
            '#figure(\n'
            '  [Body.],\n'
            '  caption: context_note[Context prefix.] + setting[Set prefix.] '
            '+ format[For prefix.] + canvas_title[Canvas prefix.],\n'
            ')\n'
            '#proof[Proof body.]\n'
            '#proposition[Proposition body.]\n'
            '#scope(s => [Closure body.])\n'
        )
        extracted = [source[start:end] for start, end, _ in markup_ranges(source)]
        for forbidden in ('$xi_(1)$', '$eta$', '$zeta$', '$omega$', '$a$', '$b$'):
            self.assertNotIn(forbidden, extracted)
        for retained in (
            'Context figure caption.',
            'Direct CeTZ caption.',
            'Trailing canvas caption.',
            'Frame caption.',
            'Conditional caption.',
            'Context prefix.',
            'Set prefix.',
            'For prefix.',
            'Canvas prefix.',
            'Proof body.',
            'Proposition body.',
            'Closure body.',
        ):
            self.assertIn(retained, extracted)

    def test_passage_index_and_mapped_source_range_handle_equation_number_ranges(self):
        html = (
            '<html><body>'
            '<p data-reader-key="p1">Intro text.</p>'
            '<div class="flow-equation" data-reader-key="eq1">'
            '<math>u=0</math><div class="flow-equation-number"> (4.1.16) </div>'
            '</div>'
            '<div class="flow-equation" data-reader-key="eq2">'
            '<math>v=1</math><div class="flow-equation-number">(4.1.17)</div>'
            '</div>'
            '<p data-reader-key="p2">Mapped Unmapped</p>'
            '</body></html>'
        )
        blocks = {'p1': 'section-0', 'eq1': 'section-0', 'eq2': 'section-0', 'p2': 'section-0'}
        passages = PassageIndex(html, blocks).passages
        by_key = {part['key']: part for part in passages}
        self.assertEqual(by_key['p1']['equation_number_ranges'], [])
        self.assertEqual(by_key['eq1']['text'], 'u=0 (4.1.16)')
        self.assertEqual(by_key['eq1']['equation_number_ranges'], [(4, 12)])
        self.assertEqual(by_key['eq1']['text'][4:12], '(4.1.16)')
        self.assertEqual(by_key['eq2']['text'], 'v=1(4.1.17)')
        self.assertEqual(by_key['eq2']['equation_number_ranges'], [(3, 11)])
        self.assertEqual(by_key['eq2']['text'][3:11], '(4.1.17)')

        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            entry = root / 'main.typ'
            source = 'Intro text.\n\n$ u = 0 $\n\n$ v = 1 $\n\nMapped\n'
            entry.write_text(source)
            digest = hashlib.sha256(source.encode()).hexdigest()
            project = Project(root, Path('main.typ'), root / 'packages')

            def span(snippet, kind, text_start, text_end):
                start = source.index(snippet)
                return {'path': str(entry), 'source_hash': digest,
                        'start': start, 'end': start + len(snippet),
                        'kind': kind, 'text_start': text_start, 'text_end': text_end}

            by_key['p1']['source_ranges'] = [span('Intro text.', 'text', 0, len('Intro text.'))]
            by_key['eq1']['source_ranges'] = [span('$ u = 0 $', 'math', 0, 3)]
            by_key['eq2']['source_ranges'] = [span('$ v = 1 $', 'math', 0, 3)]
            by_key['p2']['source_ranges'] = [span('Mapped', 'text', 0, len('Mapped'))]
            bundle = SimpleNamespace(passages=passages)

            including = validate_fragments([
                {'key': 'p1', 'exact': 'Intro text.'},
                {'key': 'eq1', 'exact': 'u=0 (4.1.16)'},
                {'key': 'eq2', 'exact': 'v=1(4.1.17)'},
            ])
            located_inc = mapped_source_range(project, (), bundle, including)
            self.assertEqual(located_inc['status'], 'located')
            self.assertEqual(len(located_inc['spans']), 3)

            excluding_trailing = validate_fragments([
                {'key': 'p1', 'exact': 'Intro text.'},
                {'key': 'eq1', 'exact': 'u=0 (4.1.16)'},
                {'key': 'eq2', 'exact': 'v=1'},
            ])
            located_exc = mapped_source_range(project, (), bundle, excluding_trailing)
            self.assertEqual(located_exc['status'], 'located')
            self.assertEqual(located_exc['spans'], located_inc['spans'])

            number_only = validate_fragments([{'key': 'eq1', 'exact': '(4.1.16)'}])
            self.assertEqual(mapped_source_range(project, (), bundle, number_only)['status'], 'unmapped')

            uncovered = validate_fragments([{'key': 'p2', 'exact': 'Mapped Unmapped'}])
            self.assertEqual(mapped_source_range(project, (), bundle, uncovered)['status'], 'unmapped')


class SourceExcerptTests(unittest.TestCase):
    def test_verified_math_range_copies_without_its_computed_label(self):
        formula = '$alpha + beta$'
        rendered = 'α+β'
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            entry = root / 'main.typ'
            project = Project(root, Path('main.typ'), root / 'packages')
            for suffix in ('', ' <literal>', ' #<literal>',
                           ' #(s.tag)("periodic-cell-solution")',
                           ' #tag("price-$", ("nested",))'):
                with self.subTest(suffix=suffix):
                    source = formula + suffix
                    entry.write_text(source)
                    span = {'path': str(entry), 'source_hash': hashlib.sha256(source.encode()).hexdigest(),
                            'start': 0, 'end': len(source), 'kind': 'math',
                            'text_start': 0, 'text_end': len(rendered)}
                    bundle = SimpleNamespace(passages=[{'key': 'equation', 'id': 'equation',
                        'section': 'section-0', 'text': rendered + '(3.4.48)', 'source_ranges': [span]}])
                    fragment = {'key': 'equation', 'exact': rendered, 'suffix': '(3.4.48)'}
                    self.assertEqual(source_excerpt(project, (), bundle, [fragment]),
                                     {'status': 'located', 'text': formula})

    def test_stale_client_boundary_lone_surrogates_disambiguate_repeated_non_bmp_formula(self):
        formula = '$Lambda^(-s)$'
        rendered = 'Λ−𝑠'
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            entry = root / 'main.typ'
            project = Project(root, Path('main.typ'), root / 'packages')
            source = (
                'Because $Lambda^(s)$ is surjective with inverse $Lambda^(-s)$, '
                'the candidate limit $u:=Lambda^(-s)f$ belongs to $H^(s)$.'
            )
            entry.write_text(source)
            digest = hashlib.sha256(source.encode()).hexdigest()
            passage_text = (
                'Because Λ𝑠 is surjective with inverse Λ−𝑠, '
                'the candidate limit 𝑢≔Λ−𝑠𝑓 belongs to 𝐻𝑠.'
            )
            first_rendered_start = passage_text.index(rendered)
            first_source_start = source.index(formula)
            second_rendered_start = passage_text.index(rendered, first_rendered_start + len(rendered))
            second_source_start = source.index('$u:=Lambda^(-s)f$')
            spans = [
                {
                    'path': str(entry),
                    'source_hash': digest,
                    'start': first_source_start,
                    'end': first_source_start + len(formula),
                    'kind': 'math',
                    'text_start': first_rendered_start,
                    'text_end': first_rendered_start + len(rendered),
                },
                {
                    'path': str(entry),
                    'source_hash': digest,
                    'start': second_source_start,
                    'end': second_source_start + len('$u:=Lambda^(-s)f$'),
                    'kind': 'math',
                    'text_start': second_rendered_start - 2,
                    'text_end': second_rendered_start + len(rendered) + 1,
                },
            ]
            bundle = SimpleNamespace(passages=[{
                'key': 'p-inverse',
                'id': 'p-inverse',
                'section': 'section-0',
                'text': passage_text,
                'source_ranges': spans,
            }])

            # Stale cached client slicing UTF-16 code units leaves a leading low
            # surrogate in prefix and trailing high surrogate in suffix.
            stale_fragment = {
                'key': 'p-inverse',
                'exact': rendered,
                'prefix': '\udc3f is surjective with inverse ',
                'suffix': ', the candidate limit \ud835',
            }
            self.assertEqual(
                source_excerpt(project, (), bundle, [stale_fragment]),
                {'status': 'located', 'text': formula},
            )
            # Clean context also locates identically.
            clean_fragment = {
                'key': 'p-inverse',
                'exact': rendered,
                'prefix': 'is surjective with inverse ',
                'suffix': ', the candidate limit ',
            }
            self.assertEqual(
                source_excerpt(project, (), bundle, [clean_fragment]),
                {'status': 'located', 'text': formula},
            )
            # Genuinely ambiguous context (no matching prefix/suffix) still returns ambiguous.
            ambiguous_fragment = {
                'key': 'p-inverse',
                'exact': rendered,
                'prefix': '',
                'suffix': '',
            }
            self.assertEqual(
                source_excerpt(project, (), bundle, [ambiguous_fragment]),
                {'status': 'ambiguous'},
            )
            # validate_fragments never mutates exact or key.
            validated = validate_fragments([{
                'key': '\udc3f-key-\ud835',
                'exact': '\udc3f' + rendered + '\ud835',
                'prefix': ' \udc3f with inverse ',
                'suffix': ', limit \ud835 ',
            }])[0]
            self.assertEqual(validated['key'], '\udc3f-key-\ud835')
            self.assertEqual(validated['exact'], '\udc3f' + rendered + '\ud835')
            self.assertEqual(validated['prefix'], 'with inverse')
            self.assertEqual(validated['suffix'], ', limit')


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

    def mathematics_fragment(self, state, source, marker):
        for passage in state.bundle.passages:
            for span in passage.get("source_ranges", []):
                if span["kind"] != "math" or not source[span["start"]:span["end"]].startswith(marker):
                    continue
                exact = passage["text"][span["text_start"]:span["text_end"]]
                return {
                    "key": passage["key"],
                    "exact": exact,
                    "prefix": passage["text"][:span["text_start"]][-64:],
                    "suffix": passage["text"][span["text_end"]:][:64],
                }
        self.fail(f"No mathematical source range starts with {marker}")

    def test_complete_mathematics_exports_verified_typst_for_copying(self):
        source = ('Before $alpha^2 + beta$ after.\n\n'
                  'A labeled formula $x + y$ <named-equation>\n\n'
                  'Ordinary prose stays prose.')
        state = self.state(source)
        formula = self.mathematics_fragment(state, source, "$alpha^2 + beta$")
        result = state.source_text(state.revision, [formula])
        self.assertEqual(result["status"], "located")
        self.assertEqual(result["text"], "$alpha^2 + beta$")
        labeled = self.mathematics_fragment(state, source, "$x + y$")
        self.assertEqual(state.source_text(state.revision, [labeled])["text"], "$x + y$")
        partial = {**formula, "exact": formula["exact"][:-1],
                   "suffix": formula["exact"][-1] + formula["suffix"]}
        self.assertEqual(state.source_text(state.revision, [partial])["status"], "unmapped")
        prose = self.fragment(state, "Ordinary prose")
        self.assertEqual(state.source_text(state.revision, [prose])["status"], "unmapped")

        server = ThreadingHTTPServer(("127.0.0.1", 0), handler_for(state))
        worker = threading.Thread(target=server.serve_forever, daemon=True)
        worker.start()
        try:
            payload = json.dumps({"revision": state.revision, "fragments": [formula]}).encode()
            request = Request(f"http://127.0.0.1:{server.server_port}/api/source-text", payload,
                              {"Content-Type": "application/json"})
            with urlopen(request) as response:
                self.assertEqual(json.load(response)["text"], "$alpha^2 + beta$")
        finally:
            server.shutdown()
            server.server_close()
            worker.join()

    def test_dots_helper_preserves_formula_copying_and_adjacent_prose_mapping(self):
        source = (ROOT / 'tests/fixtures/dots-space.typ').read_text()
        state = self.state(source)
        formulas = ['$alpha #dots_space beta$',
                    '$x^(#dots_space) + frac(1, #dots_space) + mat(#dots_space, 1; 2, 3)$',
                    source[source.index('$\n'):source.index('$ <dots-aligned>') + 1]]
        for formula in formulas:
            with self.subTest(formula=formula):
                fragment = self.mathematics_fragment(state, source, formula)
                self.assertEqual(state.source_text(state.revision, [fragment])['text'], formula)
        for phrase in ['Before helper', 'after helper.', 'Inline formula',
                       'remains in this paragraph.', 'Nested formula', 'stays inline.']:
            with self.subTest(phrase=phrase):
                located = state.source(state.revision, [self.fragment(state, phrase)])
                self.assertEqual(located['status'], 'located', located)
                self.assertEqual(located['path'], str(self.entry))
                offset = source.index(phrase)
                line_start = source.rfind('\n', 0, offset) + 1
                self.assertEqual(located['line'], source.count('\n', 0, offset) + 1)
                self.assertEqual(located['column'], len(source[line_start:offset].encode()))
                self.assertEqual(located['end_line'], located['line'])
                self.assertEqual(located['end_column'], len(source[line_start:offset + len(phrase)].encode()))

    def test_numbered_aligned_equation_with_computed_label_copies_whole_source(self):
        source = (ROOT / 'tests/fixtures/aligned-equation-copy.typ').read_text()
        state = self.state(source)
        formula = self.mathematics_fragment(state, source, '$\n')
        expected = source[source.index('$\n'):source.index('$ #(s.tag)') + 1]
        passage = next(part for part in state.bundle.passages if part['key'] == formula['key'])
        self.assertEqual(formula['suffix'], '(3.4.48)')
        self.assertIn(b'<mtable class="multiline-equation aligned">', state.document)
        self.assertEqual(state.source_text(state.revision, [formula])['text'], expected)
        whole_block = self.fragment(state, passage['text'])
        self.assertEqual(state.source_text(state.revision, [whole_block])['status'], 'unmapped')
        partial = {**formula, 'exact': formula['exact'][:-1],
                   'suffix': formula['exact'][-1] + formula['suffix']}
        self.assertEqual(state.source_text(state.revision, [partial])['status'], 'unmapped')

        server = ThreadingHTTPServer(('127.0.0.1', 0), handler_for(state))
        worker = threading.Thread(target=server.serve_forever, daemon=True)
        worker.start()
        try:
            payload = json.dumps({'revision': state.revision, 'fragments': [formula]}).encode()
            request = Request(f'http://127.0.0.1:{server.server_port}/api/source-text', payload,
                              {'Content-Type': 'application/json'})
            with urlopen(request) as response:
                result = json.load(response)
            self.assertEqual(result['status'], 'located')
            self.assertEqual(result['text'], expected)
        finally:
            server.shutdown()
            server.server_close()
            worker.join()

        plain = compile_project(self.project, self.work / 'plain', map_sources=False)
        self.assertTrue(plain['contentGatePassed'])
        self.assertEqual(state.document, (self.work / 'plain/document.html').read_bytes())
        self.entry.write_text(source + '\nChanged saved source.\n')
        self.assertEqual(state.source_text(state.revision, [formula])['status'], 'stale')

    def test_callout_title_and_unwrapped_body_map_only_to_navigation_container(self):
        source = ('#import "@local/math-blocks:0.2.0": note\n'
                  'Before the note.\n\n'
                  '#note(title: "Green functions")[Unwrapped #strong[Green function] body.]\n\n'
                  'After the note.')
        state = self.state(source)
        for text in ('Green functions', 'Unwrapped', 'Green function'):
            offset = source.index(text)
            location = edit_location(self.project, state.accepted_dependencies, state.bundle, {
                'path': str(self.entry), 'source_hash': hashlib.sha256(source.encode()).hexdigest(),
                'start': offset, 'end': offset + len(text), 'line': 4, 'column': 0})
            self.assertEqual(location['status'], 'located', (text, location))
            self.assertTrue(location['target'].startswith('reader-callout-'))
            self.assertEqual(state.bundle.manifest['anchors'][location['target']], location['section'])
        title = source.index('Green functions')
        self.assertFalse(any(span['start'] <= title < span['end'] for passage in state.bundle.passages
                             for span in passage.get('source_ranges', [])))
        self.assertEqual(state.cursor(state.revision, str(self.entry), 4, len('#note(title: "'.encode()))['status'],
                         'unmapped')
        self.assertNotIn('navigation_ranges', json.dumps(state.bundle.manifest))
        self.assertNotIn(b'data-flow-navigation-', state.document)
        plain = compile_project(self.project, self.work / 'plain', map_sources=False)
        self.assertTrue(plain['contentGatePassed'])
        self.assertEqual(state.document, (self.work / 'plain/document.html').read_bytes())

    def test_native_figure_arguments_map_to_verified_figure_without_selection_ranges(self):
        (self.root / 'picture.svg').write_text(
            '<svg xmlns="http://www.w3.org/2000/svg" width="20" height="10">'
            '<rect width="20" height="10" fill="red"/></svg>')
        source = ('Before.\n\n#figure(image("picture.svg", width: 20pt), '
                  'caption: [Native figure caption.]) <picture>\n\nAfter.')
        state = self.state(source)
        offset = source.index('20pt')
        location = edit_location(self.project, state.accepted_dependencies, state.bundle, {
            'path': str(self.entry), 'source_hash': hashlib.sha256(source.encode()).hexdigest(),
            'start': offset, 'end': offset + 4, 'line': 3, 'column': 0})
        self.assertEqual(location['status'], 'located', location)
        self.assertTrue(location['target'].startswith('reader-figure-'))
        self.assertIn(location['target'], state.bundle.manifest['anchors'])
        self.assertFalse(any(span['start'] <= offset < span['end'] for passage in state.bundle.passages
                             for span in passage.get('source_ranges', [])))

    def test_wrapper_prose_does_not_inherit_a_nested_note_navigation_range(self):
        source = ('#import "@local/math-blocks:0.2.0": note\n'
                  '#let scope(body) = body\n'
                  '#scope[Outside wrapper paragraph.\n\n#note[Only this note.]]')
        state = self.state(source)
        outer = source.index('Outside')
        self.assertFalse(any(span['start'] <= outer < span['end'] for span in state.bundle.navigation_ranges))
        location = edit_location(self.project, state.accepted_dependencies, state.bundle, {
            'path': str(self.entry), 'source_hash': hashlib.sha256(source.encode()).hexdigest(),
            'start': outer, 'end': outer + len('Outside'), 'line': 3, 'column': len('#scope[')})
        self.assertEqual(location['status'], 'located')
        self.assertIn('key', location)

    def test_computed_labels_stay_attached_to_referenced_notes_and_figures(self):
        for label in ('#(scope.tag)', '#marker', '#label'):
            with self.subTest(label=label):
                source = ('#import "@local/math-blocks:0.2.0": note\n'
                          '#let scope = (tag: name => label(name),)\n'
                          '#let marker(name) = label(name)\n'
                          '#note(title: "Named note")[#par[The referenced note body.]] '
                          + label + '("named-note")\n\n'
                          '#figure([Figure body.], caption: [Figure caption.]) '
                          + label + '("named-figure")\n\n'
                          'See @named-note and @named-figure.')
                state = self.state(source)
                plain = compile_project(self.project, self.work / "baseline", map_sources=False)
                self.assertTrue(plain["contentGatePassed"])
                self.assertEqual(state.document, (self.work / "baseline/document.html").read_bytes())
                self.assertEqual(state.source(state.revision, [self.fragment(
                    state, "The referenced note body.")])["status"], "located")
                offset = source.index('Named note')
                location = edit_location(self.project, state.accepted_dependencies, state.bundle, {
                    'path': str(self.entry), 'source_hash': hashlib.sha256(source.encode()).hexdigest(),
                    'start': offset, 'end': offset + len('Named note'), 'line': 4, 'column': 0})
                self.assertEqual(location['status'], 'located', location)
                self.assertTrue(location['target'].startswith('reader-callout-'))

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

    def test_computed_reference_output_maps_only_as_a_complete_generated_range(self):
        source = ('#let s = (ref: name => [Equation (3.4.28)],)\n'
                  'We verify $alpha + beta$ by the image series '
                  '#(s.ref)("interval-images") before continuing.\n')
        state = self.state(source)
        plain = compile_project(self.project, self.work / 'plain', map_sources=False)
        self.assertTrue(plain['contentGatePassed'])
        self.assertEqual(state.document, (self.work / 'plain/document.html').read_bytes())
        paragraph = next(part for part in state.bundle.passages
                         if part['text'].startswith('We verify'))
        fragment = self.fragment(state, paragraph['text'])
        location = state.source(state.revision, [fragment])
        saved = state.save_focus(state.revision, [fragment], state.focus.service, 42)
        reference = next(span for span in paragraph['source_ranges']
                         if span['kind'] == 'reference')
        self.assertEqual(location['status'], 'located', location)
        self.assertEqual(saved['status'], 'selected')
        self.assertEqual(saved['source']['filepath'], str(self.entry))
        self.assertEqual(saved['source']['range']['start']['line'], 2)
        self.assertEqual(saved['source']['range']['start']['column'], 1)
        self.assertEqual(saved['source']['range']['end']['column'], len(source.splitlines()[1]) + 1)
        self.assertEqual(reference['start'], source.index('#(s.ref)'))
        self.assertEqual(source[reference['start']:reference['end']],
                         '#(s.ref)("interval-images")')

        output = paragraph['text'][reference['text_start']:reference['text_end']]
        selected = output[:max(1, len(output) // 2)]
        start = paragraph['text'].index(selected)
        partial = {'key': paragraph['key'], 'exact': selected,
                   'prefix': paragraph['text'][:start][-64:],
                   'suffix': paragraph['text'][start + len(selected):][:64]}
        self.assertEqual(state.source(state.revision, [partial])['status'], 'unmapped')

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

    def test_cetz_context_and_html_frame_figures_compile_without_paragraph_warnings(self):
        source = (
            '#import "@preview/cetz:0.4.2" as cetz\n'
            '#let proof(body) = block(par(body))\n'
            '#let proposition(body) = block(par(body))\n'
            '#let scope(body) = body(none)\n'
            'Before figures with $alpha$.\n\n'
            '#figure(\n'
            '  context {\n'
            '    import "@preview/cetz:0.4.2": canvas, draw\n'
            '    canvas(length: 1cm, {\n'
            '      import draw: *\n'
            '      line((0, 0), (1, 0))\n'
            '      content((0.5, 0.2), text(size: 9pt)[$xi_(1)$])\n'
            '    })\n'
            '  },\n'
            '  caption: [CeTZ context caption with $xi_(1)$.],\n'
            ')\n\n'
            '#figure(\n'
            '  cetz.canvas(length: 1cm, {\n'
            '    import cetz.draw: *\n'
            '    line((0, 0), (1, 1))\n'
            '    content((0.5, 0.5), text(size: 9pt)[$xi_(2)$])\n'
            '  }),\n'
            '  caption: [Direct CeTZ caption.],\n'
            ')\n\n'
            '#figure(\n'
            '  html.frame[Framed $omega$ content],\n'
            '  caption: [HTML frame caption.],\n'
            ')\n\n'
            '#proposition[Proposition statement.]\n\n'
            '#proof[Proof argument.]\n\n'
            '#scope(s => [Closure content.])\n'
        )
        state = self.state(source)
        self.assertEqual(state.report.get("sourceMapStatus"), "verified")
        self.assertFalse(any("elem may not occur inside of a paragraph" in warning
                             for warning in state.report.get("warnings", {})))
        for phrase in (
            "Before figures",
            "CeTZ context caption",
            "Direct CeTZ caption.",
            "HTML frame caption.",
            "Proposition statement.",
            "Proof argument.",
            "Closure content.",
        ):
            with self.subTest(phrase=phrase):
                self.assertEqual(state.source(state.revision, [self.fragment(state, phrase)])["status"], "located")

    def test_numbered_display_equation_selection_locates_with_or_without_equation_number(self):
        source = (
            '#set math.equation(numbering: n => "(4.1." + str(15 + n) + ")")\n'
            '#let hidden = [Generated words.]\n\n'
            'Introductory prose.\n\n'
            '$ u_t - Delta u = 0 $\n\n'
            '$ u(0, x) = g(x) $\n\n'
            'Plain prose and #hidden\n'
        )
        state = self.state(source)
        intro = next(part for part in state.bundle.passages if part["text"] == "Introductory prose.")
        eq1 = next(part for part in state.bundle.passages if "(4.1.16)" in part["text"])
        eq2 = next(part for part in state.bundle.passages if "(4.1.17)" in part["text"])
        mixed = next(part for part in state.bundle.passages if "Generated words." in part["text"])

        self.assertTrue(eq1.get("equation_number_ranges"))
        self.assertTrue(eq2.get("equation_number_ranges"))
        eq2_without_number = eq2["text"].removesuffix("(4.1.17)").strip()

        including = [
            self.fragment(state, intro["text"]),
            self.fragment(state, eq1["text"]),
            self.fragment(state, eq2["text"]),
        ]
        located_inc = state.source(state.revision, including)
        self.assertEqual(located_inc["status"], "located")

        excluding_trailing = [
            self.fragment(state, intro["text"]),
            self.fragment(state, eq1["text"]),
            self.fragment(state, eq2_without_number),
        ]
        located_exc = state.source(state.revision, excluding_trailing)
        self.assertEqual(located_exc["status"], "located")
        self.assertEqual((located_exc["line"], located_exc["end_line"]),
                         (located_inc["line"], located_inc["end_line"]))

        self.assertEqual(state.source(state.revision, [self.fragment(state, "(4.1.16)")])["status"], "unmapped")
        self.assertEqual(state.source(state.revision, [self.fragment(state, mixed["text"])])["status"], "unmapped")

    def test_at_label_references_locate_and_save_focus_across_multiblock_selection(self):
        source = (
            '#set heading(numbering: "1.1")\n'
            '#set math.equation(numbering: "(1)")\n\n'
            '= Unitary Fourier Transform <unitary_fourier_transform_and_inverse>\n\n'
            '$ norm(hat(f)) = norm(f) $ <Fourier>\n\n'
            "By Plancherel's theorem (@Fourier), $u_t - Delta u = 0$ holds. "
            'By @Fourier, see @Fourier[Theorem 1] in @unitary_fourier_transform_and_inverse.\n'
        )
        state = self.state(source)
        plain = compile_project(self.project, self.work / 'plain-at-ref', map_sources=False)
        self.assertTrue(plain['contentGatePassed'])
        self.assertEqual(state.document, (self.work / 'plain-at-ref/document.html').read_bytes())

        equation = next(part for part in state.bundle.passages if '(1)' in part['text'] and 'Plancherel' not in part['text'])
        paragraph = next(part for part in state.bundle.passages if "Plancherel" in part['text'])
        ref_spans = [span for span in paragraph['source_ranges'] if span['kind'] == 'reference']
        self.assertEqual(
            [source[span['start']:span['end']] for span in ref_spans],
            ['@Fourier', '@Fourier', '@Fourier[Theorem 1]', '@unitary_fourier_transform_and_inverse'],
        )

        fragments = [
            self.fragment(state, equation['text']),
            self.fragment(state, paragraph['text']),
        ]
        located = state.source(state.revision, fragments)
        saved = state.save_focus(state.revision, fragments, state.focus.service, 42)
        self.assertEqual(located['status'], 'located', located)
        self.assertEqual(located['path'], str(self.entry))
        self.assertEqual(saved['status'], 'selected', saved)
        self.assertEqual(saved['source']['filepath'], str(self.entry))
        self.assertTrue(state.read_focus()['source_excerpt_matches_disk'])

        # Partial selection inside a rendered @label reference must remain unmapped.
        first_ref = ref_spans[0]
        rendered_ref = paragraph['text'][first_ref['text_start']:first_ref['text_end']]
        partial_text = rendered_ref[:max(1, len(rendered_ref) // 2)]
        partial_start = first_ref['text_start']
        partial = {
            'key': paragraph['key'],
            'exact': partial_text,
            'prefix': paragraph['text'][:partial_start][-64:],
            'suffix': paragraph['text'][partial_start + len(partial_text):][:64],
        }
        self.assertEqual(state.source(state.revision, [partial])['status'], 'unmapped')


if __name__ == "__main__":
    unittest.main()
