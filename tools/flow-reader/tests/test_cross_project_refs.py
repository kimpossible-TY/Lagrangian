"""Swift-compatible catalog semantics and read-only real HTTP preview contracts."""
from copy import deepcopy
from http.client import HTTPConnection
from http.server import ThreadingHTTPServer
import json
import os
from pathlib import Path
import sys
import tempfile
import threading
import unittest
from unittest.mock import Mock, patch
from urllib.parse import urlencode

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
sys.path.insert(0, str(Path(__file__).resolve().parent))
from flow_reader.compiler.project import Project
from flow_reader.document.native_document import import_accepted_document
from flow_reader.document.sections import split_document
from flow_reader.server.http import handler_for
from flow_reader.server.routing import handler_for_reader, peer_registry
from flow_reader.server.state import ReaderState
from flow_reader.services.cross_project_refs import (
    CrossProjectCatalog, CrossProjectPreviewService, MAX_CATALOG_BYTES,
    extract_snippet, preview_query, target_url,
)
from flow_reader.services.home_account import HomeAccount
from flow_reader.services.homepage import HomeInventory
from test_homepage import FakeAuth, FakeProvider, FakeManager


PDF = 'https://example.test/book.pdf'


def catalog_data():
    return {'schema': 1, 'projects': {'book': {'title': 'Book Title', 'pdf_url': PDF,
        'references': {'theorem': {'page': 2, 'text': 'Theorem 1', 'x': 3.5, 'y': None},
                       'duplicate': {'page': 3, 'text': 'Duplicate'}},
        'ambiguous_labels': ['duplicate', 'unpublished']}}}


def imported(html, **kwargs):
    return import_accepted_document(split_document('<html><body>' + html + '</body></html>', 'r1', **kwargs),
        document_id='fixture', service_id='offline', generation=0).document


class Fixture(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory(prefix='cross-project-')
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.packages = self.root / 'packages'
        self.path = self.packages / 'local/project-references/0.1.0/projects.json'
        self.path.parent.mkdir(parents=True)
        self.write_catalog()

    def write_catalog(self, data=None):
        self.path.write_text(json.dumps(catalog_data() if data is None else data))

    def state(self, name='origin', html=None):
        root = self.root / name
        root.mkdir(exist_ok=True)
        (root / 'main.typ').write_text('Source remains untouched')
        state = ReaderState(Project(root, Path('main.typ'), self.packages), root / 'out', None, False)
        self.addCleanup(state.close)
        if html is not None:
            state.bundle = split_document('<html><body>' + html + '</body></html>', 'r1')
            state.revision = 'r1'
        return state


class CatalogTests(Fixture):
    def load(self):
        return CrossProjectCatalog.load(self.packages)

    def test_explicit_resolution_and_ambiguity_precedence(self):
        catalog = self.load()
        result = catalog.resolve(project_key='book', label='theorem')
        self.assertEqual(result['status'], 'unique')
        self.assertEqual((result['projectKey'], result['label'], result['refText']), ('book', 'theorem', 'Theorem 1'))
        for label in ('duplicate', 'unpublished'):
            self.assertEqual(catalog.resolve(project_key='book', label=label), {'status': 'ambiguous', 'candidates': []})
        for project, label in [('Book', 'theorem'), ('book', 'missing'), ('missing', 'theorem')]:
            self.assertEqual(catalog.resolve(project_key=project, label=label)['status'], 'unresolved')
        self.assertEqual(catalog.resolve(project_key='missing', label='theorem', href=PDF+'#page=2')['status'], 'unresolved')

    def test_pdf_resolution_exact_text_title_suffix_and_page(self):
        catalog = self.load()
        for text in (None, 'Theorem 1', 'Theorem 1 of Book Title'):
            self.assertEqual(catalog.resolve(href=PDF+'#page=2', link_text=text)['status'], 'unique')
        self.assertEqual(catalog.resolve(href=PDF+'#page=3')['status'], 'ambiguous')
        for href, text in [(PDF+'#page=0', None), (PDF+'#theorem', None), (PDF, None),
                           (PDF+'#page=2&x=1', None), (PDF+'#page=2', 'theorem 1'),
                           ('https://different.test/book.pdf#page=2', None), ('http://[broken', None)]:
            self.assertEqual(catalog.resolve(href=href, link_text=text)['status'], 'unresolved')

    def test_multiple_projects_and_bounded_sorted_candidates(self):
        data = catalog_data()
        for index in range(40):
            data['projects'][f'book-{index:02}'] = deepcopy(data['projects']['book'])
        self.write_catalog(data)
        result = self.load().resolve(href=PDF+'#page=2')
        self.assertEqual(result['status'], 'ambiguous')
        self.assertEqual(len(result['candidates']), 32)
        self.assertEqual(result['candidates'][0]['projectKey'], 'book')
        self.assertTrue(all(len(value) <= 1024 for c in result['candidates'] for value in c.values() if isinstance(value, str)))

    def test_strict_schema_and_no_filesystem_paths_in_errors(self):
        changes = [({'schema': True}), ({'schema': 2}), ({'projects': []})]
        invalid = [dict(catalog_data(), **change) for change in changes]
        for field, value in [('title', 1), ('pdf_url', []), ('references', []), ('ambiguous_labels', 'x'),
                             ('ambiguous_labels', [3])]:
            data = catalog_data()
            data['projects']['book'][field] = value
            invalid.append(data)
        for entry in ({'page': True, 'text': 'x'}, {'page': 0, 'text': 'x'}, {'page': 2**63, 'text': 'x'},
                      {'page': 1, 'text': 2}, {'page': 1, 'text': 'x', 'x': True},
                      {'page': 1, 'text': 'x', 'x': float('inf')}):
            data = catalog_data()
            data['projects']['book']['references']['theorem'] = entry
            invalid.append(data)
        for data in invalid:
            with self.subTest(data=data):
                self.write_catalog(data)
                with self.assertRaises(ValueError) as raised:
                    self.load()
                self.assertNotIn(str(self.root), str(raised.exception))
        for raw in ('{"schema":1,"schema":1,"projects":{}}', '[]', '{',
                    '{"schema":1,"projects":{},"ignored":NaN}', '{"schema":1,"projects":{"x":{"title":"\\ud800"}}}'):
            self.path.write_text(raw)
            with self.assertRaises(ValueError):
                self.load()

    def test_catalog_exact_16_mib_and_custom_bounds(self):
        raw = self.path.read_bytes()
        self.path.write_bytes(raw + b' ' * (MAX_CATALOG_BYTES - len(raw)))
        self.assertEqual(self.load().resolve(project_key='book', label='theorem')['status'], 'unique')
        with self.path.open('ab') as stream:
            stream.write(b' ')
        with self.assertRaises(ValueError):
            self.load()
        self.write_catalog()
        for size in (0, -1, True, MAX_CATALOG_BYTES+1, 2):
            with self.assertRaises(ValueError):
                CrossProjectCatalog.load(self.packages, size)

    def test_symlink_traversal_and_nonregular_files_rejected(self):
        outside = self.root / 'private.json'
        outside.write_text(json.dumps(catalog_data()))
        self.path.unlink()
        self.path.symlink_to(outside)
        with self.assertRaises(ValueError) as raised:
            self.load()
        self.assertNotIn(str(outside), str(raised.exception))
        self.path.unlink()
        self.path.mkdir()
        with self.assertRaises(ValueError):
            self.load()
        self.path.rmdir()
        self.path.parent.rename(self.path.parent.with_name('saved'))
        self.path.parent.symlink_to(self.root, target_is_directory=True)
        with self.assertRaises(ValueError):
            self.load()

    def test_missing_catalog_and_safe_internal_symlink(self):
        self.path.unlink()
        with self.assertRaises(ValueError):
            self.load()
        internal = self.packages / 'internal.json'
        internal.write_text(json.dumps(catalog_data()))
        self.path.symlink_to(internal)
        self.assertIn('book', self.load().projects)

    def test_symlinks_to_package_root_and_cycles_have_fixed_errors(self):
        self.path.unlink()
        for destination in (self.packages, self.path):
            with self.subTest(destination=destination):
                self.path.symlink_to(destination)
                try:
                    with self.assertRaisesRegex(ValueError, '^Project reference catalog unavailable or invalid$'):
                        self.load()
                finally:
                    self.path.unlink()

    def test_unsafe_pdf_is_never_exposed(self):
        for value in ('file:///private/document.pdf', '/private/document.pdf', 'javascript:alert(1)'):
            data = catalog_data()
            data['projects']['book']['pdf_url'] = value
            self.write_catalog(data)
            self.assertIsNone(self.load().resolve(project_key='book', label='theorem')['pdfUrl'])

    def test_non_utf8_catalog_rejected(self):
        self.path.write_bytes(json.dumps(catalog_data()).encode('utf-16'))
        with self.assertRaises(ValueError):
            self.load()

    def test_missing_required_fields_and_future_fields(self):
        for field in ('title', 'pdf_url', 'references', 'ambiguous_labels'):
            data = catalog_data()
            del data['projects']['book'][field]
            self.write_catalog(data)
            with self.subTest(field=field), self.assertRaises(ValueError):
                self.load()
        data = catalog_data()
        data['future'] = {'format': 'extension'}
        data['projects']['book']['future'] = True
        self.write_catalog(data)
        self.assertEqual(self.load().resolve(project_key='book', label='theorem')['status'], 'unique')

    def test_fifo_and_directory_replacement_cannot_escape_package_root(self):
        self.path.unlink()
        os.mkfifo(self.path)
        with self.assertRaises(ValueError):
            self.load()  # O_NONBLOCK must prevent waiting for a FIFO writer.
        self.path.unlink()
        self.write_catalog()
        outside = self.root / 'outside'
        outside.mkdir()
        (outside / 'projects.json').write_text(json.dumps(catalog_data()))
        real_open = os.open
        replaced = False

        def swap_directory(path, flags, **kwargs):
            nonlocal replaced
            if path == '0.1.0' and not replaced:
                replaced = True
                self.path.parent.rename(self.path.parent.with_name('saved'))
                self.path.parent.symlink_to(outside, target_is_directory=True)
            return real_open(path, flags, **kwargs)

        with patch('flow_reader.services.cross_project_refs.os.open', side_effect=swap_directory):
            with self.assertRaisesRegex(ValueError, '^Project reference catalog unavailable or invalid$'):
                self.load()
        self.assertTrue(replaced)


class SnippetTests(unittest.TestCase):
    def test_canonical_nested_anchor_and_text_fallback(self):
        doc = imported('<h2>Introduction</h2><p>Before</p><p><strong id="theorem">Theorem 1</strong> &amp; result</p>'
                       '<p>Proof</p><h3>Next</h3><p>Excluded</p>')
        result = extract_snippet(doc, 'theorem', 'Before')
        self.assertEqual(result, {'text': 'Theorem 1 & result\n\nProof', 'truncated': False})
        self.assertEqual(extract_snippet(doc, 'absent', '  THEOREM   1 ') , result)
        self.assertEqual(extract_snippet(doc, doc['blocks'][2]['id']), result)
        self.assertIsNone(extract_snippet(doc, 'absent', 'missing'))
        self.assertNotIn('<strong', result['text'])

    def test_labels_and_section_boundary(self):
        doc = imported('<h2>Topic</h2><p data-flow-label="theorem">Theorem 1</p><p>Next block</p>', max_blocks=1)
        self.assertEqual(extract_snippet(doc, 'theorem'), {'text': 'Theorem 1', 'truncated': False})

    def test_character_and_block_truncation_and_heading_stop(self):
        doc = imported('<p id="start">' + 'x'*601 + '</p>')
        result = extract_snippet(doc, 'start')
        self.assertEqual(result, {'text': 'x'*597+'...', 'truncated': True})
        self.assertEqual(extract_snippet(doc, 'start', max_chars=2)['text'], 'xx')
        self.assertIsNone(extract_snippet(doc, 'start', max_blocks=0))
        self.assertIsNone(extract_snippet(doc, 'start', max_chars=0))
        doc = imported('<p id="start">A</p>' + '<p>B</p>'*4)
        self.assertEqual(extract_snippet(doc, 'start'), {'text': 'A\n\nB\n\nB\n\nB', 'truncated': True})
        doc = imported('<p id="start">A</p>' + '<p>B</p>'*3+'<h3>Stop</h3>')
        self.assertFalse(extract_snippet(doc, 'start')['truncated'])

    def test_display_preferred_and_canonical_fallback(self):
        doc = imported('<p id="start">Canonical</p>')
        doc['blocks'][0]['displayText'] = ' Display '
        self.assertEqual(extract_snippet(doc, None, 'Canonical')['text'], 'Display')
        doc['blocks'][0]['displayText'] = ' '
        self.assertEqual(extract_snippet(doc, 'start')['text'], 'Canonical')

    def test_canonical_math_and_literal_markup_remain_plain_text(self):
        doc = imported('<p id="theorem">Theorem &lt;img src=x onerror=alert(1)&gt; '
                       '<math><mi>x</mi><mo>+</mo><mn>1</mn></math></p>')
        result = extract_snippet(doc, 'theorem')
        self.assertEqual(result, {'text': 'Theorem <img src=x onerror=alert(1)> x+1', 'truncated': False})
        # Literal source text may resemble markup. The contract carries text,
        # never the canonical tree's serialized MathML/HTML payload.
        self.assertNotIn('<math', result['text'])


class PreviewTests(Fixture):
    def test_metadata_bounds_do_not_change_lookup_or_snippet_match(self):
        data = catalog_data()
        long_key, long_title = 'k'*1025, 't'*1025
        project = data['projects'].pop('book')
        project['title'] = long_title
        project['references']['theorem']['text'] = 'x'*1025
        data['projects'][long_key] = project
        self.write_catalog(data)
        origin, target = self.state(), self.state('target', '<p>'+'x'*1024+'</p>')
        lookup = Mock(return_value=(target, '/d/book/'))
        result = CrossProjectPreviewService(origin, lookup).preview(href=PDF+'#page=2')
        lookup.assert_called_once_with(long_key, long_title)
        self.assertEqual(len(result['projectKey']), 1024)
        self.assertIsNone(result['snippet'])  # Never match just a truncated text prefix.

    def test_unmounted_uncompiled_compiling_and_failed_import_keep_unique_metadata(self):
        origin, target = self.state(), self.state('book')
        service = CrossProjectPreviewService(origin)
        result = service.preview(project_key='book', label='theorem')
        self.assertEqual(result['status'], 'unique')
        self.assertIsNone(result['snippet'])
        self.assertIsNone(result['targetUrl'])
        service = CrossProjectPreviewService(origin, peer_registry({'book': target}))
        result = service.preview(project_key='book', label='theorem')
        self.assertEqual(result['targetUrl'], '/d/book/#theorem')
        self.assertIsNone(result['snippet'])
        target.bundle = split_document('<html><body><p id="theorem">Accepted</p></body></html>', 'r1')
        target.revision = 'r1'
        result = service.preview(project_key='book', label='theorem')
        self.assertEqual(result['snippet'], 'Accepted')
        target.compiling = True
        self.assertIsNone(service.preview(project_key='book', label='theorem')['snippet'])
        target.compiling = False
        for html in ('<p>Missing match</p>', '<script>unsafe</script>'):
            target.bundle = split_document('<html><body>'+html+'</body></html>', 'r1')
            result = service.preview(project_key='book', label='theorem')
            self.assertEqual(result['status'], 'unique')
            self.assertIsNone(result['snippet'])
            self.assertEqual(result['targetUrl'], '/d/book/#theorem')
        target.bundle = split_document('<html><body><p id="theorem">Wrong revision</p></body></html>', 'r2')
        self.assertIsNone(service.preview(project_key='book', label='theorem')['snippet'])
        target.revision = 'r2'
        with patch('flow_reader.services.cross_project_refs.import_accepted_document',
                   side_effect=ValueError('private import failure: '+str(self.root))):
            result = service.preview(project_key='book', label='theorem')
        self.assertEqual((result['status'], result['snippet'], result['targetUrl']),
                         ('unique', None, '/d/book/#theorem'))
        self.assertNotIn(str(self.root), json.dumps(result))
        self.assertEqual((origin.project.root/'main.typ').read_text(), 'Source remains untouched')

    def test_peer_registry_aliases_explicit_precedence_and_duplicates(self):
        one, two = self.state('Book_Title'), self.state('other')
        docs = {'first': one, 'second': two}
        lookup = peer_registry(docs, [{'id': 'first', 'title': 'Book Title'},
                                     {'id': 'second', 'projectRefKey': 'book'}])
        self.assertIs(lookup('book', 'Book Title')[0], two)
        self.assertIs(lookup('first', '')[0], one)
        self.assertIs(lookup('book-title', '')[0], one)
        self.assertIsNone(lookup('other', ''))
        self.assertIsNone(peer_registry(docs, [{'id': 'first', 'projectRefKey': 'book'},
                                              {'id': 'second', 'projectRefKey': 'book'}])('book', ''))
        self.assertIsNone(peer_registry(docs, [{'id': 'first', 'title': 'Same'},
                                              {'id': 'second', 'title': 'Same'}])('same', ''))

    def test_target_url_restricts_origin_route_and_encodes_anchor(self):
        self.assertEqual(target_url('/d/book/', 'a#/? b'), '/d/book/#a%23%2F%3F%20b')
        self.assertEqual(target_url('https://reader.test/d/book/', 'a', 'https://reader.test/'),
                         'https://reader.test/d/book/#a')
        for route in ('javascript:alert(1)', 'file:///d/book/', '//evil.test/d/book/',
                      '///d/book/', '////d/book/',
                      'https://evil.test/d/book/', 'https://reader.test/d/book/', '/d/../book/',
                      '/d/book/?x=1', '/d/book/#anchor', '/d/%62ook/', '/private/book/', '/d/book/\\x'):
            self.assertIsNone(target_url(route, 'a'))
        for route in ('https://reader.test/d/book/?', 'https://reader.test/d/book/#',
                      'https://user@reader.test/d/book/', 'https://reader.test:bad/d/book/',
                      'http://reader.test/d/book/', 'https://reader.test/d/book/\x7f'):
            self.assertIsNone(target_url(route, 'a', 'https://reader.test/'))
        self.assertEqual(target_url('http://127.0.0.1:8769/d/book/', 'a', 'http://127.0.0.1:8769/'),
                         'http://127.0.0.1:8769/d/book/#a')
        origin, target = self.state(), self.state('target', '<p id="theorem">Secret</p>')
        service = CrossProjectPreviewService(origin, lambda *_: (target, 'file:///private'))
        result = service.preview(project_key='book', label='theorem')
        self.assertIsNone(result['targetUrl'])
        self.assertIsNone(result['snippet'])

    def test_service_and_query_failures_are_bounded_and_non_sensitive(self):
        state = self.state()
        self.path.write_text('not json')
        result = CrossProjectPreviewService(state).preview(project_key='book', label='theorem')
        self.assertEqual(result['status'], 'unresolved')
        self.assertNotIn(str(self.root), json.dumps(result))
        self.assertEqual(state.public()['viewer'], {'name': 'Lagrangian Web Viewer', 'crossProject': False})
        self.assertEqual(preview_query('href=x&text=y'), {'href': 'x', 'link_text': 'y'})
        self.assertEqual(preview_query('project='+('a'*1024)+'&label=x')['label'], 'x')


class HTTPTests(Fixture):
    def serve(self, handler):
        server = ThreadingHTTPServer(('127.0.0.1', 0), handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        self.addCleanup(lambda: (server.shutdown(), server.server_close(), thread.join()))
        return server

    def request(self, server, path, method='GET', headers=None):
        connection = HTTPConnection('127.0.0.1', server.server_port, timeout=3)
        connection.request(method, path, headers=headers or {})
        response = connection.getresponse()
        result = response.status, response.read()
        connection.close()
        return result

    def test_static_only_native_and_preview_unavailable(self):
        with patch('flow_reader.server.native_reader.NativeReaderService') as native, \
             patch('flow_reader.server.native_pages.NativePageService') as pages:
            server = self.serve(handler_for(None))
        native.assert_not_called()
        pages.assert_not_called()
        self.assertEqual(self.request(server, '/reader.js')[0], 200)
        self.assertEqual(self.request(server, '/assets.json')[0], 404)
        self.assertEqual(self.request(server, '/../flow_reader/server/state.py')[0], 404)
        for route in ('/api/native-document', '/api/native-pages', '/api/native-assets/x',
                      '/api/cross-project/preview?project=book&label=theorem', '/api/state'):
            self.assertEqual(self.request(server, route)[0], 503)
        self.assertEqual(self.request(server, '/api/native-action', 'POST')[0], 503)

    def test_standalone_and_routed_preview_state_and_read_only_fallback(self):
        origin, target = self.state(), self.state('target', '<p id="theorem">Accepted theorem</p>')
        standalone = self.serve(handler_for(origin))
        inventory = HomeInventory(FakeManager(), loaded=([], [], {'source': origin, 'book': target}))
        self.addCleanup(inventory.close)
        account = HomeAccount(FakeAuth(self.root), FakeProvider())
        routed = self.serve(handler_for_reader({'source': origin, 'book': target}, inventory, account, capability='proof'))
        for server, prefix in ((standalone, '/'), (routed, '/d/source/')):
            status, raw = self.request(server, prefix+'api/state')
            self.assertEqual(status, 200)
            self.assertEqual(json.loads(raw)['viewer'], {'name': 'Lagrangian Web Viewer', 'crossProject': True})
            for query in ({'project': 'book', 'label': 'theorem'}, {'href': PDF+'#page=2', 'text': 'Theorem 1'}):
                status, raw = self.request(server, prefix+'api/cross-project/preview?'+urlencode(query))
                result = json.loads(raw)
                self.assertEqual(status, 200)
                self.assertEqual(result['status'], 'unique')
                self.assertEqual(result['snippet'], 'Accepted theorem' if server is routed else None)
                self.assertEqual(result['targetUrl'], '/d/book/#theorem' if server is routed else None)
                self.assertEqual(result['pdfUrl'], PDF)
                self.assertNotIn(str(self.root), raw.decode())
            for label, expected in [('missing', 'unresolved'), ('duplicate', 'ambiguous')]:
                status, raw = self.request(server, prefix+'api/cross-project/preview?project=book&label='+label)
                self.assertEqual((status, json.loads(raw)['status']), (200, expected))
            for fragment in ('#', '#unexpected'):
                self.assertEqual(self.request(server, prefix+'api/cross-project/preview?href=x'+fragment)[0], 400)
            self.assertEqual(self.request(server, prefix+'api/cross-project/preview?href=x&href=y')[0], 400)
            self.assertEqual(self.request(server, prefix+'api/cross-project/preview?href='+('x'*1025))[0], 400)
        target.bundle = None
        status, raw = self.request(routed, '/d/source/api/cross-project/preview?project=book&label=theorem')
        result = json.loads(raw)
        self.assertEqual((status, result['status'], result['snippet'], result['targetUrl']),
                         (200, 'unique', None, '/d/book/#theorem'))
        self.assertIsNone(origin._paragraph_chat)
        self.assertIsNone(target._paragraph_chat)

    def test_http_rejects_malformed_duplicate_unknown_and_oversized_queries(self):
        server = self.serve(handler_for(self.state()))
        queries = ['', 'project=book', 'label=theorem', 'href=', 'project=&label=x', 'href=x&url=y',
                   'project=book&label=x&href=y', 'href=x&href=y', 'href=x&text=y&text=z',
                   'href=%ZZ', 'href=%FF', 'href=%00', 'href=x&', 'href=x&text',
                   'href=x&text=%7F', 'href=x&text='+('a'*1025),
                   'project='+('a'*1025)+'&label=x',
                   'project=book&label='+('a'*1025), 'href='+('%F0%9F%90%88'*1025)]
        for query in queries:
            with self.subTest(query=query[:60]):
                status, raw = self.request(server, '/api/cross-project/preview?'+query)
                self.assertEqual(status, 400, raw)
                self.assertNotIn(str(self.root), raw.decode())
        self.assertEqual(self.request(server, '/api/cross-project/preview?href=x',
                                     headers={'Host': 'evil.example'})[0], 421)

    def test_runtime_injects_configured_peer_registry_without_compiling(self):
        from flow_reader.server.cli import ReaderRuntime, argument_parser
        origin, target = self.state(), self.state('target', '<p id="theorem">Runtime target</p>')
        states = {'source': origin, 'target': target}
        manager = Mock()
        manager.shared_settings.return_value = {'port': 0}
        manager.parent_profiles.return_value = [
            {'id': key, 'name': title, 'port': 31001+index}
            for index, (key, title) in enumerate((('source', 'Source'), ('target', 'Book Title')))]
        manager.profiles.return_value = [
            {'id': key, 'parentID': key, 'name': key+' Reader', 'port': 0,
             'root': str(state.project.root), **({'projectRefKey': 'book'} if key == 'target' else {})}
            for key, state in states.items()]
        manager.document_arguments.side_effect = lambda p: ['python', 'serve.py', '--root', p['root'],
            '--original-url', 'https://paged.example/', '--port', '0']
        options = argument_parser().parse_args(['--managed', '--chat-data', str(self.root/'private')])
        def factory(plan, _provider, _directory):
            return origin if plan.root == origin.project.root else target
        with patch('flow_reader.server.cli.ChatAuth', FakeAuth):
            runtime = ReaderRuntime(options, manager, state_factory=factory)
        self.addCleanup(runtime.close)
        self.assertIs(runtime.peer_lookup('book', 'Book Title')[0], target)
        with patch.object(origin, 'compile') as compile_origin, patch.object(target, 'compile') as compile_target:
            # Start only the HTTP listener: previews must not invoke either compiler.
            thread = threading.Thread(target=runtime.admin.serve_forever, daemon=True)
            thread.start()
            runtime.threads.append((runtime.admin, thread))
            status, raw = self.request(runtime.admin,
                '/d/source/api/cross-project/preview?project=book&label=theorem')
            self.assertEqual(status, 200)
            self.assertEqual(json.loads(raw)['snippet'], 'Runtime target')
            self.assertEqual(json.loads(raw)['targetUrl'], '/d/target/#theorem')
            compile_origin.assert_not_called()
            compile_target.assert_not_called()
            manager.control.assert_not_called()


if __name__ == '__main__':
    unittest.main()
