"""Disposable native layout storage, using isolated directories and current Swift."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]


@unittest.skipUnless(sys.platform == 'darwin', 'AppKit tests require macOS')
class LayoutCache(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        temp = tempfile.TemporaryDirectory(dir='/private/tmp', prefix='cross-project-layout-cache-tests-')
        cls.addClassCleanup(temp.cleanup)
        cls.executable = Path(temp.name) / 'layout-cache-tests'
        cls.env = dict(os.environ, TMPDIR=temp.name,
            CLANG_MODULE_CACHE_PATH=str(Path(temp.name) / 'clang-cache'),
            SWIFT_MODULECACHE_PATH=str(Path(temp.name) / 'swift-cache'))
        manifest = json.loads((ROOT / 'apps/macos/sources.json').read_text())
        result = subprocess.run([
            '/usr/bin/swiftc', '-swift-version', '5', '-warnings-as-errors',
            *[ROOT / 'apps/macos' / name for group in ('core', 'native', 'app') for name in manifest[group] if name != 'main.swift'],
            ROOT / 'tests/flow-app/native-reader-app/LayoutCacheTests.swift',
            '-o', cls.executable,
        ], capture_output=True, text=True, timeout=300, env=cls.env)
        if result.returncode != 0 or result.stderr:
            raise RuntimeError(result.stdout + result.stderr)

    def scenario(self, name):
        result = subprocess.run([self.executable, name], capture_output=True, text=True, timeout=30, env=self.env)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_shared_envelope(self): self.scenario('envelope')
    def test_identical_content_skips_write_and_close_flushes_position(self): self.scenario('skip')
    def test_document_written_once_per_revision(self): self.scenario('document')
    def test_owner_and_document_filter_by_filename(self): self.scenario('filter')
    def test_legacy_and_unsafe_entries_are_disposable(self): self.scenario('unsafe')
    def test_lru_and_corruption(self): self.scenario('lru')


if __name__ == '__main__': unittest.main()
