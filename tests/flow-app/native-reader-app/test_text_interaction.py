"""Bounded NA02: actual AppKit views + real NA01 compiler fixture, no GUI acceptance.

Object callbacks below are deliberately unit fixtures, not NA03 fidelity evidence.
Artifacts include failed compiler/runtime attempts; missing prerequisites fail.
"""
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import time
import unittest

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
DEV = Path('/Volumes/devSSD/Developer/lagrangian-native-20261117')
PRODUCT = ['apps/macos/NativeReaderTextView.swift', 'apps/macos/NativeReaderSelection.swift',
           'apps/macos/NativeReaderAccessibility.swift']
COMMON = ['apps/macos/NativeReaderDocument.swift', 'apps/macos/NativeReaderOperations.swift']


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def save(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')


class TextInteractionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.evidence_root = Path(os.environ.get('NA02_OUTPUT_ROOT', str(DEV / 'test-output/text'))).resolve()
        if not cls.evidence_root.is_relative_to(DEV / 'test-output/text'):
            raise RuntimeError('Evidence must remain under test-output/text')
        cls.out = cls.evidence_root / time.strftime('run-%Y%m%d-%H%M%S')
        cls.out.mkdir(parents=True, exist_ok=False)
        cls.commands = []
        for key, folder in [('TMPDIR', 'tmp/text'), ('CLANG_MODULE_CACHE_PATH', 'cache/text/clang'),
                            ('SWIFT_MODULECACHE_PATH', 'cache/text/swift')]:
            value = DEV / folder
            value.mkdir(parents=True, exist_ok=True)
            os.environ[key] = str(value)
        cls.started = time.time()

        def command(argv):
            start = time.time()
            result = subprocess.run([str(a) for a in argv], cwd=REPO, text=True, capture_output=True,
                                    timeout=180, env=os.environ.copy())
            cls.commands.append({'argv': [str(a) for a in argv], 'exit': result.returncode,
                                 'seconds': time.time() - start, 'stdout': result.stdout, 'stderr': result.stderr})
            save(cls.out / 'commands.json', cls.commands)
            if result.returncode:
                raise RuntimeError(f'command exit {result.returncode}: {argv[0]}\n{result.stderr}\n{result.stdout}')
            return result.stdout.strip()

        cls.command = staticmethod(command)
        fixture = Path(os.environ.get('NA02_FIXTURE', str(DEV / 'test-output/contract/final-contract'))).resolve()
        if not fixture.is_relative_to(DEV / 'test-output/contract'):
            raise RuntimeError('Only prepared NA01 evidence may be consumed')
        provenance = json.loads((fixture / 'provenance.json').read_text())
        if provenance['compilerExit'] != 0 or not provenance['contentGatePassed']:
            raise RuntimeError('NA01 actual compiler/content gate not passed')
        if provenance['fixtureSHA256'] != sha(HERE / 'fixtures/document.typ'):
            raise RuntimeError('Actual compiler fixture source hash differs')
        for name in ['native.json', 'provenance.json', 'commands.json']:
            shutil.copyfile(fixture / name, cls.out / ('na01-' + name))
        cls.binary = cls.out / 'TextInteractionTests'
        resolved_swiftc = command(['xcrun', '--find', 'swiftc'])
        swiftc = shutil.which('swiftc')
        if not swiftc:
            raise RuntimeError('swiftc driver required')
        metadata = {
            'task': 'NA02/S-text/F15-find-v2', 'correctionBase': '540e70d170b6989f94ce348c9fae24030379af1e', 'commonBase': '312502ceb573f4791e61d01000df132d6da16323',
            'head': command(['git', 'rev-parse', 'HEAD']), 'dirty': command(['git', 'status', '--short']),
            'os': platform.platform(), 'arch': platform.machine(), 'python': sys.version,
            'swiftc': swiftc, 'xcrunSwiftc': resolved_swiftc, 'swiftVersion': command([swiftc, '--version']),
            'sdk': command(['xcrun', '--show-sdk-path']), 'sdkVersion': command(['xcrun', '--show-sdk-version']),
            'target': 'arm64-apple-macosx13.0', 'swiftMode': '5', 'warningsAsErrors': True,
            'environment': {k: os.environ[k] for k in ['TMPDIR', 'CLANG_MODULE_CACHE_PATH', 'SWIFT_MODULECACHE_PATH']},
            'sourceHashes': {p: sha(REPO / p) for p in COMMON + PRODUCT +
                             ['tests/flow-app/native-reader-app/TextInteractionTests.swift',
                              'tests/flow-app/native-reader-app/test_text_interaction.py']},
            'oracle': 'Author-written literals/scalars/ranges/order inside TextInteractionTests.swift; independent of layout implementation; external review pending',
            'oracleSHA256': sha(HERE / 'TextInteractionTests.swift'),
            'actualCompilerFixture': str(fixture), 'fixtureHashes': {n: sha(fixture / n) for n in
                     ['native.json', 'provenance.json', 'commands.json', 'compiled/document.html']},
            'scope': 'Actual headless NSView/TextKit draw, runloop and AX API only; object metrics/paint injected unit fixture; GUI/VoiceOver, actual object fidelity and macOS13 runtime unverified',
            'skips': 0,
        }
        save(cls.out / 'provenance.json', metadata)
        command([swiftc, '-v', '-swift-version', '5', '-warnings-as-errors', '-target', 'arm64-apple-macosx13.0',
                 '-module-cache-path', os.environ['SWIFT_MODULECACHE_PATH'],
                 *[REPO / p for p in COMMON + PRODUCT], HERE / 'TextInteractionTests.swift', '-o', cls.binary])
        cls.results = json.loads(command([cls.binary, cls.out / 'na01-native.json', cls.out]))
        save(cls.out / 'results.json', cls.results)
        save(cls.evidence_root / 'latest.json', {'evidence': str(cls.out), 'seconds': time.time() - cls.started})

    def test_18_native_layout_draw_conditions(self):
        self.assertEqual(len(self.results['matrix']), 18)
        self.assertTrue(all(r['inkPixels'] > 100 and r['painted'] for r in self.results['matrix']))

    def test_independent_unicode_grapheme_bidi_ranges(self):
        self.assertGreaterEqual(self.results['unicodeAssertions'], 200)

    def test_native_keyboard_mouse_and_focus(self):
        self.assertEqual(self.results['input'], 'pass')

    def test_cross_block_and_verified_source_copy(self):
        self.assertEqual(self.results['copy'], 'pass')

    def test_actual_accessibility_api_order_roles_selection_actions(self):
        self.assertEqual(self.results['accessibility'], 'pass')

    def test_reflow_zoom_theme_anchor_and_stale_geometry(self):
        self.assertEqual(self.results['reflow'], 'pass')

    def test_publication_hold_release_cancel_dispose_late_ack(self):
        self.assertEqual(self.results['lifetime'], 'pass')

    def test_negative_geometry_ranges_and_unsupported_objects(self):
        self.assertEqual(self.results['negative'], 'pass')

    def test_native_find_bar_keyboard_unicode_and_selection_guards(self):
        self.assertEqual(self.results['find']['status'], 'pass')
        self.assertGreater(self.results['find']['privateFindPasteboardCalls'], 0)
        self.assertEqual(self.results['find']['visibleWindows'], 0)
        self.assertEqual(self.results['find']['globalFindPanels'], 0)
        self.assertEqual(self.results['find']['visibleOrFocusEvents'], [])
