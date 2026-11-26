"""NA04: owned temporary HTTP + real prebuilt compiler + injected native services.
No managed services, real provider/account, GUI activation or Rust builds.
"""
import copy
import dataclasses
import hashlib
from http.client import HTTPConnection
from http.server import ThreadingHTTPServer
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from urllib.parse import urlencode
from uuid import uuid4
from types import SimpleNamespace
from unittest.mock import patch

REPO = Path(__file__).resolve().parents[3]
DEV = Path('/Volumes/devSSD/Developer/lagrangian-native-20261117')
CLOSURE = Path(os.environ["NA09_ROOT"]).resolve() if os.environ.get("NA09_ROOT") else None
EVIDENCE = CLOSURE if CLOSURE else DEV / 'test-output/services/adoption-v3'
ISOLATED = CLOSURE if CLOSURE else DEV
OUT = Path(os.environ['NA04_OUTPUT']).resolve() if os.environ.get('NA04_OUTPUT') else EVIDENCE / os.environ.get('NA04_RUN', 'services-' + str(time.time_ns()))
if not (OUT.resolve().is_relative_to(EVIDENCE) or OUT.resolve().is_relative_to(DEV / 'test-output/services')) or OUT.exists():
    raise RuntimeError('NA04 evidence directory must be new under adoption-v3; preserve historical bytes')
OUT.mkdir(parents=True, exist_ok=True)
for name, value in {'TMPDIR': ISOLATED / 'tmp/services', 'CLANG_MODULE_CACHE_PATH': ISOLATED / 'cache/services/clang',
                    'SWIFT_MODULECACHE_PATH': ISOLATED / 'cache/services/swift'}.items():
    value.mkdir(parents=True, exist_ok=True)
    os.environ[name] = str(value)
tempfile.tempdir = os.environ['TMPDIR']
sys.dont_write_bytecode = True
sys.path.insert(0, str(REPO / 'tools/flow-reader'))
sys.path.insert(0, str(REPO / 'tools/flow-reader/tests'))
from flow_reader.compiler.execution import local_compile
from flow_reader.compiler.project import Project
from flow_reader.compiler.inputs import input_fingerprint, source_signature
from flow_reader.document.sections import split_document
from flow_reader.server.state import ReaderState
from flow_reader.server.http import handler_for
from flow_reader.server.native_reader import service_id
from flow_reader.server.routing import handler_for_reader
from flow_reader.services.home_account import HomeAccount
from flow_reader.services.homepage import HomeInventory
from flow_reader.services.paragraph_chat import ParagraphChat
from flow_reader.services.manager import ReaderManager
from test_homepage import FakeAuth, FakeProvider, FakeManager

COMMANDS = []
RUN = str(time.time_ns())

def save(name, value):
    (OUT / name).write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')

def digest_bytes(data):
    return hashlib.sha256(data).hexdigest()

def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def command(argv, *, timeout=120):
    started = time.monotonic()
    result = subprocess.run(list(map(str, argv)), cwd=REPO, capture_output=True, text=True, timeout=timeout)
    COMMANDS.append({'argv': list(map(str, argv)), 'exit': result.returncode, 'seconds': time.monotonic()-started,
                     'stdout': result.stdout, 'stderr': result.stderr,
                     'environment': {k: os.environ[k] for k in ('TMPDIR', 'CLANG_MODULE_CACHE_PATH', 'SWIFT_MODULECACHE_PATH')}})
    save('commands.json', COMMANDS)
    save('commands-' + RUN + '.json', COMMANDS)
    return result


class FixtureProvider:
    """Deterministic injected provider; no token/account/network inference."""
    def __init__(self, auth):
        self.auth, self.calls, self.questions = auth, [], []
        self.started, self.release = threading.Event(), threading.Event()
        self.stall = False
    def models(self):
        return [{'id': 'fixture-model', 'label': 'Fixture model'}]
    def run(self, **options):
        self.calls.append(options['context'])
        self.questions.append(json.loads(options['history'][-1]['content'])['question'])
        self.started.set()
        if self.stall:
            while not self.release.wait(.02):
                if options['cancelled']():
                    return
        yield {'type': 'delta', 'text': '**Fixture answer**\n$$\nx^2\n$$\n<script>literal</script>'}


class NativeServiceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.work = Path(tempfile.mkdtemp(prefix='native-services-', dir=ISOLATED / 'tmp/services'))
        compiler = Path(shutil.which('typst') or '/missing')
        if not compiler.is_file() or not shutil.which('sandbox-exec'):
            raise RuntimeError('prebuilt typst and sandbox-exec required; missing is failure')
        cls.cache = ISOLATED / 'cache/services/typst-packages'
        if not cls.cache.exists():
            shutil.copytree(Path(os.environ['FLOW_TEST_PACKAGE_CACHE']) if os.environ.get('FLOW_TEST_PACKAGE_CACHE') else Path.home() / 'Library/Caches/typst/packages', cls.cache)
        os.environ['TYPST_PACKAGE_CACHE_PATH'] = str(cls.cache)
        wrapper = OUT / 'offline-typst'
        # Inputs are immutable even during source-mapping proof compilation.
        profile = '(version 1)(allow default)(deny network*)' + ''.join(
            '(deny file-write* (subpath ' + json.dumps(str(p)) + '))' for p in (REPO, cls.cache))
        wrapper.write_text('#!' + sys.executable + '\nimport json,os,sys\n' +
            'with open(' + repr(str(OUT / 'compiler-argv.jsonl')) + ',"a") as f: f.write(json.dumps(sys.argv[1:])+"\\n")\n' +
            'import subprocess,time\nstart=time.monotonic()\nargs=["/usr/bin/sandbox-exec","-p",' + repr(profile) + ',' + repr(str(compiler)) + '] + sys.argv[1:]\nr=subprocess.run(args)\n' + 'with open(' + repr(str(OUT / 'compiler-executions.jsonl')) + ',"a") as f: f.write(json.dumps({"argv":args,"exit":r.returncode,"seconds":time.monotonic()-start})+"\\n")\nsys.exit(r.returncode)\n')
        wrapper.chmod(0o700)
        cls.wrapper = wrapper
        root = cls.work / 'compiler-source'; root.mkdir()
        cls.raw_source = ('First paragraph keeps its own question.\n\nA second independent paragraph.\n\n$alpha + beta$\n\n'
            '#let shape = rect(width: 20pt, height: 10pt, fill: blue)\n'
            '#figure(context { if target() == "html" { html.frame(shape) } else { shape } }, caption: [Fixture vector])\n')
        (root / 'main.typ').write_text(cls.raw_source)
        # Use the real ReaderState compile/accept path with default map_sources=True.
        project = Project(root, Path('main.typ'), REPO / 'tools/flow-reader/packages', compiler=str(wrapper))
        state = ReaderState(project, cls.work / 'compiler-output', '', False)
        state.compile()
        save('compiler-report.json', state.report)
        if not state.revision or not state.report.get('contentGatePassed'):
            raise RuntimeError('actual prebuilt accepted compilation failed: ' + json.dumps(state.report))
        cls.real_html = state.document.decode()
        cls.real_report = json.loads((state.output / 'report.json').read_text())
        cls.real_dependencies = set(state.accepted_dependencies)
        (OUT / 'compiler-document.html').write_bytes(state.document)
        state.close()
        save('provenance.json', {'base': command(['git', 'rev-parse', 'HEAD']).stdout.strip(),
            'host': platform.platform(), 'python': sys.version, 'compiler': str(compiler), 'compilerSHA256': digest(compiler),
            'compilerVersion': command([compiler, '--version']).stdout.strip(),
            'swiftVersion': command(['swiftc', '--version']).stdout.strip(),
            'swiftCompilerSHA256': digest(command(['xcrun', '--find', 'swiftc']).stdout.strip()),
            'sdk': command(['xcrun', '--show-sdk-path']).stdout.strip(),
            'fixtureSHA256': hashlib.sha256(cls.raw_source.encode()).hexdigest(),
            'oracle': 'hand-authored literal source and exact formula, fake provider; no live provider/GUI/macOS13 runtime claim',
            'packageHashes': {str(p.relative_to(project.packages)): digest(p) for p in project.packages.rglob('*') if p.is_file()},
            'sourceMapping': 'actual compiler default map_sources=True; tested exact math excerpt separately'})
        cls.binary = OUT / 'ServiceTests'
        manifest = json.loads((REPO / 'apps/macos/sources.json').read_text())
        sources = [REPO / 'apps/macos' / n for n in [*[n for n in manifest['core'] if n != 'CLI.swift'], *manifest['native'], 'NativeReaderWindowController.swift']]
        build = command(['swiftc', '-parse-as-library', '-swift-version', '5', '-warnings-as-errors', '-target', 'arm64-apple-macosx13.0',
            '-module-cache-path', os.environ['SWIFT_MODULECACHE_PATH'], *sources, REPO / 'tests/flow-app/native-reader-app/ServiceTests.swift', '-o', cls.binary])
        if build.returncode:
            raise RuntimeError('Swift build failed: ' + build.stderr)
        save('source-hashes.json', {str(p.relative_to(REPO)): digest(p) for p in sources + [Path(__file__), REPO / 'tests/flow-app/native-reader-app/ServiceTests.swift', REPO / 'tools/flow-reader/flow_reader/server/native_reader.py', REPO / 'tools/flow-reader/flow_reader/server/http.py']})

    def setUp(self):
        self.work = self.__class__.work / self._testMethodName; self.work.mkdir()
        self.root = self.work / 'source'; self.root.mkdir()
        self.entry = self.root / 'main.typ'; self.entry.write_text(self.raw_source)
        project = Project(self.root, Path('main.typ'), REPO / 'tools/flow-reader/packages', compiler=str(self.wrapper))
        self.state = ReaderState(project, self.work / 'output', '', False)
        # Source-map paths/hashes are recompiled for this exact isolated source.
        self.state.compile()
        self.assertIsNotNone(self.state.revision, self.state.report)
        self.auth = FakeAuth(self.work)
        self.provider = FixtureProvider(self.auth)
        self.state._paragraph_chat = ParagraphChat(self.state, directory=self.work / 'chat', provider=self.provider)
        self.addCleanup(self.state.close)
        self.addCleanup(self.provider.release.set)
        self.root_server = self.serve(handler_for(self.state))
        self.inventory = HomeInventory(FakeManager()); self.inventory.observe(); self.addCleanup(self.inventory.close)
        self.shared = self.serve(handler_for_reader({'first': self.state}, self.inventory,
            HomeAccount(self.auth, self.provider), capability='test-proof'))
        self.context = {'documentID': self.state.document_id, 'serviceID': service_id(self.state.focus.service),
            'revision': self.state.revision, 'schemaVersion': 1, 'capabilities': ['image-layout-v1', 'semantic-tree-v1'],
            'generation': 1, 'requestID': str(uuid4()), 'viewID': str(uuid4())}
        code, raw, headers = self.get_document()
        self.assertEqual(code, 200, raw)
        self.document = json.loads(raw)
        self.context['inputID'] = headers['X-Native-Input-ID']

    def serve(self, handler):
        class Quiet(handler):
            def log_message(self, *_args): pass
        server = ThreadingHTTPServer(('127.0.0.1', 0), Quiet)
        thread = threading.Thread(target=server.serve_forever, daemon=True); thread.start()
        self.addCleanup(lambda: (server.shutdown(), server.server_close(), thread.join()))
        return server

    def request(self, path, *, body=None, headers=None, shared=False):
        server = self.shared if shared else self.root_server
        origin = f'http://127.0.0.1:{server.server_port}'
        fields = {'Host': origin.split('//')[1], 'Origin': origin, 'Content-Type': 'application/json'}
        fields.update(headers or {})
        for k in list(fields):
            if fields[k] is None: del fields[k]
        conn = HTTPConnection('127.0.0.1', server.server_port, timeout=35)
        conn.request('GET' if body is None else 'POST', path, json.dumps(body) if body is not None else None, fields)
        response = conn.getresponse(); result = response.status, response.read(), dict(response.getheaders()); conn.close()
        return result

    def get_document(self, context=None, *, shared=False, prefix=None, headers=None):
        fields = {k: v for k, v in (context or self.context).items() if k != 'inputID'}
        fields['capabilities'] = ','.join(fields['capabilities'])
        return self.request((prefix if prefix is not None else '/d/first/' if shared else '/') + 'api/native-document?' + urlencode(fields), shared=shared, headers=headers)

    def selection(self, index=0, exact=None):
        block = self.document['blocks'][index]
        text = block['canonicalText'] if exact is None else exact
        start = block['canonicalText'].index(text)
        unit = lambda s: len(s.encode('utf-16-le')) // 2
        return {'ticket': str(uuid4()), 'fragments': [{'blockID': block['id'], 'rangeUTF16': [unit(block['canonicalText'][:start]), unit(block['canonicalText'][:start+len(text)])], 'exact': text}]}

    def action(self, operation, **fields):
        return self.request('/api/native-action', body={**self.context, 'operation': operation, **fields})

    def chat(self, operation, **fields):
        code, raw, _ = self.request('/api/native-chat', body={**self.context, 'operation': operation, **fields})
        self.assertEqual(code, 200, raw)
        return json.loads(raw)

    def test_dynamic_capability_negotiation_and_warm_cache(self):
        old = {**self.context, 'capabilities': ['semantic-tree-v1']}
        for _ in range(2):
            self.assertEqual(self.get_document(old)[0], 400)
            self.assertEqual(self.get_document()[0], 200)
            self.assertEqual(self.action('last-change', capabilities=['semantic-tree-v1'])[0], 400)
            query = {k: v for k, v in old.items() if k != 'inputID'}
            query['capabilities'] = 'semantic-tree-v1'
            self.assertEqual(self.request('/api/native-assets/' + self.document['assets'][0]['id'] + '?' + urlencode(query))[0], 400)
        reordered = {**self.context, 'capabilities': ['semantic-tree-v1', 'image-layout-v1']}
        self.assertEqual(json.loads(self.get_document(reordered)[1]), self.document)
        for caps in [[], ['semantic-tree-v1', 'semantic-tree-v1'], ['semantic-tree-v1', 'future-image-v9']]:
            self.assertEqual(self.get_document({**self.context, 'capabilities': caps})[0], 400)
        # A fresh real compile with legacy semantics remains usable by old clients.
        self.entry.write_text('Legacy semantic-only document.\n')
        self.state.compile()
        self.assertTrue(self.state.report['contentGatePassed'])
        legacy = {**old, 'revision': self.state.revision}
        code, raw, _ = self.get_document(legacy)
        self.assertEqual(code, 200, raw)
        self.assertEqual(json.loads(raw)['requiredCapabilities'], ['semantic-tree-v1'])
        self.assertEqual(json.loads(self.get_document({**legacy, 'capabilities': self.context['capabilities']})[1])['requiredCapabilities'], ['semantic-tree-v1'])

    def test_raw_compiler_http_metadata_session_and_generic_recovery(self):
        source = self.work / 'raw-source'; source.mkdir()
        shutil.copyfile(REPO / 'tests/flow-app/native-reader-app/fixtures/objects.typ', source / 'main.typ')
        image_input = Path(os.environ.get('NA09_IMAGE_INPUT', str(DEV / 'test-output/objects/fidelity-v2/final2/source')))
        for name in ['pattern.png', 'pattern.jpg']:
            shutil.copyfile(image_input / name, source / name)
        oracle = json.loads((REPO / 'tests/flow-app/native-reader-app/fixtures/objects.expect.json').read_text())
        (source / 'symbol-hidden.svg').write_text(oracle['hiddenSymbolSVG'])
        def execute(request):
            result = local_compile(dataclasses.replace(request, inputs=(*request.inputs, ('fidelity-v2', 'true'))))
            COMMANDS.append(dict(operation='raw-compiler', target=request.target, exit=result.returncode, stderr=result.stderr))
            save('raw-compiler-commands.json', COMMANDS)
            return result
        attachment = OUT / 'raw-attachment.json'
        attachment.write_text('{}')
        output = OUT / 'raw-pipeline'; output.mkdir()
        save('raw-compiler-commands.json', [])
        project = Project(source, Path('main.typ'), REPO / 'tools/flow-reader/packages', compiler=str(self.wrapper), execute=execute)
        state = ReaderState(project, self.work / 'raw-output', '', False)
        self.addCleanup(state.close)
        state.compile()
        self.assertTrue(state.report.get('contentGatePassed'), state.report)
        server = self.serve(handler_for(state))
        save('raw-attachment.json', dict(url=f'http://127.0.0.1:{server.server_port}/', documentID=state.document_id, service=state.focus.service))
        result = command([self.binary, 'raw-contract', attachment, state.revision, output], timeout=180)
        self.assertEqual(result.returncode, 0, result.stderr)
        report = json.loads(result.stdout)
        self.assertEqual(report['skips'], 0)
        self.assertGreaterEqual(report['layouts'], 8)
        (OUT / 'raw-compiler.html').write_bytes(state.document)
        save('raw-pipeline-results.json', report)
        save('raw-source-hashes.json', {str(p): digest(p) for p in [source / 'main.typ', source / 'pattern.png', source / 'pattern.jpg', source / 'symbol-hidden.svg']})

    def test_root_and_registered_prefix_actual_compiler_tree_and_asset_binding(self):
        code, raw, _ = self.get_document(shared=True)
        self.assertEqual(code, 200)
        self.assertEqual(json.loads(raw), self.document)
        self.assertEqual([b['canonicalText'] for b in self.document['blocks']][:2], ['First paragraph keeps its own question.', 'A second independent paragraph.'])
        self.assertEqual(self.document['identity']['serviceID'], service_id(self.state.focus.service))
        for prefix in ('/d/unknown/', '/d/first/../', '/d/%66irst/'):
            self.assertEqual(self.get_document(shared=True, prefix=prefix)[0], 404)
        self.assertEqual(self.get_document(shared=True, prefix='/')[0], 404)
        self.assertEqual(self.get_document(prefix='/d/first/')[0], 404)
        self.assertNotIn(str(self.root), raw.decode())
        self.assertGreater(len(self.document['assets']), 0)
        query = {k:v for k,v in self.context.items() if k != 'inputID'}
        query['capabilities'] = ','.join(query['capabilities'])
        for asset in self.document['assets']:
            path = 'api/native-assets/' + asset['id'] + '?' + urlencode(query)
            for prefix, shared in [('/', False), ('/d/first/', True)]:
                code, data, headers = self.request(prefix+path, shared=shared)
                self.assertEqual(code, 200); self.assertEqual(digest_bytes(data), asset['sha256'])
                self.assertEqual(headers['Content-Type'], asset['mime'])
            self.assertEqual(self.request('/'+path.replace(query['revision'], 'old'))[0], 409)

    def test_host_origin_schema_caps_identity_revision_and_query_negatives(self):
        for headers, code in [({'Host': 'evil.invalid'}, 421), ({'Origin': None}, 403), ({'Origin': 'http://evil.invalid'}, 403),
                              ({'Origin': f'http://127.0.0.1:{self.root_server.server_port}/'}, 403), ({'X-Forwarded-For': '127.0.0.1'}, 403)]:
            self.assertEqual(self.get_document(headers=headers)[0], code)
        for key, value, code in [('schemaVersion', 2, 400), ('capabilities', ['unknown'], 400), ('documentID', 'wrong', 409),
                                  ('serviceID', 'reader:1:1', 409), ('revision', 'old', 409), ('generation', -1, 400)]:
            self.assertEqual(self.get_document({**self.context, key: value})[0], code, key)
        self.assertEqual(self.request('/api/native-document')[0], 400)
        self.assertEqual(self.request('/api/native-document?' + 'x'*4100)[0], 403)
        self.assertEqual(self.request('/api/native-action', body={**self.context, 'operation': 'highlight', 'padding': 'x'*262144})[0], 413)

    def test_failed_compile_changed_inputs_and_service_restart_preserve_accepted(self):
        accepted = self.state.bundle
        self.entry.write_text('#not-valid(')
        self.state.compile()
        self.assertIs(self.state.bundle, accepted)
        self.assertEqual(self.get_document()[0], 409)
        self.entry.write_text(self.raw_source)
        self.state.compile()
        self.state.focus.service = {**self.state.focus.service, 'startedAt': self.state.focus.service['startedAt']+1}
        self.assertEqual(self.get_document()[0], 409)

    def test_real_source_excerpt_and_locate_owner_without_raw_source_reconstruction(self):
        math_index = next(i for i,b in enumerate(self.document['blocks']) if any(n['kind']=='math' for n in self.walk(b)))
        code, raw, _ = self.action('excerpt', selection=self.selection(math_index), receiptID=str(uuid4()))
        self.assertEqual(code, 200, raw)
        result = json.loads(raw)
        self.assertEqual(result['status'], 'located', (self.state.report, raw))
        self.assertEqual(result['text'], '$alpha + beta$')
        code, raw, _ = self.action('locate', selection=self.selection(), receiptID=str(uuid4()))
        self.assertEqual(code, 200, raw)
        self.assertEqual(json.loads(raw)['status'], 'located')
        self.assertNotIn('path', json.loads(raw)); self.assertNotIn(str(self.root), raw.decode())
        self.assertEqual(self.entry.read_text(), self.raw_source)
        self.assertEqual(json.loads(self.action('last-change')[1])['status'], 'unmapped')

    @staticmethod
    def walk(node):
        yield node
        for child in node['children']: yield from NativeServiceTests.walk(child)

    def test_exact_order_stale_input_and_unmapped_mutation_negatives(self):
        selected = self.selection()
        for mutate in ('exact', 'range', 'order'):
            value = copy.deepcopy(selected)
            if mutate == 'exact': value['fragments'][0]['exact'] = 'forged'
            elif mutate == 'range': value['fragments'][0]['rangeUTF16'] = [0, 9999]
            else: value['fragments'] = self.selection(1)['fragments'] + value['fragments']
            self.assertEqual(self.action('highlight', selection=value, receiptID=str(uuid4()), editorAttachment='invalid')[0], 400)
        self.assertEqual(self.action('locate', selection=selected, inputID='bad')[0], 409)
        self.assertEqual(json.loads(self.action('highlight', selection=selected, receiptID=str(uuid4()))[1])['status'], 'editor-mismatch')
        self.assertEqual(json.loads(self.action('highlight', selection=selected, receiptID=str(uuid4()), editorAttachment='invalid')[1])['status'], 'editor-mismatch')
        self.assertEqual(self.entry.read_text(), self.raw_source)

    def test_receipt_query_missing_unfinished_and_lost_ack_never_replays(self):
        identifier = str(uuid4())
        self.assertEqual(json.loads(self.action('receipt', receiptID=identifier)[1])['status'], 'unknown')
        request = {'requestID': identifier, 'service': self.state.focus.service}
        def crash(): raise OSError('fixture uncertain write')
        with self.assertRaises(OSError): self.state.selection.receipts.run(request, self.state.focus.service, crash)
        with patch.object(self.state.selection, 'highlight', side_effect=AssertionError('must not write')):
            self.assertEqual(json.loads(self.action('receipt', receiptID=identifier)[1])['status'], 'uncertain')
        self.assertEqual(self.entry.read_text(), self.raw_source)

    def test_verified_highlight_respects_unsaved_editor_and_durable_receipt(self):
        edits = []
        def reject(path, original, updated):
            edits.append((path, original, updated))
            return 'modified'
        editor = SimpleNamespace(address='fixture-editor', executable='fixture-nvim', write=reject)
        identifier = str(uuid4())
        fields = dict(selection=self.selection(0, 'keeps its own'), receiptID=identifier, editorAttachment='fixture-private-registration')
        with patch.object(self.state.editor_attachments, 'resolve', return_value=editor):
            code, raw, _ = self.action('highlight', **fields)
            self.assertEqual(code, 200, raw)
            self.assertEqual(json.loads(raw)['status'], 'modified', raw)
            self.assertEqual(len(edits), 1)
            self.assertEqual(json.loads(self.action('receipt', receiptID=identifier)[1])['status'], 'modified')
            self.assertEqual(json.loads(self.action('highlight', **fields)[1])['status'], 'modified')
            self.assertEqual(len(edits), 1)
        self.assertEqual(self.entry.read_text(), self.raw_source)

    def test_chat_only_explicit_send_dedup_independent_versions_drafts_and_cancel(self):
        a = self.chat('open', selection=self.selection())['conversations'][0]
        b = self.chat('open', selection=self.selection(1))['conversations'][0]
        self.assertNotEqual(a['conversation_id'], b['conversation_id'])
        a = self.chat('draft', conversationID=a['conversation_id'], version=a['version'], draft='Saved question')['conversations'][0]
        self.assertEqual(a['draft'], 'Saved question'); self.assertEqual(self.provider.calls, [])
        self.provider.stall = True
        message = str(uuid4())
        payload = dict(conversationID=a['conversation_id'], version=a['version'], messageID=message, question='Explain', model='fixture-model')
        sent = self.chat('send', **payload)['conversations'][0]
        self.assertTrue(self.provider.started.wait(3))
        duplicate = self.chat('send', **payload)['conversations'][0]
        self.assertEqual(sent['version'], duplicate['version']); self.assertEqual(len(self.provider.calls), 1)
        history = self.chat('list')['conversations']
        self.assertEqual(next(x for x in history if x['conversation_id']==b['conversation_id'])['draft'], '')
        self.assertTrue(all('context' not in r and 'source' not in r and 'anchor_evidence' not in r for r in history)); self.assertNotIn(str(self.root), json.dumps(history))
        self.chat('cancel', conversationID=a['conversation_id'], version=sent['version'])
        self.provider.release.set()
        self.assertEqual(self.entry.read_text(), self.raw_source)

    def test_auth_stays_status_models_only_and_forwarded_home_never_mutates(self):
        payload = {'documentID': self.state.document_id, 'service': self.state.focus.service, 'revision': self.state.revision}
        for operation in ('login', 'logout', 'cancel'):
            for prefix, shared in [('/', False), ('/d/first/', True)]:
                self.assertEqual(self.request(prefix+'api/chat/auth', body={**payload, 'operation':operation}, shared=shared)[0], 403)
            self.assertEqual(self.request('/api/home/account', body={'operation':operation}, shared=True,
                headers={'X-Forwarded-For':'127.0.0.1'})[0], 403)
        self.assertEqual(self.auth.calls, [])
        self.assertEqual(self.provider.calls, [])

    def test_swift_real_http_root_prefixed_and_injected_state_recovery_appkit(self):
        attachment = {'url': f'http://127.0.0.1:{self.root_server.server_port}/', 'documentID': self.state.document_id, 'service':self.state.focus.service}
        shared = {**attachment, 'url': f'http://127.0.0.1:{self.shared.server_port}/d/first/'}
        (self.work/'attachment.json').write_text(json.dumps(attachment))
        (self.work/'shared.json').write_text(json.dumps(shared))
        result = command([self.binary, self.work/'attachment.json', self.work/'shared.json', self.state.revision, self.work/'recovery'])
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        report = json.loads(result.stdout)
        self.assertGreaterEqual(report['assertions'], 35)
        cache = report['stage3']
        self.assertGreater(cache['byteCap'], 0)
        self.assertEqual(cache['mathEntryCap'], 256)
        for field in ['lru', 'privateDirectory', 'keyInvalidation', 'sha256', 'strictRebinding',
                      'viewedAssets', 'recoveryCoexistence', 'noFollow', 'sharedProfiles', 'sharedLRU',
                      'restoreRetryWait', 'restoreRetryAdopted']:
            self.assertTrue(cache[field], field)
        save('swift-results.json', report)
        from collections import Counter
        # Each original explicit message reaches the real owner's fake provider
        # once. Dedup retries, history controls, layout and late callbacks add none.
        self.assertEqual(Counter(self.provider.questions), Counter({
            'Question': 1, 'lost': 1, 'new after confirmed lost Send': 1,
            'new private draft after lost Send': 1, 'uncertain original': 4}))
        self.assertEqual(len(self.provider.calls), 8)
        save('ui-provider-proof.json', {'questions': self.provider.questions, 'inferenceCalls': len(self.provider.calls),
            'explicitOriginalMessages': 8, 'extraInference': 0, 'provider': 'injected FixtureProvider only'})

    def test_cross_registered_document_and_disconnected_subscription_guards(self):
        other_root = self.work / 'other-source'; other_root.mkdir()
        (other_root/'main.typ').write_text('Another document.')
        other = ReaderState(Project(other_root, Path('main.typ'), REPO/'tools/flow-reader/packages', compiler=str(self.wrapper)), self.work/'other-output', '', False)
        self.addCleanup(other.close); other.compile(); self.assertIsNotNone(other.revision)
        server = self.serve(handler_for_reader({'first':self.state, 'second':other}, self.inventory, HomeAccount(self.auth,self.provider), capability='fixture'))
        fields = {k:v for k,v in self.context.items() if k != 'inputID'}; fields['capabilities']='image-layout-v1,semantic-tree-v1'
        conn = HTTPConnection('127.0.0.1',server.server_port,timeout=5)
        conn.request('GET','/d/second/api/native-document?'+urlencode(fields),headers={'Origin':f'http://127.0.0.1:{server.server_port}'})
        response=conn.getresponse(); self.assertEqual(response.status,409); response.read(); conn.close()
        opened = self.chat('open',selection=self.selection())['conversations'][0]
        self.provider.stall=True
        sent = self.chat('send',conversationID=opened['conversation_id'],version=opened['version'],messageID=str(uuid4()),question='Wait for cancel',model='fixture-model')['conversations'][0]
        self.assertTrue(self.provider.started.wait(3))
        conn=HTTPConnection('127.0.0.1',self.root_server.server_port,timeout=5)
        conn.request('POST','/api/native-chat',body=json.dumps({**self.context,'operation':'events'}),headers={'Content-Type':'application/json','Origin':f'http://127.0.0.1:{self.root_server.server_port}'})
        response=conn.getresponse(); self.assertEqual(response.status,200); self.assertTrue(response.readline().startswith(b'data: '))
        response.close(); conn.close()
        self.assertIn(opened['conversation_id'],self.state.paragraph_chat.jobs)
        self.assertFalse(self.state.paragraph_chat.jobs[opened['conversation_id']]['cancel'].is_set())
        self.chat('cancel',conversationID=opened['conversation_id'],version=sent['version'])
        self.provider.release.set()

    def test_manager_existing_attach_with_injected_process_and_network(self):
        manager = ReaderManager(data=self.work/'manager', agents=self.work/'agents')
        profile = {'id':'exact', 'root':str(self.root), 'entry':'main.typ', 'port': self.root_server.server_port}
        with patch.object(manager, 'match_document', return_value=profile) as match, patch.object(manager, 'job_pid', side_effect=[None, self.state.focus.service['pid']]), patch.object(manager,'control') as control, patch.object(manager,'document_url',return_value=f'http://127.0.0.1:{self.root_server.server_port}/'):
            plan = manager.attach(self.root, 'main.typ', identifier='exact')
            match.assert_called_once_with(self.root,'main.typ','exact'); control.assert_called_once_with('start',profile)
            self.assertEqual(plan['documentID'], self.state.document_id)
            self.assertEqual(plan['service'], self.state.focus.service)


if __name__ == '__main__': unittest.main()
