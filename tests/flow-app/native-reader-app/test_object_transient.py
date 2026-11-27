"""Self-contained lazy object recovery, using the real AppKit viewport owner."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]


@unittest.skipUnless(sys.platform == 'darwin', 'AppKit tests require macOS')
class ObjectTransient(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        temp = tempfile.TemporaryDirectory(dir='/private/tmp', prefix='object-transient-tests-')
        cls.addClassCleanup(temp.cleanup)
        cls.executable = Path(temp.name) / 'object-transient-tests'
        cls.env = dict(os.environ, TMPDIR=temp.name,
            CLANG_MODULE_CACHE_PATH=str(Path(temp.name) / 'clang-cache'),
            SWIFT_MODULECACHE_PATH=str(Path(temp.name) / 'swift-cache'))
        registry = json.loads((ROOT / 'apps/macos/sources.json').read_text())
        # TextView's concrete dependencies, without the app entrypoint/FlowApp.
        sources = [ROOT / 'apps/macos' / name for group in ('core', 'native')
                   for name in registry[group] if name != 'CLI.swift']
        sources.append(ROOT / 'apps/macos/NativeReaderWindowController.swift')
        result = subprocess.run([
            '/usr/bin/swiftc', '-swift-version', '5', '-warnings-as-errors',
            '-target', 'arm64-apple-macosx13.0',
            '-module-cache-path', cls.env['SWIFT_MODULECACHE_PATH'],
            *sources, Path(__file__).with_name('ObjectTransientTests.swift'),
            '-o', cls.executable,
        ], capture_output=True, text=True, timeout=300, env=cls.env)
        if result.returncode != 0 or result.stderr:
            raise RuntimeError(result.stdout + result.stderr)

    def scenario(self, name):
        result = subprocess.run([self.executable, name], capture_output=True, text=True,
                                timeout=30, env=self.env, cwd=self.executable.parent)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_classification_table(self): self.scenario('classification')
    def test_transient_preparation_propagates_without_isolation(self): self.scenario('propagation')
    def test_timeout_once_retries_and_publishes_all_siblings(self): self.scenario('once')
    def test_two_timeouts_use_both_backoff_delays(self): self.scenario('twice')
    def test_persistent_timeout_isolates_leaf_on_last_attempt(self): self.scenario('timeout-leaf')
    def test_all_timeouts_stop_within_budget_with_placeholders(self): self.scenario('cap')
    def test_all_timeouts_exhaust_logarithmic_preparation_budget(self): self.scenario('timeout-budget')
    def test_single_timeout_leaf_in_128_objects_preserves_siblings(self): self.scenario('timeout-single-leaf')
    def test_large_initial_timeout_adopts_then_retries_in_viewport(self): self.scenario('large-initial')
    def test_deterministic_failure_isolates_only_bad_node(self): self.scenario('deterministic')
    def test_cancel_and_stale_abort_without_backoff(self): self.scenario('obsolete')


if __name__ == '__main__': unittest.main()
