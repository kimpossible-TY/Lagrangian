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
from types import SimpleNamespace
from unittest.mock import patch

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
                      'width="101%"', 'width="1e999"', 'width', 'style', 'loading="auto"', 'decoding="lazy"',
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

    def test_pde_metadata_attributes_and_unknown_attributes(self):
        def imported(html):
            bundle = SectionBundle({'revision': 'pde-attributes', 'sections': [{'id': 's'}]},
                {'s': ('<html><body>' + html + '</body></html>').encode()}, {}, [])
            return import_accepted_document(bundle, document_id='fixture', service_id='offline', generation=1)

        canvas = imported('<div class="flow-canvas" data-flow-canvas-identity="canvas-1">Canvas</div>')
        self.assertEqual(canvas.document['blocks'][0]['canonicalText'], 'Canvas')
        anchor = imported('<a href="https://example.org" data-project-ref-project="p" '
                          'data-project-ref-label="l" data-project-ref-title="t" '
                          'data-project-ref-page="1" data-project-ref-text="text">Link</a>')
        self.assertEqual(anchor.document['blocks'][0]['link'], 'https://example.org')
        for html in ['<div data-unknown="x">Canvas</div>', '<a href="https://example.org" data-unknown="x">Link</a>']:
            with self.subTest(html=html), self.assertRaisesRegex(NativeImportError, '^unsupported-attribute$'):
                imported(html)

    def test_pde_constructs_and_sanitization(self):
        def imported(html):
            bundle = SectionBundle({'revision': 'pde', 'sections': [{'id': 's'}]},
                {'s': ('<html><body>' + html + '</body></html>').encode()}, {}, [])
            return import_accepted_document(bundle, document_id='fixture', service_id='offline', generation=1)
        classes = 'flow-callout flow-callout-title flow-definition flow-note flow-lemma flow-proposition flow-emphasis flow-theorem flow-paragraph-tab flow-highlight flow-flowbox flow-aligned prefix flow-graphic flow-grid flow-book-cover flow-canvas flow-canvas-stage flow-canvas-labels flow-canvas-label flow-canvas-label-number flow-canvas-label-body flow-canvas-stack'
        html = ('<section class="' + classes + '" data-flow-canvas="x"><header role="doc-toc">H</header><nav><ol style="list-style-type:decimal"><li value="3"><sup>3</sup><mark>M</mark><code>C</code></li></ol><ul><li>L</li></ul></nav>'
                '<div style="display:flex;flex-wrap:wrap;flex-direction:row;gap:1em"><span aria-hidden="true" data-flow-request="x" data-flow-graphic="x" data-flow-canvas-package="x" data-flow-canvas-model="x" data-flow-canvas-label="x" style="white-space:pre;display:inline;font-size:1em;font-weight:bold;font-style:italic;color:red">x</span></div>'
                '<p><math><mmultiscripts><mi data-flow-mark="m" style="color:red">x</mi><mprescripts></mprescripts><mrow data-flow-mark="m"></mrow></mmultiscripts><sup id="fn"><a href="#end">1</a></sup><span class="flow-graphic"></span><br><code>c</code></math><span data-flow-targets="[&quot;m&quot;]">z</span></p><p id="end" role="doc-endnotes"><a role="doc-backlink" href="#fn">back</a></p></section>')
        result = imported(html)
        def walk(node):
            yield node
            for child in node['children']:
                yield from walk(child)
        nodes = [n for block in result.document['blocks'] for n in walk(block)]
        mathnode = next(n for n in nodes if n['kind'] == 'math')
        self.assertEqual(mathnode['anchors'], ['mark:m', 'fn'])
        self.assertIn('<msup><mrow></mrow><mtext>1</mtext></msup>', mathnode['math']['mathML'])
        self.assertNotIn('data-flow-', mathnode['math']['mathML'])
        self.assertEqual(mathnode['canonicalText'], 'x1\nc')
        duplicate = imported('<p><math><mi id="mark:x" data-flow-mark="x">x</mi><mi data-flow-mark="x">y</mi></math><span data-flow-targets="[&quot;x&quot;]">z</span></p>')
        duplicate_math = next(n for b in duplicate.document['blocks'] for n in walk(b) if n['kind'] == 'math')
        self.assertEqual(duplicate_math['anchors'], ['mark:x'])
        gradient = imported('<svg><defs><linearGradient id="g"><stop stop-color="#ff000080" stop-opacity="0.5"/></linearGradient></defs><rect fill="url(#g)" style="stroke:#00ff0080;stroke-opacity:0.5"/><rect style="fill:#ff000080;fill-opacity:0.5"/></svg>')
        normalized = next(iter(gradient.assets.values())).decode()
        self.assertIn('stop-color="#ff0000"', normalized)
        self.assertIn('stop-opacity="0.25098039215686274"', normalized)
        self.assertIn('stroke:#00ff00;stroke-opacity:0.25098039215686274', normalized)
        self.assertIn('fill:#ff0000;fill-opacity:0.25098039215686274', normalized)
        png = base64.b64encode(b'\x89PNG\r\n\x1a\n').decode()
        svg = '<svg xmlns:h5="http://www.w3.org/1999/xhtml"><svg><rect fill="#ff000080" stroke="oklab(100% 0 0)"/><image width="1" height="1" href="data:image/png;base64,' + png + '" data-flow-raster-layer="x"/></svg></svg>'
        data = next(iter(imported(svg).assets.values())).decode()
        for part in ['fill="#ff0000"', 'fill-opacity=', 'stroke="#ffffff"', '<image', '<svg><svg>']:
            self.assertIn(part, data)
        self.assertNotIn('xmlns:h5', data)
        for bad in ['<span style="color:expression(x)">x</span>', '<div style="position:absolute">x</div>', '<svg><image width="1" height="1" href="https://example.org/x"/></svg>', '<svg><image width="1" height="1" href="data:image/jpeg;base64,AAAA"/></svg>', '<svg><text>x</text></svg>']:
            with self.subTest(bad=bad), self.assertRaises(NativeImportError):
                imported(bad)

    def test_pde_marks_math_html_styles_and_numbering(self):
        from html import escape
        from xml.etree import ElementTree as ET
        def imported(html):
            bundle = SectionBundle({'revision': 'pde-regression', 'sections': [{'id': 'a'}, {'id': 'b'}]},
                {'a': ('<html><body>' + html + '</body></html>').encode(),
                 'b': b'<html><body><p id="same"><span data-flow-mark="repeat">again</span></p></body></html>'}, {}, [])
            return import_accepted_document(bundle, document_id='fixture', service_id='offline', generation=1).document
        name = '한글 mark, spaced'
        encoded = 'mark:h-' + hashlib.sha256(name.encode()).hexdigest()[:24]
        targets = escape(json.dumps([name, 'repeat'], ensure_ascii=False), quote=True)
        html = ('<p id="same"><span data-flow-mark="' + name + '">A</span><span id="mark:repeat" data-flow-mark="repeat">B</span></p>'
                '<p><math><mi data-flow-mark="repeat">x</mi>'
                '<span class="flow-annotation" data-flow-targets="' + targets + '">α<span style="font-family:serif;text-decoration:underline">β</span></span>'
                '<span class="flow-graphic" data-flow-graphic="opaque" data-flow-targets="repeat">G</span>'
                '<span>plain</span><sup id="note" role="doc-noteref"><a href="#same">1</a></sup>'
                '<a href="https://example.org">link</a><br><code data-lang="typst">code</code></math>'
                '<span data-flow-targets="repeat, repeat">Z</span></p>'
                '<ol start="4"><li>four</li><li value="9">nine</li><li>ten<ol><li>one</li></ol></li><li value="-2">minus</li><li>minus one</li></ol>')
        document = imported(html)
        def walk(n):
            yield n
            for c in n['children']:
                yield from walk(c)
        nodes = [n for b in document['blocks'] for n in walk(b)]
        anchors = [a for n in nodes for a in n['anchors']]
        self.assertEqual(anchors, ['same', encoded, 'mark:repeat', 'note'])
        mathnode = next(n for n in nodes if n['kind'] == 'math')
        self.assertEqual(mathnode['annotationTargets'], [encoded, 'mark:repeat', 'mark:repeat'])
        self.assertEqual(mathnode['canonicalText'], 'xαβGplain1link\ncode')
        self.assertEqual(mathnode['canonicalText'], mathnode['displayText'])
        xml = ET.fromstring(mathnode['math']['mathML'])
        self.assertEqual(''.join(xml.itertext()), mathnode['canonicalText'])
        self.assertTrue(all(e.tag in {'math', 'mi', 'mrow', 'mtext', 'msup'} for e in xml.iter()))
        self.assertEqual([n['listItemNumber'] for n in nodes if 'listItemNumber' in n], [4, 9, 10, 1, -2, -1])
        self.assertEqual(imported(html), document)
        # Exercise the actual Swift wire decoder, recovery encoding and rebinding,
        # including mark: tokens whose prefix extends the 128-character name.
        names = ['a' * 128, 'a' * 129, '공백 이름']
        extra = ''.join('<span data-flow-mark="' + n + '">' + n + '</span>' for n in names)
        extra += '<span data-flow-targets="' + escape(json.dumps(names), quote=True) + '">target</span>'
        pde = self.out / 'pde-contract.json'
        save(pde, imported(html + '<p>' + extra + '</p>'))
        self.assertEqual(self.command([self.out / 'ContractTests', '--roundtrip', pde]), 'ok')
        for family in ['sans-serif', 'serif', 'monospace']:
            for decoration in ['underline', 'none', 'line-through']:
                imported('<p><span style="font-family:' + family + ';text-decoration:' + decoration + '">ok</span></p>')
        for bad in ['<span data-flow-targets="[1]">x</span>', '<span data-flow-targets="[]">x</span>',
                    '<span data-flow-targets="[&quot;x&quot;,]">x</span>', '<span data-flow-targets="[&quot;&quot;]">x</span>',
                    '<span style="font-family:evil">x</span>', '<span style="text-decoration:blink">x</span>',
                    '<math><span style="font-family:url(evil)">x</span></math>', '<math><a href="file:///x">x</a></math>',
                    '<math><span onclick="x">x</span></math>', '<math><code data-lang="x"><script>x</script></code></math>',
                    '<ol><li value="2147483648">x</li></ol>', '<ol start="oops"><li>x</li></ol>']:
            with self.subTest(bad=bad), self.assertRaises(NativeImportError):
                imported(bad)

    def test_svg_alpha_precedence_and_oklab(self):
        from xml.etree import ElementTree as ET
        def normalized(body):
            bundle = SectionBundle({'revision': 'colors', 'sections': [{'id': 's'}]},
                {'s': ('<html><body><svg viewBox="0 0 10 10">' + body + '</svg></body></html>').encode()}, {}, [])
            result = import_accepted_document(bundle, document_id='fixture', service_id='offline', generation=1)
            return ET.fromstring(next(iter(result.assets.values())))
        for color, opacity in [('fill', 'fill-opacity'), ('stroke', 'stroke-opacity'), ('stop-color', 'stop-opacity')]:
            for paint_style in [False, True]:
                for alpha_style in [False, True]:
                    attrs, style = {}, {}
                    (style if paint_style else attrs)[color] = '#12345680'
                    (style if alpha_style else attrs)[opacity] = '0.5'
                    if style:
                        attrs['style'] = ';'.join(k + ':' + v for k, v in style.items())
                    attr = ' '.join(k + '="' + v + '"' for k, v in attrs.items())
                    body = '<stop ' + attr + '/>' if color == 'stop-color' else '<rect width="10" height="10" ' + attr + '/>'
                    if color == 'stop-color':
                        body = '<defs><linearGradient id="g">' + body + '</linearGradient></defs>'
                    node = next(e for e in normalized(body).iter() if e.tag == ('stop' if color == 'stop-color' else 'rect'))
                    effective = dict(node.attrib)
                    effective.update(dict(p.split(':') for p in effective.pop('style', '').split(';') if p))
                    self.assertEqual(effective[color], '#123456')
                    self.assertAlmostEqual(float(effective[opacity]), 0.5 * 128 / 255)
            # A style paint overrides the attribute paint and its alpha.
            node = normalized('<rect fill="#12345680" fill-opacity="0.5" style="fill:#abcdef40;fill-opacity:0.25"/>')[0]
            self.assertIn('fill-opacity:' + str(0.25 * 64 / 255), node.attrib['style'])
        colors = ['oklab(0% 0 0)', 'oklab(100% 0 0)', 'oklab(50% 0 0)', 'oklab(200% 0 0)', 'oklab(-20% 0 0)', 'oklab(70% 0.4 -0.4)']
        root = normalized(''.join('<rect fill="' + c + '"/>' for c in colors))
        self.assertEqual([e.attrib['fill'] for e in root][:5], ['#000000', '#ffffff', '#636363', '#ffffff', '#000000'])
        self.assertRegex(root[-1].attrib['fill'], r'^#[0-9a-f]{6}$')

    def test_svg_hex_alpha_inherits_paint_and_explicit_opacity_separately(self):
        from xml.etree import ElementTree as ET
        def effective(node):
            attrs = dict(node.attrib)
            attrs.update(dict(p.split(':') for p in attrs.pop('style', '').split(';') if p))
            return attrs
        def normalized(body, delivery='inline'):
            svg = '<svg viewBox="0 0 10 10">' + body + '</svg>'
            assets = {}
            if delivery == 'data':
                html = '<img src="data:image/svg+xml;base64,' + base64.b64encode(svg.encode()).decode() + '">'
            elif delivery == 'asset':
                key = hashlib.sha256(svg.encode()).hexdigest() + '.svg'
                assets[key] = svg.encode()
                html = '<img src="api/assets/' + key + '">'
            else:
                html = svg
            bundle = SectionBundle({'revision': 'alpha-inheritance', 'sections': [{'id': 's'}]},
                {'s': ('<html><body>' + html + '</body></html>').encode()}, assets, [])
            result = import_accepted_document(bundle, document_id='fixture', service_id='offline', generation=1)
            return ET.fromstring(next(iter(result.assets.values())))[0]
        for paint in ['fill', 'stroke']:
            opacity = paint + '-opacity'
            for color, alpha in [('#ff000080', 128 / 255), ('#f008', 136 / 255)]:
                for css in [False, True]:
                    def attr(values):
                        return ('style="' + ';'.join(k + ':' + v for k, v in values.items()) + '"' if css else
                                ' '.join(k + '="' + v + '"' for k, v in values.items()))
                    with self.subTest(paint=paint, color=color, css=css):
                        group = normalized('<g ' + attr({opacity: '0.5'}) + '><g><rect ' + attr({paint: color}) + '/></g></g>')
                        child = effective(group[0][0])
                        self.assertEqual(child[paint], '#ff0000')
                        self.assertAlmostEqual(float(child[opacity]), 0.5 * alpha)
                        group = normalized('<g ' + attr({paint: color, opacity: '0.5'}) + '><g><rect ' + attr({paint: '#0000ff'}) + '/></g><rect/><rect ' + attr({opacity: '0.25'}) + '/></g>')
                        self.assertAlmostEqual(float(effective(group)[opacity]), 0.5 * alpha)
                        self.assertEqual(effective(group[0][0])[paint], '#0000ff')
                        self.assertAlmostEqual(float(effective(group[0][0])[opacity]), 0.5)
                        self.assertAlmostEqual(float(effective(group[1])[opacity]), 0.5 * alpha)
                        self.assertAlmostEqual(float(effective(group[2])[opacity]), 0.25 * alpha)
                        group = normalized('<g ' + attr({paint: color}) + '><rect ' + attr({paint: '#0000ff'}) + '/></g>')
                        self.assertEqual(float(effective(group[0])[opacity]), 1)
                for delivery in ['inline', 'data', 'asset']:
                    # CSS paint and presentation opacity have independent
                    # cascades, including through digest-bound SVG delivery.
                    group = normalized('<g style="' + opacity + ':0.5"><g ' + paint + '="' + color +
                        '"><rect style="' + paint + ':#0000ff"/><rect ' + opacity +
                        '="0.25"/><rect ' + paint + '="' + color + '" style="' + opacity + ':0.75"/></g></g>', delivery)
                    children = [effective(child) for child in group[0]]
                    with self.subTest(paint=paint, color=color, delivery=delivery):
                        self.assertEqual(float(children[0][opacity]), 0.5)
                        self.assertAlmostEqual(float(children[1][opacity]), 0.25 * alpha)
                        self.assertAlmostEqual(float(children[2][opacity]), 0.75 * alpha)

    def test_svg_use_hex_alpha_inherits_instance_opacity(self):
        from xml.etree import ElementTree as ET
        for paint in ('fill', 'stroke'):
            opacity = paint + '-opacity'
            for color, alpha in (('#ff000080', 128 / 255), ('#f008', 136 / 255)):
                for opaque in (False, True):
                    target = ('<g id="target" ' + paint + '="' + color + '"><rect ' + paint + '="#0000ff"/></g>'
                              if opaque else '<rect id="target" ' + paint + '="' + color + '"/>')
                    svg = '<svg viewBox="0 0 10 10"><defs>' + target + '</defs><use href="#target" ' + opacity + '="0.5"/></svg>'
                    bundle = SectionBundle({'revision': 'use-alpha', 'sections': [{'id': 's'}]},
                        {'s': ('<html><body>' + svg + '</body></html>').encode()}, {}, [])
                    result = import_accepted_document(bundle, document_id='fixture', service_id='offline', generation=1)
                    root = ET.fromstring(next(iter(result.assets.values())))
                    use = next(e for e in root.iter() if e.tag.endswith('use'))
                    identifier = next(v[1:] for k, v in use.attrib.items() if k.endswith('href'))
                    instance = next(e for e in root.iter() if e.attrib.get('id') == identifier)
                    rect = next(e for e in instance.iter() if e.tag.endswith('rect'))
                    attrs = dict(rect.attrib)
                    attrs.update(dict(p.split(':') for p in attrs.pop('style', '').split(';') if p))
                    with self.subTest(paint=paint, color=color, opaque=opaque):
                        self.assertAlmostEqual(float(attrs[opacity]), 0.5 * (1 if opaque else alpha))
                        self.assertEqual(attrs[paint], '#0000ff' if opaque else '#ff0000')

    def test_percentage_image_layout(self):
        data = b'<svg viewBox="0 0 20 10"><rect width="20" height="10"/></svg>'
        key = hashlib.sha256(data).hexdigest() + '.svg'
        for attrs in ['width="50%" height="100%"', 'style="width:50%;height:100%"']:
            b = SectionBundle({'revision': 'percent', 'sections': [{'id': 's'}]},
                {'s': ('<html><body><img src="api/assets/' + key + '" ' + attrs + '></body></html>').encode()}, {key: data}, [])
            result = import_accepted_document(b, document_id='fixture', service_id='offline', generation=1)
            layout = result.document['blocks'][0]['imageLayout']
            self.assertEqual(layout['width'], {'value': 50, 'unit': '%'})
            self.assertEqual(layout['height'], {'value': 100, 'unit': '%'})
            fixture = self.out / 'percentage-contract.json'
            save(fixture, result.document)
            self.assertEqual(self.command([self.out / 'ContractTests', '--roundtrip', fixture]), 'ok')
        from flow_reader.document.native_document import _image_layout
        for value in ['0%', '-1%', '100.01%', 'NaN%', 'inf%', '1e999%']:
            with self.subTest(value=value), self.assertRaises(NativeImportError):
                _image_layout({'width': value}, natural_unit='px')

    def test_compact_document_budget(self):
        from flow_reader.server import native_reader
        self.assertEqual(native_reader.MAX_DOCUMENT, 64 * 1024 * 1024)
        document = {'values': ['a', 'b']}
        compact = len(json.dumps(document, ensure_ascii=False, separators=(',', ':')).encode())
        snapshot = SimpleNamespace(revision='r', inputs='i', bundle=None)
        state = SimpleNamespace(focus=SimpleNamespace(service={'pid': 1, 'startedAt': 2}), document_id='d')
        service = native_reader.NativeReaderService.__new__(native_reader.NativeReaderService)
        service.state, service.cached = state, None
        result = SimpleNamespace(document=document, assets={})
        with patch.object(native_reader, 'import_accepted_document', return_value=result), patch.object(native_reader, 'MAX_DOCUMENT', compact):
            self.assertIs(service.imported(snapshot), result)
            service.cached = None
            with patch.object(native_reader, 'MAX_DOCUMENT', compact - 1), self.assertRaisesRegex(ValueError, 'document limit'):
                service.imported(snapshot)

    def test_independent_units(self):
        for case in self.oracle['unicodeCases']:
            text = self.model['blocks'][1]['canonicalText']
            self.assertIn(case['text'], text)
            self.assertEqual([ord(c) for c in case['text']], case['scalars'])
        decomposed = self.oracle['unicodeCases'][1]['text']
        self.assertNotEqual(list(decomposed), list('한글'))

    def test_atomic_import_rejections(self):
        original = copy.deepcopy(self.model)
        for html in ['<unknown>lost</unknown>', '<p><span style="color:url(evil)">unsafe style</span></p>',
                     '<p><a href="file:///private/data">bad</a></p>',
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
