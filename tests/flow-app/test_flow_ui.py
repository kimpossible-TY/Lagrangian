"""AppKit reading actions with isolated settings and injected service operations."""
import importlib.util
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('flow_ui_package', ROOT / 'scripts/flow-app.py')
package = importlib.util.module_from_spec(spec)
spec.loader.exec_module(package)


@unittest.skipUnless(sys.platform == 'darwin', 'AppKit tests require macOS')
class ReadingUI(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        temp = tempfile.TemporaryDirectory(prefix='flow-ui-tests-')
        cls.addClassCleanup(temp.cleanup)
        cls.executable = Path(temp.name) / 'flow-ui-tests'
        package.run([
            '/usr/bin/swiftc', *package.swift_flags(),
            *(p for p in package.swift_sources() if p.name != 'main.swift'),
            ROOT / 'tests/flow-app/FlowAppTests.swift', '-o', cls.executable,
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
        import os
        temp = tempfile.TemporaryDirectory(prefix='native-shell-tests-')
        cls.addClassCleanup(temp.cleanup)
        cls.executable = Path(temp.name) / 'native-shell-tests'
        package.run(['/usr/bin/swiftc', *package.swift_flags(), '-D', 'NATIVE_SHELL_TESTS',
            *(p for p in package.swift_sources() if p.name != 'main.swift'),
            ROOT / 'tests/flow-app/ReadingSessionTests.swift', '-o', cls.executable])
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
