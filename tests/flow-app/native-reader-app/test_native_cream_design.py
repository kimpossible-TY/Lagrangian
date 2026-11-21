"""Opt-in production AppKit component checks; never launches or activates the app."""
import sys
sys.dont_write_bytecode = True
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import time
import unittest

ROOT = Path(__file__).resolve().parents[3]
D = Path('/Volumes/devSSD/Developer/lagrangian-native-20261117')
OUTPUT = D / 'test-output/native-cream-na18'
SOURCES = ['apps/macos/NativeAppDesign.swift', 'apps/macos/NativeBrandMark.swift',
           'tests/flow-app/native-reader-app/NativeCreamDesignTests.swift']


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def save(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')


class NativeCreamDesign(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        configured = os.environ.get('NATIVE_CREAM_OUTPUT')
        if not configured:
            raise unittest.SkipTest('Requires explicit NATIVE_CREAM_OUTPUT and shared outer Swift lock')
        if sys.platform != 'darwin' or Path(configured).resolve() != OUTPUT:
            raise RuntimeError('Only the owned macOS NA18 output is permitted')
        if not os.environ.get('LAGRANGIAN_NATIVE_SWIFT_LOCK_HELD'):
            raise RuntimeError('Use with-native-swift-lock.py once at the outer test command')
        OUTPUT.mkdir(parents=True, exist_ok=True)
        # Independent reference is read from the untouched original SVG/CSS, never Swift tokens.
        html = (ROOT / 'tools/flow-reader/web/index.html').read_text()
        svg = re.search(r'<svg[^>]*class="reader-logo-mark".*?</svg>', html, re.S).group()
        paths = re.findall(r'\bd="([^"]+)"', svg)
        if len(paths) != 3 or len(set(paths)) != 1:
            raise RuntimeError('Original three-layer logo contract changed')
        if hashlib.sha256(paths[0].encode()).hexdigest() != 'b4d1dbfb513c47994dd54017b03e8f66da0ae1364f1d9bb92816f0ef50c2ce84':
            raise RuntimeError('Logo no longer matches the user-approved original d string')
        css = (ROOT / 'tools/flow-reader/web/reader.css').read_text()
        widths = [float(re.search(r'\.reader-logo-' + name + r'\s*\{[^}]*stroke-width:\s*([\d.]+)', css).group(1))
                  for name in ['base', 'halo', 'beam']]
        save(OUTPUT / 'oracle.json', dict(paths=paths, widths=widths,
             coordinates=[float(x) for x in re.findall(r'[-+]?\d+(?:\.\d+)?', paths[0])],
             originals={p: sha(ROOT / p) for p in ['tools/flow-reader/web/index.html', 'tools/flow-reader/web/reader.css']}))
        cls.binary = D / 'tmp/native-cream-na18/NativeCreamDesignTests'
        argv = ['swiftc', '-parse-as-library', '-swift-version', '5', '-warnings-as-errors',
                '-target', 'arm64-apple-macosx13.0', '-module-cache-path', os.environ['SWIFT_MODULECACHE_PATH'],
                *[str(ROOT / p) for p in SOURCES], '-o', str(cls.binary)]
        result = cls.execute('compile', argv, inputs={p: sha(ROOT / p) for p in SOURCES})
        if result.returncode:
            raise RuntimeError(result.stdout + result.stderr)

    @classmethod
    def execute(cls, name, argv, inputs=None):
        start = time.time()
        result = subprocess.run(argv, cwd=ROOT, capture_output=True, text=True, timeout=180)
        (OUTPUT / (name + '.stdout.log')).write_text(result.stdout)
        (OUTPUT / (name + '.stderr.log')).write_text(result.stderr)
        save(OUTPUT / (name + '.command.json'), dict(actualargv=argv, cwd=str(ROOT),
             started=start, finished=time.time(), exit=result.returncode, skip=0, inputhash=inputs,
             environment={k: os.environ.get(k) for k in ['TMPDIR', 'SWIFT_MODULECACHE_PATH', 'CLANG_MODULE_CACHE_PATH',
                                                       'LAGRANGIAN_NATIVE_SWIFT_LOCK_HELD']}))
        return result

    def scenario(self, name):
        result = self.execute(name, [str(self.binary), str(OUTPUT), name],
                              inputs={'binary': sha(self.binary), 'oracle.json': sha(OUTPUT / 'oracle.json')})
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_actual_colors_and_preference_matrix(self): self.scenario('palette')
    def test_original_vector_and_native_strokes(self): self.scenario('vector')
    def test_semantic_activation_keyboard_focus_and_cancel(self): self.scenario('controls')
    def test_real_multilingual_font_shaping(self): self.scenario('fonts')
    def test_native_offscreen_paint(self): self.scenario('paint')
    def test_effective_appearance_and_accessibility_preferences(self): self.scenario('preferences')
