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
        subprocess.run([
            '/usr/bin/swiftc', '-swift-version', '5', '-warnings-as-errors',
            *(p for p in package.swift_sources() if p.name != 'main.swift'),
            ROOT / 'tests/flow-app/FlowAppTests.swift', '-o', cls.executable,
        ], check=True)

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


if __name__ == '__main__':
    unittest.main()
