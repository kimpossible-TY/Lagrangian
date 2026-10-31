"""Configuration contract and failed-update recovery, without touching live jobs."""
import argparse
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('flow_package', ROOT / 'scripts/flow-app.py')
package = importlib.util.module_from_spec(spec); spec.loader.exec_module(package)
_COMPILED_DIR = None
_COMPILED_APP = None
# Reader tree from before symlink-aware owns_agent (merge-base of this branch).
PRE_PR_READER = 'cb3f55c4cf277ecdd84e43eb4132d9ee2a97a99b'

def substitute_swift(original, old, new, marker):
    if old not in original:
        raise AssertionError(f'Swift substitution site for {marker} is missing')
    updated = original.replace(old, new)
    if marker not in updated or updated == original:
        raise AssertionError(f'Swift substitution for {marker} did not apply')
    return updated

def compiled_app_binary():
    global _COMPILED_DIR, _COMPILED_APP
    if _COMPILED_APP is None:
        _COMPILED_DIR = tempfile.TemporaryDirectory(prefix='flow-app-tests-')
        _COMPILED_APP = Path(_COMPILED_DIR.name) / 'Lagrangian'
        sources = []
        for src in package.swift_sources():
            if src.name == 'CommandRunner.swift':
                patched = Path(_COMPILED_DIR.name) / 'CommandRunner.swift'
                patched.write_text(substitute_swift(
                    src.read_text(),
                    'let task = Process()\n    task.executableURL = URL(fileURLWithPath: path)\n    task.arguments = arguments',
                    'let task = Process()\n'
                    '    if path == "/bin/launchctl" || path == "/usr/sbin/lsof" {\n'
                    '      guard let stub = ProcessInfo.processInfo.environment["FLOW_TEST_SYSTEM_STUB"], !stub.isEmpty else {\n'
                    '        throw FlowError(message: "Refusing to invoke real \\(path) in test")\n'
                    '      }\n'
                    '      task.executableURL = URL(fileURLWithPath: stub)\n'
                    '      task.arguments = [path] + arguments\n'
                    '    } else {\n'
                    '      task.executableURL = URL(fileURLWithPath: path)\n'
                    '      task.arguments = arguments\n'
                    '    }',
                    'FLOW_TEST_SYSTEM_STUB',
                ))
                sources.append(patched)
            elif src.name in {'AppEnvironment.swift', 'main.swift'}:
                patched = Path(_COMPILED_DIR.name) / src.name
                patched.write_text(substitute_swift(
                    src.read_text(),
                    'FileManager.default.homeDirectoryForCurrentUser',
                    '(ProcessInfo.processInfo.environment["HOME"].map { URL(fileURLWithPath: $0) } ?? FileManager.default.homeDirectoryForCurrentUser)',
                    'environment["HOME"]',
                ))
                sources.append(patched)
            else:
                sources.append(src)
        subprocess.run(['/usr/bin/swiftc', '-swift-version', '5', '-warnings-as-errors',
                        *sources, '-o', _COMPILED_APP], check=True)
    return _COMPILED_APP

class Profiles(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if sys.platform != 'darwin': raise unittest.SkipTest('Native app tests require macOS')
        cls.app = compiled_app_binary()
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.env = dict(os.environ, FLOW_DATA_DIR=str(self.root / 'data'), FLOW_LOG_DIR=str(self.root / 'logs'))
        self.profile = {'id': 'test', 'name': 'A project with spaces', 'root': str(self.root / 'project with spaces'),
                        'entry': 'main.typ', 'fonts': ['fonts'], 'packages': '', 'port': 24650,
                        'publicURL': 'https://preview.example:24650/', 'label': 'com.example.flow.test'}
    def config(self, profiles=None):
        config = {'schemaVersion': 1, 'selectedID': 'test', 'profiles': profiles if profiles is not None else [self.profile]}
        path = self.root / 'data/profiles.json'; path.parent.mkdir(exist_ok=True); path.write_text(json.dumps(config))
    def cli(self, *args):
        return subprocess.run([self.app, *args], env=self.env, text=True, capture_output=True)
    def test_arguments_and_identity(self):
        self.config(); result = self.cli('--launch-plan', 'test'); self.assertEqual(result.returncode, 0, result.stderr)
        plan = json.loads(result.stdout)
        self.assertIn('--data-plane-host=127.0.0.1:24650', plan['arguments'])
        self.assertIn(str(self.root / 'project with spaces/main.typ'), plan['arguments'])
        self.assertIn('--no-open', plan['arguments'])
        self.assertIn('--follow-system-theme', plan['arguments'])
        self.assertEqual(plan['environment']['TINYMIST_ALLOWED_ORIGINS'], 'https://preview.example:24650')
        self.assertEqual(plan['agent']['ProgramArguments'][1:], ['--serve', 'test'])
        self.assertIn(package.APP_ID, plan['agent']['AssociatedBundleIdentifiers'])
        self.assertEqual(plan['agent']['ProcessType'], 'Interactive')
        self.assertTrue(plan['environment']['TINYMIST_PREVIEW_FOCUS_FILE'].endswith('/data/focus/test.json'))
        self.assertTrue(plan['environment']['TINYMIST_PREVIEW_CHANGE_FILE'].endswith('/data/changes/test.json'))
    def test_duplicate_port_rejected(self):
        second = dict(self.profile, id='second', label='com.example.second')
        self.config([self.profile, second]); self.assertNotEqual(self.cli('--check-config').returncode, 0)
    def test_invalid_origins_and_entry(self):
        for url in ['http://example.com', 'https://user:pass@example.com', 'https://example.com/path', 'https://example.com/?query=1']:
            with self.subTest(url=url):
                self.profile['publicURL'] = url; self.config(); self.assertNotEqual(self.cli('--check-config').returncode, 0)
        self.profile['publicURL'] = ''; self.profile['entry'] = '../outside.typ'; self.config()
        self.assertNotEqual(self.cli('--check-config').returncode, 0)
    def test_bad_id_and_port_rejected(self):
        self.profile['id'] = '../escape'; self.config(); self.assertNotEqual(self.cli('--check-config').returncode, 0)
        self.profile['id'] = 'test'; self.profile['port'] = 0; self.config(); self.assertNotEqual(self.cli('--check-config').returncode, 0)
    def test_missing_project_does_not_start_job(self):
        self.config(); result = self.cli('--control', 'start', 'test')
        self.assertNotEqual(result.returncode, 0); self.assertIn('진입 파일', result.stderr)

class EngineInput(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory(); self.addCleanup(temp.cleanup)
        self.root = Path(temp.name).resolve()
        self.engine = self.root / 'external engine'
        self.engine.write_text('engine'); self.engine.chmod(0o755)

    def test_explicit_engine_takes_precedence_over_environment(self):
        with patch.dict(os.environ, FLOW_ENGINE_PATH='/missing/engine'), patch.object(package, 'capture', side_effect=['tinymist test', '--follow-system-theme']):
            engine, version = package.resolve_engine(self.engine)
        self.assertEqual(engine, self.engine); self.assertEqual(version, 'tinymist test')

    def test_environment_and_installed_engine_sources(self):
        with patch.dict(os.environ, FLOW_ENGINE_PATH=str(self.engine)), patch.object(package, 'capture', side_effect=['tinymist test', '--follow-system-theme']):
            self.assertEqual(package.resolve_engine()[0], self.engine)
        installed = self.root / 'installed.app'; binary = installed / 'Contents/MacOS/flow-engine'
        binary.parent.mkdir(parents=True); binary.write_text('engine'); binary.chmod(0o755)
        with patch.dict(os.environ, {}, clear=True), patch.object(package, 'DEFAULT_APP', installed), patch.object(package, 'capture', side_effect=['tinymist test', '--follow-system-theme']):
            self.assertEqual(package.resolve_engine()[0], binary)

    def test_invalid_engine_keeps_previous_output(self):
        output = self.root / 'Lagrangian.app'; output.mkdir(); marker = output / 'previous'; marker.write_text('preserved')
        args = argparse.Namespace(engine=self.root / 'missing', output=output)
        with self.assertRaisesRegex(ValueError, 'external engine'): package.build(args)
        self.assertEqual(marker.read_text(), 'preserved')
        args.engine = self.engine
        with patch.object(package, 'capture', side_effect=['tinymist test', 'standard preview']), self.assertRaisesRegex(ValueError, 'Flow preview features'):
            package.build(args)
        self.assertEqual(marker.read_text(), 'preserved')

    def test_failed_bundle_build_keeps_previous_output(self):
        output = self.root / 'Lagrangian.app'; output.mkdir(); marker = output / 'previous'; marker.write_text('preserved')
        args = argparse.Namespace(engine=self.engine, output=output)
        with patch.object(package, 'resolve_engine', return_value=(self.engine, 'tinymist test')), patch.object(package, 'build_bundle', side_effect=RuntimeError('build failed')):
            with self.assertRaisesRegex(RuntimeError, 'build failed'): package.build(args)
        self.assertEqual(marker.read_text(), 'preserved')

class Signing(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory(); self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        data = patch.object(package, 'DATA', self.root); data.start(); self.addCleanup(data.stop)
        env = patch.dict(os.environ, {}, clear=True); env.start(); self.addCleanup(env.stop)
        self.identity = 'A' * 40

    def save(self, **values):
        (self.root / 'signing.json').write_text(json.dumps({'schemaVersion': 1, 'identity': self.identity, **values}))

    def test_build_selection_preserves_explicit_and_environment_overrides(self):
        self.assertEqual(package.resolve_signing_identity(), '-')
        self.save()
        with patch.object(package, 'signing_identities', return_value={self.identity: 'Local'}):
            self.assertEqual(package.resolve_signing_identity(), self.identity)
        with patch.dict(os.environ, FLOW_SIGN_IDENTITY='Environment'), patch.object(package, 'signing_identities') as identities:
            self.assertEqual(package.resolve_signing_identity(), 'Environment')
            self.assertEqual(package.resolve_signing_identity('Explicit'), 'Explicit')
            self.assertEqual(package.resolve_signing_identity('-'), '-')
            identities.assert_not_called()

    def test_missing_identity_stops_build_without_replacing_output(self):
        self.save()
        output = self.root / 'Lagrangian.app'; output.mkdir()
        marker = output / 'previous'; marker.write_text('preserved')
        args = argparse.Namespace(engine=self.root / 'engine', output=output, identity=None)
        with patch.object(package, 'resolve_engine', return_value=(args.engine, 'fixture')), \
                patch.object(package, 'signing_identities', return_value={}):
            with self.assertRaisesRegex(ValueError, 'refusing ad-hoc fallback'): package.build(args)
        self.assertEqual(marker.read_text(), 'preserved')

    def test_invalid_config_is_not_treated_as_ad_hoc(self):
        for values in ({'schemaVersion': 2}, {'identity': '-'}, {'identity': None}):
            with self.subTest(values=values):
                self.save(**values)
                with self.assertRaisesRegex(ValueError, 'Invalid signing configuration'):
                    package.resolve_signing_identity()
        (self.root / 'signing.json').write_text('[]')
        with self.assertRaisesRegex(ValueError, 'Invalid signing configuration'):
            package.resolve_signing_identity()

    def test_configure_pins_verified_certificate_and_no_secret(self):
        with patch.object(package, 'signing_identities', return_value={self.identity: 'Local'}), \
                patch.object(package, 'run'), \
                patch.object(package, 'signing_certificate', return_value={'sha1': self.identity, 'sha256': 'B' * 64}):
            package.configure_signing(argparse.Namespace(identity='Local'))
        path = self.root / 'signing.json'
        self.assertEqual(json.loads(path.read_text()), {'schemaVersion': 1, 'identity': self.identity, 'name': 'Local'})
        self.assertEqual(path.stat().st_mode & 0o777, 0o600)

    def test_ambiguous_name_or_failed_probe_keeps_config(self):
        self.save(); original = (self.root / 'signing.json').read_bytes()
        with patch.object(package, 'signing_identities', return_value={self.identity: 'Local', 'B' * 40: 'Local'}):
            with self.assertRaisesRegex(ValueError, 'exactly one'): package.configure_signing(argparse.Namespace(identity='Local'))
        with patch.object(package, 'signing_identities', return_value={self.identity: 'Local'}), \
                patch.object(package, 'run'), patch.object(package, 'signing_certificate', return_value=None):
            with self.assertRaisesRegex(ValueError, 'probe'): package.configure_signing(argparse.Namespace(identity='Local'))
        self.assertEqual((self.root / 'signing.json').read_bytes(), original)

    def test_verification_rejects_other_signer_before_running_executable(self):
        app = self.root / 'Lagrangian.app'; resources = app / 'Contents/Resources'; resources.mkdir(parents=True)
        (app / 'Contents/Info.plist').write_bytes(package.plistlib.dumps({'CFBundleIdentifier': package.APP_ID, 'CFBundleExecutable': 'Lagrangian'}))
        (resources / 'release.json').write_text(json.dumps({'signingCertificateSHA256': 'expected'}))
        for certificates in ([{'sha256': 'other'}], [{'sha256': 'expected'}, None]):
            with self.subTest(certificates=certificates), patch.object(package, 'run'), \
                    patch.object(package, 'signing_certificate', side_effect=certificates), patch.object(package, 'capture') as execute:
                with self.assertRaisesRegex(ValueError, 'Signing certificate mismatch'): package.validate(app)
                execute.assert_not_called()

class InstallRecovery(unittest.TestCase):
    def test_update_does_not_take_over_legacy_service(self):
        with patch.object(package, 'profiles', return_value=[{'id': 'test'}]), patch.object(package, 'capture', return_value=json.dumps({'running': True, 'managedByApp': False})):
            self.assertEqual(package.running(Path('/fake/app')), [])
        with patch.object(package, 'profiles', return_value=[{'id': 'test'}]), patch.object(package, 'capture', return_value=json.dumps({'running': True, 'managedByApp': True})):
            self.assertEqual(package.running(Path('/fake/app')), ['test'])
    def test_failed_update_restores_previous_bundle(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); old = root / 'Applications/Lagrangian.app'; incoming = root / 'new/Lagrangian.app'
            for path, text in [(old, 'old'), (incoming, 'new')]:
                package.executable(path).parent.mkdir(parents=True); package.executable(path).write_text(text)
            settings = root / 'data/profiles.json'; settings.parent.mkdir(); settings.write_text('preserved')
            with patch.object(package, 'validate', return_value={}), patch.object(package, 'running', return_value=['test']), patch.object(package, 'capture', return_value='{"running": false}'), patch.object(package, 'run'), patch.object(package.subprocess, 'run'), patch.object(package, 'healthy', side_effect=RuntimeError('failed')):
                with self.assertRaises(RuntimeError): package.replace_app(incoming, old, root / 'data')
            self.assertEqual(package.executable(old).read_text(), 'old')
            self.assertEqual(settings.read_text(), 'preserved')
    def test_update_waits_for_asynchronous_stop_before_replacement(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); old = root / 'Applications/Lagrangian.app'; incoming = root / 'new/Lagrangian.app'
            for path, text in [(old, 'old'), (incoming, 'new')]:
                package.executable(path).parent.mkdir(parents=True); package.executable(path).write_text(text)
            states = iter([True, False])
            def status(args):
                self.assertEqual(package.executable(old).read_text(), 'old')
                return json.dumps({'running': next(states)})
            def control(args):
                if args[-2] == 'start': self.assertEqual(package.executable(old).read_text(), 'new')
            with patch.object(package, 'validate', return_value={}), patch.object(package, 'running', return_value=['test']), \
                    patch.object(package, 'run', side_effect=control) as commands, patch.object(package, 'capture', side_effect=status) as checks, \
                    patch.object(package.time, 'sleep'), patch.object(package, 'healthy'):
                package.replace_app(incoming, old, root / 'data')
            self.assertEqual(checks.call_count, 2)
            self.assertEqual([call.args[0][-2] for call in commands.call_args_list], ['stop', 'start'])
    def test_stop_timeout_is_reported(self):
        with patch.object(package, 'capture', return_value='{"running": true}'), \
                patch.object(package.time, 'monotonic', side_effect=[0, 0, 11]), patch.object(package.time, 'sleep'):
            with self.assertRaisesRegex(RuntimeError, 'did not stop.*test'):
                package.wait_stopped(Path('/fake/app'), ['test'])
    def test_successful_update_keeps_recovery_bundle(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); old = root / 'Applications/Lagrangian.app'; incoming = root / 'new/Lagrangian.app'
            for path, text in [(old, 'old'), (incoming, 'new')]:
                package.executable(path).parent.mkdir(parents=True); package.executable(path).write_text(text)
            with patch.object(package, 'validate', return_value={'version': 'test'}), patch.object(package, 'running', return_value=[]):
                package.replace_app(incoming, old, root / 'data')
            previous = Path(json.loads((root / 'data/previous-release.json').read_text())['app'])
            self.assertEqual(package.executable(previous).read_text(), 'old')
            self.assertEqual(package.executable(old).read_text(), 'new')

class NativeBuild(unittest.TestCase):
    def test_native_packaging_failure_preserves_previous_output(self):
        with tempfile.TemporaryDirectory() as tmp:
            output = Path(tmp) / 'Lagrangian.app'; output.mkdir()
            marker = output / 'previous'; marker.write_text('preserved')
            engine = Path(tmp) / 'native-engine'
            metadata = {'profile': 'flow-release', 'target': 'aarch64-apple-darwin'}
            args = argparse.Namespace(engine=None, output=output, build_engine=True, jobs=2)
            with patch.object(package, 'build_native_engine', return_value=(engine, metadata)) as native, \
                    patch.object(package, 'resolve_engine', return_value=(engine, 'tinymist test')) as resolve, \
                    patch.object(package, 'build_bundle', side_effect=RuntimeError('build failed')) as bundle:
                with self.assertRaisesRegex(RuntimeError, 'build failed'): package.build(args)
            native.assert_called_once_with(2)
            resolve.assert_called_once_with(engine)
            self.assertEqual(bundle.call_args.args[2:], (engine, 'tinymist test', metadata))
            self.assertEqual(marker.read_text(), 'preserved')

    def test_native_build_uses_metadata_target_directory_and_locked_profile(self):
        with patch.object(package.sys, 'platform', 'darwin'), \
                patch.object(package.platform, 'machine', return_value='arm64'), \
                patch.object(package, 'capture', return_value=json.dumps({'target_directory': '/tmp/custom target'})), \
                patch.object(package, 'run') as run:
            engine, metadata = package.build_native_engine(2)
        self.assertEqual(engine, Path('/tmp/custom target/aarch64-apple-darwin/flow-release/tinymist'))
        self.assertEqual(metadata['target'], 'aarch64-apple-darwin')
        self.assertEqual(metadata['configuredLto'], 'thin')
        command = run.call_args.args[0]
        self.assertIn('--locked', command)
        self.assertEqual(command[command.index('--profile') + 1], 'flow-release')
        self.assertEqual(command[command.index('--jobs') + 1], '2')

class EngineArtifact(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory(); self.addCleanup(temp.cleanup)
        self.root = Path(temp.name).resolve()
        self.engine = self.root / 'target/aarch64-apple-darwin/flow-release/tinymist'
        self.engine.parent.mkdir(parents=True)
        self.engine.write_bytes(b'native-engine')
        self.engine.chmod(0o755)
        self.digest = hashlib.sha256(b'native-engine').hexdigest()
        self.app = self.root / 'dist/Lagrangian.app'
        (self.app / 'Contents').mkdir(parents=True)
        (self.app / 'Contents/Info.plist').write_text('app')
        self.manifest = {
            'engineInputSHA256': self.digest,
            'engineVersion': 'tinymist test',
            'engineBuild': {'profile': 'flow-release', 'target': 'aarch64-apple-darwin', 'configuredLto': 'thin'},
        }
        self.manifest_path = self.root / 'dist/release.json'
        self.manifest_path.write_text(json.dumps(self.manifest))
        self.output = self.root / 'artifact'

    def capture(self, args, **kwargs):
        if args[0] == 'cargo':
            return json.dumps({'target_directory': str(self.root / 'target')})
        if args[-1] == '--version':
            return 'tinymist test'
        if args[-2:] == ['preview', '--help']:
            return 'Options:\n --follow-system-theme\n'
        raise AssertionError(args)

    def test_stage_copies_unsigned_engine_checksum_manifest_and_app(self):
        args = argparse.Namespace(app=self.app, manifest=self.manifest_path, output=self.output)
        with patch.object(package, 'capture', side_effect=self.capture):
            package.stage_engine_artifact(args)
        staged = self.output / 'flow-engine'
        self.assertEqual(staged.read_bytes(), b'native-engine')
        self.assertTrue(staged.stat().st_mode & 0o111)
        self.assertEqual((self.output / 'flow-engine.sha256').read_text(), self.digest + '  flow-engine\n')
        self.assertEqual(json.loads((self.output / 'release.json').read_text())['engineInputSHA256'], self.digest)
        self.assertEqual((self.output / 'Lagrangian.app/Contents/Info.plist').read_text(), 'app')

    def test_stage_rejects_other_targets_before_probing_the_binary(self):
        self.manifest['engineBuild']['target'] = 'x86_64-apple-darwin'
        self.manifest_path.write_text(json.dumps(self.manifest))
        args = argparse.Namespace(app=self.app, manifest=self.manifest_path, output=self.output)
        with patch.object(package, 'capture', side_effect=AssertionError('probed')):
            with self.assertRaisesRegex(ValueError, 'aarch64-apple-darwin'):
                package.stage_engine_artifact(args)

    def test_stage_rejects_hash_mismatch_before_version_probe(self):
        self.manifest['engineInputSHA256'] = '0' * 64
        self.manifest_path.write_text(json.dumps(self.manifest))
        args = argparse.Namespace(app=self.app, manifest=self.manifest_path, output=self.output)
        def capture(cmd, **kwargs):
            self.assertEqual(cmd[0], 'cargo')
            return json.dumps({'target_directory': str(self.root / 'target')})
        with patch.object(package, 'capture', side_effect=capture):
            with self.assertRaisesRegex(ValueError, 'engineInputSHA256'):
                package.stage_engine_artifact(args)

    def test_stage_rejects_engine_without_flow_preview_support(self):
        def capture(cmd, **kwargs):
            if cmd[0] == 'cargo':
                return json.dumps({'target_directory': str(self.root / 'target')})
            if cmd[-1] == '--version':
                return 'tinymist test'
            return 'standard preview'
        args = argparse.Namespace(app=self.app, manifest=self.manifest_path, output=self.output)
        with patch.object(package, 'capture', side_effect=capture):
            with self.assertRaisesRegex(ValueError, '--follow-system-theme'):
                package.stage_engine_artifact(args)
        self.assertFalse(self.output.exists())

class FetchEngine(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory(); self.addCleanup(temp.cleanup)
        self.root = Path(temp.name).resolve()
        self.dest = self.root / 'engines' / '42'
        self.digest = hashlib.sha256(b'native-engine').hexdigest()
        self.calls = []

    def manifest(self, **overrides):
        value = {
            'engineInputSHA256': self.digest,
            'engineBuild': {'profile': 'flow-release', 'target': 'aarch64-apple-darwin'},
        }
        value.update(overrides)
        return value

    def write_artifact(self, directory, checksum=None, manifest=None, body=b'native-engine'):
        directory.mkdir(parents=True, exist_ok=True)
        (directory / 'flow-engine').write_bytes(body)
        (directory / 'flow-engine.sha256').write_text((checksum or self.digest) + '  flow-engine\n')
        (directory / 'release.json').write_text(json.dumps(manifest or self.manifest()))
        app = directory / 'Lagrangian.app/Contents'
        app.mkdir(parents=True)
        (app / 'Info.plist').write_text('app')

    def gh(self, args, **kwargs):
        self.calls.append(list(map(str, args)))
        if args[:3] == ['gh', 'repo', 'view']:
            return 'kimpossible-TY/Lagrangian'
        if args[:3] == ['gh', 'run', 'list']:
            return json.dumps([{'databaseId': 42, 'url': 'https://example.test/runs/42', 'headSha': 'abc', 'conclusion': 'success'}])
        if args[:3] == ['gh', 'run', 'download']:
            dest = Path(args[args.index('--dir') + 1])
            root = dest / 'flow-engine-darwin-arm64' if self.layout == 'nested' else dest
            self.write_artifact(root, checksum=self.checksum, manifest=self.payload_manifest, body=self.body)
            return ''
        if args[:2] == ['/usr/bin/xattr', '-dr']:
            return ''
        raise AssertionError(args)

    def fetch(self, platform='linux', run_id=None, branch='main', checksum=None, manifest=None, body=b'native-engine', layout='nested'):
        self.layout = layout
        self.checksum = checksum or hashlib.sha256(body).hexdigest()
        self.body = body
        self.digest = self.checksum
        self.payload_manifest = manifest or self.manifest()
        stdout = io.StringIO()
        args = argparse.Namespace(branch=branch, run_id=run_id, dest=self.dest)
        with patch.object(package.shutil, 'which', return_value='/usr/bin/gh'), \
                patch.object(package.sys, 'platform', platform), \
                patch.object(package, 'capture', side_effect=self.gh), \
                patch.object(package, 'run', side_effect=self.gh), \
                patch.object(package, 'resolve_engine', return_value=(self.dest / 'flow-engine', 'tinymist test')) as resolve, \
                patch('sys.stdout', stdout):
            package.fetch_engine(args)
        self.resolve = resolve
        return stdout.getvalue().strip()

    def test_latest_successful_run_is_verified_outside_target(self):
        printed = self.fetch()
        self.assertEqual(printed, str(self.dest / 'flow-engine'))
        self.assertEqual((self.dest / 'flow-engine').read_bytes(), b'native-engine')
        self.assertTrue(any(call[:3] == ['gh', 'run', 'list'] and '--branch' in call and 'main' in call for call in self.calls))
        self.assertFalse(any(call[0] == 'cargo' for call in self.calls))
        self.assertFalse(package.path_inside(self.dest, package.ROOT / 'target'))
        self.resolve.assert_not_called()

    def test_explicit_run_skips_the_branch_lookup(self):
        printed = self.fetch(run_id='42', layout='flat')
        self.assertEqual(printed, str(self.dest / 'flow-engine'))
        self.assertEqual((self.dest / 'Lagrangian.app/Contents/Info.plist').read_text(), 'app')
        self.assertFalse(any(call[:3] == ['gh', 'run', 'list'] for call in self.calls))

    def test_checksum_parser_accepts_shasum_lines(self):
        digest = 'ab' * 32
        for text in (digest, digest + '  flow-engine\n', digest.upper() + ' *flow-engine\n'):
            self.assertEqual(package.parse_engine_checksum(text), digest)
        with self.assertRaisesRegex(ValueError, 'one SHA-256'):
            package.parse_engine_checksum(digest + '\n' + digest + '\n')
        with self.assertRaisesRegex(ValueError, 'does not contain'):
            package.parse_engine_checksum('nope  flow-engine\n')

    def test_darwin_clears_quarantine_and_probes_preview_support(self):
        self.fetch(platform='darwin', run_id='42')
        self.assertTrue(any(call[:3] == ['/usr/bin/xattr', '-dr', 'com.apple.quarantine'] for call in self.calls))
        self.resolve.assert_called_once()
        self.assertFalse(any(call[0] == 'cargo' for call in self.calls))

    def test_checksum_mismatch_keeps_the_destination_absent(self):
        with self.assertRaisesRegex(ValueError, 'SHA-256 mismatch'):
            self.fetch(run_id='42', checksum='ab' * 32)
        self.assertFalse(self.dest.exists())

    def test_manifest_mismatch_and_wrong_target_are_rejected(self):
        with self.assertRaisesRegex(ValueError, 'engineInputSHA256'):
            self.fetch(run_id='42', manifest=self.manifest(engineInputSHA256='cd' * 32))
        self.assertFalse(self.dest.exists())
        with self.assertRaisesRegex(ValueError, 'flow-release'):
            self.fetch(run_id='42', manifest=self.manifest(engineBuild={'profile': 'release', 'target': 'aarch64-apple-darwin'}))

    def test_missing_run_and_target_directory_and_gh_are_rejected(self):
        with patch.object(package.shutil, 'which', return_value=None):
            with self.assertRaisesRegex(ValueError, 'does not compile Rust'):
                package.fetch_engine(argparse.Namespace(branch='main', run_id=None, dest=self.dest))
        with patch.object(package.shutil, 'which', return_value='/usr/bin/gh'), \
                patch.object(package, 'capture', return_value='[]'), \
                patch.object(package, 'run', side_effect=AssertionError('downloaded')):
            with self.assertRaisesRegex(ValueError, 'No successful'):
                package.fetch_engine(argparse.Namespace(branch='main', run_id=None, dest=self.dest))
        with patch.object(package.shutil, 'which', return_value='/usr/bin/gh'), \
                patch.object(package, 'run', side_effect=AssertionError('downloaded')):
            with self.assertRaisesRegex(ValueError, 'target directory'):
                package.fetch_engine(argparse.Namespace(branch='main', run_id='42', dest=package.ROOT / 'target' / 'engine'))

    def test_default_cache_is_outside_the_repository_target(self):
        self.assertFalse(package.path_inside(package.engine_cache_dir('42'), package.ROOT / 'target'))

class TailHostingMigration(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if sys.platform != 'darwin':
            raise unittest.SkipTest('Native app tests require macOS')
        cls.compiled_binary = compiled_app_binary()
        temp = tempfile.TemporaryDirectory(prefix='flow-migration-template-')
        cls.addClassCleanup(temp.cleanup)
        cls.template_app = Path(temp.name) / 'Lagrangian.app'
        macos = cls.template_app / 'Contents/MacOS'
        resources = cls.template_app / 'Contents/Resources'
        macos.mkdir(parents=True)
        resources.mkdir(parents=True)
        shutil.copy2(cls.compiled_binary, macos / package.APP_EXECUTABLE)
        (macos / package.APP_EXECUTABLE).chmod(0o755)
        bundled_engine = macos / 'flow-engine'
        bundled_engine.write_text('#!/bin/sh\necho "tinymist 0.14.10 --follow-system-theme"\n')
        bundled_engine.chmod(0o755)
        info = {
            'CFBundleIdentifier': package.APP_ID,
            'CFBundleName': package.APP_NAME,
            'CFBundleDisplayName': package.APP_NAME,
            'CFBundleExecutable': package.APP_EXECUTABLE,
            'CFBundlePackageType': 'APPL',
            'CFBundleShortVersionString': '0.1.0',
            'CFBundleVersion': '0.1.0',
        }
        (cls.template_app / 'Contents/Info.plist').write_bytes(package.plistlib.dumps(info))
        manifest = {
            'version': '0.1.0',
            'engineSHA256': package.digest(bundled_engine),
            'signing': 'ad-hoc',
        }
        (resources / 'release.json').write_text(json.dumps(manifest))
        subprocess.run(['/usr/bin/codesign', '--force', '--sign', '-', '--identifier', package.APP_ID + '.engine', bundled_engine],
                       check=True, capture_output=True)
        subprocess.run(['/usr/bin/codesign', '--force', '--sign', '-', '--identifier', package.APP_ID, cls.template_app],
                       check=True, capture_output=True)

    def setUp(self):
        temp = tempfile.TemporaryDirectory(prefix='flow-migration-home-')
        self.addCleanup(temp.cleanup)
        self.workspace = Path(temp.name).resolve()
        self.home = self.workspace / 'home'
        self.tail_root = self.workspace / 'Tail_hosting'
        self._build_fixture()
        self._install_system_stubs()

    def _install_system_stubs(self):
        self.stub_site = self.workspace / 'site-stubs'
        self.stub_site.mkdir(parents=True, exist_ok=True)
        self.launchctl_log = self.workspace / 'launchctl.log'
        self.system_stub = self.workspace / 'bin/system-stub'
        self.system_stub.parent.mkdir(parents=True, exist_ok=True)
        self.real_home = str(Path.home().resolve())
        stub_logic = (
            'import os, pathlib, shlex, subprocess\n'
            f'_LOG_PATH = pathlib.Path({str(self.launchctl_log)!r})\n'
            f'_REPO_ROOT = {str(ROOT)!r}\n'
            f'_REAL_HOME = {self.real_home!r}\n'
            'def _is_system_tool(argv, exe=None):\n'
            '    first = str(exe) if exe else (str(argv[0]) if argv else "")\n'
            '    if not first:\n'
            '        return False\n'
            '    tokens = [first] + (shlex.split(first) if " " in first else [])\n'
            '    return any(\n'
            '        t in {"/bin/launchctl", "/usr/sbin/lsof"} or pathlib.Path(t).name in {"launchctl", "lsof"}\n'
            '        for t in tokens\n'
            '    )\n'
            'def _is_repo_git_porcelain(argv):\n'
            '    return len(argv) >= 5 and pathlib.Path(argv[0]).name == "git" and argv[1:4] == ["-C", _REPO_ROOT, "status"] and "--porcelain" in argv\n'
            'def _check_safe_args(argv):\n'
            '    joined = " ".join(str(x) for x in argv)\n'
            '    if any(tok in joined for tok in ("23625", "23627")):\n'
            '        raise AssertionError(f"Refusing to target production port or label: {argv}")\n'
            '    if _REAL_HOME and _REAL_HOME in joined and "Library" in joined:\n'
            '        raise AssertionError(f"Refusing to target the real home Library: {argv}")\n'
            'def _emulate_system_tool(argv):\n'
            '    _check_safe_args(argv)\n'
            '    with _LOG_PATH.open("a") as _f:\n'
            '        _f.write(" ".join(argv) + "\\n")\n'
            '    name = pathlib.Path(argv[0]).name\n'
            '    if name == "launchctl" and len(argv) >= 2 and argv[1] == "print":\n'
            '        lines = _LOG_PATH.read_text().splitlines()[:-1]\n'
            '        for prev in reversed(lines):\n'
            '            if "launchctl " in prev and ("bootout " in prev or "bootstrap " in prev):\n'
            '                out = "\\tpid = 4242\\n" if "bootstrap " in prev else ""\n'
            '                return subprocess.CompletedProcess(argv, 0, stdout=out, stderr="")\n'
            '        preset = os.environ.get("FLOW_TEST_READER_PID", "")\n'
            '        if preset.isdigit():\n'
            '            return subprocess.CompletedProcess(argv, 0, stdout=f"\\tpid = {preset}\\n", stderr="")\n'
            '        return subprocess.CompletedProcess(argv, 0, stdout="", stderr="")\n'
            '    return subprocess.CompletedProcess(argv, 0, stdout="", stderr="")\n'
        )
        (self.stub_site / 'sitecustomize.py').write_text(
            stub_logic +
            '_orig_popen = subprocess.Popen\n'
            'def _guarded_popen(args, *a, **kw):\n'
            '    argv = [str(x) for x in args] if isinstance(args, (list, tuple)) else [str(args)]\n'
            '    if _is_system_tool(argv, kw.get("executable")):\n'
            '        raise AssertionError(f"Refusing to invoke real system binary: {argv}")\n'
            '    return _orig_popen(args, *a, **kw)\n'
            'subprocess.Popen = _guarded_popen\n'
            '_orig_run = subprocess.run\n'
            'def _patched_run(args, *a, **kw):\n'
            '    argv = [str(x) for x in args] if isinstance(args, (list, tuple)) else [str(args)]\n'
            '    if _is_system_tool(argv, kw.get("executable")):\n'
            '        if os.environ.get("FLOW_DISABLE_SYSTEM_STUB") == "1":\n'
            '            raise AssertionError(f"Refusing to invoke real system binary: {argv}")\n'
            '        return _emulate_system_tool(argv)\n'
            '    if _is_repo_git_porcelain(argv):\n'
            '        dirty = " M tools/flow-reader/install.py\\n" if os.environ.get("FLOW_TEST_GIT_DIRTY") == "1" else ""\n'
            '        return subprocess.CompletedProcess(argv, 0, stdout=dirty, stderr="")\n'
            '    return _orig_run(args, *a, **kw)\n'
            'subprocess.run = _patched_run\n'
        )
        self.system_stub.write_text(
            f'#!{sys.executable}\n'
            'import sys\n' +
            stub_logic +
            'res = _emulate_system_tool(sys.argv[1:])\n'
            'sys.stdout.write(res.stdout)\n'
            'sys.exit(res.returncode)\n'
        )
        self.system_stub.chmod(0o755)

        orig_popen = subprocess.Popen
        orig_run = subprocess.run
        ns = {}
        exec(stub_logic, ns)
        is_system_tool = ns['_is_system_tool']
        is_repo_git_porcelain = ns['_is_repo_git_porcelain']
        emulate_system_tool = ns['_emulate_system_tool']

        def guarded_popen(args, *a, **kw):
            argv = [str(x) for x in args] if isinstance(args, (list, tuple)) else [str(args)]
            if is_system_tool(argv, kw.get('executable')):
                raise AssertionError(f'Refusing to invoke real system binary: {argv}')
            return orig_popen(args, *a, **kw)

        def patched_run(args, *a, **kw):
            argv = [str(x) for x in args] if isinstance(args, (list, tuple)) else [str(args)]
            if is_system_tool(argv, kw.get('executable')):
                if os.environ.get('FLOW_DISABLE_SYSTEM_STUB') == '1':
                    raise AssertionError(f'Refusing to invoke real system binary: {argv}')
                return emulate_system_tool(argv)
            if is_repo_git_porcelain(argv):
                dirty = ' M tools/flow-reader/install.py\n' if os.environ.get('FLOW_TEST_GIT_DIRTY') == '1' else ''
                return subprocess.CompletedProcess(argv, 0, stdout=dirty, stderr='')
            return orig_run(args, *a, **kw)

        for patcher in (
            patch.object(subprocess, 'Popen', side_effect=guarded_popen),
            patch.object(subprocess, 'run', side_effect=patched_run),
            patch.object(package, 'HOME', self.home, create=True),
            patch.object(package, 'DATA', self.target_data),
            patch.object(package, 'LEGACY_DATA', self.legacy_data),
            patch.object(package, 'DEFAULT_APP', self.app),
            patch.object(package, 'LEGACY_APP', self.legacy_app),
        ):
            patcher.start()
            self.addCleanup(patcher.stop)

        existing_pythonpath = os.environ.get('PYTHONPATH', '')
        combined_pythonpath = str(self.stub_site) + (os.pathsep + existing_pythonpath if existing_pythonpath else '')
        env_patch = patch.dict(os.environ, {
            'HOME': str(self.home),
            'PYTHONPATH': combined_pythonpath,
            'FLOW_TEST_SYSTEM_STUB': str(self.system_stub),
        })
        env_patch.start()
        self.addCleanup(env_patch.stop)
        os.environ.pop('FLOW_DATA_DIR', None)
        os.environ.pop('FLOW_LOG_DIR', None)
        self.env = dict(os.environ)

    def _build_fixture(self):
        project = self.home / 'Documents/Typst- PDE'
        (project / 'fonts').mkdir(parents=True)
        (project / 'main.typ').write_text('= PDE Notes\n')
        (self.home / 'Library/Application Support/typst/packages').mkdir(parents=True)

        # Build legacy tinymist-flow.app and new Lagrangian.app in fake HOME
        self.legacy_data = self.home / 'Library/Application Support/tinymist-flow'
        self.target_data = self.home / 'Library/Application Support/Lagrangian'
        self.legacy_app = self.home / 'Applications/tinymist-flow.app'
        legacy_macos = self.legacy_app / 'Contents/MacOS'
        legacy_macos.mkdir(parents=True)
        legacy_parent = {
            'id': 'typst-pde',
            'name': 'Typst PDE Notes Live Preview',
            'root': str(project),
            'entry': 'main.typ',
            'fonts': [str(project / 'fonts')],
            'packages': str(self.home / 'Library/Application Support/typst/packages'),
            'port': 24655,
            'publicURL': 'https://preview.example:25655/',
            'label': 'com.example.typst-pde-preview',
        }
        legacy_plan = {
            'environment': {
                'TINYMIST_PREVIEW_CHANGE_FILE': str(self.legacy_data / 'changes/typst-pde.json'),
            },
        }
        legacy_flow = legacy_macos / 'tinymist-flow'
        legacy_flow.write_text(
            f'#!{sys.executable}\nimport json, sys\n'
            f'profiles = {repr({"profiles": [legacy_parent]})}\n'
            f'plan = {repr(legacy_plan)}\n'
            'if sys.argv[1:] == ["--profiles"]:\n'
            '    print(json.dumps(profiles))\n'
            'elif len(sys.argv) >= 2 and sys.argv[1] == "--launch-plan":\n'
            '    print(json.dumps(plan))\n'
            'else:\n'
            '    print("legacy tinymist-flow")\n'
        )
        legacy_flow.chmod(0o755)
        legacy_engine = legacy_macos / 'flow-engine'
        legacy_engine.write_text('#!/bin/sh\necho "legacy flow-engine"\n')
        legacy_engine.chmod(0o755)

        self.app = self.home / 'Applications/Lagrangian.app'
        shutil.copytree(self.template_app, self.app, symlinks=True)
        subprocess.run(['/usr/bin/xattr', '-cr', self.app], check=True)
        subprocess.run(['/usr/bin/codesign', '--force', '--sign', '-', '--identifier', package.APP_ID + '.engine', self.app / 'Contents/MacOS/flow-engine'],
                       check=True, capture_output=True)
        subprocess.run(['/usr/bin/codesign', '--force', '--sign', '-', '--identifier', package.APP_ID, self.app],
                       check=True, capture_output=True)

        # Build legacy reader data under ~/Library/Application Support/tinymist-flow/reader
        reader_root = self.legacy_data / 'reader'
        engine_bytes = b'#!/bin/sh\necho "reader-flow-engine"\n'
        engine_sha = hashlib.sha256(engine_bytes).hexdigest()
        self.reader_engine = reader_root / 'engines' / engine_sha / 'flow-engine'
        self.reader_engine.parent.mkdir(parents=True)
        self.reader_engine.write_bytes(engine_bytes)
        self.reader_engine.chmod(0o755)

        release_id = 'aa80b4bafc0176e46506add14bbc7303e05123d3-wasm-47af2ba11080f593'
        self.release_dir = reader_root / 'releases' / release_id
        self.release_dir.mkdir(parents=True)
        # The installed release is the pre-PR tree: strict owns_agent and the tinymist-flow bundle id.
        # Copying the current tree would hide restore's "does not own" failure.
        archive = subprocess.check_output(
            ['git', '-C', str(ROOT), 'archive', PRE_PR_READER, 'tools/flow-reader'],
        )
        with tarfile.open(fileobj=io.BytesIO(archive)) as tar:
            tar.extractall(self.release_dir, filter='data')
        tools_dst = self.release_dir / 'tools/flow-reader'
        manager_py = tools_dst / 'flow_reader/services/manager.py'
        manager_text = manager_py.read_text()
        if 'Path(arguments[0]).resolve()' in manager_text:
            raise AssertionError('legacy release must keep the pre-PR owns_agent')
        if 'return agent.get("ProgramArguments") == self.agent(profile)["ProgramArguments"]' not in manager_text:
            raise AssertionError('legacy release is missing the pre-PR owns_agent')
        manager_py.write_text(manager_text.replace(
            '"io.github.kimpossible-ty.lagrangian"',
            '"io.github.kimpossible-ty.tinymist-flow"',
        ))
        compiler_dir = tools_dst / 'compiler-assets'
        compiler_dir.mkdir(parents=True, exist_ok=True)
        compiler_js = compiler_dir / 'compiler.js'
        compiler_js.write_text('export const compile = () => true;\n')
        compiler_wasm = compiler_dir / 'compiler_bg.wasm'
        compiler_wasm.write_bytes(b'\x00asm\x01\x00\x00\x00')
        compiler_files = {
            'compiler.js': package.digest(compiler_js),
            'compiler_bg.wasm': package.digest(compiler_wasm),
        }
        compiler_manifest = {
            'schemaVersion': 1,
            'files': compiler_files,
            'engine': hashlib.sha256(json.dumps(compiler_files, sort_keys=True).encode()).hexdigest(),
        }
        (compiler_dir / 'manifest.json').write_text(json.dumps(compiler_manifest, indent=2) + '\n')

        release_files = {}
        for item in sorted(self.release_dir.rglob('*')):
            if item.is_file() and item.name != 'release.json':
                release_files[str(item.relative_to(self.release_dir))] = package.digest(item)
        (self.release_dir / 'release.json').write_text(json.dumps({
            'schemaVersion': 1,
            'releaseId': release_id,
            'sourceRevision': 'aa80b4bafc0176e46506add14bbc7303e05123d3',
            'wasmHash': '47af2ba11080f593',
            'engineSHA256': engine_sha,
            'files': release_files,
        }, indent=2) + '\n')

        focus_file = reader_root / 'documents/typst-pde-reader/focus.json'
        focus_file.parent.mkdir(parents=True)
        focus_file.write_text(json.dumps({'page': 1}) + '\n')

        mock_typst = self.workspace / 'bin/typst'
        mock_typst.parent.mkdir(parents=True, exist_ok=True)
        mock_typst.write_text('#!/bin/sh\necho "typst 0.14.0"\n')
        mock_typst.chmod(0o755)

        self.reader_config = {
            'schemaVersion': 1,
            'services': [
                {
                    'id': 'typst-pde-reader',
                    'parentID': 'typst-pde',
                    'port': 24657,
                    'publicURL': 'https://preview.example:25657/',
                    'development': False,
                    'semanticCanvases': True,
                    'extraFonts': [],
                }
            ],
            'flowManager': str(self.legacy_app / 'Contents/MacOS/tinymist-flow'),
            'python': sys.executable,
            'compiler': str(mock_typst),
            'engine': str(self.reader_engine),
            'browserCompiler': str(compiler_dir),
        }
        (reader_root / 'config.json').write_text(json.dumps(self.reader_config, indent=2) + '\n')
        (reader_root / 'config.previous.json').write_text(json.dumps(self.reader_config, indent=2) + '\n')

        launcher = reader_root / 'bin/flow-reader'
        launcher.parent.mkdir(parents=True)
        launcher.write_text(
            '#!/bin/sh\n'
            '# Flow Reader managed launcher\n'
            f"export FLOW_READER_DATA_DIR='{reader_root}'\n"
            f"exec {sys.executable} '{tools_dst / 'manage.py'}' \"$@\"\n"
        )
        launcher.chmod(0o755)

        # Simulate prior `Lagrangian --migrate-data`: target_data holds data, legacy_data is a compatibility symlink
        shutil.move(str(self.legacy_data), str(self.target_data))
        os.symlink(self.target_data, self.legacy_data)

        # LaunchAgents in fake HOME
        self.agents_dir = self.home / 'Library/LaunchAgents'
        self.agents_dir.mkdir(parents=True)
        self.preview_plist = self.agents_dir / 'com.example.typst-pde-preview.plist'
        self.preview_plist.write_bytes(package.plistlib.dumps({
            'Label': 'com.example.typst-pde-preview',
            'ProgramArguments': [str(self.legacy_app / 'Contents/MacOS/tinymist-flow'), '--serve', 'typst-pde'],
            'RunAtLoad': True,
            'KeepAlive': True,
            'AssociatedBundleIdentifiers': ['io.github.kimpossible-ty.tinymist-flow'],
        }))
        resolved_reader = (self.target_data / 'reader').resolve()
        self.reader_label = 'com.example.typst-pde-reader'
        self.reader_plist = self.agents_dir / f'{self.reader_label}.plist'
        self.reader_plist.write_bytes(package.plistlib.dumps({
            'Label': self.reader_label,
            'ProgramArguments': [str(self.legacy_data / 'reader/bin/flow-reader'), '--serve', 'typst-pde-reader'],
            'AssociatedBundleIdentifiers': ['io.github.kimpossible-ty.tinymist-flow'],
            'WorkingDirectory': str(resolved_reader),
            'RunAtLoad': True,
            'KeepAlive': True,
            'ThrottleInterval': 10,
            'ProcessType': 'Interactive',
            'EnvironmentVariables': {
                'FLOW_READER_DATA_DIR': str(resolved_reader),
                'PYTHONDONTWRITEBYTECODE': '1',
            },
            'StandardOutPath': str(resolved_reader / 'logs/typst-pde-reader.out.log'),
            'StandardErrorPath': str(resolved_reader / 'logs/typst-pde-reader.err.log'),
        }))
        self.login_plist = self.agents_dir / 'io.github.kimpossible-ty.tinymist-flow.login.plist'
        self.login_plist.write_bytes(package.plistlib.dumps({
            'Label': 'io.github.kimpossible-ty.tinymist-flow.login',
            'ProgramArguments': [str(self.legacy_app / 'Contents/MacOS/tinymist-flow'), '--background'],
            'RunAtLoad': True,
            'AssociatedBundleIdentifiers': ['io.github.kimpossible-ty.tinymist-flow'],
        }))

        # Fake Tail_hosting root
        (self.tail_root / 'config').mkdir(parents=True)
        (self.tail_root / 'bin').mkdir(parents=True)
        self.services_path = self.tail_root / 'config/services.json'
        self.services_data = {
            'schemaVersion': 1,
            'host': {'name': 'test-mac', 'dnsName': 'preview.example', 'tailscaleIp': '100.64.0.1'},
            'services': [
                {
                    'id': 'web',
                    'name': 'Static Web',
                    'kind': 'node-static',
                    'registration': 'managed',
                    'desiredState': 'running',
                    'launchAgentLabel': 'com.example.web',
                    'ingress': {'mode': 'tls', 'port': 8443, 'path': '/'},
                    'backend': {'protocol': 'http', 'host': '127.0.0.1', 'port': 3000},
                },
                {
                    'id': 'typst-pde',
                    'name': 'Typst PDE Notes Live Preview',
                    'kind': 'typst-always-preview',
                    'registration': 'managed',
                    'desiredState': 'running',
                    'launchAgentLabel': 'com.example.typst-pde-preview',
                    'projectRoot': str(project),
                    'entrypoint': 'main.typ',
                    'fontPaths': [str(project / 'fonts')],
                    'ingress': {'mode': 'tls', 'port': 25655, 'path': '/'},
                    'backend': {'protocol': 'http', 'host': '127.0.0.1', 'port': 24655},
                    'managerBinary': str(self.legacy_app / 'Contents/MacOS/tinymist-flow'),
                    'enginePath': str(self.legacy_app / 'Contents/MacOS/flow-engine'),
                    'focusFile': str(self.legacy_data / 'focus/typst-pde.json'),
                },
                {
                    'id': 'typst-pde-reader',
                    'name': 'Typst PDE Reader',
                    'kind': 'typst-reader',
                    'registration': 'managed',
                    'desiredState': 'running',
                    'launchAgentLabel': 'com.example.typst-pde-reader',
                    'projectRoot': str(project),
                    'entrypoint': 'main.typ',
                    'fontPaths': [str(project / 'fonts')],
                    'ingress': {'mode': 'tls', 'port': 25657, 'path': '/'},
                    'backend': {'protocol': 'http', 'host': '127.0.0.1', 'port': 24657},
                    'managerBinary': str(launcher),
                    'focusFile': str(focus_file),
                },
            ],
        }
        self.services_path.write_text(json.dumps(self.services_data, indent=2) + '\n')
        self.tail_script = self.tail_root / 'bin/tail-hosting'
        self.commands_log = self.tail_root / 'commands.log'
        self.tail_script.write_text(
            '#!/bin/sh\n'
            '# Flow app lifecycle adapter\n'
            '# typst_reader_service_p\n'
            '# typst_service_focus_file\n'
            '# Allow mobile tap propagation into PDF Canvas\n'
            f'echo "$@" >> "{self.commands_log}"\n'
        )
        self.tail_script.chmod(0o755)

    def place_legacy_reader_plist(self, launcher):
        """Point the job at the legacy label install.py keeps, with an explicit launcher path."""
        legacy_label = 'io.github.kimpossible-ty.tinymist-flow.reader.typst-pde-reader'
        agent = package.plistlib.loads(self.reader_plist.read_bytes())
        agent['Label'] = legacy_label
        agent['ProgramArguments'] = [str(launcher), '--serve', 'typst-pde-reader']
        legacy_plist = self.agents_dir / f'{legacy_label}.plist'
        if self.reader_plist != legacy_plist and self.reader_plist.exists():
            self.reader_plist.unlink()
        legacy_plist.write_bytes(package.plistlib.dumps(agent))
        self.reader_plist = legacy_plist
        services = json.loads(self.services_path.read_text())
        for service in services['services']:
            if service.get('id') == 'typst-pde-reader':
                service['launchAgentLabel'] = legacy_label
        self.services_path.write_text(json.dumps(services, indent=2) + '\n')

    def run_cli(self, *args):
        env = dict(os.environ, HOME=str(self.home))
        env.pop('FLOW_DATA_DIR', None)
        env.pop('FLOW_LOG_DIR', None)
        return subprocess.run(
            [sys.executable, str(ROOT / 'scripts/flow-app.py'), *map(str, args)],
            env=env,
            text=True,
            capture_output=True,
        )

    def test_dry_run_prints_planned_changes_without_modifying_files(self):
        before = {
            'services': package.digest(self.services_path),
            'script': package.digest(self.tail_script),
            'preview_plist': package.digest(self.preview_plist),
            'reader_plist': package.digest(self.reader_plist),
            'login_plist': package.digest(self.login_plist),
            'reader_config': package.digest(self.legacy_data / 'reader/config.json'),
            'reader_launcher': package.digest(self.legacy_data / 'reader/bin/flow-reader'),
        }
        buf = io.StringIO()
        with patch('sys.stdout', buf):
            package.migrate(argparse.Namespace(root=self.tail_root, app=self.app, dry_run=True))
        output = buf.getvalue()
        self.assertIn('[dry-run] port-check typst-pde-reader tcp/24657: free', output)
        self.assertIn('[dry-run] install-preflight: clean checkout', output)
        self.assertIn('[dry-run] install-preflight typst-pde-reader: parentID typst-pde, stopped', output)
        self.assertIn('[dry-run] migrate typst-always-preview typst-pde:', output)
        self.assertIn('[dry-run] migrate typst-reader typst-pde-reader (port 24657):', output)
        self.assertIn('[dry-run] migrate background-manager', output)
        self.assertIn('Dry run complete; no files or services were modified.', output)
        self.assertFalse((self.target_data / 'profiles.json').exists())
        self.assertFalse((self.target_data / 'migration-backup').exists())
        after = {
            'services': package.digest(self.services_path),
            'script': package.digest(self.tail_script),
            'preview_plist': package.digest(self.preview_plist),
            'reader_plist': package.digest(self.reader_plist),
            'login_plist': package.digest(self.login_plist),
            'reader_config': package.digest(self.legacy_data / 'reader/config.json'),
            'reader_launcher': package.digest(self.legacy_data / 'reader/bin/flow-reader'),
        }
        self.assertEqual(before, after)

    def test_dry_run_reports_a_running_reader_as_stopped_before_install(self):
        self.place_legacy_reader_plist(self.legacy_data / 'reader/bin/flow-reader')
        before = package.digest(self.services_path)
        buf = io.StringIO()
        with patch.dict(os.environ, {'FLOW_TEST_READER_PID': '4242'}), patch('sys.stdout', buf):
            package.migrate(argparse.Namespace(root=self.tail_root, app=self.app, dry_run=True))
        output = buf.getvalue()
        self.assertIn(
            f'[dry-run] install-preflight typst-pde-reader: parentID typst-pde, '
            f'will stop via launchctl bootout gui/{os.getuid()}/{self.reader_plist.stem}',
            output,
        )
        self.assertIn('Dry run complete; no files or services were modified.', output)
        self.assertEqual(package.digest(self.services_path), before)
        log = self.launchctl_log.read_text() if self.launchctl_log.exists() else ''
        self.assertNotIn('bootout ', log)
        self.assertNotIn('disable ', log)

    def test_dry_run_rejects_a_running_reader_it_does_not_own(self):
        self.place_legacy_reader_plist('/tmp/other-reader/bin/flow-reader')
        with patch.dict(os.environ, {'FLOW_TEST_READER_PID': '4242'}):
            with self.assertRaisesRegex(ValueError, 'does not own'):
                package.migrate(argparse.Namespace(root=self.tail_root, app=self.app, dry_run=True))
        self.assertFalse((self.target_data / 'migration-backup').exists())

    def test_dry_run_rejects_a_dirty_reader_checkout_and_a_mismatched_reader_id(self):
        with patch.dict(os.environ, {'FLOW_TEST_GIT_DIRTY': '1'}):
            with self.assertRaisesRegex(ValueError, 'clean commit'):
                package.migrate(argparse.Namespace(root=self.tail_root, app=self.app, dry_run=True))
        self.assertFalse((self.target_data / 'migration-backup').exists())
        services = json.loads(self.services_path.read_text())
        services['services'][2]['id'] = 'other-reader'
        self.services_path.write_text(json.dumps(services))
        cfg = json.loads((self.target_data / 'reader/config.json').read_text())
        cfg['services'][0]['id'] = 'other-reader'
        (self.target_data / 'reader/config.json').write_text(json.dumps(cfg))
        with self.assertRaisesRegex(ValueError, 'other-reader must be named typst-pde-reader'):
            package.migrate(argparse.Namespace(root=self.tail_root, app=self.app, dry_run=True))

    def test_migrate_stops_a_running_reader_before_install_and_restarts_it(self):
        self.place_legacy_reader_plist(self.legacy_data / 'reader/bin/flow-reader')
        buf = io.StringIO()
        with patch.dict(os.environ, {'FLOW_TEST_READER_PID': '4242'}), patch('sys.stdout', buf):
            package.migrate(argparse.Namespace(root=self.tail_root, app=self.app, dry_run=False))
        output = buf.getvalue()
        launcher = self.target_data / 'reader/bin/flow-reader'
        self.assertIn(f'Restart reader typst-pde-reader: {launcher} --control restart typst-pde-reader', output)
        log = self.launchctl_log.read_text()
        self.assertNotIn('disable ', log)
        self.assertIn(f'bootout gui/{os.getuid()}/{self.reader_plist.stem}', log)
        self.assertLess(log.index('bootout '), log.index(f'bootstrap gui/{os.getuid()} {self.reader_plist}'))
        cfg = json.loads((self.target_data / 'reader/config.json').read_text())
        self.assertEqual(cfg['flowManager'], str(package.executable(self.app)))
        restarted = package.plistlib.loads(self.reader_plist.read_bytes())
        self.assertEqual(restarted['AssociatedBundleIdentifiers'], [package.APP_ID])
        self.assertEqual(
            restarted['ProgramArguments'][0],
            str(self.target_data.resolve() / 'reader/bin/flow-reader'),
        )

    def test_failed_install_bootstraps_the_running_reader_again(self):
        self.place_legacy_reader_plist(self.legacy_data / 'reader/bin/flow-reader')
        before = {
            'services': package.digest(self.services_path),
            'reader_config': package.digest(self.target_data / 'reader/config.json'),
            'reader_launcher': package.digest(self.target_data / 'reader/bin/flow-reader'),
            'reader_plist': package.digest(self.reader_plist),
        }
        with patch.dict(os.environ, {'FLOW_TEST_READER_PID': '4242'}), \
                patch.object(package, 'finalize_reader_migration', side_effect=RuntimeError('simulated install failure')):
            with self.assertRaisesRegex(RuntimeError, 'simulated install failure'):
                package.migrate(argparse.Namespace(root=self.tail_root, app=self.app, dry_run=False))
        self.assertEqual(package.digest(self.services_path), before['services'])
        self.assertEqual(package.digest(self.target_data / 'reader/config.json'), before['reader_config'])
        self.assertEqual(package.digest(self.target_data / 'reader/bin/flow-reader'), before['reader_launcher'])
        self.assertEqual(package.digest(self.reader_plist), before['reader_plist'])
        self.assertFalse((self.target_data / 'profiles.json').exists())
        log = self.launchctl_log.read_text()
        self.assertNotIn('disable ', log)
        bootout = f'bootout gui/{os.getuid()}/{self.reader_plist.stem}'
        bootstrap = f'bootstrap gui/{os.getuid()} {self.reader_plist}'
        self.assertIn(bootout, log)
        self.assertIn(bootstrap, log)
        self.assertLess(log.index(bootout), log.index(bootstrap))
        restored = package.plistlib.loads(self.reader_plist.read_bytes())
        self.assertEqual(
            restored['ProgramArguments'],
            [str(self.legacy_data / 'reader/bin/flow-reader'), '--serve', 'typst-pde-reader'],
        )

    def test_restart_failure_prints_the_manual_command_and_state(self):
        self.place_legacy_reader_plist(self.legacy_data / 'reader/bin/flow-reader')
        original = package.run

        def flaky(args, **kwargs):
            argv = [str(item) for item in args]
            if '--control' in argv and 'restart' in argv:
                raise RuntimeError('restart failed')
            return original(args, **kwargs)

        buf = io.StringIO()
        with patch.dict(os.environ, {'FLOW_TEST_READER_PID': '4242'}), \
                patch.object(package, 'run', side_effect=flaky), \
                patch('sys.stdout', buf):
            package.migrate(argparse.Namespace(root=self.tail_root, app=self.app, dry_run=False))
        output = buf.getvalue()
        launcher = self.target_data / 'reader/bin/flow-reader'
        self.assertIn('Reader restart failed: restart failed', output)
        self.assertIn(f'Restart reader typst-pde-reader: {launcher} --control restart typst-pde-reader', output)
        self.assertIn('state: stopped', output)
        cfg = json.loads((self.target_data / 'reader/config.json').read_text())
        self.assertEqual(cfg['flowManager'], str(package.executable(self.app)))

    def test_bootstrap_retries_once_after_launchd_refuses(self):
        calls = {'bootstrap': 0}
        original = package.run

        def flaky(args, **kwargs):
            argv = [str(item) for item in args]
            if 'bootstrap' in argv:
                calls['bootstrap'] += 1
                if calls['bootstrap'] == 1:
                    raise subprocess.CalledProcessError(1, argv)
            return original(args, **kwargs)

        with patch.object(package, 'run', side_effect=flaky):
            package.bootstrap_restored_reader(self.reader_plist.stem, self.reader_plist)
        self.assertEqual(calls['bootstrap'], 2)

    def test_unmigrated_legacy_data_fails_preflight_with_migrate_data_instruction(self):
        # Revert compatibility symlink back to an unmigrated legacy directory
        self.legacy_data.unlink()
        shutil.move(str(self.target_data), str(self.legacy_data))
        before_services = package.digest(self.services_path)
        before_login = package.digest(self.login_plist)
        before_reader_cfg = package.digest(self.legacy_data / 'reader/config.json')

        for dry_run in (True, False):
            with self.subTest(dry_run=dry_run):
                with self.assertRaisesRegex(ValueError, '--migrate-data'):
                    package.migrate(argparse.Namespace(root=self.tail_root, app=self.app, dry_run=dry_run))
                self.assertFalse(self.target_data.exists())
                self.assertEqual(package.digest(self.services_path), before_services)
                self.assertEqual(package.digest(self.login_plist), before_login)
                self.assertEqual(package.digest(self.legacy_data / 'reader/config.json'), before_reader_cfg)

    def test_migrate_and_restore_round_trip(self):
        original_hashes = {
            'services': package.digest(self.services_path),
            'script': package.digest(self.tail_script),
            'preview_plist': package.digest(self.preview_plist),
            'reader_plist': package.digest(self.reader_plist),
            'login_plist': package.digest(self.login_plist),
            'reader_config': package.digest(self.legacy_data / 'reader/config.json'),
            'reader_prev_config': package.digest(self.legacy_data / 'reader/config.previous.json'),
            'reader_launcher': package.digest(self.legacy_data / 'reader/bin/flow-reader'),
            'engine': package.digest(self.reader_engine),
            'compiler_js': package.digest(self.release_dir / 'tools/flow-reader/compiler-assets/compiler.js'),
        }
        migrate_buf = io.StringIO()
        with patch('sys.stdout', migrate_buf):
            package.migrate(argparse.Namespace(root=self.tail_root, app=self.app, dry_run=False))
        self.assertIn(
            f"Restart reader typst-pde-reader: {self.target_data / 'reader/bin/flow-reader'} --control restart typst-pde-reader",
            migrate_buf.getvalue(),
        )

        # Verify migrated services.json
        migrated_services = {s['id']: s for s in json.loads(self.services_path.read_text())['services']}
        self.assertEqual(migrated_services['web']['kind'], 'node-static')
        self.assertEqual(migrated_services['typst-pde']['managerBinary'], str(package.executable(self.app)))
        self.assertEqual(migrated_services['typst-pde']['enginePath'], str(self.app / 'Contents/MacOS/flow-engine'))
        self.assertEqual(migrated_services['typst-pde']['focusFile'], str(self.target_data / 'focus/typst-pde.json'))
        self.assertEqual(migrated_services['typst-pde-reader']['managerBinary'], str(self.target_data / 'reader/bin/flow-reader'))
        self.assertEqual(migrated_services['typst-pde-reader']['focusFile'], str(self.target_data / 'reader/documents/typst-pde-reader/focus.json'))

        # Verify reader artifacts in target_data (and via legacy_data compatibility symlink) remain intact
        rel_engine = self.reader_engine.relative_to(self.legacy_data)
        rel_compiler = (self.release_dir / 'tools/flow-reader/compiler-assets/compiler.js').relative_to(self.legacy_data)
        self.assertTrue((self.legacy_data / rel_engine).is_file())
        self.assertTrue((self.legacy_data / rel_compiler).is_file())
        self.assertEqual(package.digest(self.legacy_data / rel_engine), original_hashes['engine'])
        self.assertEqual(package.digest(self.target_data / rel_engine), original_hashes['engine'])
        self.assertEqual(package.digest(self.target_data / rel_compiler), original_hashes['compiler_js'])

        # Verify migrated reader config.json, launcher (via install.py), and background login manager (via Lagrangian --login on)
        migrated_reader_cfg = json.loads((self.target_data / 'reader/config.json').read_text())
        self.assertEqual(migrated_reader_cfg['flowManager'], str(package.executable(self.app)))
        self.assertTrue(migrated_reader_cfg['engine'].startswith(str(self.target_data / 'reader/engines/')))
        self.assertTrue(migrated_reader_cfg['browserCompiler'].startswith(str(self.target_data / 'reader/releases/')))
        migrated_launcher = self.target_data / 'reader/bin/flow-reader'
        launch_plan = json.loads(subprocess.check_output(
            [str(migrated_launcher), '--launch-plan', 'typst-pde-reader'], env=self.env, text=True,
        ))
        self.assertEqual(
            launch_plan['agent']['ProgramArguments'],
            [str(self.target_data.resolve() / 'reader/bin/flow-reader'), '--serve', 'typst-pde-reader'],
        )
        self.assertEqual(launch_plan['agent']['AssociatedBundleIdentifiers'], [package.APP_ID])
        login_agent = package.plistlib.loads(self.login_plist.read_bytes())
        self.assertEqual(login_agent['ProgramArguments'], [str(package.executable(self.app)), '--background'])
        self.assertEqual(login_agent['AssociatedBundleIdentifiers'], [package.APP_ID])

        # Verify restore --dry-run does not modify migrated state
        dry_buf = io.StringIO()
        with patch('sys.stdout', dry_buf):
            package.restore_hosting(argparse.Namespace(dry_run=True))
        self.assertIn('[dry-run] restore typst-reader typst-pde-reader:', dry_buf.getvalue())
        self.assertEqual(
            package.plistlib.loads(self.login_plist.read_bytes())['ProgramArguments'],
            [str(package.executable(self.app)), '--background'],
        )

        # Run full restore-tail-hosting and verify byte-for-byte restoration
        restore_buf = io.StringIO()
        with patch('sys.stdout', restore_buf):
            package.restore_hosting(argparse.Namespace(dry_run=False))
        self.assertIn(
            f'Restart reader typst-pde-reader: launchctl bootout gui/{os.getuid()}/'
            f'{self.reader_plist.stem}; enable; bootstrap {self.reader_plist}',
            restore_buf.getvalue(),
        )

        self.assertEqual(package.digest(self.services_path), original_hashes['services'])
        self.assertEqual(package.digest(self.tail_script), original_hashes['script'])
        self.assertEqual(package.digest(self.preview_plist), original_hashes['preview_plist'])
        self.assertEqual(package.digest(self.reader_plist), original_hashes['reader_plist'])
        self.assertEqual(package.digest(self.login_plist), original_hashes['login_plist'])
        self.assertEqual(package.digest(self.target_data / 'reader/config.json'), original_hashes['reader_config'])
        self.assertEqual(package.digest(self.target_data / 'reader/config.previous.json'), original_hashes['reader_prev_config'])
        self.assertEqual(package.digest(self.target_data / 'reader/bin/flow-reader'), original_hashes['reader_launcher'])
        self.assertEqual(package.digest(self.legacy_data / 'reader/config.json'), original_hashes['reader_config'])
        self.assertEqual(package.digest(self.legacy_data / 'reader/bin/flow-reader'), original_hashes['reader_launcher'])
        logged = self.commands_log.read_text().splitlines()
        self.assertIn('start typst-pde', logged)
        self.assertNotIn('start typst-pde-reader', logged)
        self.assertIn(f'bootstrap gui/{os.getuid()} {self.reader_plist}', self.launchctl_log.read_text())

    def test_symlinked_legacy_data_and_stale_backup_round_trip(self):
        # Simulate stale pre-reader migration-backup from an earlier preview-only run
        backup = self.target_data / 'migration-backup'
        backup.mkdir(parents=True)
        stale_services = {'schemaVersion': 1, 'host': self.services_data['host'], 'services': [self.services_data['services'][0]]}
        (backup / 'services.json').write_text(json.dumps(stale_services))
        (backup / 'tail-hosting').write_text('#!/bin/sh\necho stale\n')
        (backup / 'migration.json').write_text(json.dumps({'hostingRoot': str(self.tail_root), 'app': str(self.app)}))

        # Simulate services.json where typst-pde was already updated by the old migrate command while its plist still runs tinymist-flow.app
        partially_migrated = json.loads(self.services_path.read_text())
        partially_migrated['services'][1]['managerBinary'] = str(package.executable(self.app))
        partially_migrated['services'][1]['enginePath'] = str(self.app / 'Contents/MacOS/flow-engine')
        partially_migrated['services'][1]['focusFile'] = str(self.target_data / 'focus/typst-pde.json')
        self.services_path.write_text(json.dumps(partially_migrated, indent=2) + '\n')

        res_migrate = self.run_cli('migrate-tail-hosting', self.tail_root, '--app', self.app)
        self.assertEqual(res_migrate.returncode, 0, res_migrate.stderr)
        self.assertTrue((backup / 'pre-reader-backup/services.json').is_file())
        self.assertTrue((backup / 'reader/config.json').is_file())
        self.assertTrue((backup / 'reader/bin/flow-reader').is_file())

        migrated_services = {s['id']: s for s in json.loads(self.services_path.read_text())['services']}
        self.assertEqual(migrated_services['typst-pde-reader']['managerBinary'], str(self.target_data / 'reader/bin/flow-reader'))

        res_restore = self.run_cli('restore-tail-hosting')
        self.assertEqual(res_restore.returncode, 0, res_restore.stderr)
        restored_services = {s['id']: s for s in json.loads(self.services_path.read_text())['services']}
        self.assertEqual(restored_services['typst-pde']['managerBinary'], str(self.legacy_app / 'Contents/MacOS/tinymist-flow'))
        self.assertEqual(restored_services['typst-pde-reader']['managerBinary'], str(self.legacy_data / 'reader/bin/flow-reader'))
        login_agent = package.plistlib.loads(self.login_plist.read_bytes())
        self.assertEqual(login_agent['ProgramArguments'], [str(self.legacy_app / 'Contents/MacOS/tinymist-flow'), '--background'])

    def test_port_conflict_and_corrupted_hashes_abort_before_switching(self):
        before_services = package.digest(self.services_path)
        before_login = package.digest(self.login_plist)
        # 1. Unrelated listener PID on port 24657
        with patch.object(package, 'listening_pids', return_value=[99999]), \
                patch.object(package, 'launchd_job_pid', return_value=11111), \
                patch.object(package, 'pid_belongs_to_reader_service', return_value=False):
            with self.assertRaisesRegex(ValueError, 'Port conflict on 24657'):
                package.migrate(argparse.Namespace(root=self.tail_root, app=self.app, dry_run=False))
        self.assertEqual(package.digest(self.services_path), before_services)
        self.assertEqual(package.digest(self.login_plist), before_login)

        # 2. Corrupted release file hash
        compiler_js = self.release_dir / 'tools/flow-reader/compiler-assets/compiler.js'
        original_js = compiler_js.read_bytes()
        compiler_js.write_text('corrupted();\n')
        try:
            with self.assertRaisesRegex(ValueError, 'SHA-256 mismatch'):
                package.migrate(argparse.Namespace(root=self.tail_root, app=self.app, dry_run=False))
        finally:
            compiler_js.write_bytes(original_js)
        self.assertEqual(package.digest(self.services_path), before_services)
        self.assertEqual(package.digest(self.login_plist), before_login)

    def test_patch_preflight_idempotency_for_already_applied_unapplied_and_incompatible_roots(self):
        # 1. Build an unpatched scripts/test-management.py from the pre-image of tail-hosting-reader.patch
        reader_patch_text = (ROOT / 'apps/macos/tail-hosting-reader.patch').read_text()
        test_mgmt_section = dict(package.split_patch_file_sections(reader_patch_text))['scripts/test-management.py']
        pre_lines = []
        for line in test_mgmt_section.splitlines():
            if line.startswith(('--- ', '+++ ', '@@ ')):
                continue
            if line.startswith((' ', '-')):
                pre_lines.append(line[1:])
        test_mgmt_path = self.tail_root / 'scripts/test-management.py'
        test_mgmt_path.parent.mkdir(parents=True, exist_ok=True)
        unpatched_test_mgmt = '\n'.join(pre_lines) + '\n'
        test_mgmt_path.write_text(unpatched_test_mgmt)
        unpatched_test_mgmt_sha = package.digest(test_mgmt_path)

        # Ensure focus & mobile markers are present on test-management.py so only reader.patch needs forward-apply first
        test_mgmt_with_later_markers = unpatched_test_mgmt + '# 1000+86400*30\n# def test_reader_observation_time_and_native_mode_are_explicit\n# def test_document_role_and_entrypoint_reach_the_status_report\n'
        test_mgmt_path.write_text(test_mgmt_with_later_markers)
        unpatched_test_mgmt_sha = package.digest(test_mgmt_path)

        # Dry-run detects unapplied tail-hosting-reader.patch and skips already-applied patches without mutating
        dry_buf = io.StringIO()
        with patch('sys.stdout', dry_buf):
            package.migrate(argparse.Namespace(root=self.tail_root, app=self.app, dry_run=True))
        dry_out = dry_buf.getvalue()
        self.assertIn('with tail-hosting.patch: already applied (skip)', dry_out)
        self.assertIn('with tail-hosting-reader.patch: apply', dry_out)
        self.assertEqual(package.digest(test_mgmt_path), unpatched_test_mgmt_sha)

        # Live migrate applies the unapplied patch and records scripts/test-management.py for restoration
        package.migrate(argparse.Namespace(root=self.tail_root, app=self.app, dry_run=False))
        self.assertIn('def test_reader_compile_state_comes_from_compiler_not_http_success', test_mgmt_path.read_text())
        self.assertNotEqual(package.digest(test_mgmt_path), unpatched_test_mgmt_sha)

        # Restore reverts scripts/test-management.py byte-for-byte
        package.restore_hosting(argparse.Namespace(dry_run=False))
        self.assertEqual(package.digest(test_mgmt_path), unpatched_test_mgmt_sha)
        subprocess.run(
            ['/bin/launchctl', 'bootout', f'gui/{os.getuid()}/{self.reader_plist.stem}'],
            check=False,
        )

        # 2. Simulate real Tail_hosting where all 4 patches (including mobile patch modifying reader patch lines) are already applied
        (self.tail_root / 'AGENTS.md').write_text('# AGENTS\nneeds_preview_selection and context_read_errors\n')
        (self.tail_root / 'docs').mkdir(parents=True, exist_ok=True)
        (self.tail_root / 'docs/architecture.md').write_text('# Architecture\ncompile.observedAt\n')
        self.tail_script.write_text(
            '#!/bin/sh\n'
            '# Flow app lifecycle adapter\n'
            "# if s.get('kind') == 'typst-reader':\n"
            "# if s.get('kind')=='typst-reader' and s.get('managerBinary') and s.get('registration')=='managed':\n"
            '# def read_document_focus(previews):\n'
            '# semanticCanvases observedAt\n'
            f'echo "$@" >> "{self.commands_log}"\n'
        )
        self.tail_script.chmod(0o755)
        test_mgmt_path.write_text(
            '#!/usr/bin/env python3\n'
            'def test_reader_compile_state_comes_from_compiler_not_http_success(self): pass\n'
            'def test_reader_control_delegates_only_to_its_manager(self): pass\n'
            '# 1000+86400*30\n'
            'def test_reader_observation_time_and_native_mode_are_explicit(self): pass\n'
            'def test_document_role_and_entrypoint_reach_the_status_report(self): pass\n'
        )
        already_applied_script_sha = package.digest(self.tail_script)
        already_applied_test_sha = package.digest(test_mgmt_path)

        dry_buf2 = io.StringIO()
        with patch('sys.stdout', dry_buf2):
            package.migrate(argparse.Namespace(root=self.tail_root, app=self.app, dry_run=True))
        dry_out2 = dry_buf2.getvalue()
        for patch_name in (
            'tail-hosting.patch',
            'tail-hosting-reader.patch',
            'tail-hosting-reader-focus.patch',
            'tail-hosting-reader-mobile.patch',
        ):
            self.assertIn(f'with {patch_name}: already applied (skip)', dry_out2)

        package.migrate(argparse.Namespace(root=self.tail_root, app=self.app, dry_run=False))
        self.assertEqual(package.digest(self.tail_script), already_applied_script_sha)
        self.assertEqual(package.digest(test_mgmt_path), already_applied_test_sha)
        package.restore_hosting(argparse.Namespace(dry_run=False))

        # 3. Incompatible file where neither already-applied detection nor forward patch succeeds fails in pre-flight before any mutation
        test_mgmt_path.write_text('#!/usr/bin/env python3\n# completely unrelated file content\n')
        before_services = package.digest(self.services_path)
        before_login = package.digest(self.login_plist)
        before_reader_plist = package.digest(self.reader_plist)
        with self.assertRaisesRegex(ValueError, 'Patch tail-hosting-reader.patch failed pre-flight check for scripts/test-management.py'):
            package.migrate(argparse.Namespace(root=self.tail_root, app=self.app, dry_run=False))
        self.assertFalse((self.target_data / 'profiles.json').exists())
        self.assertEqual(package.digest(self.services_path), before_services)
        self.assertEqual(package.digest(self.login_plist), before_login)
        self.assertEqual(package.digest(self.reader_plist), before_reader_plist)

    def test_reader_launchagent_ownership_transfer_and_restart_after_migration_and_restore(self):
        # Verify that if login_plist did not exist, migrate does not create one
        self.login_plist.unlink()

        # The post-migrate-data plist keeps the legacy label and the tinymist-flow symlink path.
        self.place_legacy_reader_plist(self.legacy_data / 'reader/bin/flow-reader')

        package.migrate(argparse.Namespace(root=self.tail_root, app=self.app, dry_run=False))
        self.assertFalse(self.login_plist.exists())
        self.assertFalse((self.agents_dir / f'{package.APP_ID}.login.plist').exists())

        migrated_launcher = self.target_data / 'reader/bin/flow-reader'
        # Before restart, reader_plist still has the legacy symlinked path, and owns_agent recognizes it across the symlink
        reader_agent_before_restart = package.plistlib.loads(self.reader_plist.read_bytes())
        self.assertEqual(
            reader_agent_before_restart['ProgramArguments'],
            [str(self.legacy_data / 'reader/bin/flow-reader'), '--serve', 'typst-pde-reader'],
        )
        status_after_migrate = json.loads(subprocess.check_output(
            [str(migrated_launcher), '--status', 'typst-pde-reader'], env=self.env, text=True,
        ))
        self.assertTrue(status_after_migrate['managedByApp'])

        # Restarting via flow-reader --control restart updates the LaunchAgent plist to Lagrangian
        restart_res = subprocess.run(
            [str(migrated_launcher), '--control', 'restart', 'typst-pde-reader'],
            env=self.env, text=True, capture_output=True,
        )
        self.assertEqual(restart_res.returncode, 0, restart_res.stderr)
        restarted_agent = package.plistlib.loads(self.reader_plist.read_bytes())
        self.assertEqual(
            restarted_agent['ProgramArguments'],
            [str(self.target_data.resolve() / 'reader/bin/flow-reader'), '--serve', 'typst-pde-reader'],
        )
        self.assertEqual(restarted_agent['AssociatedBundleIdentifiers'], [package.APP_ID])

        # Even if the plist has the symlinked tinymist-flow path, owns_agent accepts it across the compatibility symlink
        symlink_agent = dict(restarted_agent)
        symlink_agent['ProgramArguments'] = [str(self.legacy_data / 'reader/bin/flow-reader'), '--serve', 'typst-pde-reader']
        self.reader_plist.write_bytes(package.plistlib.dumps(symlink_agent))
        restart_via_symlink = subprocess.run(
            [str(migrated_launcher), '--control', 'restart', 'typst-pde-reader'],
            env=self.env, text=True, capture_output=True,
        )
        self.assertEqual(restart_via_symlink.returncode, 0, restart_via_symlink.stderr)

        # If plist points to an unrelated reader executable, flow-reader --control restart refuses ownership
        unrelated_agent = dict(restarted_agent)
        unrelated_agent['ProgramArguments'] = ['/tmp/other-reader/bin/flow-reader', '--serve', 'typst-pde-reader']
        self.reader_plist.write_bytes(package.plistlib.dumps(unrelated_agent))
        rejected = subprocess.run(
            [str(migrated_launcher), '--control', 'restart', 'typst-pde-reader'],
            env=self.env, text=True, capture_output=True,
        )
        self.assertNotEqual(rejected.returncode, 0)
        self.assertIn('The reader will not replace a LaunchAgent it does not own', rejected.stderr)
        self.reader_plist.write_bytes(package.plistlib.dumps(restarted_agent))

        # Restore puts the backed-up plist back and bootstraps it with launchctl.
        # The restored release's owns_agent matches the launcher string exactly, so the symlink path is refused.
        package.restore_hosting(argparse.Namespace(dry_run=False))
        restored_agent = package.plistlib.loads(self.reader_plist.read_bytes())
        self.assertEqual(
            restored_agent['ProgramArguments'],
            [str(self.legacy_data / 'reader/bin/flow-reader'), '--serve', 'typst-pde-reader'],
        )
        self.assertEqual(restored_agent['AssociatedBundleIdentifiers'], ['io.github.kimpossible-ty.tinymist-flow'])
        self.assertIn(f'bootstrap gui/{os.getuid()} {self.reader_plist}', self.launchctl_log.read_text())
        rejected_legacy = subprocess.run(
            [str(self.target_data / 'reader/bin/flow-reader'), '--control', 'restart', 'typst-pde-reader'],
            env=self.env, text=True, capture_output=True,
        )
        self.assertNotEqual(rejected_legacy.returncode, 0)
        self.assertIn('does not own', rejected_legacy.stderr)

    def test_transactional_migration_auto_restores_on_mid_flight_failure(self):
        before = {
            'services': package.digest(self.services_path),
            'script': package.digest(self.tail_script),
            'preview_plist': package.digest(self.preview_plist),
            'reader_plist': package.digest(self.reader_plist),
            'login_plist': package.digest(self.login_plist),
            'reader_config': package.digest(self.legacy_data / 'reader/config.json'),
            'reader_launcher': package.digest(self.legacy_data / 'reader/bin/flow-reader'),
        }
        self.assertFalse((self.target_data / 'profiles.json').exists())

        undo_trace = []
        orig_restore_login = package.restore_background_manager
        orig_restore_reader = package.restore_reader_environment

        def traced_restore_login(*a, **kw):
            undo_trace.append('login')
            return orig_restore_login(*a, **kw)

        def traced_restore_reader(*a, **kw):
            undo_trace.append('reader')
            return orig_restore_reader(*a, **kw)

        # Fail right after profiles.json, reader config/launcher, and login_plist have been mutated
        with patch.object(package, 'restore_background_manager', side_effect=traced_restore_login), \
                patch.object(package, 'restore_reader_environment', side_effect=traced_restore_reader), \
                patch.object(package, 'apply_tail_hosting_patches', side_effect=RuntimeError('simulated mid-migration failure')):
            with self.assertRaisesRegex(RuntimeError, 'simulated mid-migration failure'):
                package.migrate(argparse.Namespace(root=self.tail_root, app=self.app, dry_run=False))

        # Rollback ran completed steps in reverse order (login, then reader) and did not stop/start any services
        self.assertEqual(undo_trace, ['login', 'reader'])
        self.assertFalse(self.commands_log.exists())
        launchctl_calls = self.launchctl_log.read_text() if self.launchctl_log.exists() else ''
        self.assertNotIn('bootout ', launchctl_calls)
        self.assertNotIn('disable ', launchctl_calls)

        after = {
            'services': package.digest(self.services_path),
            'script': package.digest(self.tail_script),
            'preview_plist': package.digest(self.preview_plist),
            'reader_plist': package.digest(self.reader_plist),
            'login_plist': package.digest(self.login_plist),
            'reader_config': package.digest(self.legacy_data / 'reader/config.json'),
            'reader_launcher': package.digest(self.legacy_data / 'reader/bin/flow-reader'),
        }
        self.assertEqual(before, after)
        self.assertEqual(package.digest(self.target_data / 'reader/config.json'), before['reader_config'])
        self.assertEqual(package.digest(self.target_data / 'reader/bin/flow-reader'), before['reader_launcher'])
        self.assertFalse((self.target_data / 'profiles.json').exists())

    def test_failing_undo_still_runs_the_remaining_undos(self):
        calls = []

        def failing_login(*_args, **_kwargs):
            calls.append('login')
            raise RuntimeError('undo login failed')

        def traced_reader(*_args, **_kwargs):
            calls.append('reader')

        with patch.object(package, 'restore_background_manager', side_effect=failing_login), \
                patch.object(package, 'restore_reader_environment', side_effect=traced_reader), \
                patch.object(package, 'apply_tail_hosting_patches', side_effect=RuntimeError('simulated mid-migration failure')):
            with self.assertRaisesRegex(RuntimeError, 'undo login failed') as caught:
                package.migrate(argparse.Namespace(root=self.tail_root, app=self.app, dry_run=False))
        self.assertEqual(calls, ['login', 'reader'])
        self.assertIn('simulated mid-migration failure', str(caught.exception.__cause__))

    def test_subprocess_guard_rejects_real_launchctl_and_lsof_invocations(self):
        with self.assertRaisesRegex(AssertionError, 'Refusing to invoke real system binary'):
            subprocess.Popen(['/bin/launchctl', 'print', 'gui/501/com.example.test'])
        with self.assertRaisesRegex(AssertionError, 'Refusing to invoke real system binary'):
            subprocess.Popen(['/usr/sbin/lsof', '-nP'])
        with patch.dict(os.environ, {'FLOW_DISABLE_SYSTEM_STUB': '1'}):
            with self.assertRaisesRegex(AssertionError, 'Refusing to invoke real system binary'):
                subprocess.run(['/bin/launchctl', 'print', 'gui/501/com.example.test'])
            with self.assertRaisesRegex(AssertionError, 'Refusing to invoke real system binary'):
                subprocess.run(['/usr/sbin/lsof', '-nP'])
            child = subprocess.run(
                [sys.executable, '-c', 'import subprocess; subprocess.run(["/bin/launchctl", "print"])'],
                capture_output=True, text=True,
            )
            self.assertNotEqual(child.returncode, 0)
            self.assertIn('Refusing to invoke real system binary', child.stderr)
        with self.assertRaisesRegex(AssertionError, 'Refusing to target production port or label'):
            subprocess.run(['/usr/sbin/lsof', '-nP', '-iTCP:23627'])
        with self.assertRaisesRegex(AssertionError, 'Refusing to target the real home Library'):
            subprocess.run(['/bin/launchctl', 'print', str(Path(self.real_home) / 'Library/LaunchAgents/com.example.plist')])

if __name__ == '__main__': unittest.main()
