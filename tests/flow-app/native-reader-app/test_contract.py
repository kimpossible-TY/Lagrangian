"""NA01 real compiler/import/Swift contract tests. Missing prerequisites fail, never skip.

Run python3 -B -m unittest discover -s tests/flow-app/native-reader-app -p test_contract.py -v.
All artifacts/caches are isolated on DevSSD. No server, live service or GUI is used.
"""
import copy
import base64
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import unittest

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
DEV = Path('/Volumes/devSSD/Developer/lagrangian-native-20261117')
CLOSURE = Path(os.environ["NA09_ROOT"]).resolve() if os.environ.get("NA09_ROOT") else None
EVIDENCE = CLOSURE if CLOSURE else DEV / 'test-output/contract'
ISOLATED = CLOSURE if CLOSURE else DEV
sys.path.insert(0, str(REPO / 'tools/flow-reader'))
from flow_reader.compiler.build import compile_project
from flow_reader.compiler.project import Project, document_identity
from flow_reader.compiler.execution import local_compile
from flow_reader.document.sections import split_document, SectionBundle
from flow_reader.document.native_document import import_accepted_document, NativeImportError


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def save(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')


class ContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.out = Path(os.environ.get('NA01_OUTPUT', str(EVIDENCE / 'contract'))).resolve()
        if not cls.out.is_relative_to(EVIDENCE) or cls.out.exists():
            raise RuntimeError('NA01_OUTPUT must be a fresh directory under test-output/contract')
        cls.out.mkdir(parents=True)
        cls.commands = []

        def command(argv):
            result = subprocess.run([str(x) for x in argv], text=True, capture_output=True, cwd=REPO)
            cls.commands.append({'argv': [str(x) for x in argv], 'exit': result.returncode,
                                 'stdout': result.stdout, 'stderr': result.stderr})
            save(cls.out / 'commands.json', cls.commands)
            if result.returncode:
                raise RuntimeError('command failed: ' + str(argv[0]) + ': ' + result.stderr[:2000])
            return result.stdout.strip()
        cls.command = staticmethod(command)
        compiler = Path(shutil.which('typst') or '/missing')
        if not compiler.is_file() or not shutil.which('sandbox-exec'):
            raise RuntimeError('prebuilt typst and sandbox-exec required')
        for name, value in {'TMPDIR': ISOLATED / 'tmp/contract', 'CLANG_MODULE_CACHE_PATH': ISOLATED / 'cache/contract/clang',
                            'SWIFT_MODULECACHE_PATH': ISOLATED / 'cache/contract/swift'}.items():
            Path(value).mkdir(parents=True, exist_ok=True)
            os.environ[name] = str(value)
        # Only copy the existing local cache; deny network in every compiler run.
        cache = ISOLATED / 'cache/contract/test-packages'
        if not cache.exists():
            shutil.copytree(Path(os.environ['FLOW_TEST_PACKAGE_CACHE']) if os.environ.get('FLOW_TEST_PACKAGE_CACHE') else Path.home() / 'Library/Caches/typst/packages', cache)
        os.environ['TYPST_PACKAGE_CACHE_PATH'] = str(cache)
        packages = REPO / 'tools/flow-reader/packages'
        wrapper = cls.out / 'offline-typst'
        profile = '(version 1)(allow default)(deny network*)' + ''.join(
            '(deny file-write* (subpath ' + json.dumps(str(p)) + '))' for p in (REPO, packages, cache))
        wrapper.write_text('#!' + sys.executable + '\nimport json,os,sys\n' +
                          'with open(' + repr(str(cls.out / 'compiler-argv.jsonl')) + ',"a") as f: f.write(json.dumps(sys.argv[1:])+"\\n")\n' +
                          'os.execv("/usr/bin/sandbox-exec", ["sandbox-exec","-p",' + repr(profile) + ',' + repr(str(compiler)) + '] + sys.argv[1:])\n')
        wrapper.chmod(0o700)
        cls.wrapper = wrapper
        source_root = cls.out / 'source'
        source_root.mkdir()
        shutil.copyfile(HERE / 'fixtures/document.typ', source_root / 'main.typ')

        def execute(request):
            result = local_compile(request)
            cls.commands.append({'operation': 'local_compile', 'target': request.target,
                                 'compiler': request.compiler, 'root': str(request.root),
                                 'inputs': request.inputs, 'exit': result.returncode, 'stderr': result.stderr})
            save(cls.out / 'commands.json', cls.commands)
            return result
        cls.report = compile_project(Project(source_root, Path('main.typ'), packages, compiler=str(wrapper), execute=execute),
                                     cls.out / 'compiled', map_sources=False)
        if cls.report['exitCode'] != 0 or not cls.report['contentGatePassed']:
            raise RuntimeError('actual compiler/content gate failed')
        cls.bundle = split_document((cls.out / 'compiled/document.html').read_text(), cls.report['revision'], max_blocks=2)
        cls.imported = import_accepted_document(cls.bundle, document_id=document_identity(source_root, Path('main.typ')),
                                               service_id='offline-no-service', generation=1, identity_scope='fixture')
        cls.model = cls.imported.document
        cls.oracle = json.loads((HERE / 'fixtures/contract.expect.json').read_text())
        for folder, items in [('sections', cls.bundle.documents), ('assets', cls.imported.assets)]:
            (cls.out / folder).mkdir()
            for key, content in items.items():
                (cls.out / folder / key).write_bytes(content)
        save(cls.out / 'manifest.json', cls.bundle.manifest)
        save(cls.out / 'native.json', cls.model)
        binary = cls.out / 'ContractTests'
        command(['swiftc', '-swift-version', '5', '-warnings-as-errors', '-target', 'arm64-apple-macosx13.0',
                 '-module-cache-path', os.environ['SWIFT_MODULECACHE_PATH'],
                 REPO / 'apps/macos/NativeReaderDocument.swift', REPO / 'apps/macos/NativeReaderOperations.swift',
                 HERE / 'ContractTests.swift', '-o', binary])
        cls.swift = json.loads(command([binary, cls.out / 'native.json', HERE / 'fixtures/contract.expect.json']))
        save(cls.out / 'swift-results.json', cls.swift)
        sources = [REPO / 'apps/macos/NativeReaderDocument.swift', REPO / 'apps/macos/NativeReaderOperations.swift',
                   REPO / 'tools/flow-reader/flow_reader/document/native_document.py', *sorted(HERE.rglob('*'))]
        inherited = [REPO / 'tools/flow-reader/flow_reader' / p for p in ['compiler/build.py', 'compiler/project.py',
                     'compiler/execution.py', 'compiler/audit.py', 'document/sections.py', 'document/passages.py']]
        save(cls.out / 'provenance.json', {
            'taskID': 'lagrangian-native-app-20261117-v1:NA01:ab1cf0a8cfb5',
            'head': command(['git', 'rev-parse', 'HEAD']), 'dirty': command(['git', 'status', '--short']),
            'os': platform.platform(), 'arch': platform.machine(), 'python': sys.version,
            'compiler': str(compiler), 'compilerSHA256': digest(compiler), 'compilerVersion': command([compiler, '--version']),
            'swiftVersion': command(['swiftc', '--version']), 'sdk': command(['xcrun', '--show-sdk-path']),
            'sdkVersion': command(['xcrun', '--show-sdk-version']), 'target': 'arm64-apple-macosx13.0',
            'runtimeScope': 'current host only; macOS13 runtime unverified; no live service or GUI',
            'sourceHashes': {str(p.relative_to(REPO)): digest(p) for p in sources + inherited if p.is_file()},
            'dependencyHashes': {p: digest(p) for p in cls.report['dependencies']},
            'packageHashes': {str(p.relative_to(packages)): digest(p) for p in packages.rglob('*') if p.is_file()},
            'cacheHashes': {str(p.relative_to(cache)): digest(p) for p in cache.rglob('*') if p.is_file()},
            'fixtureSHA256': digest(HERE / 'fixtures/document.typ'), 'oracleSHA256': digest(HERE / 'fixtures/contract.expect.json'),
            'oracleStatus': cls.oracle['oracleScope'], 'P0': 'inherited input only; independent review/testing pending',
            'compilerExit': cls.report['exitCode'], 'contentGatePassed': cls.report['contentGatePassed'],
            'sourceMapping': 'unmapped; map_sources=False; server freshness not simulated'})

    def nodes(self):
        def walk(n):
            yield n
            for c in n['children']:
                yield from walk(c)
        return [n for b in self.model['blocks'] for n in walk(b)]

    def test_real_order_and_transport(self):
        self.assertEqual(self.model['requiredCapabilities'], self.oracle['requiredCapabilities'])
        self.assertEqual([b['kind'] for b in self.model['blocks']], self.oracle['kinds'])
        self.assertEqual([b['canonicalText'] for b in self.model['blocks']], self.oracle['texts'])
        self.assertGreater(len(self.bundle.documents), 1)
        reordered = copy.copy(self.bundle)
        reordered.documents = dict(reversed(list(self.bundle.documents.items())))
        again = import_accepted_document(reordered, document_id=self.model['identity']['documentID'],
                                         service_id='offline-no-service', generation=1, identity_scope='fixture')
        self.assertEqual(again.document, self.model)

    def test_semantics_and_anchors(self):
        nodes = self.nodes()
        self.assertEqual([n['math']['normalizedText'] for n in nodes if n['kind'] == 'math'], self.oracle['mathTexts'])
        self.assertIn('<mfrac>', next(n['math']['mathML'] for n in nodes if n['kind'] == 'math' and n['math']['display']))
        self.assertEqual([n['canonicalText'] for n in nodes if n['kind'] == 'equationNumber'], [self.oracle['equationNumber']])
        cells = [n for n in nodes if n['kind'] == 'cell']
        self.assertEqual([n['canonicalText'] for n in cells], self.oracle['cellTexts'])
        self.assertEqual([n['cell']['columnSpan'] for n in cells], self.oracle['cellSpans'])
        self.assertEqual([n['cell']['header'] for n in cells], self.oracle['headers'])
        self.assertIn(self.oracle['externalLink'], [n.get('link') for n in nodes])
        self.assertEqual([n['canonicalText'] for n in nodes if n['kind'] == 'caption'], [self.oracle['figureCaption']])
        self.assertIn(self.oracle['annotationTarget'], [a for n in nodes for a in n['anchors']])
        self.assertIn(self.oracle['annotationTarget'], [a for n in nodes for a in n['annotationTargets']])
        svg = next(v.decode() for k, v in self.imported.assets.items() if k.endswith('.svg'))
        for token in self.oracle['figureSVGContains']:
            self.assertIn(token, svg)
        self.assertTrue(all(n['visible'] and n['mapping'] == 'unmapped' for n in nodes))

    def test_existing_asset_delivery_and_aria_heading(self):
        data = b'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 48 24"><path d="M0 0h48v24H0Z" fill="#2060c0"></path></svg>'
        key = hashlib.sha256(data).hexdigest() + '.svg'
        html = ('<html><body><div role="heading" aria-level="7" lang="ko" dir="rtl">Title</div>'
                '<figure><img src="api/assets/' + key + '" alt="Blue rectangle"></figure></body></html>')
        bundle = SectionBundle({'revision': 'asset-test', 'sections': [{'id': 's'}]}, {'s': html.encode()}, {key: data}, [])
        result = import_accepted_document(bundle, document_id='fixture', service_id='offline', generation=1, identity_scope='fixture')
        heading = result.document['blocks'][0]
        self.assertEqual(heading['headingLevel'], 7)
        self.assertEqual(heading['language'], 'ko')
        self.assertEqual(heading['direction'], 'rtl')
        self.assertEqual(result.document['blocks'][1]['children'][0]['alt'], 'Blue rectangle')
        self.assertTrue(result.assets)
        bundle.assets[key] = b'wrong bytes'
        with self.assertRaisesRegex(NativeImportError, 'asset-digest-mismatch'):
            import_accepted_document(bundle, document_id='fixture', service_id='offline', generation=1)

    def test_image_layout_units_css_and_atomic_negatives(self):
        data = b'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 12"><rect width="24" height="12" fill="#2060c0"/></svg>'
        key = hashlib.sha256(data).hexdigest() + '.svg'
        def image(attrs):
            return SectionBundle({'revision': 'image', 'sections': [{'id': 's'}]},
                {'s': ('<html><body><p>A<img src="api/assets/' + key + '" ' + attrs + '>Z</p></body></html>').encode()}, {key: data}, [])
        result = import_accepted_document(image('width="24" height="12" style="width: 48pt; height: 18pt; display: block" loading="lazy" decoding="async"'), document_id='fixture', service_id='offline', generation=1)
        layout = result.document['blocks'][0]['children'][1]['imageLayout']
        self.assertEqual(layout, dict(naturalUnit='pt', width=dict(value=48, unit='pt'), height=dict(value=18, unit='pt'), placement='block', fit='fill', loading='lazy', decoding='async'))
        self.assertEqual(result.assets[key], data)  # Original digest-bound SVG bytes.
        for attrs in ['width="0"', 'width="NaN"', 'height="inf"', 'width="4097"', 'width="-1"',
                      'width="20%"', 'width="1e999"', 'width', 'style', 'loading="auto"', 'decoding="lazy"',
                      'style="width: calc(1pt + 2pt)"', 'style="width: 2pt; width: 3pt"',
                      'style="position: absolute"', 'style="display: none"', 'style="overflow: visible"',
                      'style="object-fit: cover"', 'style="background: url(https://example.org/x)"']:
            with self.subTest(attrs=attrs), self.assertRaises(NativeImportError):
                import_accepted_document(image(attrs), document_id='fixture', service_id='offline', generation=1)
        for overflow in ['visible', 'hidden']:
            raw = '<svg viewBox="0 0 20 20"><defs><symbol id="s" viewBox="0 0 20 20" overflow="' + overflow + '"><rect width="20" height="20"/></symbol></defs><use href="#s" width="20" height="20"/></svg>'
            b = SectionBundle({'revision': 'svg', 'sections': [{'id': 's'}]}, {'s': ('<html><body>' + raw + '</body></html>').encode()}, {}, [])
            imported = import_accepted_document(b, document_id='fixture', service_id='offline', generation=1)
            self.assertIn(('overflow="' + overflow + '"').encode(), next(iter(imported.assets.values())))
            self.assertIn('image-layout-v1', imported.document['requiredCapabilities'])
        for svg in ['<svg viewBox="0 0 20 20" overflow="visible"/>',
                    '<svg viewBox="0 0 20 20"><symbol overflow="scroll"/></svg>',
                    '<svg viewBox="0 0 20 20"><g overflow="hidden"/></svg>',
                    '<svg viewBox="0 0 20 20"><use href="#missing"/></svg>',
                    '<svg viewBox="0 0 20 20"><defs><g id="a"><use href="#a"/></g></defs><use href="#a"/></svg>',
                    '<svg viewBox="0 0 20 20"><use href="https://example.org/x"/></svg>',
                    '<!DOCTYPE svg [<!ENTITY x SYSTEM "file:///private/x">]><svg viewBox="0 0 20 20">&x;</svg>',
                    '<svg viewBox="0 0 20 20" style="filter: blur(2px)"/>']:
            b = SectionBundle({'revision': 'svg', 'sections': [{'id': 's'}]}, {'s': ('<html><body>' + svg + '</body></html>').encode()}, {}, [])
            with self.subTest(svg=svg), self.assertRaises(NativeImportError):
                import_accepted_document(b, document_id='fixture', service_id='offline', generation=1)
        old = SectionBundle({'revision': 'legacy', 'sections': [{'id': 's'}]}, {'s': b'<html><body><p>Old semantic tree.</p></body></html>'}, {}, [])
        self.assertEqual(import_accepted_document(old, document_id='fixture', service_id='offline', generation=1).document['requiredCapabilities'], ['semantic-tree-v1'])

    def test_compiler_svg_data_uri_retains_bytes_and_rejects_unsafe_input(self):
        svg = json.loads((HERE / 'fixtures/objects.expect.json').read_text())['hiddenSymbolSVG'].encode()
        def bundle(source):
            html = '<html><body><img src="' + source + '" width="100" height="40" style="width: 100pt; height: 40pt; display: block"></body></html>'
            return SectionBundle({'revision': 'svg-data-image', 'sections': [{'id': 's'}]}, {'s': html.encode()}, {}, [])
        def uri(data):
            return 'data:image/svg+xml;base64,' + base64.b64encode(data).decode()
        imported = import_accepted_document(bundle(uri(svg)), document_id='fixture', service_id='offline', generation=1)
        key = hashlib.sha256(svg).hexdigest() + '.svg'
        self.assertEqual(imported.assets[key], svg)
        node = imported.document['blocks'][0]
        self.assertEqual(node['assetID'], key)
        self.assertEqual(node['imageLayout']['width'], dict(value=100, unit='pt'))
        self.assertEqual(imported.document['requiredCapabilities'], ['image-layout-v1', 'semantic-tree-v1'])
        bad = [('invalid-base64', 'data:image/svg+xml;base64,!!!!'), ('invalid-encoding', uri(b'\xff')),
               ('wrong-mime-content', uri(b'\x89PNG\r\n\x1a\n')), ('empty', uri(b'')),
               ('external', uri(b'<svg viewBox="0 0 20 20"><use href="https://example.org/x"/></svg>')),
               ('unresolved', uri(b'<svg viewBox="0 0 20 20"><use href="#absent"/></svg>')),
               ('cycle', uri(b'<svg viewBox="0 0 20 20"><symbol id="s" overflow="hidden"><use href="#s"/></symbol><use href="#s"/></svg>')),
               ('entity', uri(b'<!DOCTYPE svg [<!ENTITY e SYSTEM "file:///private/x">]><svg>&e;</svg>')),
               ('active', uri(b'<svg viewBox="0 0 20 20"><script/></svg>')),
               ('unknown-mime', 'data:application/xml;base64,' + base64.b64encode(svg).decode()),
               ('byte-budget', 'data:image/svg+xml;base64,' + 'A' * (4 * ((8 * 1024 * 1024 + 2) // 3) + 4))]
        for name, source in bad:
            with self.subTest(name=name), self.assertRaises(NativeImportError):
                import_accepted_document(bundle(source), document_id='fixture', service_id='offline', generation=1)

    def test_independent_units(self):
        for case in self.oracle['unicodeCases']:
            text = self.model['blocks'][1]['canonicalText']
            self.assertIn(case['text'], text)
            self.assertEqual([ord(c) for c in case['text']], case['scalars'])
        decomposed = self.oracle['unicodeCases'][1]['text']
        self.assertNotEqual(list(decomposed), list('한글'))

    def test_atomic_import_rejections(self):
        original = copy.deepcopy(self.model)
        for html in ['<unknown>lost</unknown>', '<p><span style="color:red">unhandled style</span></p>',
                     '<p id="same">A</p><p id="same">B</p>', '<p><a href="file:///private/data">bad</a></p>',
                     '<p><math><unknown>x</unknown></math></p>', '<p><img src="/private/picture.png"></p>',
                     '<svg><script>unsafe</script></svg>', '<svg><use href="file:///private/glyph"></use></svg>',
                     '<p role="button">unknown role</p>']:
            b = SectionBundle({'revision': 'negative', 'sections': [{'id': 's'}]}, {'s': ('<html><body>' + html + '</body></html>').encode()}, {}, [])
            with self.assertRaises(NativeImportError):
                import_accepted_document(b, document_id='fixture', service_id='offline', generation=1, identity_scope='fixture')
        with self.assertRaisesRegex(NativeImportError, 'unsupported-required-capability'):
            import_accepted_document(self.bundle, document_id='fixture', service_id='offline', generation=1, required_capabilities=['unknown'])
        self.assertEqual(original, self.model)

    def test_swift_adoption_selection_and_nine_layouts(self):
        self.assertEqual(self.swift['status'], 'pass')
        self.assertEqual(len(self.swift['matrix']), 9)
        self.assertTrue(all(r['status'] == 'pass' for r in self.swift['matrix']))

    def test_no_private_payload(self):
        payload = json.dumps(self.model)
        for value in [str(REPO), str(self.out), 'rawSource', 'source_ranges', 'credentials', 'source_stamp']:
            self.assertNotIn(value, payload)
        self.assertEqual(self.model['identity']['scope'], 'fixture')
        self.assertTrue(self.model['diagnostics'])
