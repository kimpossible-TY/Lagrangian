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
        if not root.is_relative_to(Path('/Volumes/devSSD/Developer/lagrangian-native-20261117/test-output')):
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

    def test_startup_timeline_does_not_retain_its_owner(self):
        self.scenario('timeline-owner')

    def test_duplicate_profile_labels_preserve_exact_profile_selection(self):
        self.scenario('duplicate-names')

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


@unittest.skipUnless(sys.platform == 'darwin', 'AppKit tests require macOS')
class OptimizedStartup(unittest.TestCase):
    def test_optimized_production_run_completes_profile_load(self):
        """Execute the production entrypoint/run loop, with only presentation and a deadline instrumented.

        The observer reads NSApp.delegate only inside its bounded callback. No windows are ordered.
        STARTUP_FIXED_MAIN permits an immutable Git main for the before counterexample.
        """
        if explicit := os.environ.get('GUI_PREP_OUTPUT'):
            output = Path(explicit).resolve()
            if not output.is_relative_to(Path('/Volumes/devSSD/Developer/lagrangian-native-20261117/test-output')):
                raise RuntimeError('Startup evidence must remain in isolated DevSSD output')
        else:
            temporary = tempfile.TemporaryDirectory(prefix='flow-startup-')
            self.addCleanup(temporary.cleanup)
            output = Path(temporary.name)
        folder = output / ('startup-' + str(time.time_ns())); folder.mkdir()
        original = Path(os.environ.get('STARTUP_FIXED_MAIN', ROOT / 'apps/macos/main.swift')).read_text()
        probe = '''
    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
      guard let observed = NSApp.delegate as? FlowApp else { print("delegateReleasedBeforeCompletion"); exit(3) }
      guard !observed.mutating, observed.active?.id == "startup",
            observed.controls[#selector(FlowApp.openPreview)]?.isEnabled == true,
            !observed.window.isVisible else {
        print("startupIncomplete", observed.mutating, observed.status.stringValue, "active", observed.active?.id ?? "nil", "read", observed.controls[#selector(FlowApp.openPreview)]?.isEnabled ?? false, "windows", NSApp.windows.map { $0.isVisible }); exit(4)
      }
      print("startupReady; selected=startup; mainWindowVisible=false; activationProhibited=true")
      observed.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
      observed.window.close()
      exit(0)
    }
'''
        instrumented = original.replace('app.setActivationPolicy(.accessory)', 'app.setActivationPolicy(.prohibited)')
        instrumented = instrumented.replace('    app.delegate = delegate', '    app.delegate = delegate\n' + probe)
        self.assertNotEqual(instrumented, original)
        main = folder / 'main.swift'; main.write_text(instrumented)
        binary = folder / 'startup'
        argv = ['/usr/bin/swiftc', *package.swift_flags(), '-O',
                *(p for p in package.swift_sources() if p.name != 'main.swift'), main, '-o', binary]
        started = time.monotonic()
        compiled = subprocess.run(list(map(str, argv)), capture_output=True, text=True)
        (folder / 'compile.json').write_text(json.dumps(dict(argv=list(map(str, argv)), exit=compiled.returncode,
            elapsed=time.monotonic()-started, stderr=compiled.stderr,
            sourceSHA256={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in package.swift_sources() + [main]},
            originalMainSHA256=hashlib.sha256(original.encode()).hexdigest()), indent=2))
        self.assertEqual(compiled.returncode, 0, compiled.stderr)
        dev = folder / 'dev'
        data = dev / 'home/Library/Application Support/Lagrangian'; data.mkdir(parents=True)
        project = folder / 'project'; project.mkdir(); (project / 'main.typ').write_text('Startup fixture')
        (data / 'profiles.json').write_text(json.dumps(dict(schemaVersion=1, selectedID='startup', profiles=[dict(
            id='startup', name='Startup', root=str(project), entry='main.typ', fonts=[], packages='',
            port=23625, publicURL='', label='test.startup')])))
        result = subprocess.run([binary, '--dev-root', dev, '--dev-no-activate'],
                                capture_output=True, text=True, timeout=12)
        (folder / 'run.json').write_text(json.dumps(dict(exit=result.returncode, stdout=result.stdout, stderr=result.stderr,
            argv=[str(binary), '--dev-root', str(dev), '--dev-no-activate'], guiLaunch=False), indent=2))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        if not os.environ.get('STARTUP_FIXED_MAIN'):
            rows=[json.loads(line) for line in (dev/'startup-timeline.jsonl').read_text().splitlines()]
            events=[r['event'] for r in rows]
            for event in ['load-begin','load-end','mutation-enqueued','mutation-completion','completion-owner','settings-adopted']:
                self.assertIn(event,events)
            completion=next(r for r in rows if r['event']=='mutation-completion')
            self.assertEqual(completion['capturedGeneration'],completion['currentGeneration'])
            self.assertFalse(completion['disposed']);self.assertTrue(completion['storageMutationRunning'])
            adopted=next(r for r in rows if r['event']=='settings-adopted')
            self.assertEqual(adopted['profileCount'],1);self.assertTrue(adopted['readEnabled'])
            self.assertEqual(adopted['selectedIDHash'],hashlib.sha256(b'startup').hexdigest())
            serialized=json.dumps(rows)
            self.assertNotIn(str(project),serialized);self.assertNotIn('Startup',serialized)
            self.assertTrue(next(r for r in rows if r['event']=='completion-owner')['weakOwnerPresent'])


if __name__ == '__main__':
    unittest.main()
