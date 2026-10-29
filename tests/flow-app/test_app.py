"""Configuration contract and failed-update recovery, without touching live jobs."""
import argparse
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('flow_package', ROOT / 'scripts/flow-app.py')
package = importlib.util.module_from_spec(spec); spec.loader.exec_module(package)

class Profiles(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if sys.platform != 'darwin': raise unittest.SkipTest('Native app tests require macOS')
        temp = tempfile.TemporaryDirectory(prefix='flow-app-tests-'); cls.addClassCleanup(temp.cleanup)
        cls.app = Path(temp.name) / 'Lagrangian'
        subprocess.run(['/usr/bin/swiftc', '-swift-version', '5', '-warnings-as-errors',
                        *package.swift_sources(), '-o', cls.app], check=True)
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.env = dict(os.environ, FLOW_DATA_DIR=str(self.root / 'data'), FLOW_LOG_DIR=str(self.root / 'logs'))
        self.profile = {'id': 'test', 'name': 'A project with spaces', 'root': str(self.root / 'project with spaces'),
                        'entry': 'main.typ', 'fonts': ['fonts'], 'packages': '', 'port': 24650,
                        'publicURL': 'https://example.ts.net:24650/', 'label': 'com.example.flow.test'}
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
        self.assertEqual(plan['environment']['TINYMIST_ALLOWED_ORIGINS'], 'https://example.ts.net:24650')
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

if __name__ == '__main__': unittest.main()
