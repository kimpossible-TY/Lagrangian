"""AppKit reading actions with isolated settings and injected service operations."""
import importlib.util
import os
import hashlib
import json
import time
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('flow_ui_package', ROOT / 'scripts/flow-app.py')
package = importlib.util.module_from_spec(spec)
spec.loader.exec_module(package)


def compile_fixture(cls, name, arguments):
    output = os.environ.get('GUI_PREP_OUTPUT')
    if output:
        root = Path(output).resolve()
        if not root.is_relative_to(Path('/Volumes/devSSD/Developer/lagrangian-native-20261117/test-output/integration')):
            raise RuntimeError('UI evidence must remain in isolated integration output')
        folder = root / (name + '-' + str(time.time_ns())); folder.mkdir()
        cls.executable = folder / name
        argv = ['/usr/bin/swiftc', *package.swift_flags(), *arguments, '-o', cls.executable]
        started = time.monotonic()
        result = subprocess.run(list(map(str, argv)), capture_output=True, text=True)
        (folder / 'compile.json').write_text(json.dumps(dict(argv=list(map(str, argv)), cwd=str(ROOT),
            exit=result.returncode, elapsed=time.monotonic()-started, stdout=result.stdout, stderr=result.stderr,
            environment={k:os.environ.get(k) for k in ['TMPDIR','CLANG_MODULE_CACHE_PATH','SWIFT_MODULECACHE_PATH']},
            sourceSHA256={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in package.swift_sources() + [ROOT / 'tests/flow-app/FlowAppTests.swift', ROOT / 'tests/flow-app/ReadingSessionTests.swift']},
            binarySHA256=hashlib.sha256(cls.executable.read_bytes()).hexdigest() if result.returncode==0 else None),indent=2))
        if result.returncode: raise RuntimeError(result.stderr)
    else:
        temp = tempfile.TemporaryDirectory(prefix=name+'-')
        cls.addClassCleanup(temp.cleanup)
        cls.executable = Path(temp.name) / name
        package.run(['/usr/bin/swiftc', *package.swift_flags(), *arguments, '-o', cls.executable])


@unittest.skipUnless(sys.platform == 'darwin', 'AppKit tests require macOS')
class ReadingUI(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        compile_fixture(cls, 'flow-ui-tests', [
            *(p for p in package.swift_sources() if p.name != 'main.swift'),
            ROOT / 'tests/flow-app/FlowAppTests.swift',
        ])

    def scenario(self, name):
        result = subprocess.run([self.executable, name], capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_read_opens_only_when_document_ready(self):
        self.scenario('read')

    def test_project_switch_cancels_pending_browser_open(self):
        self.scenario('switch')

    def test_read_saves_edited_settings_before_start(self):
        self.scenario('save-and-read')

    def test_failures_are_inline_and_retryable(self):
        self.scenario('failure')

    def test_native_lifecycle_observers_deliver_and_dispose(self):
        self.scenario('environment')

    def test_sleep_during_settings_save_cancels_pending_read(self):
        self.scenario('sleep-save')


@unittest.skipUnless(sys.platform == 'darwin', 'AppKit tests require macOS')
class NativeShell(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        compile_fixture(cls, 'native-shell-tests', ['-D', 'NATIVE_SHELL_TESTS',
            *(p for p in package.swift_sources() if p.name != 'main.swift'),
            ROOT / 'tests/flow-app/ReadingSessionTests.swift'])
        cls.fixture = os.environ.get('FLOW_NATIVE_FIXTURE')

    def scenario(self, name, fixture=False):
        if fixture and not self.fixture:
            self.fail('FLOW_NATIVE_FIXTURE must select the actual NA01 fixture, not a synthetic response')
        result = subprocess.run([self.executable, name, *([self.fixture] if fixture else [])],
                                capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_semantic_acceptance_window_initialization_and_paint_are_distinct(self): self.scenario('native-progress')
    def test_project_switch_rejects_late_paint(self): self.scenario('native-stale')
    def test_paint_deadline_cancels_request(self): self.scenario('native-timeout')
    def test_external_action_preserves_existing_service_and_browser_readiness(self): self.scenario('native-external')
    def test_native_read_saves_settings_before_request(self): self.scenario('native-save')
    def test_default_native_read_is_honestly_unavailable(self): self.scenario('native-unavailable')


if __name__ == '__main__':
    unittest.main()
