"""NA10 real pinned computation + native attributed paint. No downloads/GUI.

Every invocation retains fresh commands, inputs, source bytes and exits on DevSSD.
The NA11 package is read-only; its original helper is never overwritten.
"""
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import time
import unittest
import uuid
import xml.etree.ElementTree as ET

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
DEV = Path('/Volumes/devSSD/Developer/lagrangian-native-20261117')
ROOT = Path(os.environ.get('NA10_ROOT', DEV / 'test-output/chat-math/NA10'))
RUNTIME = Path(os.environ.get('FLOW_TEST_NATIVE_RUNTIME', DEV / 'build/runtime-producer/NA11/runtime'))
NODE = Path(os.environ.get('FLOW_TEST_NODE', '/opt/homebrew/Cellar/node/26.13.1/bin/node'))
OWNED = ['tools/flow-reader/native/math_layout.mjs', 'apps/macos/NativeReaderObjectRenderer.swift',
         'apps/macos/NativeReaderChatView.swift', 'tests/flow-app/native-reader-app/ChatMathTests.swift',
         'tests/flow-app/native-reader-app/test_chat_math.py', 'tests/flow-app/native-reader-app/fixtures/chat-math.expect.json',
         'tests/flow-app/native-reader-app/fixtures/chat-math.typ', 'docs/tinymist/dev/native-reader-chat-math.typ']
for name, folder in [('TMPDIR', DEV / 'tmp/chat-math'), ('CLANG_MODULE_CACHE_PATH', DEV / 'cache/chat-math/clang'),
                     ('SWIFT_MODULECACHE_PATH', DEV / 'cache/chat-math/swift')]:
    folder = Path(os.environ.get(name, folder))
    folder.mkdir(parents=True, exist_ok=True)
    os.environ[name] = str(folder)


def digest(path):
    p = Path(path)
    return hashlib.sha256(os.readlink(p).encode() if p.is_symlink() else p.read_bytes()).hexdigest()


def save(path, value):
    Path(path).write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')


class ChatMathTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.out = Path(os.environ.get('NA10_OUTPUT', ROOT / ('run-' + str(time.time_ns())))).resolve()
        if not cls.out.is_relative_to(ROOT) or cls.out.exists():
            raise RuntimeError('NA10_OUTPUT must be a fresh directory below chat-math/NA10')
        cls.out.mkdir(parents=True)
        cls.commands = []
        save(cls.out / 'run.json', {'uuid': str(uuid.uuid4()), 'session': os.environ.get('CODEX_THREAD_ID'),
                                  'scope': 'headless component; no GUI/product delivery/macOS13 runtime claim'})
        manifest = RUNTIME / 'runtime-manifest.json'
        if digest(manifest) != os.environ.get('FLOW_TEST_RUNTIME_MANIFEST_SHA256', 'e2fbdb745477db56a4a6505503656cd64d27ad9e13c428c395ec46537c531eb7'):
            raise RuntimeError('NA11 manifest binding changed')
        cls.runtime_before = {str(p.relative_to(RUNTIME)): digest(p) for p in RUNTIME.rglob('*') if p.is_file()}
        inventory = json.loads(manifest.read_text())
        for item in inventory['files']:
            if cls.runtime_before.get(item['path']) != item['sha256']:
                raise RuntimeError('NA11 verified file mismatch: ' + item['path'])
        save(cls.out / 'runtime-input-binding.json', cls.runtime_before)
        cls.sources = [REPO / p for p in OWNED if (REPO / p).is_file()]
        (cls.out / 'source-before').mkdir()
        for p in cls.sources:
            target = cls.out / 'source-before' / p.relative_to(REPO)
            target.parent.mkdir(parents=True, exist_ok=True); shutil.copyfile(p, target)
        cls.before = {str(p.relative_to(REPO)): digest(p) for p in cls.sources}
        save(cls.out / 'source-before.json', cls.before)
        cls.oracle = json.loads((HERE / 'fixtures/chat-math.expect.json').read_text())
        cls.helper = ['/usr/bin/sandbox-exec', '-p', '(version 1)(allow default)(deny network*)(deny file-write*)',
                      NODE, '--max-old-space-size=128', '--stack-size=1024', REPO / OWNED[0], '--runtime', RUNTIME]
        cls.positive = {}
        for item in cls.oracle['cases']:
            cls.positive[item['id']] = json.loads(cls.command(cls.helper, cls.input(tex=item['tex'], display=item['display'], kind='tex')).stdout)
        manifest_sources = json.loads((REPO / 'apps/macos/sources.json').read_text())
        cls.swift_sources = [REPO / 'apps/macos' / n for n in
                             [*[n for n in manifest_sources['core'] if n != 'CLI.swift'], *manifest_sources['native']]]
        cls.binary = cls.out / 'ChatMathTests'
        cls.command(['swiftc', '-parse-as-library', '-swift-version', '5', '-warnings-as-errors', '-target', 'arm64-apple-macosx13.0',
                     '-module-cache-path', os.environ['SWIFT_MODULECACHE_PATH'], *cls.swift_sources, HERE / 'ChatMathTests.swift', '-o', cls.binary], timeout=120)
        slow = cls.out / 'slow.mjs'; slow.write_text("setTimeout(()=>process.stdout.write('{}'),5000);")
        flood = cls.out / 'flood.mjs'; flood.write_text("process.stdout.write('x'.repeat(9*1024*1024));")
        memory = cls.out / 'memory.mjs'; memory.write_text("globalThis.held=Buffer.alloc(280*1024*1024,1);setTimeout(()=>{},5000);")
        save(cls.out / 'config.json', dict(node=str(NODE), runtime=str(RUNTIME), helper=str(REPO / OWNED[0]), slow=str(slow), flood=str(flood), memory=str(memory)))
        save(cls.out / 'compile-source-binding.json', {str(p.relative_to(REPO)): digest(p) for p in cls.swift_sources})

    @classmethod
    def command(cls, args, payload=None, expected=0, timeout=30):
        argv = list(map(str, args)); start = time.monotonic()
        raw = json.dumps(payload, ensure_ascii=False) if payload is not None else None
        try:
            p = subprocess.run(argv, input=raw, text=True, capture_output=True, cwd=REPO, timeout=timeout)
            record = dict(argv=argv, exit=p.returncode, stdout=p.stdout, stderr=p.stderr, seconds=time.monotonic()-start)
        except subprocess.TimeoutExpired as e:
            record = dict(argv=argv, exit=None, timeout=True, stdout=str(e.stdout), stderr=str(e.stderr))
            cls.commands.append(record); save(cls.out / 'commands.json', cls.commands)
            raise
        if payload is not None:
            record['input'] = payload
        cls.commands.append(record); save(cls.out / 'commands.json', cls.commands)
        if p.returncode != expected:
            raise RuntimeError(f'exit {p.returncode}, expected {expected}: {argv}: {p.stderr[-4000:]}')
        return p

    @staticmethod
    def input(**source):
        return dict(width=320, fontSize=20, font='MathJaxNewcm', context=dict(revision='na10', generation=1, theme='light'), **source)

    @classmethod
    def tearDownClass(cls):
        after = {str(p.relative_to(REPO)): digest(p) for p in cls.sources}
        save(cls.out / 'source-after.json', after)
        runtime_after = {str(p.relative_to(RUNTIME)): digest(p) for p in RUNTIME.rglob('*') if p.is_file()}
        save(cls.out / 'immutability.json', dict(sourceUnchanged=after == cls.before, runtimeUnchanged=runtime_after == cls.runtime_before))
        if after != cls.before or runtime_after != cls.runtime_before:
            raise RuntimeError('input bytes changed during test')

    def test_independent_semantics_metrics_unicode_and_topology(self):
        for item in self.oracle['cases']:
            r = self.positive[item['id']]
            self.assertIn(item['semantic'], r['semanticText'])
            tree = ET.fromstring(r['normalizedMathML'])
            kinds = {n.tag.split('}')[-1] for n in tree.iter()}
            self.assertTrue(set(item['nodes']).issubset(kinds), item['id'])
            svg = ET.fromstring(r['whole']['svg'])
            glyphs = {n.get('data-c') for n in svg.iter() if n.tag.endswith('path')}
            self.assertTrue(set(item['glyphs']).issubset(glyphs), (item['id'], glyphs))
            self.assertNotRegex(r['whole']['svg'], r'<text|<image|<use|href=')
            self.assertEqual(r['inputHash'], hashlib.sha256(item['tex'].encode()).hexdigest())
            for field in ['width', 'ascent', 'descent']:
                self.assertGreaterEqual(r['whole'][field], 0)
        r = self.positive['fraction']; ns = {'s': 'http://www.w3.org/2000/svg'}
        frac = ET.fromstring(r['whole']['svg']).find('.//s:g[@data-mml-node="mfrac"]', ns)
        groups = frac.findall('s:g', ns); bar = frac.find('s:rect', ns).attrib
        self.assertEqual(groups[0].find('.//s:path', ns).get('data-c'), self.oracle['fraction']['numerator'])
        self.assertEqual(groups[1].find('.//s:path', ns).get('data-c'), self.oracle['fraction']['denominator'])
        y = lambda n: float(re.search(r'translate\([^,]+,([^)]+)\)', n.get('transform'))[1])
        self.assertGreater(y(groups[0]), float(bar['y']) + float(bar['height']))
        self.assertLess(y(groups[1]), float(bar['y']))
        self.assertAlmostEqual(float(bar['height']) / 1000, self.oracle['fraction']['ruleEm'])

    def test_tex_security_and_budgets(self):
        bad = [r'\require{html}', r'\autoload{evil}', r'\href{file:///etc/passwd}{x}', r'\htmlClass{x}{y}',
               r'\def\x{\x}\x', r'\newcommand{\x}{\x}\x', r'\csname require\endcsname{x}',
               r'\input{/etc/passwd}', r'\includegraphics{https://invalid/x}', r'\unknown{x}',
               r'\frac{1}{', r'\begin{unknown}x\end{unknown}', r'\begin{matrix}x\end{aligned}',
               '{' * 65 + 'x' + '}' * 65, 'x' * 16385, 'x+' * 4100, '$x$', r'\text{https://invalid/}', '𠀀']
        for tex in bad:
            p = self.command(self.helper, self.input(kind='tex', tex=tex, display=False), expected=2)
            self.assertEqual(p.stdout, '')
            self.assertEqual(json.loads(p.stderr)['status'], 'unsupported')
        good = self.input(kind='tex', tex='x', display=False)
        for patch in [dict(mathML='<math/>'), dict(kind='arbitrary'), dict(display='false'), dict(macros={}), dict(width=0), dict(tex='x'*65537)]:
            self.command(self.helper, good | patch, expected=2)

    def test_existing_mathml_contract_and_negative_preservation(self):
        for mml in ['<math display="inline"><mi>x</mi></math>', '<math><mi>Ж</mi></math>',
                    '<math><mfrac><mn>1</mn><mn>2</mn></mfrac></math>', '<math><mi>x</mi><mo>+</mo><mi>y</mi></math>']:
            old = json.loads(self.command(self.helper, self.input(mathML=mml)).stdout)
            new = json.loads(self.command(self.helper, self.input(kind='mathml', mathML=mml)).stdout)
            self.assertEqual(old, new)
            self.assertGreaterEqual(old['whole']['descent'], 0)
        for mml in ['<!DOCTYPE math><math/>', '<math><mi href="file:///etc/passwd">x</mi></math>',
                    '<math><mi>x</math>', '<math>raw</math>', '<math><unknown/></math>', '<math><mtext>𠀀</mtext></math>']:
            self.command(self.helper, self.input(mathML=mml), expected=2)

    def test_real_native_worker_painter_chat_lifetime_copy_ax_runloop(self):
        self.command([self.binary, self.out, HERE / 'fixtures/chat-math.expect.json'], timeout=100)
        report = json.loads((self.out / 'native-results.json').read_text())
        self.assertGreaterEqual(report['assertions'], 100)
        self.assertEqual(report['paintCases'], 12)
        self.assertEqual(report['skips'], 0)
        self.assertEqual(report['actions'], 0)
        self.assertGreater(report['uiTicks'], 2)
        proof = json.loads((self.out / 'transcript-pixel-proof.json').read_text())
        self.assertEqual([p['theme'] for p in proof], ['light', 'dark'])
        for item in proof:
            self.assertTrue(item['actual']['pass'])
            self.assertEqual(len(item['actual']['foregroundCounts']), 6)
            for mutant in ['empty', 'headingOnly', 'brokenAttachment']:
                self.assertFalse(item[mutant]['pass'])
        self.assertEqual(report['transcriptMutantsRejected'], 6)

    def test_explicit_module_and_font_inventory(self):
        files = set().union(*(r['runtime']['moduleFiles'] for r in self.positive.values()))
        self.assertTrue(any(p.endswith('/tex.js') for p in files))
        self.assertTrue(any(p.endswith('/tex/ams/AmsConfiguration.js') for p in files))
        forbidden = ['/tex/require/', '/tex/autoload/', '/tex/html/', '/tex/configmacros/']
        self.assertFalse(any(word in p for p in files for word in forbidden))
        transitive = {p.split('/tex/newcommand/')[-1] for p in files if '/tex/newcommand/' in p}
        self.assertEqual(transitive, {'NewcommandConfiguration.js', 'NewcommandItems.js', 'NewcommandMappings.js', 'NewcommandMethods.js', 'NewcommandUtil.js'})
        # Pinned AMS imports its internal utility; no user newcommand package is enabled.
        for result in self.positive.values():
            self.assertEqual(result['runtime']['inputPackages'], ['base', 'ams'])
        self.assertTrue(any('/svg/dynamic/cyrillic.js' in p for p in files))
        save(self.out / 'tex-module-inventory.json', {p: self.runtime_before[p] for p in sorted(files)})

    def test_os_network_and_file_write_denied(self):
        prefix = self.helper[:6]
        # Keep exactly the worker's own sandbox, never an outer nested sandbox.
        for code in ["require('net').createServer().listen(0,'127.0.0.1')",
                     "require('fs').writeFileSync(" + json.dumps(str(self.out / 'forbidden')) + ",'x')"]:
            p = self.command([*prefix, '-e', code], expected=1)
            self.assertRegex(p.stderr, 'EPERM|EACCES')
        self.assertFalse((self.out / 'forbidden').exists())

    def test_prebuilt_typst_oracle_and_canonical_document(self):
        compiler = shutil.which('typst')
        self.assertIsNotNone(compiler)
        for name, source in [('oracle', HERE / 'fixtures/chat-math.typ'), ('handoff', REPO / OWNED[-1])]:
            self.command(['/usr/bin/sandbox-exec', '-p', '(version 1)(allow default)(deny network*)', compiler,
                          'compile', source, self.out / (name + '.pdf')])


if __name__ == '__main__':
    unittest.main()
