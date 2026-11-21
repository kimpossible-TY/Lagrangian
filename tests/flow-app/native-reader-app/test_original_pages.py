"""NA12 actual compiler -> accepted scoped HTTP -> native transport/session/paint.
Required prerequisites fail, never skip. No installed service or visible window.
"""
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
from unittest.mock import patch

REPO = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
DEV = Path('/Volumes/devSSD/Developer/lagrangian-native-20261117')
EVIDENCE = Path(os.environ.get('NATIVE_DELIVERY_EVIDENCE_DIR', str(DEV / 'test-output/page-service/NA12')))
OUT = EVIDENCE / os.environ.get('NA12_RUN', 'run-' + str(time.time_ns()))
if not OUT.is_relative_to(EVIDENCE) or OUT.exists():
    raise RuntimeError('NA12 needs new evidence directory')
OUT.mkdir(parents=True)
for key, path in {'TMPDIR': DEV / 'tmp/page-service', 'CLANG_MODULE_CACHE_PATH': DEV / 'cache/page-service/clang',
                  'SWIFT_MODULECACHE_PATH': DEV / 'cache/page-service/swift', 'TYPST_PACKAGE_CACHE_PATH': DEV / 'cache/page-service/packages'}.items():
    path = Path(os.environ.get(key, path))
    path.mkdir(parents=True, exist_ok=True); os.environ[key] = str(path)
tempfile.tempdir = os.environ['TMPDIR']
sys.dont_write_bytecode = True
sys.path.insert(0, str(REPO / 'tools/flow-reader'))
sys.path.insert(0, str(REPO / 'tools/flow-reader/tests'))
from flow_reader.compiler.execution import CompileResult, local_compile
from flow_reader.compiler.project import Project
from flow_reader.server.state import ReaderState
from flow_reader.server.http import handler_for
from flow_reader.server.routing import handler_for_reader
from flow_reader.server.native_reader import NativeReaderService, service_id
from flow_reader.server.native_pages import NativePageService
from flow_reader.services.home_account import HomeAccount
from flow_reader.services.homepage import HomeInventory
from flow_reader.errors import RevisionChanged
from test_homepage import FakeAuth, FakeProvider, FakeManager

COMMANDS = []

def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def save(path, value):
    Path(path).write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')

def command(argv, *, timeout=180):
    start = time.monotonic()
    result = subprocess.run(list(map(str, argv)), cwd=REPO, capture_output=True, text=True, timeout=timeout)
    COMMANDS.append(dict(argv=list(map(str, argv)), cwd=str(REPO), exit=result.returncode,
                         elapsed=time.monotonic()-start, stdout=result.stdout, stderr=result.stderr))
    save(OUT / 'commands.json', COMMANDS)
    return result


def hostile_pdf(kind):
    catalog = {'js':'/OpenAction 6 0 R', 'launch':'/OpenAction 6 0 R', 'form':'/AcroForm 6 0 R', 'embed':'/Names << /EmbeddedFiles 6 0 R >>', 'unsafe':'', 'unknown':''}[kind]
    payload = {'js':'<< /S /JavaScript /JS (never-execute) >>', 'launch':'<< /S /Launch /F (never) >>', 'form':'<< /Fields [] >>', 'embed':'<< /Names [] >>', 'unsafe':'<< /Type /Annot /Subtype /Link /Rect [20 20 100 40] /A << /S /URI /URI (javascript:never) >> >>', 'unknown':'<< /Type /Annot /Subtype /Link /Rect [20 20 100 40] /Dest [3 0 R /XYZ 20 20 0] /A << /S /Unknown >> >>'}[kind]
    objects = [f'<< /Type /Catalog /Pages 2 0 R {catalog} >>', '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
        '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 320 360] /Contents 4 0 R >>', '<< /Length 0 >>\nstream\n\nendstream', '<< >>', payload]
    if kind in ['unsafe','unknown']: objects[2] = objects[2].replace('/Contents 4 0 R', '/Contents 4 0 R /Annots [6 0 R]')
    data=b'%PDF-1.7\n';offsets=[0]
    for i,obj in enumerate(objects,1):
        offsets.append(len(data));data+=f'{i} 0 obj\n{obj}\nendobj\n'.encode()
    xref=len(data);data+=f'xref\n0 {len(offsets)}\n0000000000 65535 f \n'.encode()
    data+=''.join(f'{value:010} 00000 n \n' for value in offsets[1:]).encode()
    return data+f'trailer\n<< /Size {len(offsets)} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n'.encode()


class OriginalPageTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        compiler = shutil.which('typst')
        if not compiler or not shutil.which('xcrun') or not shutil.which('sandbox-exec'):
            raise RuntimeError('prebuilt Typst/macOS Swift/sandbox-exec required')
        cls.oracle = json.loads((HERE / "fixtures/original-pages.expect.json").read_text())
        cls.compiler = Path(compiler)
        # Copy pre-existing compiler packages into this task cache; compiler network remains denied.
        shutil.copytree(Path(os.environ["FLOW_TEST_PACKAGE_CACHE"]) if os.environ.get("FLOW_TEST_PACKAGE_CACHE") else Path.home() / "Library/Caches/typst/packages", Path(os.environ["TYPST_PACKAGE_CACHE_PATH"]), dirs_exist_ok=True)
        cls.wrapper = OUT / 'offline-typst'
        profile = '(version 1)(allow default)(deny network*)' + ''.join(
            '(deny file-write* (subpath ' + json.dumps(str(p)) + '))' for p in [REPO, DEV / 'cache/page-service/packages'])
        cls.wrapper.write_text('#!' + sys.executable + '\nimport os,sys,json\n' +
            'with open(' + repr(str(OUT / 'compiler-argv.jsonl')) + ',"a") as f:f.write(json.dumps(dict(argv=sys.argv[1:],cwd=os.getcwd()))+"\\n")\n' +
            'os.execv("/usr/bin/sandbox-exec",["sandbox-exec","-p",' + repr(profile) + ',' + repr(compiler) + ']+sys.argv[1:])\n')
        cls.wrapper.chmod(0o700)
        registry = json.loads((REPO / 'apps/macos/sources.json').read_text())
        paths = list(dict.fromkeys(registry['core'] + registry['native'] + ['NativeReaderWindowController.swift', 'NativeReaderOriginalPageView.swift', 'NativeReaderOriginalPageTransport.swift']))
        cls.sources = [REPO / 'apps/macos' / p for p in paths]
        harness = HERE / 'OriginalPageTests.swift'
        if fixed := os.environ.get('ORIGINAL_FIXED_SOURCES'):
            fixed = Path(fixed).resolve()
            allowed = DEV / 'test-output'
            if not any(fixed.is_relative_to(allowed / n) for n in ['closure-review-fixes-v2','native-app-corrections-v4']):
                raise RuntimeError('Fixed before sources must remain in isolated evidence')
            harness = Path(os.environ['ORIGINAL_FIXED_TEST']).resolve()
            if not fixed.is_relative_to(allowed) or not harness.is_relative_to(allowed):
                raise RuntimeError('Fixed before sources must remain in isolated closure evidence')
            cls.sources = [fixed / p.name for p in cls.sources]
        cls.binary = OUT / 'OriginalPageTests'
        result = command(['xcrun', 'swiftc', '-swift-version', '5', '-warnings-as-errors', '-target',
            'arm64-apple-macosx13.0', '-module-cache-path', os.environ['SWIFT_MODULECACHE_PATH'], '-parse-as-library', *cls.sources, harness, '-o', cls.binary])
        if result.returncode:
            raise RuntimeError('Swift13 compile failed: ' + result.stderr)
        save(OUT / 'environment.json', dict(OS=platform.platform(), macOS=platform.mac_ver(),
            sdk=command(['xcrun', '--show-sdk-path']).stdout.strip(),
            swift=command(['xcrun', 'swiftc', '--version']).stdout.strip(),
            target='arm64-apple-macosx13.0', warningsAsErrors=True, compilerSHA256=digest(compiler),
            sources={(str(p.relative_to(REPO)) if p.is_relative_to(REPO) else str(p)):digest(p) for p in cls.sources},
            testSHA256=digest(HERE/'OriginalPageTests.swift'), binarySHA256=digest(cls.binary),
            registryChanged=False, newSourcesExplicit=True, GUI=False, VoiceOver=False))

    def setUp(self):
        self.work = OUT / self._testMethodName; self.work.mkdir()
        self.root = self.work / 'source'; self.root.mkdir()
        self.entry = self.root / 'main.typ'; shutil.copyfile(HERE / 'fixtures/original-pages.typ', self.entry)
        (self.root / 'html.txt').write_text('HTML dependency A')
        (self.root / 'pdf.txt').write_text('PDF dependency A')
        self.calls = []
        def execute(request):
            started = time.monotonic()
            result = local_compile(request)
            self.calls.append(dict(target=request.target, purpose=request.purpose, exit=result.returncode,
                elapsed=time.monotonic()-started, dependencies=result.dependencies,
                artifactSHA256=hashlib.sha256(result.artifact).hexdigest() if result.artifact else None, stderr=result.stderr,
                publicationLockHeld=self.state.lock._is_owned() if hasattr(self, 'state') else False))
            save(self.work / 'compiles.json', self.calls)
            return result
        self.execute = execute
        project = Project(self.root, Path('main.typ'), REPO / 'tools/flow-reader/packages', compiler=str(self.wrapper), execute=execute)
        self.state = ReaderState(project, self.work / 'output', '', False, change_file=self.work / 'owned-change.json')
        self.state.output.mkdir(exist_ok=True)
        self.state.compile()
        self.assertIsNotNone(self.state.revision, self.state.report)
        self.addCleanup(self.state.close)
        self.native = NativeReaderService(self.state); self.pages = NativePageService(self.state, self.native)
        self.context = dict(documentID=self.state.document_id, serviceID=service_id(self.state.focus.service),
            revision=self.state.revision, schemaVersion=1, capabilities=['original-pdf-full-v1'], generation=1,
            requestID=str(uuid4()), viewID=str(uuid4()))

    def query(self, **updates):
        value = {**self.context, **updates}; value['capabilities'] = ','.join(value['capabilities'])
        return urlencode(value)

    def serve(self, handler):
        class Quiet(handler):
            def log_message(self, *_args): pass
        server = ThreadingHTTPServer(('127.0.0.1', 0), Quiet)
        thread = threading.Thread(target=server.serve_forever, daemon=True); thread.start()
        self.addCleanup(lambda: (server.shutdown(), server.server_close(), thread.join()))
        return server

    def get(self, server, path, *, origin=True, host=None):
        headers = {'Origin': f'http://127.0.0.1:{server.server_port}'} if origin else {}
        if host: headers['Host'] = host
        connection = HTTPConnection('127.0.0.1', server.server_port, timeout=120)
        connection.request('GET', path, headers=headers)
        response = connection.getresponse(); data = response.read(); status = response.status
        connection.close(); return status, data

    def test_actual_scoped_service_transport_session_native_paint(self):
        auth = FakeAuth(self.work)
        inventory = HomeInventory(FakeManager()); inventory.observe(); self.addCleanup(inventory.close)
        server = self.serve(handler_for_reader({'na12':self.state}, inventory,
            HomeAccount(auth, FakeProvider()), capability='owned-test'))
        config = dict(attachment=dict(url=f'http://127.0.0.1:{server.server_port}/d/na12/',
            documentID=self.state.document_id, service=self.state.focus.service), revision=self.state.revision)
        save(self.work / 'attachment.json', config)
        for kind in ['js','launch','form','embed','unsafe','unknown']: (self.work/(kind+'.pdf')).write_bytes(hostile_pdf(kind))
        result = command([self.binary, self.work / 'attachment.json', self.work])
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        native = json.loads((self.work / 'native-results.json').read_text())
        self.assertEqual(native['pages'], self.oracle['pages'])
        self.assertEqual(native['sourceAnchors'], self.oracle['sourceAnchors'])
        self.assertLessEqual(native['metrics']['peakRasterBytes'], self.oracle['maximumRasterBytes'])
        self.assertLessEqual(native['metrics']['peakTextBytes'], self.oracle['maximumTextBytes'])
        self.assertLessEqual(native['metrics']['cachedPages'], self.oracle['maximumRasterPages'])
        self.assertLessEqual(native['metrics']['textPages'], self.oracle['maximumTextPages'])
        self.assertGreater(native['metrics']['evictions'], 0)
        self.assertEqual(native['visibleWindows'], 0)
        self.assertGreater(native['assertions'], 40)
        self.assertFalse(any(c['publicationLockHeld'] for c in self.calls if c['target'] == 'pdf'))
        self.assertTrue(any('pdf.txt' in str(c['dependencies']) for c in self.calls if c['target'] == 'pdf'))
        self.assertEqual(self.get(server, '/d/not-registered/api/native-pages?' + self.query())[0], 404)

    def review_case(self, name):
        auth = FakeAuth(self.work)
        inventory = HomeInventory(FakeManager()); self.addCleanup(inventory.close)
        server = self.serve(handler_for_reader({'na12':self.state}, inventory,
            HomeAccount(auth, FakeProvider()), capability='owned-test'))
        save(self.work / 'review-attachment.json', dict(attachment=dict(url=f'http://127.0.0.1:{server.server_port}/d/na12/',
            documentID=self.state.document_id, service=self.state.focus.service), revision=self.state.revision))
        result = command([self.binary, self.work/'review-attachment.json', self.work, name])
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('review pass ' + name, result.stdout)

    def test_review_N1_selection_begins_during_pdf_prepare(self): self.review_case('N1')
    def test_review_N2_offline_reflow_assets(self): self.review_case('N2')
    def test_review_N3_current_page_accessibility(self): self.review_case('N3')
    def test_D2_automatic_across_original_mode(self): self.review_case('D2')
    def test_native_original_export_atomic_ui(self): self.review_case('EXPORT')
    def test_review_N4_real_clip_find_and_goto(self): self.review_case('N4')

    def test_saved_input_dependency_tamper_and_same_html_new_input(self):
        first = json.loads(self.pages.manifest(self.query()))
        resource = first['resource'].removeprefix('api/native-pages/')
        pdf = self.pages.resource(self.query(), resource)
        (self.work/'accepted.pdf').write_bytes(pdf)
        self.assertEqual(hashlib.sha256(pdf).hexdigest(), first['pdfSHA256'])
        # Additional PDF-only input must revoke old bytes despite unchanged HTML.
        (self.root/'pdf.txt').write_text('PDF dependency B')
        with self.assertRaises(RevisionChanged): self.pages.resource(self.query(), resource)
        second = json.loads(self.pages.manifest(self.query()))
        self.assertEqual(first['revision'], second['revision'])
        self.assertEqual(first['htmlInputFingerprint'], second['htmlInputFingerprint'])
        self.assertNotEqual(first['inputFingerprint'], second['inputFingerprint'])
        self.assertNotEqual(first['pdfSHA256'], second['pdfSHA256'])
        self.assertEqual(second['sequence'], first['sequence']+1)
        (self.root/'html.txt').write_text('HTML dependency B')
        with self.assertRaises(RevisionChanged): self.pages.manifest(self.query())
        self.state.compile(); self.context['revision'] = self.state.revision
        third = json.loads(self.pages.manifest(self.query()))
        html = (self.state.output/'document.html').read_bytes()
        self.entry.write_text(self.entry.read_text()+'\n// saved input changed without changing HTML or PDF\n')
        with self.assertRaises(RevisionChanged): self.pages.resource(self.query(), third['resource'].removeprefix('api/native-pages/'))
        self.state.compile(); self.context['revision'] = self.state.revision
        fourth = json.loads(self.pages.manifest(self.query()))
        self.assertEqual(html, (self.state.output/'document.html').read_bytes())
        self.assertNotEqual(third['inputFingerprint'], fourth['inputFingerprint'])
        self.assertEqual(third['pdfSHA256'], fourth['pdfSHA256'])
        self.assertEqual(fourth['sequence'], third['sequence']+1)
        original = self.pages.accepted
        self.pages.accepted = dataclasses.replace(original, data=original.data[:-1]+b'X')
        with self.assertRaises(ValueError): self.pages.resource(self.query(), fourth['resource'].removeprefix('api/native-pages/'))
        self.pages.accepted = original
        save(self.work/'publications.json', [first,second,third,fourth])

    def test_stale_compile_failure_restart_and_bounds_preserve_accepted(self):
        first = json.loads(self.pages.manifest(self.query())); accepted = self.pages.accepted
        (self.root/'pdf.txt').write_text('candidate B')
        with self.assertRaises(OSError): self.pages.manifest(self.query(), connected=lambda: False)
        self.assertIs(self.pages.accepted, accepted)
        def changing(request):
            result = self.execute(request)
            if request.target == 'pdf': (self.root/'pdf.txt').write_text('changed during PDF compile')
            return result
        self.state.project = dataclasses.replace(self.state.project, execute=changing)
        with self.assertRaises(RevisionChanged): self.pages.manifest(self.query())
        self.assertIs(self.pages.accepted, accepted)
        def failed(_request): return CompileResult(1, 'owned failure', None, (), 0)
        self.state.project = dataclasses.replace(self.state.project, execute=failed)
        with self.assertRaises(OSError): self.pages.manifest(self.query())
        self.assertIs(self.pages.accepted, accepted)
        def oversized(request): return CompileResult(0, '', b'%PDF-'+b'x'*(16*1024*1024), (), 0)
        self.state.project = dataclasses.replace(self.state.project, execute=oversized)
        with self.assertRaises(ValueError): self.pages.manifest(self.query())
        self.assertIs(self.pages.accepted, accepted)
        self.state.focus.service = {**self.state.focus.service, 'startedAt':self.state.focus.service['startedAt']+1}
        with self.assertRaises(RevisionChanged): self.pages.manifest(self.query())
        self.state.project = dataclasses.replace(self.state.project, execute=self.execute)
        self.context['serviceID'] = service_id(self.state.focus.service)
        restarted = NativePageService(self.state, NativeReaderService(self.state))
        fresh = json.loads(restarted.manifest(self.query()))
        self.assertEqual(fresh['sequence'], 1)
        self.assertNotEqual(first['publicationID'], fresh['publicationID'])
        self.assertNotEqual(first['serviceID'], fresh['serviceID'])
        self.assertFalse(any(c['publicationLockHeld'] for c in self.calls if c['target'] == 'pdf'))

    def test_scoped_http_host_origin_payload_and_publication_authority(self):
        server = self.serve(handler_for(self.state)); route = '/api/native-pages?'+self.query()
        status, raw = self.get(server, route); self.assertEqual(status,200,raw)
        publication = json.loads(raw)
        self.assertEqual(self.get(server, route, origin=False)[0],403)
        self.assertEqual(self.get(server, route, host='evil.invalid')[0],421)
        for query in [self.query(capabilities=['arbitrary']), self.query(serviceID='reader:1:1'),
                      self.query(revision='old'), self.query(generation=-1), self.query(requestID='bad')]:
            self.assertIn(self.get(server, '/api/native-pages?'+query)[0], [400,409])
        self.assertEqual(self.get(server, route+'&pdfSHA256='+publication['pdfSHA256'])[0],400)
        self.assertEqual(self.get(server, '/api/native-pages/forged/1.pdf?'+self.query())[0],409)
        self.assertEqual(self.get(server, '/api/native-pages/?'+self.query())[0],404)
        self.assertEqual(publication['sourceAnchors'],'unsupported')
        save(self.work/'manifest.json',publication)

    def test_disconnected_pdf_request_drops_candidate(self):
        started, release = threading.Event(), threading.Event()
        def gated(request):
            if request.target == 'pdf':
                started.set()
                if not release.wait(5): raise RuntimeError('owned compiler gate timed out')
            return self.execute(request)
        self.state.project = dataclasses.replace(self.state.project, execute=gated)
        # Inject only the observable page adapter instance; the HTTP handler and
        # actual compiler remain production implementations on owned loopback.
        with patch('flow_reader.server.native_pages.NativePageService', return_value=self.pages):
            server = self.serve(handler_for(self.state))
        client = HTTPConnection('127.0.0.1', server.server_port, timeout=10)
        client.request('GET', '/api/native-pages?'+self.query(), headers={'Origin':f'http://127.0.0.1:{server.server_port}'})
        self.assertTrue(started.wait(5))
        client.close(); release.set()
        deadline=time.monotonic()+10
        while self.pages.compile_lock.locked() and time.monotonic()<deadline: time.sleep(.01)
        self.assertFalse(self.pages.compile_lock.locked())
        self.assertIsNone(self.pages.accepted)
        self.assertEqual(self.pages.sequence,0)
        save(self.work/'disconnect.json',dict(actualPeerClosed=True,compilerInvoked=started.is_set(),publicationDropped=self.pages.accepted is None))

    def test_prebuilt_engine_source_anchor_probe(self):
        engine=Path(os.environ.get('FLOW_TEST_ENGINE', '/Users/taeyoung/Applications/Lagrangian.app/Contents/MacOS/flow-engine'))
        self.assertTrue(engine.is_file())
        profile='(version 1)(allow default)(deny network*)'
        invocations=[['--version'], ['compile','--help'], ['compile','--root',str(self.root),str(self.entry),str(self.work/'engine.pdf')],
                     ['compile','--root',str(self.root),str(self.entry),str(self.work/'source.pdf'),'--source-map'],
                     ['source-anchor','--artifact',str(self.work/'engine.pdf')]]
        results=[]
        for args in invocations:
            result=command(['/usr/bin/sandbox-exec','-p',profile,engine,*args])
            results.append(dict(args=args,exit=result.returncode,stdout=result.stdout,stderr=result.stderr))
        self.assertEqual(results[2]['exit'],0,results[2])
        self.assertNotEqual(results[3]['exit'],0); self.assertNotEqual(results[4]['exit'],0)
        save(self.work/'source-probe.json',dict(engineSHA256=digest(engine),results=results,
            pdfSHA256=digest(self.work/'engine.pdf'), sourceAnchor='unsupported by tested CLI/HTTP contract',
            rawDiffV1='native consumer unverified', scope='isolated owned artifact; no LSP/preview source authority asserted'))


if __name__ == '__main__': unittest.main()
