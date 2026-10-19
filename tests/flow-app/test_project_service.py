"""Exercise native profile updates without AppKit or live LaunchAgents."""
import importlib.util
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('flow_services', ROOT / 'scripts/flow-app.py')
package = importlib.util.module_from_spec(spec)
spec.loader.exec_module(package)


class SwiftSources(unittest.TestCase):
    def test_manifest_covers_production_sources_once(self):
        sources = package.swift_sources()
        self.assertEqual(len(sources), len(set(sources)))
        self.assertEqual(set(sources), set((ROOT / 'apps/macos').glob('*.swift')))
        core = package.swift_sources(include_app=False)
        self.assertNotIn(ROOT / 'apps/macos/main.swift', core)
        self.assertNotIn(ROOT / 'apps/macos/FlowApp.swift', core)


@unittest.skipUnless(sys.platform == 'darwin', 'Native app tests require macOS')
class ProjectServices(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        temp = tempfile.TemporaryDirectory(prefix='flow-service-tests-')
        cls.addClassCleanup(temp.cleanup)
        cls.executable = Path(temp.name) / 'project-service-tests'
        subprocess.run([
            '/usr/bin/swiftc', '-swift-version', '5', '-warnings-as-errors',
            *package.swift_sources(include_app=False),
            ROOT / 'tests/flow-app/ProjectServiceTests.swift', '-o', cls.executable,
        ], check=True)

    def scenario(self, name):
        result = subprocess.run([self.executable, name], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_invalid_profile_does_not_stop_service(self):
        self.scenario('invalid-profile')

    def test_duplicate_port_does_not_stop_service(self):
        self.scenario('duplicate-port')

    def test_stopped_profile_is_saved_without_starting_service(self):
        self.scenario('stopped')

    def test_running_profile_is_stopped_saved_and_restarted(self):
        self.scenario('running')

    def test_save_failure_restores_settings_and_service(self):
        self.scenario('save-failure')

    def test_start_failure_restores_settings_and_service(self):
        self.scenario('start-failure')

    def test_stop_failure_keeps_settings(self):
        self.scenario('stop-failure')

    def test_settings_store_uses_isolated_paths_and_private_permissions(self):
        self.scenario('settings-store')


if __name__ == '__main__':
    unittest.main()
