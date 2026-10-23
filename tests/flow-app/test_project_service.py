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

    def test_profile_selection_preserves_profiles_and_saves_without_service_control(self):
        self.scenario('select-profile')

    def test_invalid_profile_selection_does_not_save_or_control_service(self):
        self.scenario('select-invalid-profile')

    def test_profile_selection_save_failure_preserves_caller_settings(self):
        self.scenario('select-save-failure')

    def test_project_creation_preserves_defaults_and_existing_settings(self):
        self.scenario('create-project')

    def test_project_creation_detects_fonts_and_chooses_first_unused_port(self):
        self.scenario('create-fonts-and-used-ports')

    def test_invalid_project_creation_does_not_save_or_control_service(self):
        self.scenario('create-invalid-project')

    def test_project_creation_save_failure_preserves_caller_settings(self):
        self.scenario('create-save-failure')

    def test_generated_agent_ownership_rejects_foreign_or_malformed_jobs(self):
        self.scenario('agent-ownership')

    def test_profile_update_waits_for_old_process_before_starting_new_settings(self):
        self.scenario('agent-update-delayed-exit')

    def test_restart_waits_for_old_process_before_bootstrap(self):
        self.scenario('agent-restart-delayed-exit')

    def test_shutdown_timeout_does_not_bootstrap_replacement(self):
        self.scenario('agent-shutdown-timeout')

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
