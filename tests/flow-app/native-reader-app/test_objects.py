"""NA03 headless compiler/helper/native object evidence. Missing prerequisites fail.

NA03_OUTPUT must be a fresh directory in DevSSD/test-output/objects. Runtime is a
provisional offline scratch install, never evidence of delivered .app resources.
"""
import hashlib
import dataclasses
import base64
import zlib
import struct
from html import escape
import json
import os
from pathlib import Path
import platform
import re
import xml.etree.ElementTree as ET
import shutil
import subprocess
import sys
import time
import unittest

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
DEV = Path('/Volumes/devSSD/Developer/lagrangian-native-20261117')
CLOSURE = Path(os.environ["NA09_ROOT"]).resolve() if os.environ.get("NA09_ROOT") else None
EVIDENCE = CLOSURE if CLOSURE else DEV / 'test-output/objects'
ISOLATED = CLOSURE if CLOSURE else DEV
RUNTIME = Path(os.environ.get('FLOW_TEST_NATIVE_RUNTIME', DEV / 'dependencies/mathjax413'))
OWNED = ['apps/macos/NativeReaderObjectRenderer.swift', 'apps/macos/NativeReaderPagedLayout.swift',
         'tools/flow-reader/native/math_layout.mjs', 'tests/flow-app/native-reader-app/ObjectsTests.swift',
         'tests/flow-app/native-reader-app/test_objects.py',
         'tests/flow-app/native-reader-app/fixtures/objects.typ',
         'tests/flow-app/native-reader-app/fixtures/objects.expect.json']
for name, value in {'TMPDIR': ISOLATED / 'tmp/objects', 'CLANG_MODULE_CACHE_PATH': ISOLATED / 'cache/objects/clang',
                    'SWIFT_MODULECACHE_PATH': ISOLATED / 'cache/objects/swift'}.items():
    value.mkdir(parents=True, exist_ok=True)
    os.environ[name] = str(value)
sys.path.insert(0, str(REPO / 'tools/flow-reader'))
from flow_reader.compiler.build import compile_project
from flow_reader.compiler.project import Project
from flow_reader.compiler.execution import local_compile, CompileRequest
from flow_reader.compiler.inputs import input_fingerprint, source_signature
from flow_reader.document.sections import split_document, SectionBundle
from flow_reader.document.native_document import import_accepted_document, NativeImportError


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def save(path, data):
    Path(path).write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n')


def walk(node):
    yield node
    for child in node['children']:
        yield from walk(child)


def prepare_input_refresh(output, compiler):
    """Real unchanged HTML revision with changed saved input; fixture authority only."""
    folder = output / 'refresh'; folder.mkdir()
    source = folder / 'source'; source.mkdir()
    entry = source / 'main.typ'
    entry.write_text('#set page(width: 320pt, height: 360pt, margin: 20pt)\n'
                     '#set text(size: 14pt)\nStable input refresh office 한글.\n')
    packages = REPO / 'tools/flow-reader/packages'
    cache = ISOLATED / 'cache/objects/typst-packages'
    if not cache.is_dir():
        raise RuntimeError('existing copied package cache required')
    profile = '(version 1)(allow default)(deny network*)' + ''.join(
        '(deny file-write* (subpath ' + json.dumps(str(p)) + '))'
        for p in [REPO, source, packages, cache])
    (folder / 'bin').mkdir()
    wrapper = folder / 'bin/offline-typst'
    wrapper.write_text('#!' + sys.executable + '\nimport os,sys,json\n' +
        'with open(' + repr(str(folder / 'compiler-argv.jsonl')) + ',"a") as f:f.write(json.dumps(sys.argv[1:])+"\\n")\n' +
        'os.execv("/usr/bin/sandbox-exec",["sandbox-exec","-p",' + repr(profile) + ',' + repr(str(compiler)) + ']+sys.argv[1:])\n')
    wrapper.chmod(0o700)
    commands = []
    def execute(request):
        result = local_compile(dataclasses.replace(request, timestamp=0))
        commands.append(dict(target=request.target, exit=result.returncode, elapsed=result.elapsed_seconds,
                             stderr=result.stderr, dependencies=result.dependencies))
        save(folder / 'commands.json', commands)
        return result
    project = Project(source, Path('main.typ'), packages, compiler=str(wrapper), execute=execute)
    records = {}
    for phase in ['before', 'after']:
        if phase == 'after':
            with entry.open('a') as stream:
                stream.write('// PAGED-PM-01: saved input changed; display remains identical.\n')
        shutil.copyfile(entry, folder / (phase + '.typ'))
        report = compile_project(project, folder / phase, map_sources=False)
        if report['exitCode'] != 0 or not report['contentGatePassed']:
            raise RuntimeError('input-refresh actual HTML content gate failed')
        fingerprint = input_fingerprint(project, report['dependencies'])
        signature = source_signature(project, report['dependencies'])
        pdf = execute(CompileRequest(str(wrapper), source, packages, 'pdf', entry=entry, timestamp=0))
        if pdf.returncode != 0:
            raise RuntimeError('input-refresh actual PDF compile failed: ' + pdf.stderr)
        (folder / (phase + '.pdf')).write_bytes(pdf.artifact)
        assert fingerprint == input_fingerprint(project, report['dependencies'])
        assert signature == source_signature(project, report['dependencies'])
        records[phase] = dict(revision=report['revision'], inputFingerprint=fingerprint,
            sourceSignature=signature, sourceSHA256=digest(entry), pdfSHA256=digest(folder / (phase + '.pdf')),
            htmlSHA256=digest(folder / phase / 'document.html'), scope='compiler fixture; not server publication')
    save(folder / 'inputs.json', records)
    assert records['before']['revision'] == records['after']['revision'], 'actual HTML revision changed'
    assert records['before']['htmlSHA256'] == records['after']['htmlSHA256']
    assert records['before']['inputFingerprint'] != records['after']['inputFingerprint']
    assert records['before']['sourceSignature'] != records['after']['sourceSignature']
    return records


class ObjectsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.out = Path(os.environ.get('NA03_OUTPUT', str(EVIDENCE / ('objects-' + str(time.time_ns()))))).resolve()
        if not cls.out.is_relative_to(EVIDENCE) or cls.out.exists():
            raise RuntimeError('NA03_OUTPUT must be a fresh DevSSD object evidence directory')
        cls.out.mkdir(parents=True)
        cls.commands = []

        def command(argv, input=None, timeout=60, expected=0):
            a = [str(x) for x in argv]
            start = time.monotonic()
            try:
                p = subprocess.run(a, input=input, text=True, capture_output=True, cwd=REPO, timeout=timeout)
                record = dict(argv=a, exit=p.returncode, elapsed=time.monotonic()-start,
                              stdout=p.stdout, stderr=p.stderr)
            except subprocess.TimeoutExpired as e:
                record = dict(argv=a, exit=None, status='timeout-killed-by-subprocess', elapsed=time.monotonic()-start,
                              stdout=str(e.stdout), stderr=str(e.stderr))
                cls.commands.append(record); save(cls.out / 'commands.json', cls.commands)
                raise
            if input is not None:
                record['inputSHA256'] = hashlib.sha256(input.encode()).hexdigest()
            cls.commands.append(record); save(cls.out / 'commands.json', cls.commands)
            if p.returncode != expected:
                raise RuntimeError(f'expected exit {expected}, got {p.returncode}: {a}: {p.stderr[:2000]}')
            return p.stdout
        cls.command = staticmethod(command)
        compiler = Path(shutil.which('typst') or '/missing')
        node = shutil.which('node')
        if not compiler.is_file() or not node or not shutil.which('sandbox-exec'):
            raise RuntimeError('prebuilt Typst, Node and sandbox-exec required')
        for package in ['@mathjax/src', '@mathjax/mathjax-newcm-font']:
            if json.loads((RUNTIME / 'node_modules' / package / 'package.json').read_text())['version'] != '4.1.3':
                raise RuntimeError('exact offline 4.1.3 runtime required')
        # Existing cache only. Missing cache is a blocker, never a download.
        source_cache = Path(os.environ['FLOW_TEST_PACKAGE_CACHE']) if os.environ.get('FLOW_TEST_PACKAGE_CACHE') else Path.home() / 'Library/Caches/typst/packages'
        cache = ISOLATED / 'cache/objects/typst-packages'
        if not cache.exists():
            if not source_cache.is_dir():
                raise RuntimeError('existing local package cache missing')
            shutil.copytree(source_cache, cache)
        os.environ['TYPST_PACKAGE_CACHE_PATH'] = str(cache)
        packages = REPO / 'tools/flow-reader/packages'
        source = cls.out / 'source'; source.mkdir()
        shutil.copyfile(HERE / 'fixtures/objects.typ', source / 'main.typ')
        (source / 'symbol-hidden.svg').write_text(json.loads((HERE / 'fixtures/objects.expect.json').read_text())['hiddenSymbolSVG'])
        cls.binary = cls.out / 'ObjectsTests'
        command(['swiftc', '-swift-version', '5', '-warnings-as-errors', '-target', 'arm64-apple-macosx13.0',
                 '-module-cache-path', os.environ['SWIFT_MODULECACHE_PATH'],
                 REPO / 'apps/macos/NativeReaderDocument.swift', REPO / 'apps/macos/NativeReaderOperations.swift',
                 REPO / OWNED[0], REPO / OWNED[1], HERE / 'ObjectsTests.swift', '-o', cls.binary], timeout=120)
        command([cls.binary, 'assets', cls.out, HERE / 'fixtures/objects.expect.json'])
        (source / 'pattern.webp').write_bytes(base64.b64decode(json.loads((HERE / 'fixtures/objects.expect.json').read_text())['rasterWebPBase64'], validate=True))
        def png_chunk(kind, value):
            return struct.pack('>I', len(value)) + kind + value + struct.pack('>I', zlib.crc32(kind + value))
        compressor = zlib.compressobj()
        compressed = b''.join(compressor.compress(b'\0' + b'\0' * (2400 * 4)) for _ in range(2400)) + compressor.flush()
        (cls.out / 'oversized.png').write_bytes(b'\x89PNG\r\n\x1a\n' + png_chunk(b'IHDR', struct.pack('>IIBBBBB', 2400, 2400, 8, 6, 0, 0, 0)) + png_chunk(b'IDAT', compressed) + png_chunk(b'IEND', b''))

        profile = '(version 1)(allow default)(deny network*)' + ''.join(
            '(deny file-write* (subpath ' + json.dumps(str(p)) + '))' for p in [REPO, packages, cache, source])
        cls.compiler_profile = profile
        wrapper = cls.out / 'offline-typst'
        wrapper.write_text('#!' + sys.executable + '\nimport os,sys,json,time\n' +
            'with open(' + repr(str(cls.out / 'compiler-argv.jsonl')) + ',"a") as f: f.write(json.dumps(dict(argv=sys.argv[1:],time=time.time()))+"\\n")\n' +
            'os.execv("/usr/bin/sandbox-exec", ["sandbox-exec","-p",' + repr(profile) + ',' + repr(str(compiler)) + '] + sys.argv[1:])\n')
        wrapper.chmod(0o700)
        cls.compiler = compiler

        def execute(request):
            p = local_compile(request)
            cls.commands.append(dict(operation='actual-local-compile', exit=p.returncode, elapsed=p.elapsed_seconds,
                                     stderr=p.stderr, compiler=request.compiler, target=request.target))
            save(cls.out / 'commands.json', cls.commands)
            return p
        cls.report = compile_project(Project(source, Path('main.typ'), packages, compiler=str(wrapper), execute=execute),
                                     cls.out / 'compiled', map_sources=False)
        if cls.report['exitCode'] != 0 or not cls.report['contentGatePassed']:
            raise RuntimeError('actual compiler/content gate failed: ' + (cls.out / 'compiled/compile.log').read_text()[:2000])
        bundle = split_document((cls.out / 'compiled/document.html').read_text(), cls.report['revision'], max_blocks=2)
        cls.oracle = json.loads((HERE / 'fixtures/objects.expect.json').read_text())
        # Controlled assets exercise legitimate schema1 decoding independently of
        # the compiler/importer gap. They are not substituted for compiler output.
        controlled_assets = dict(bundle.assets)
        controlled_html = []
        def add_asset(data, ext, alt):
            key = hashlib.sha256(data).hexdigest() + '.' + ext
            controlled_assets[key] = data
            return '<img src="api/assets/' + key + '" alt="' + escape(alt, quote=True) + '">'
        for case in cls.oracle['richAssets']:
            view_box = ' '.join(str(n) for n in case.get('viewBox', [0, 0, 100, 80]))
            data = ('<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="' + view_box + '" width="100pt" height="80pt">' + case['svg'] + '</svg>').encode()
            controlled_html.append('<figure>' + add_asset(data, 'svg', case['name']) + '<figcaption>' + case['name'] + '</figcaption></figure>')
        for ext in ['png', 'jpg', 'gif', 'webp']:
            controlled_html.append('<figure>' + add_asset((source / ('pattern.' + ext)).read_bytes(), ext, 'raster-' + ext) + '<figcaption>Raster ' + ext + '</figcaption></figure>')
        controlled_html.append('<p>Inline ' + add_asset((source / 'pattern.png').read_bytes(), 'png', 'inline-png') + ' tail</p>')
        fixture_documents = {**bundle.documents, 'controlled-rich': ('<html><body>' + ''.join(controlled_html) + '</body></html>').encode()}
        # The controlled snapshot gets its own content revision. Never reuse a
        # compiler/server revision as authority for an augmented fixture.
        fixture_revision = hashlib.sha256(b''.join(fixture_documents.values()) +
            json.dumps(sorted((key, hashlib.sha256(data).hexdigest()) for key, data in controlled_assets.items())).encode()).hexdigest()
        bundle = SectionBundle({**bundle.manifest, 'revision': fixture_revision, 'sections': [*bundle.manifest['sections'], {'id': 'controlled-rich'}]},
                               fixture_documents, controlled_assets, bundle.passages)
        save(cls.out / 'snapshot-origin.json', dict(scope='fixture', compilerBaseRevision=cls.report['revision'],
            fixtureRevision=fixture_revision, kind='actual compiler base plus independently authored controlled assets; no server acceptance authority'))
        imported = import_accepted_document(bundle, document_id='objects', service_id='isolated', generation=1, identity_scope='fixture')
        cls.model = imported.document
        cls.nodes = [n for b in cls.model['blocks'] for n in walk(b)]
        save(cls.out / 'native.json', cls.model)
        (cls.out / 'assets').mkdir()
        for key, value in imported.assets.items():
            (cls.out / 'assets' / key).write_bytes(value)
        cls.oracle = json.loads((HERE / 'fixtures/objects.expect.json').read_text())
        def rich_execute(request):
            return execute(dataclasses.replace(request, inputs=(*request.inputs, ('fidelity-v2', 'true'))))
        cls.rich_report = compile_project(Project(source, Path('main.typ'), packages, compiler=str(wrapper), execute=rich_execute),
                                          cls.out / 'rich-compiled', map_sources=False)
        if cls.rich_report['exitCode'] != 0 or not cls.rich_report['contentGatePassed']:
            raise RuntimeError('rich actual compiler failed: ' + (cls.out / 'rich-compiled/compile.log').read_text()[-2000:])
        raw = (cls.out / 'rich-compiled/document.html').read_text()
        svgs = re.findall(r'<svg\b[\s\S]*?</svg>', raw)
        (cls.out / 'raw-labeled.svg').write_text(svgs[-1])
        rich_bundle = split_document(raw, cls.rich_report['revision'], max_blocks=2)
        cls.blockers = []
        cls.raw_imports = {}
        for label, candidate in [('full-rich-compiler', rich_bundle),
                                 ('labeled-cetz', SectionBundle({'revision': cls.rich_report['revision'], 'sections': [{'id': 'probe'}]},
                                                              {'probe': ('<html><body><figure>' + svgs[-1] + '</figure></body></html>').encode()}, {}, []))]:
            try:
                cls.raw_imports[label] = import_accepted_document(candidate, document_id='objects', service_id='isolated', generation=1, identity_scope='fixture')
            except NativeImportError as error:
                cls.blockers.append(dict(construct=label, code=str(error), fixtureSHA256=digest(source / 'main.typ'),
                    htmlSHA256=hashlib.sha256(b''.join(candidate.documents.values())).hexdigest(), compilerExit=cls.rich_report['exitCode']))
        # Isolate a real compiler image after the existing asset separation.
        for document in rich_bundle.documents.values():
            tags = re.findall(rb'<img\b[^>]*>', document)
            if tags:
                try:
                    import_accepted_document(SectionBundle({'revision': cls.rich_report['revision'], 'sections': [{'id': 'probe'}]},
                        {'probe': b'<html><body>' + tags[0] + b'</body></html>'}, rich_bundle.assets, []),
                        document_id='objects', service_id='isolated', generation=1, identity_scope='fixture')
                except NativeImportError as error:
                    cls.blockers.append(dict(construct='compiler-raster-attributes', code=str(error),
                        fixtureSHA256=digest(source / 'main.typ'), htmlSHA256=hashlib.sha256(tags[0]).hexdigest(), tag=tags[0].decode()))
                break
        save(cls.out / 'importer-blockers.json', cls.blockers)
        if cls.blockers:
            raise RuntimeError('raw compiler import remains blocked: ' + repr(cls.blockers))
        raw_import = cls.raw_imports['full-rich-compiler']
        save(cls.out / 'raw-native.json', raw_import.document)
        (cls.out / 'raw-assets').mkdir()
        for key, value in raw_import.assets.items():
            (cls.out / 'raw-assets' / key).write_bytes(value)
        # The exact newly compiled tree, no controlled additions/revision.
        save(cls.out / 'raw-origin.json', dict(revision=cls.rich_report['revision'],
            htmlSHA256=digest(cls.out / 'rich-compiled/document.html'), sourceSHA256=digest(source / 'main.typ'),
            assets={key: hashlib.sha256(value).hexdigest() for key, value in raw_import.assets.items()},
            scope='actual compiler SectionBundle, fixture authority; raw HTML unmodified',
            dependencyHashes={p: digest(p) for p in cls.rich_report['dependencies'] if Path(p).is_file()}))
        command([cls.binary, 'requests', cls.out, HERE / 'fixtures/objects.expect.json'])
        cls.helper_command = ['/usr/bin/sandbox-exec', '-p', '(version 1)(allow default)(deny network*)(deny file-write*)',
                              node, REPO / 'tools/flow-reader/native/math_layout.mjs', '--runtime', RUNTIME]
        requests = json.loads((cls.out / 'requests.json').read_text())
        (cls.out / 'math').mkdir()
        for request in requests:
            raw = command(cls.helper_command, json.dumps(request['input']), timeout=15)
            save(cls.out / 'math' / (request['id'] + '.json'), json.loads(raw))
        save(cls.out / 'worker-config.json', dict(node=node, helper=str(REPO / 'tools/flow-reader/native/math_layout.mjs'), runtime=str(RUNTIME)))
        cls.raw_result = json.loads(command([cls.binary, 'raw-import', cls.out, HERE / 'fixtures/objects.expect.json']))
        save(cls.out / 'raw-paint.json', cls.raw_result)
        cls.result = json.loads(command([cls.binary, 'verify', cls.out, HERE / 'fixtures/objects.expect.json'], timeout=120))
        save(cls.out / 'native-results.json', cls.result)
        # Retain tool/runtime/source/oracle/package provenance even when later
        # assertions fail. Every run has a new directory and actual argv/exits.
        save(cls.out / 'provenance.json', dict(
            base='312502ceb573f4791e61d01000df132d6da16323', head=command(['git', 'rev-parse', 'HEAD']).strip(),
            dirty=command(['git', 'status', '--short']), os=platform.platform(), arch=platform.machine(),
            swift=command(['swiftc', '--version']), swiftCompiler=command(['xcrun', '--find', 'swiftc']).strip(),
            toolHashes={name: digest(command(['xcrun', '--find', 'swiftc']).strip() if name == 'swiftc' else shutil.which(name)) for name in ['swiftc', 'node', 'sandbox-exec']},
            inheritedHashes={name: digest(REPO / name) for name in ['tools/flow-reader/flow_reader/document/native_document.py', 'tools/flow-reader/flow_reader/compiler/build.py', 'tools/flow-reader/flow_reader/compiler/execution.py', 'tools/flow-reader/flow_reader/document/sections.py']}, sdk=command(['xcrun', '--show-sdk-path']).strip(),
            sdkVersion=command(['xcrun', '--show-sdk-version']).strip(), node=command([node, '--version']).strip(),
            compiler=str(compiler), compilerSHA256=digest(compiler), compilerVersion=command([compiler, '--version']).strip(),
            target='arm64-apple-macosx13.0', environment={k: os.environ[k] for k in ['TMPDIR', 'CLANG_MODULE_CACHE_PATH', 'SWIFT_MODULECACHE_PATH', 'TYPST_PACKAGE_CACHE_PATH']},
            sourceHashes={p: digest(REPO / p) for p in OWNED + ['apps/macos/NativeReaderDocument.swift', 'apps/macos/NativeReaderOperations.swift']},
            fixtureSHA256=digest(HERE / 'fixtures/objects.typ'), oracleSHA256=digest(HERE / 'fixtures/objects.expect.json'),
            dependencyHashes={p: digest(p) for p in cls.report['dependencies'] if Path(p).is_file()},
            runtimeHashes={str(p.relative_to(RUNTIME)): digest(p) for p in (RUNTIME / 'node_modules').rglob('*') if p.is_file()},
            cacheHashes={str(p.relative_to(cache)): digest(p) for p in cache.rglob('*') if p.is_file()},
            scope='headless current host; macOS13 deployment target only; no GUI, VoiceOver, print-page parity, app delivery or source verification',
            provisionalRuntime='scratch only; not shipped resources'))

    def test_original_compiler_pages_pdfkit(self):
        original = self.out / 'original'
        original.mkdir()
        cache = ISOLATED / 'cache/objects/typst-packages'
        packages = REPO / 'tools/flow-reader/packages'
        # Test-only captured input fingerprint. This is not an issued server
        # accepted-publication token; the production host must supply its owner.
        cache_manifest = json.loads((self.out / 'provenance.json').read_text())['cacheHashes']
        def pair(name, count=2, mutate=False):
            folder = original / name; folder.mkdir(); source = folder / 'source'; source.mkdir()
            shutil.copyfile(HERE / 'fixtures/objects.typ', source / 'main.typ')
            flags = (('original-pages-v3', 'true'), ('original-page-count', str(count)))
            def fingerprint():
                manifest = dict(sourceSHA256=digest(source / 'main.typ'), inputs=flags,
                    compilerSHA256=digest(self.compiler), cacheHashes=cache_manifest, timestamp=0)
                return hashlib.sha256(json.dumps(manifest, sort_keys=True).encode()).hexdigest()
            captured = fingerprint()
            profile = '(version 1)(allow default)(deny network*)' + ''.join(
                '(deny file-write* (subpath ' + json.dumps(str(p)) + '))' for p in [REPO, source, packages, cache])
            wrapper = folder / 'offline-typst'
            wrapper.write_text('#!' + sys.executable + '\nimport os,sys,json\n' +
                'with open(' + repr(str(folder / 'compiler-argv.jsonl')) + ',"a") as f:f.write(json.dumps(sys.argv[1:])+"\\n")\n' +
                'os.execv("/usr/bin/sandbox-exec",["sandbox-exec","-p",' + repr(profile) + ',' + repr(str(self.compiler)) + ']+sys.argv[1:])\n')
            wrapper.chmod(0o700)
            phases = []
            for target in ['html', 'pdf']:
                if target == 'pdf' and mutate:
                    shutil.copyfile(source / 'main.typ', folder / 'before-main.typ')
                    (source / 'main.typ').write_text((source / 'main.typ').read_text().replace('Page One office', 'Changed One office'))
                before = fingerprint()
                result = local_compile(CompileRequest(str(wrapper), source, packages, target,
                    entry=source / 'main.typ', inputs=flags, timestamp=0))
                phases.append(dict(target=target, exit=result.returncode, stderr=result.stderr,
                    elapsed=result.elapsed_seconds, fingerprintBefore=before, fingerprintAfter=fingerprint(),
                    dependencies={p: digest(p) for p in result.dependencies if Path(p).is_file()}))
                self.assertEqual(result.returncode, 0, result.stderr)
                (folder / ('document.' + target)).write_bytes(result.artifact)
            after = fingerprint()
            record = dict(capturedFingerprint=captured, finalFingerprint=after,
                fixtureInputConsistent=captured == after and all(x['fingerprintBefore'] == captured and x['fingerprintAfter'] == captured for x in phases),
                pdfSHA256=digest(folder / 'document.pdf'), htmlSHA256=digest(folder / 'document.html'),
                sourceSHA256=digest(source / 'main.typ'), phases=phases, scope='compiler-owned fixture, not accepted-publication authority')
            save(folder / 'binding-inputs.json', record)
            return record
        inputs = {'base': pair('base'), 'three': pair('three', 3), 'drift': pair('drift', mutate=True)}
        self.assertTrue(inputs['base']['fixtureInputConsistent'])
        self.assertTrue(inputs['three']['fixtureInputConsistent'])
        self.assertFalse(inputs['drift']['fixtureInputConsistent'])
        save(original / 'inputs.json', inputs)
        # Independently generated active-content negatives contain a real xref,
        # valid page tree and inert page stream. They are never displayed.
        def active_pdf(action):
            catalog = '<< /Type /Catalog /Pages 2 0 R ' + ('' if action == 'unit' else '/AcroForm 6 0 R' if action == 'form' else '/OpenAction 6 0 R') + ' >>'
            payload = {'js': '<< /S /JavaScript /JS (never-execute) >>',
                       'launch': '<< /S /Launch /F (file:///never) >>',
                       'url': '<< /S /URI /URI (https://example.invalid/never) >>',
                       'remote': '<< /S /GoToR /F (file:///never.pdf) /D [0 /Fit] >>',
                       'form': '<< /Fields [] >>', 'unit': '<< >>'}[action]
            objects = [catalog, '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
                '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 320 360] /Contents 4 0 R ' + ('/UserUnit 2' if action == 'unit' else '') + ' >>',
                '<< /Length 0 >>\nstream\n\nendstream', '<< >>', payload]
            data = b'%PDF-1.7\n'; offsets = [0]
            for i, obj in enumerate(objects, 1):
                offsets.append(len(data)); data += f'{i} 0 obj\n{obj}\nendobj\n'.encode()
            xref = len(data)
            data += f'xref\n0 {len(offsets)}\n0000000000 65535 f \n'.encode()
            data += ''.join(f'{v:010} 00000 n \n' for v in offsets[1:]).encode()
            data += f'trailer\n<< /Size {len(offsets)} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n'.encode()
            return data
        for action in ['js', 'launch', 'url', 'remote', 'form', 'unit']:
            (original / (action + '.pdf')).write_bytes(active_pdf(action))
        native = json.loads(self.command([self.binary, 'original-pages', self.out, HERE / 'fixtures/objects.expect.json'], timeout=120))
        save(original / 'native-results.json', native)
        self.assertEqual(native['pageCount'], 2)
        self.assertEqual(native['replacementPageCount'], 3)
        self.assertFalse(native['preparationWasMainThread'])
        self.assertGreaterEqual(native['negativeCases'], 20)
        self.assertTrue(native['painted'])
        refresh = prepare_input_refresh(self.out, self.compiler)
        self.assertEqual(refresh['before']['revision'], refresh['after']['revision'])
        result = json.loads(self.command([self.binary, 'input-refresh', self.out, HERE / 'fixtures/objects.expect.json'], timeout=120))
        save(self.out / 'refresh/native-results.json', result)
        self.assertTrue(result['freshInputAdopted'])

    def test_actual_labeled_compiler_raw_import_and_paint(self):
        self.assertEqual(self.rich_report['exitCode'], 0)
        self.assertTrue(self.rich_report['contentGatePassed'])
        self.assertEqual(self.blockers, [])
        raw = self.raw_imports['full-rich-compiler']
        self.assertEqual(raw.document['identity']['revision'], self.rich_report['revision'])
        self.assertEqual(raw.document['requiredCapabilities'], ['image-layout-v1', 'semantic-tree-v1'])
        self.assertEqual(self.raw_result['rasterCases'], len(self.oracle['rawImageLayouts']))
        self.assertGreater(self.raw_result['paintedAssets'], 4)
        self.assertGreater(self.raw_result['labeledBlackInk'], 80)
        self.assertEqual(self.raw_result['rawHiddenBluePixels'], self.oracle['hiddenSymbolBluePixels'])
        self.assertEqual(self.result['richAssetCases'], 15)
        origin = json.loads((self.out / 'snapshot-origin.json').read_text())
        self.assertNotEqual(origin['compilerBaseRevision'], self.model['identity']['revision'])
        self.assertEqual(origin['fixtureRevision'], self.model['identity']['revision'])

    def test_svg_symbol_overflow_clip_policy(self):
        # Required independent pixel masks, including instance/viewBox transforms;
        # neither raw import nor nonempty paint can substitute for these masks.
        result = json.loads(self.command([self.binary, 'symbol-overflow', self.out, HERE / 'fixtures/objects.expect.json']))
        save(self.out / 'symbol-overflow-results.json', result)
        self.assertEqual([(r['case'], r['bluePixels']) for r in result[:2]], [('visible', 800), ('hidden', 400)])
        self.assertEqual(len(result), 17)
        self.assertTrue(all(r['bluePixels'] == r['expectedBluePixels'] for r in result))
        negatives = json.loads((self.out / 'overflow-negative-results.json').read_text())
        self.assertEqual(len(negatives), 11)

    def test_actual_compiler_independent_semantics(self):
        cells = [n for n in self.nodes if n['kind'] == 'cell']
        for key, actual in [('cellTexts', [n['canonicalText'] for n in cells]),
                            ('rowSpans', [n['cell']['rowSpan'] for n in cells]),
                            ('columnSpans', [n['cell']['columnSpan'] for n in cells]),
                            ('headers', [n['cell']['header'] for n in cells])]:
            self.assertEqual(actual, self.oracle[key])
        self.assertEqual([n['canonicalText'] for n in self.nodes if n['kind'] == 'equationNumber'], [self.oracle['equationNumber']])
        self.assertEqual([n['canonicalText'] for n in self.nodes if n['kind'] == 'caption'][:2], [self.oracle['figureCaption'], 'Figure\u00a02: CeTZ vector'])
        xml = ''.join(n['math']['mathML'] for n in self.nodes if n['kind'] == 'math')
        for tag in ['mfrac', 'msqrt', 'munderover']:
            self.assertIn('<' + tag, xml)
        for text in self.oracle['unicode']:
            self.assertIn(text, ''.join(b['canonicalText'] for b in self.model['blocks']))
        anchors = {a for n in self.nodes for a in n['anchors']}
        links = [n['link'][1:] for n in self.nodes if n['kind'] == 'link' and n['link'].startswith('#')]
        self.assertTrue(links and all(a in anchors for a in links))

    def test_native_matrix_semantics_and_paint(self):
        self.assertEqual(len(self.result['matrix']), 36)
        self.assertTrue(all(r['inkPixels'] > 100 and r['bluePixels'] >= 1000 for r in self.result['matrix']))
        self.assertGreater(self.result['inlineBrokenCases'], 0)
        self.assertEqual(self.result['negativeFailures'], 0)
        self.assertEqual(self.result['vectorBlueArea'], self.oracle['vector']['blueArea'])

    def test_native_batch_chunking_parity_and_subset(self):
        result = json.loads((self.out / 'stage2-batch.json').read_text())
        self.assertEqual(result['formulas'], 260)
        self.assertLessEqual(result['subprocesses'], 2)
        self.assertEqual(result['distinctFormulas'], 260)
        self.assertEqual(result['distinctSubprocesses'], 2)
        self.assertTrue(result['invalidPreflight'])
        self.assertTrue(result['parity'])
        self.assertTrue(result['widthParity'])
        self.assertEqual(result['invalidItemsRejected'], 8)
        self.assertLessEqual(result['subsetCost'], 16 * 1024 * 1024)
        self.assertGreater(result['largeObjects'], 300)
        self.assertEqual(result['initialObjects'], 128)
        self.assertLessEqual(result['initialCost'], 16 * 1024 * 1024)

    def test_helper_fragment_advances_preserve_whole_formula(self):
        requests = json.loads((self.out / 'requests.json').read_text())
        checked = 0
        for request in requests:
            response = json.loads((self.out / 'math' / (request['id'] + '.json')).read_text())
            # The author's invariant: native reflow may change line positions,
            # never remove the original operator advances or change glyph scale.
            delta = abs(sum(f['width'] for f in response['fragments']) - response['whole']['width'])
            self.assertLess(delta, 0.02 * len(response['fragments']), request['id'])
            checked += 1
        self.assertGreater(checked, 50)

    def test_helper_multiscripts_and_bounded_batch(self):
        scripts = '<math><mmultiscripts><mi>x</mi><mi>i</mi><mi>j</mi><mprescripts/><mi>k</mi><mi>l</mi></mmultiscripts></math>'
        good = dict(kind='mathml', mathML=scripts, width=320, fontSize=20, font='MathJaxNewcm',
                    context=dict(revision='batch', generation=1, theme='light'))
        single = json.loads(self.command(self.helper_command, json.dumps(good)))
        items = [dict(good, context=dict(revision='item-' + str(i), generation=i,
                                        theme='dark' if i % 2 else 'light')) for i in range(512)]
        response = json.loads(self.command(self.helper_command, json.dumps(dict(kind='mathml-batch', items=items)), timeout=120))
        self.assertEqual(response['kind'], 'mathml-batch')
        self.assertEqual(len(response['items']), 512)
        for request, actual in zip(items, response['items']):
            self.assertEqual(actual['context'], request['context'])
            self.assertEqual(actual['inputHash'], hashlib.sha256(scripts.encode()).hexdigest())
            for field in ['whole', 'fragments', 'font', 'fontSize', 'width', 'diagnostics']:
                self.assertEqual(actual[field], single[field])
            self.assertIn('data-mml-node="mmultiscripts"', actual['whole']['svg'])
            self.assertNotRegex(actual['whole']['svg'], r'<(?:text|image|use|foreignObject)\b|href=|url\(')
        self.assertNotIn('kind', single)  # Preserve the single MathML response contract.
        one = json.loads(self.command(self.helper_command, json.dumps(dict(kind='mathml-batch', items=[good]))))
        self.assertEqual(one['items'][0]['whole'], single['whole'])
        # Force two input chunks to divide a non-ASCII scalar, independently of
        # OS pipe buffering, while executing the actual helper entry point.
        chunked = '''
          import { Readable } from 'node:stream';
          import { pathToFileURL } from 'node:url';
          const [helper, runtime, json] = process.argv.slice(1);
          const raw = Buffer.from(json), split = raw.indexOf(Buffer.from('α')) + 1;
          const stream = Readable.from((async function* () {
            yield raw.subarray(0, split);
            await new Promise(setImmediate);
            yield raw.subarray(split);
          })(), { objectMode: false });
          Object.defineProperty(process, 'stdin', { value: stream });
          process.argv = [process.execPath, helper, '--runtime', runtime];
          await import(pathToFileURL(helper).href);
        '''
        unicode_item = dict(good, mathML='<math><mi>α</mi></math>')
        payload = dict(kind='mathml-batch', items=[unicode_item])
        actual = json.loads(self.command(self.helper_command[:-3] + ['--input-type=module', '-e', chunked,
            self.helper_command[-3], self.helper_command[-1], json.dumps(payload, ensure_ascii=False)]))
        self.assertEqual(actual['items'][0]['inputHash'], hashlib.sha256(unicode_item['mathML'].encode()).hexdigest())
        invalid = [dict(kind='mathml-batch', items=x) for x in [[], [good] * 513, {}, [None],
            [dict(good, kind='tex')], [dict(good, width=0)], [dict(good, extra=True)],
            [dict(good, context=dict(theme='light', generation=-1, revision='bad'))],
            [dict(good, mathML='<math><script>x</script></math>')],
            [dict(good, mathML='<math><mi href="https://example.org">x</mi></math>')],
            [dict(good, mathML='<math><mtext>' + 'x' * 65536 + '</mtext></math>')]]]
        invalid.append(dict(kind='mathml-batch', items=[good], extra=True))
        for payload in invalid:
            with self.subTest(payload=str(payload)[:80]):
                self.assertEqual(self.command(self.helper_command, json.dumps(payload), expected=2), '')

    def test_importer_and_native_nested_svg_png(self):
        def chunk(kind, data):
            return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))
        png = (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', 1, 1, 8, 2, 0, 0, 0)) +
               chunk(b'IDAT', zlib.compress(b'\x00\x20\x60\xc0')) + chunk(b'IEND', b''))
        uri = 'data:image/png;base64,' + base64.b64encode(png).decode()
        rect = '<rect width="40" height="20" fill="#2060c0"/>'
        image = '<image x="10" y="15" width="20" height="10" preserveAspectRatio="none" href="' + uri + '"/>'
        cases = [
            ('nested-viewbox', '<svg x="10" y="15" width="20" height="10" viewBox="0 0 40 20">' + rect + '</svg>', [10, 15, 20, 10]),
            ('nested-css-px', '<svg x="10" y="15" style="width:20px;height:10px" viewBox="0 0 40 20">' + rect + '</svg>', [10, 15, 20, 10]),
            ('nested-css-em', '<svg x="10" y="15" style="width:1.25em;height:0.625em" viewBox="0 0 40 20">' + rect + '</svg>', [10, 15, 20, 10]),
            ('nested-css-pt', '<svg x="10" y="15" width="90" height="70" style="width:15pt;height:7.5pt" viewBox="0 0 40 20">' + rect + '</svg>', [10, 15, 20, 10]),
            ('nested-css-overflow', '<svg x="10" y="15" style="width:20px;height:10px;overflow:visible" viewBox="0 0 40 20"><rect width="60" height="20" fill="#2060c0"/></svg>', [10, 15, 30, 10]),
            ('nested-default', '<svg><rect x="10" y="15" width="20" height="10" fill="#2060c0"/></svg>', [10, 15, 20, 10]),
            ('nested-scalar', '<svg x="10," y="15," width="20" height="10" viewBox="0 0 40 20">' + rect + '</svg>', [10, 15, 20, 10]),
            ('nested-transform', '<svg x="10" y="15" width="20" height="10" viewBox="0 0 40 20" transform="translate(5,5)">' + rect + '</svg>', [15, 20, 20, 10]),
            ('png-href', image, [10, 15, 20, 10]),
            ('png-xlink', image.replace(' href=', ' xlink:href='), [10, 15, 20, 10]),
            ('png-whitespace', image[:-2] + '>\n </image>', [10, 15, 20, 10]),
            ('nested-png', '<svg x="10" y="15" width="20" height="10" viewBox="0 0 40 20"><image width="40" height="20" preserveAspectRatio="none" href="' + uri + '"/></svg>', [10, 15, 20, 10]),
            ('png-default-aspect', image.replace(' preserveAspectRatio="none"', ''), [15, 15, 10, 10])]
        def wrap(body):
            return '<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="0 0 100 80">' + body + '</svg>'
        def imported(svg):
            bundle = SectionBundle({'revision': 'pde-svg', 'sections': [{'id': 's'}]},
                {'s': ('<html><body>' + svg + '</body></html>').encode()}, {}, [])
            return next(iter(import_accepted_document(bundle, document_id='fixture', service_id='offline', generation=1).assets.values())).decode()
        encoded_cases = [dict(name=name, svg=imported(wrap(body)), rects=[bounds]) for name, body, bounds in cases]
        definitions = '<defs><g id="shared"><svg viewBox="0 0 40 20"><rect width="20" height="10" fill="#2060c0"/></svg></g></defs>'
        instances = ['<svg x="5" y="5" width="20" height="10"><use href="#shared"/></svg>',
                     '<svg x="40" y="30" width="40" height="20"><use href="#shared"/></svg>']
        # Both orders must resolve independently of declaration/first-use traversal.
        for implicit_viewport in [False, True]:
            # An extra SVG without dimensions or viewBox also needs a fresh
            # synthesized viewBox for each instance, not the defs viewport.
            shared = definitions.replace('<svg viewBox=', '<svg><svg viewBox=').replace('</svg></g>', '</svg></svg></g>') if implicit_viewport else definitions
            for reverse in [False, True]:
                body = shared + ''.join(reversed(instances) if reverse else instances)
                encoded_cases.append(dict(name='nested-defs-' + str(implicit_viewport) + '-' + str(reverse), svg=imported(wrap(body)),
                                          rects=[[5, 5, 10, 5], [40, 30, 20, 10]]))
        # A real PNG with uncompressed IDAT, deterministic blue pixels and >1 MiB
        # of base64 SVG bytes; no random data, fake signature or trailing padding.
        large_png = (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', 640, 480, 8, 2, 0, 0, 0)) +
                     chunk(b'IDAT', zlib.compress((b'\0' + b'\x20\x60\xc0' * 640) * 480, level=0)) + chunk(b'IEND', b''))
        large_uri = 'data:image/png;base64,' + base64.b64encode(large_png).decode()
        large_svg = imported(wrap(image.replace(uri, large_uri)))
        self.assertGreater(len(large_svg.encode()), 1024 * 1024)
        encoded_cases.append(dict(name='png-over-1mib', svg=large_svg, rects=[[10, 15, 20, 10]]))
        save(self.out / 'pde-svg-cases.json', encoded_cases)
        alpha_cases = []
        for paint in ['fill', 'stroke']:
            geometry = ('<rect x="10" y="15" width="20" height="10" ' if paint == 'fill' else
                        '<path d="M10 20H30" fill="none" stroke-width="10" ')
            for color, alpha in [('#ff000080', 128 / 255), ('#f008', 136 / 255)]:
                for name, parent, child, rgba in [
                    ('inherited-explicit', paint + '-opacity="0.5"', paint + '="' + color + '"', [1, 0, 0, 0.5 * alpha]),
                    ('same-element', '', paint + '="' + color + '" ' + paint + '-opacity="0.5"', [1, 0, 0, 0.5 * alpha]),
                    ('inherited-paint', paint + '="' + color + '" ' + paint + '-opacity="0.5"', '', [1, 0, 0, 0.5 * alpha]),
                    ('opacity-override', paint + '="' + color + '" ' + paint + '-opacity="0.5"', paint + '-opacity="0.25"', [1, 0, 0, 0.25 * alpha]),
                    ('opaque-override', paint + '="' + color + '"', paint + '="#0000ff"', [0, 0, 1, 1]),
                    ('opaque-with-explicit', paint + '="' + color + '" ' + paint + '-opacity="0.5"', paint + '="#0000ff"', [0, 0, 1, 0.5])]:
                    body = '<g ' + parent + '><g>' + geometry + child + '/></g></g>'
                    for rich in [False, True]:
                        svg = wrap('<svg>' + body + '</svg>' if rich else body)
                        alpha_cases.append(dict(name=paint + color + name + ('-rich' if rich else ''),
                                                svg=imported(svg), rgba=rgba, rich=rich))
        for paint in ['fill', 'stroke']:
            geometry = ('<rect x="10" y="15" width="20" height="10" ' if paint == 'fill' else
                        '<path d="M10 20H30" fill="none" stroke-width="10" ')
            for color, alpha in [('#ff000080', 128 / 255), ('#f008', 136 / 255)]:
                for opaque in [False, True]:
                    target = ('<g id="target" ' + paint + '="' + color + '">' + geometry + paint + '="#0000ff"/></g>'
                              if opaque else geometry + 'id="target" ' + paint + '="' + color + '"/>')
                    body = '<defs>' + target + '</defs><use href="#target" ' + paint + '-opacity="0.5"/>'
                    alpha_cases.append(dict(name=paint + '-defs-use-' + color + ('-opaque' if opaque else '-direct'),
                        svg=imported(wrap(body)), rgba=[0, 0, 1, 0.5] if opaque else [1, 0, 0, 0.5 * alpha], rich=True))
        save(self.out / 'pde-svg-alpha.json', alpha_cases)
        invalid = [image.replace(uri, bad) for bad in ['https://example.org/x', 'data:image/jpeg;base64,AAAA',
            'data:image/png;base64,!!!!', 'data:image/png;base64,' + base64.b64encode(b'not a PNG').decode(),
            uri + '\n', 'data:image/png;base64,' + 'A' * (4 * ((8 * 1024 * 1024 + 2) // 3) + 4)]]
        invalid += [image.replace('width="20"', 'width="' + v + '"') for v in ['0', '-1', '4097', 'NaN', 'inf', '1e999', '1px']]
        invalid += [image.replace('height="10"', ''), image.replace('href=', 'xlink:href="' + uri + '" href='),
            image.replace('/>', ' viewBox="0 0 1 1"/>'), image.replace('/>', ' d="M0 0"/>'),
            image.replace('preserveAspectRatio="none"', 'preserveAspectRatio="invalid"'),
            '<svg preserveAspectRatio="invalid">' + rect + '</svg>', '<svg width="1em">' + rect + '</svg>',
            '<svg xmlns="https://example.org">' + rect + '</svg>', '<svg>unrendered text</svg>',
            '<svg width="0">' + rect + '</svg>', '<svg viewBox="0 0 -1 10">' + rect + '</svg>',
            '<svg transform="scale(1e100)">' + rect + '</svg>', '<svg><script/></svg>',
            '<svg><foreignObject/></svg>', '<svg><text>x</text></svg>', '<svg><font/></svg>']
        invalid = [wrap(body) for body in invalid]
        for svg in invalid:
            with self.subTest(svg=svg[:100]), self.assertRaises(NativeImportError):
                imported(svg)
        save(self.out / 'pde-svg-invalid.json', invalid)
        self.command([self.binary, 'pde-svg', self.out, HERE / 'fixtures/objects.expect.json'])
        result = json.loads((self.out / 'pde-svg-results.json').read_text())
        self.assertEqual(result['rejected'], len(invalid))
        self.assertEqual([r['bluePixels'] for r in result['cases']],
                         [sum(b[2] * b[3] for b in item['rects']) for item in encoded_cases])
        self.assertEqual(result['alphaCases'], len(alpha_cases))
        self.assertTrue(result['byteAndPixelLimitsChecked'])

    def test_helper_independent_fraction_metrics(self):
        payload = dict(mathML=self.oracle['indivisibleMathML'], width=320, fontSize=20, font='MathJaxNewcm',
                       context=dict(revision='oracle', generation=1, theme='light'))
        response = json.loads(self.command(self.helper_command, json.dumps(payload)))
        f = response['whole']; oracle = self.oracle['indivisibleMath20']
        self.assertGreater(f['ascent'], oracle['minimumAscent'])
        self.assertGreater(f['descent'], oracle['minimumDescent'])
        self.assertGreater(f['width'], oracle['minimumWidth'])
        self.assertLess(f['width'], oracle['maximumWidth'])
        self.assertEqual(len(response['fragments']), 1)
        self.assertIn('<rect', f['svg']) # Fraction rule; not a text substitute.
        save(self.out / 'fraction-oracle.json', response)
        ns = {'s': 'http://www.w3.org/2000/svg'}
        tree = ET.fromstring(f['svg'])
        fraction = tree.find('.//s:g[@data-mml-node="mfrac"]', ns)
        terms = fraction.findall('s:g', ns)
        self.assertEqual(terms[0].find('.//s:path', ns).attrib['data-c'], oracle['numeratorGlyph'])
        self.assertEqual(terms[1].find('.//s:path', ns).attrib['data-c'], oracle['denominatorGlyph'])
        bar = fraction.find('s:rect', ns).attrib
        def translated_y(element):
            return float(re.search(r'translate\([^,]+,([^)]+)\)', element.attrib['transform'])[1])
        self.assertGreater(translated_y(terms[0]), float(bar['y']) + float(bar['height']))
        self.assertLess(translated_y(terms[1]), float(bar['y']))
        self.assertAlmostEqual(float(bar['height']) / 1000, oracle['ruleThicknessEm'])
        native = json.loads(self.command([self.binary, 'fraction', self.out, HERE / 'fixtures/objects.expect.json']))
        self.assertGreater(native['aboveRuleInk'], 10)
        self.assertGreater(native['belowRuleInk'], 10)
        self.assertGreater(native['ruleInk'], 10)
        save(self.out / 'fraction-native.json', native)

    def test_helper_rejects_resources_fonts_and_limits(self):
        good = dict(mathML='<math><mi>x</mi></math>', width=320, fontSize=20, font='MathJaxNewcm',
                    context=dict(revision='negative', generation=1, theme='light'))
        bad = [dict(good, mathML=x) for x in [
            '<!DOCTYPE math [<!ENTITY x SYSTEM "file:///etc/passwd">]><math>&x;</math>',
            '<math><mi href="https://example.org">x</mi></math>',
            '<math><annotation-xml><script/></annotation-xml></math>',
            '<math><mi mathvariant="url(https://example.org)">x</mi></math>',
            '<math><mi>x</math>', '<math>raw</math>', '<math><unknown/></math>', '<math><mtext>𠀀</mtext></math>']]
        bad += [dict(good, font='arbitrary-font'), dict(good, width=0), dict(good, mathML='x' * 65537)]
        # Legal XML whitespace never makes the converter silently keep only the
        # first child. A root with raw unsupported text must not become paint.
        spaced = dict(good, mathML='  <math>\n<mi>x</mi>\n<mo>+</mo>\n<mi>y</mi>\n</math>  ')
        result = json.loads(self.command(self.helper_command, json.dumps(spaced)))
        self.assertEqual(len(result['fragments']), 2)
        self.assertIn('data-c="2B"', result['whole']['svg'])
        for payload in bad:
            self.command(self.helper_command, json.dumps(payload), expected=2)
        overflow = dict(good, width=16, mathML='<math><mrow><mo>(</mo>' + '<mi>a</mi>' * 40 + '<mo>)</mo></mrow></math>')
        response = json.loads(self.command(self.helper_command, json.dumps(overflow)))
        self.assertEqual(len(response['fragments']), 1)
        self.assertEqual(response['diagnostics'], ['indivisible-math-overflow'])
        # OS boundary independently denies network, even if a future module tries.
        self.command(['/usr/bin/sandbox-exec', '-p', '(version 1)(allow default)(deny network*)',
                      shutil.which('node'), '-e', "require('net').createServer().listen(0,'127.0.0.1')"], expected=1)
        self.assertIn('EPERM', self.commands[-1]['stderr'])
        self.command(['/usr/bin/sandbox-exec', '-p', '(version 1)(allow default)(deny network*)',
                      shutil.which('node'), '-e', "require('net').createConnection({host:'127.0.0.1',port:9})"], expected=1)
        self.assertIn('EPERM', self.commands[-1]['stderr'])

    def test_compiler_input_is_read_only_and_network_denied(self):
        self.assertEqual(self.report['exitCode'], 0)
        self.assertTrue(self.report['contentGatePassed'])
        self.assertTrue((self.out / 'compiler-argv.jsonl').read_text())
        self.assertIn('(deny network*)', (self.out / 'offline-typst').read_text())
        self.assertIn('(deny file-write*', (self.out / 'offline-typst').read_text())
        code = 'from pathlib import Path; Path(' + repr(str(self.out / 'source/main.typ')) + ').open("ab")'
        self.command(['/usr/bin/sandbox-exec', '-p', self.compiler_profile, sys.executable, '-B', '-c', code], expected=1)
        self.assertIn('PermissionError', self.commands[-1]['stderr'])
        self.assertEqual(digest(self.out / 'source/main.typ'), digest(HERE / 'fixtures/objects.typ'))
