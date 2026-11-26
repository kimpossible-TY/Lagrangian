"""Native math batch limits and retries, using isolated directories and current Swift."""
import json
import math
import re
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]


class MathBatchContract(unittest.TestCase):
    def test_native_math_batch_limits_match_pinned_helper(self):
        helper = (ROOT / 'tools/flow-reader/native/math_layout.mjs').read_text()
        swift = (ROOT / 'apps/macos/NativeReaderObjectRenderer.swift').read_text()

        def constant(source, declaration):
            match = re.search(declaration + r' = ([0-9 *]+)(?:;|\n)', source)
            self.assertIsNotNone(match, declaration)
            return math.prod(int(n.strip()) for n in match[1].split('*'))

        self.assertEqual(constant(swift, 'static let maximumBytes'), constant(helper, 'const BATCH_LIMIT'))
        self.assertEqual(constant(swift, 'static let itemOutputBytes'), constant(helper, 'const LIMIT'))
        count = re.search(r'input.items.length > (\d+)', helper)
        self.assertIsNotNone(count)
        self.assertEqual(constant(swift, 'static let maximumItems'), int(count[1]))
        self.assertIn('inputBytes > 256 * 1024', helper)
        self.assertEqual(constant(swift, 'static let itemInputBytes'), 256 * 1024)
        self.assertIn('Buffer.byteLength(source) > 65536', helper)
        self.assertEqual(constant(swift, 'static let sourceBytes'), 65536)


@unittest.skipUnless(sys.platform == 'darwin', 'AppKit tests require macOS')
class MathBatch(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        temp = tempfile.TemporaryDirectory(dir='/private/tmp', prefix='math-batch-tests-')
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
    def test_hanging_item_has_bounded_attempts_and_cumulative_deadline(self): self.scenario('deadline')
    def test_output_limit_does_not_resplit(self): self.scenario('output-limit')
    def test_chunk_budgets_scale_and_stay_bounded(self): self.scenario('limits')


if __name__ == '__main__': unittest.main()
