import copy
import json
import tempfile
import unittest
from pathlib import Path

from flow_reader.document.native_document import NativeImportError, import_accepted_document
from flow_reader.document.sections import SectionBundle
from flow_reader.services.cross_project_refs import (
    CatalogError, load_project_catalog, resolve_cross_project_ref,
    extract_block_snippet, build_preview_payload,
)


class NativeProjectRefTests(unittest.TestCase):
    @staticmethod
    def import_link(attrs):
        html = f'<html><body><a href="https://example.com" {attrs}>Link</a></body></html>'
        bundle = SectionBundle({'revision': 'test', 'sections': [{'id': 's'}]},
                               {'s': html.encode()}, {}, [])
        return import_accepted_document(bundle, document_id='test', service_id='test',
                                        generation=1).document

    def test_project_ref(self):
        document = self.import_link('data-project-ref-project=" pde " '
                                    'data-project-ref-label=" zero_acceleration " '
                                    'data-project-ref-title=" PDE " data-project-ref-page=" 12 " '
                                    'data-project-ref-text=" Theorem 2.1 "')
        self.assertEqual(document['blocks'][0]['projectRef'], {
            'project': 'pde', 'label': 'zero_acceleration', 'title': 'PDE',
            'page': 12, 'text': 'Theorem 2.1',
        })
        self.assertEqual(document['requiredCapabilities'], ['semantic-tree-v1'])

    def test_plain_link(self):
        document = self.import_link('')
        self.assertNotIn('projectRef', document['blocks'][0])
        self.assertEqual(document['blocks'][0]['link'], 'https://example.com')

    def test_invalid_project_refs(self):
        for attrs in (
            'data-project-ref-project="pde"',
            'data-project-ref-project=" " data-project-ref-label="label"',
            'data-project-ref-project="pde" data-project-ref-label="label" data-project-ref-page="0"',
            'data-project-ref-project="pde" data-project-ref-label="label" data-project-ref-page="abc"',
            'data-project-ref-title="PDE"',
            'data-project-ref-project="pde" data-project-ref-label="label" data-project-ref-page',
        ):
            with self.subTest(attrs=attrs), self.assertRaisesRegex(NativeImportError, '^invalid-project-ref$'):
                self.import_link(attrs)

    def test_optional_fields_are_omitted_when_empty(self):
        document = self.import_link('data-project-ref-project="pde" data-project-ref-label="label" '
                                    'data-project-ref-title=" " data-project-ref-text=" "')
        self.assertEqual(document['blocks'][0]['projectRef'], {'project': 'pde', 'label': 'label'})


class CrossProjectTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name) / 'catalog.json'
        self.data = {'schema': 1, 'projects': {'p': {
            'title': 'Project One', 'pdf_url': 'https://example.org/doc.pdf',
            'references': {'a': {'page': 2, 'text': 'Theorem 1', 'x': 1.5, 'y': 0},
                           'b': {'page': 2, 'text': 'Lemma 2'},
                           'c': {'page': 3, 'text': 'Proof'}},
            'ambiguous_labels': ['duplicate']}}}
        self.write(self.data)
        self.catalog = load_project_catalog(self.path)
        self.document = {'schemaVersion': 1, 'blocks': [
            self.block('h', 'heading', 'Introduction'),
            self.block('a', 'paragraph', 'Theorem 1 statement', children=[{'anchors': ['a'], 'children': []}]),
            self.block('b', 'paragraph', 'Following text'),
            self.block('h2', 'heading', 'Next heading'),
            self.block('c', 'paragraph', 'Other section', section='s2'),
        ]}

    def write(self, data):
        self.path.write_text(json.dumps(data), encoding='utf-8')

    @staticmethod
    def block(id, kind, text, section='s', children=None):
        return {'id': id, 'sectionID': section, 'kind': kind, 'displayText': text,
                'canonicalText': text, 'anchors': [], 'children': children or []}

    def test_catalog_valid_and_limits(self):
        self.assertEqual(self.catalog.projects['p'].references['a'].x, 1.5)
        with self.assertRaises(CatalogError):
            load_project_catalog(self.path, max_bytes=2)
        with self.assertRaises(CatalogError):
            load_project_catalog(self.temp.name)
        self.path.write_bytes(b'\xff')
        with self.assertRaises(CatalogError):
            load_project_catalog(self.path)
        self.path.write_bytes(b'{')
        with self.assertRaises(CatalogError):
            load_project_catalog(self.path)

    def test_nonstandard_json_constants_rejected_anywhere(self):
        for constant in (float('nan'), float('inf'), float('-inf')):
            for location in ('coordinate', 'root_extra', 'nested_extra'):
                with self.subTest(constant=constant, location=location):
                    data = copy.deepcopy(self.data)
                    if location == 'coordinate':
                        data['projects']['p']['references']['a']['x'] = constant
                    elif location == 'root_extra':
                        data['extra'] = constant
                    else:
                        data['projects']['p']['references']['a']['extra'] = [constant]
                    self.write(data)
                    with self.assertRaises(CatalogError):
                        load_project_catalog(self.path)

    def test_invalid_catalogs(self):
        variants = [[], {'schema': True, 'projects': {}}, {'schema': 2, 'projects': {}},
                    {'schema': 1, 'projects': []}]
        for field, value in [('title', ''), ('pdf_url', ' '), ('references', []),
                             ('ambiguous_labels', ['ok', 2])]:
            data = copy.deepcopy(self.data)
            data['projects']['p'][field] = value
            variants.append(data)
        for field, value in [('page', True), ('page', 0), ('page', 1.5), ('text', ''),
                             ('x', True), ('y', float('inf')), ('x', None), ('x', '1')]:
            data = copy.deepcopy(self.data)
            data['projects']['p']['references']['a'][field] = value
            variants.append(data)
        for data in variants:
            with self.subTest(data=data):
                self.write(data)
                with self.assertRaises(CatalogError):
                    load_project_catalog(self.path)

    def test_explicit_priority_and_ambiguous(self):
        attrs = {'data-project-ref-project': 'p', 'data-project-ref-label': 'a',
                 'data-project-ref-title': 'wrong', 'data-project-ref-page': '99',
                 'data-project-ref-text': 'wrong'}
        result = resolve_cross_project_ref(self.catalog, href='bad', data_attrs=attrs)
        self.assertEqual((result.status, result.resolution_mode, result.page), ('resolved', 'explicit_metadata', 2))
        attrs['data-project-ref-label'] = 'duplicate'
        self.assertEqual(resolve_cross_project_ref(self.catalog, data_attrs=attrs).status, 'ambiguous')
        attrs['data-project-ref-label'] = 'missing'
        self.assertEqual(resolve_cross_project_ref(self.catalog, data_attrs=attrs).status, 'unresolved')
        attrs['data-project-ref-project'] = 'missing'
        self.assertEqual(resolve_cross_project_ref(self.catalog, data_attrs=attrs).status, 'unresolved')

    def test_url_fallbacks(self):
        url = 'https://example.org/doc.pdf#page=2'
        r = resolve_cross_project_ref(self.catalog, href=url, link_text='Theorem\u00a01 of Project\u00a0One')
        self.assertEqual((r.label, r.resolution_mode), ('a', 'url_text_fallback'))
        r = resolve_cross_project_ref(self.catalog, href='https://example.org/doc.pdf#page=3')
        self.assertEqual((r.label, r.resolution_mode), ('c', 'url_page_fallback'))
        r = resolve_cross_project_ref(self.catalog, href=url, link_text='unknown')
        self.assertEqual((r.status, r.resolution_mode, r.candidate_labels), ('ambiguous', 'ambiguous', ('a', 'b')))
        self.assertEqual(r.to_dict()['candidateLabels'], ['a', 'b'])
        for href in ('https://example.org/doc.pdf#page=0', 'https://example.org/doc.pdf', 'other#page=2'):
            self.assertEqual(resolve_cross_project_ref(self.catalog, href=href).status, 'unresolved')
        self.assertEqual(resolve_cross_project_ref(
            self.catalog, href='https://example.org/doc.pdf#page=' + '9' * 5000).status, 'unresolved')
        malformed = 'http://[broken#page=1'
        result = resolve_cross_project_ref(self.catalog, href=malformed)
        self.assertEqual((result.status, result.resolution_mode), ('unresolved', 'unresolved'))
        payload = build_preview_payload(self.catalog, self.document, href=malformed)
        self.assertEqual(payload['resolution']['status'], 'unresolved')
        self.assertEqual(payload['resolution']['resolutionMode'], 'unresolved')
        self.assertFalse(payload['snippet']['matched'])
        json.dumps(payload, allow_nan=False)

    def test_snippet_anchor_text_boundaries_and_truncation(self):
        snippet = extract_block_snippet(self.document, label='a', reference_text='Introduction')
        self.assertEqual((snippet.match_mode, snippet.block_id), ('anchor', 'a'))
        self.assertEqual(snippet.text, 'Theorem 1 statement\n\nFollowing text')
        self.assertEqual(len(snippet.blocks), 2)
        self.assertEqual(extract_block_snippet(self.document, reference_text='Following\u00a0text').block_id, 'b')
        self.assertEqual(len(extract_block_snippet(self.document, label='a', max_blocks=1).blocks), 1)
        snippet = extract_block_snippet(self.document, label='a', max_chars=12)
        self.assertTrue(snippet.truncated)
        self.assertEqual(len(snippet.text), 12)
        self.assertTrue(snippet.text.endswith('...'))
        self.assertFalse(extract_block_snippet(self.document, label='missing').matched)
        self.assertEqual(snippet.to_dict()['blockID'], 'a')
        for limit in (0, 1, 2, 3):
            with self.subTest(max_chars=limit):
                snippet = extract_block_snippet(self.document, label='a', max_chars=limit)
                self.assertTrue(snippet.truncated)
                self.assertEqual(snippet.text, '.' * limit)
        self.document['blocks'][1]['canonicalText'] = 'Canonical only reference'
        snippet = extract_block_snippet(self.document, reference_text='Canonical\u00a0only reference')
        self.assertEqual((snippet.match_mode, snippet.block_id), ('reference_text', 'a'))

    def test_payload(self):
        attrs = {'data-project-ref-project': 'p', 'data-project-ref-label': 'a'}
        payload = build_preview_payload(self.catalog, self.document, data_attrs=attrs)
        self.assertTrue(payload['snippet']['matched'])
        self.assertEqual(payload['resolution']['status'], 'resolved')
        self.assertFalse(build_preview_payload(self.catalog, None, data_attrs=attrs)['snippet']['matched'])
        for href in ('https://example.org/doc.pdf#page=2', 'invalid'):
            payload = build_preview_payload(self.catalog, self.document, href=href)
            self.assertFalse(payload['snippet']['matched'])
            json.dumps(payload, allow_nan=False)


if __name__ == '__main__':
    unittest.main()
