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
class MathBatch(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        temp = tempfile.TemporaryDirectory(dir='/private/tmp', prefix='cross-project-math-batch-tests-')
        cls.addClassCleanup(temp.cleanup)
        cls.executable = Path(temp.name) / 'math-batch-tests'
        cls.env = dict(os.environ, TMPDIR=temp.name,
            CLANG_MODULE_CACHE_PATH=str(Path(temp.name) / 'clang-cache'),
            SWIFT_MODULECACHE_PATH=str(Path(temp.name) / 'swift-cache'))
        manifest = json.loads((ROOT / 'apps/macos/sources.json').read_text())
        result = subprocess.run([
            '/usr/bin/swiftc', '-swift-version', '5', '-warnings-as-errors',
            *[ROOT / 'apps/macos' / name for group in ('core', 'native', 'app') for name in manifest[group] if name != 'main.swift'],
            ROOT / 'tests/flow-app/native-reader-app/MathBatchTests.swift',
            '-o', cls.executable,
        ], capture_output=True, text=True, timeout=300, env=cls.env)
        if result.returncode != 0 or result.stderr:
            raise RuntimeError(result.stdout + result.stderr)

    def scenario(self, name):
        result = subprocess.run([self.executable, name], capture_output=True, text=True, timeout=30, env=self.env)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_timeout_halves_until_success(self): self.scenario('timeout')
    def test_budget_halves_until_success(self): self.scenario('budget')
    def test_single_item_failure_terminates(self): self.scenario('single')
    def test_other_errors_do_not_retry(self): self.scenario('stale')
    def test_chunk_budgets_scale_and_stay_bounded(self): self.scenario('limits')


if __name__ == '__main__': unittest.main()
