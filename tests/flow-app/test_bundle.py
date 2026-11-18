"""Optional external-engine packaging and real preview delivery in temporary paths."""
import argparse
import base64
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import signal
import shutil
import socket
import struct
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('flow_bundle', ROOT / 'scripts/flow-app.py')
package = importlib.util.module_from_spec(spec); spec.loader.exec_module(package)


def exact(reader, length):
    data = reader.read(length)
    if len(data) != length: raise RuntimeError('Preview WebSocket closed before delivering a frame')
    return data


def document_frame(port, path, origin):
    with socket.create_connection(('127.0.0.1', port), timeout=10) as client:
        key = base64.b64encode(os.urandom(16)).decode()
        request = (f'GET {path} HTTP/1.1\r\nHost: 127.0.0.1:{port}\r\n'
                   f'Upgrade: websocket\r\nConnection: Upgrade\r\n'
                   f'Sec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\nOrigin: {origin}\r\n\r\n')
        client.sendall(request.encode())
        reader = client.makefile('rb')
        if b' 101 ' not in reader.readline(): raise RuntimeError('Preview refused the configured HTTPS origin')
        while True:
            header = reader.readline()
            if header == b'\r\n': break
            if not header: raise RuntimeError('Preview closed during WebSocket handshake')
        payload = b'current'; mask = os.urandom(4)
        client.sendall(bytes([0x81, 0x80 | len(payload)]) + mask + bytes(value ^ mask[i % 4] for i, value in enumerate(payload)))
        deadline = time.monotonic() + 20
        while time.monotonic() < deadline:
            first, second = exact(reader, 2)
            length = second & 0x7f
            if length == 126: length = struct.unpack('!H', exact(reader, 2))[0]
            elif length == 127: length = struct.unpack('!Q', exact(reader, 8))[0]
            if second & 0x80: raise RuntimeError('Unexpected masked server frame')
            data = exact(reader, length)
            if first & 0x0f == 8: raise RuntimeError('Preview WebSocket closed')
            if data.partition(b',')[0] in (b'new', b'diff-v1'): return data
        raise RuntimeError('No compiled document frame received')


# Synthetic receipts exercise the mechanism only; they are never PM acceptance.
receipt_spec = importlib.util.spec_from_file_location('delivery_receipt', ROOT / 'scripts/verify-native-reader-app.py')
receipt_verifier = importlib.util.module_from_spec(receipt_spec); receipt_spec.loader.exec_module(receipt_verifier)


class PMReceiptTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory(prefix='pm-receipt-mechanism-'); self.addCleanup(temp.cleanup)
        self.root = Path(temp.name); self.path = self.root / 'fixture-receipt.json'
        self.source, self.app = 'a' * 40, 'b' * 64
        self.receipt = dict(schemaVersion=1, kind='external-pm-acceptance', decision='accepted',
            recordedBy='SYNTHETIC MECHANISM FIXTURE ONLY', sourceRevision=self.source, bundleChecksum=self.app, gates={})
        for name in receipt_verifier.GATES:
            evidence = dict(gate=name, status='passed', sourceRevision=self.source, bundleChecksum=self.app,
                            requiredSkips=0, tests=1, fixtureOnly=True)
            self.artifact(name, evidence)
        self.write()

    def artifact(self, name, evidence):
        path = self.root / (name + '.json'); path.write_text(json.dumps(evidence))
        self.receipt['gates'][name] = dict(artifact=path.name, sha256=package.digest(path), status='passed')

    def write(self): self.path.write_text(json.dumps(self.receipt))
    def verify(self): return receipt_verifier.acceptance_receipt(self.path, self.source, self.app)

    def test_explicit_synthetic_fixture_records_only_external_decision(self):
        result = self.verify()
        self.assertEqual(set(result['gates']), set(receipt_verifier.GATES))
        self.assertIn('does not authenticate', result['meaning'])
        self.assertEqual(result['recordedBy'], 'SYNTHETIC MECHANISM FIXTURE ONLY')

    def test_source_and_signed_app_replay_reject(self):
        for source, app in [('c'*40, self.app), (self.source, 'd'*64)]:
            with self.subTest(source=source, app=app), self.assertRaises(ValueError):
                receipt_verifier.acceptance_receipt(self.path, source, app)

    def test_missing_receipt_gate_or_artifact_reject(self):
        with self.assertRaises(ValueError): receipt_verifier.acceptance_receipt(None, self.source, self.app)
        saved = self.receipt['gates'].pop('AX'); self.write()
        with self.assertRaises(ValueError): self.verify()
        self.receipt['gates']['AX'] = saved; self.write(); (self.root/'AX.json').unlink()
        with self.assertRaises(OSError): self.verify()

    def test_artifact_tamper_and_path_escape_reject(self):
        artifact=self.root/'source.json'; original=artifact.read_bytes(); artifact.write_bytes(original+b' ')
        with self.assertRaises(ValueError): self.verify()
        artifact.write_bytes(original)
        self.receipt['gates']['source']['artifact']='../outside.json'; self.write()
        with self.assertRaises(ValueError): self.verify()
        self.receipt['gates']['source']['artifact']='escape.json'; (self.root/'escape.json').symlink_to('/etc/hosts'); self.write()
        with self.assertRaises(ValueError): self.verify()

    def test_failed_pending_stale_and_required_skip_artifacts_reject(self):
        original=json.loads((self.root/'requiredtests.json').read_text())
        for changes in [{'status':'failed'}, {'status':'pending'}, {'requiredSkips':1}, {'requiredSkips':False},
                        {'sourceRevision':'0'*40}, {'bundleChecksum':'0'*64}, {'tests':0}, {'gate':'AX'}]:
            with self.subTest(changes=changes):
                self.artifact('requiredtests', {**original, **changes}); self.write()
                with self.assertRaises(ValueError): self.verify()

    def test_unaccepted_decision_and_gate_status_reject(self):
        self.receipt['decision']='pending'; self.write()
        with self.assertRaises(ValueError): self.verify()
        self.receipt['decision']='accepted'; self.receipt['gates']['nativeGUI']['status']='failed'; self.write()
        with self.assertRaises(ValueError): self.verify()


class DevelopmentBundleIdentityTests(unittest.TestCase):
    def test_default_and_explicit_namespace(self):
        self.assertEqual(package.bundle_identifier(), package.APP_ID)
        self.assertEqual(package.bundle_identifier(package.APP_ID), package.APP_ID)
        identifier = package.APP_ID + '.development.native-cream-na20'
        self.assertEqual(package.bundle_identifier(identifier), identifier)
        for value in ['', 'other.app', package.APP_ID + '.development', package.APP_ID + '.development.',
                      package.APP_ID + '.development.NA20', package.APP_ID + '.development.na20.extra',
                      package.APP_ID + '.development.na20/escape', package.APP_ID + 'evil.development.na20']:
            with self.subTest(value=value), self.assertRaises(ValueError): package.bundle_identifier(value)

    def test_plist_and_manifest_identity_must_match_before_execution(self):
        import plistlib
        with tempfile.TemporaryDirectory() as tmp:
            app = Path(tmp)/'Lagrangian.app'; resources = app/'Contents/Resources'; resources.mkdir(parents=True)
            identifier = package.APP_ID + '.development.native-cream-na20'
            (app/'Contents/Info.plist').write_bytes(plistlib.dumps(dict(CFBundleIdentifier=identifier, CFBundleExecutable=package.APP_EXECUTABLE)))
            manifest = dict(bundleIdentifier=package.APP_ID, signing='ad-hoc')
            (resources/'release.json').write_text(json.dumps(manifest))
            with patch.object(package, 'run'), patch.object(package, 'capture') as execute:
                with self.assertRaisesRegex(ValueError, 'identity/signing'): package.validate(app, allow_development=True)
                execute.assert_not_called()
            for signing in ['certificate', None]:
                manifest.update(bundleIdentifier=identifier, signing=signing)
                (resources/'release.json').write_text(json.dumps(manifest))
                with patch.object(package, 'run'), self.assertRaisesRegex(ValueError, 'identity/signing'): package.validate(app, allow_development=True)
            manifest.update(bundleIdentifier=identifier, signing='ad-hoc')
            (resources/'release.json').write_text(json.dumps(manifest))
            with patch.object(package, 'run'), patch.object(package.subprocess, 'run', return_value=argparse.Namespace(stderr='Identifier=unrelated.bundle\n')), patch.object(package, 'capture') as execute:
                with self.assertRaisesRegex(ValueError, 'Signed bundle identifier'): package.validate(app, allow_development=True)
                execute.assert_not_called()


class ProductionDevelopmentBoundaryTests(unittest.TestCase):
    """Real validation/call edges, fake bundles and injected mutation callbacks only."""
    def setUp(self):
        import plistlib
        from contextlib import ExitStack
        self.stack = ExitStack(); self.addCleanup(self.stack.close)
        self.root = Path(self.stack.enter_context(tempfile.TemporaryDirectory(prefix='dev-boundary-')))
        self.app = self.root/'Lagrangian.app'; resources = self.app/'Contents/Resources'; resources.mkdir(parents=True)
        self.identifier = package.APP_ID + '.development.native-cream-na20'
        (self.app/'Contents/Info.plist').write_bytes(plistlib.dumps(dict(CFBundleIdentifier=self.identifier, CFBundleExecutable=package.APP_EXECUTABLE)))
        self.manifest = dict(bundleIdentifier=self.identifier, signing='ad-hoc', version='0.1.0', engineSHA256='0'*64)
        (resources/'release.json').write_text(json.dumps(self.manifest))
        self.run = self.stack.enter_context(patch.object(package, 'run'))
        self.stack.enter_context(patch.object(package, 'capture', return_value='Lagrangian 0.1.0'))
        self.stack.enter_context(patch.object(package, 'digest', return_value='0'*64))
        self.stack.enter_context(patch.object(package.subprocess, 'run', return_value=argparse.Namespace(stderr='Identifier='+self.identifier+'\n', returncode=0)))

    def test_production_default_rejects_development_before_binary_execution(self):
        with self.assertRaisesRegex(ValueError, 'Development bundle'): package.validate(self.app)
        self.assertFalse(any('--version' in list(map(str,c.args[0])) for c in self.run.call_args_list))

    def test_explicit_development_verification_is_separate(self):
        self.assertEqual(package.validate(self.app, allow_development=True), self.manifest)

    def test_replacement_rejects_before_migration_lock_or_mutation(self):
        data = self.root/'must-not-be-created'
        with patch.object(package, 'DATA', data), patch.object(package, '_replace_app') as mutation:
            with self.assertRaisesRegex(ValueError, 'Development bundle'):
                package.replace_app(self.app, self.root/'destination/Lagrangian.app')
            mutation.assert_not_called()
        self.assertFalse(data.exists())
        self.assertFalse(any('--migrate-data' in list(map(str,c.args[0])) for c in self.run.call_args_list))

    def test_explicit_data_replacement_rejects_before_lock_creation(self):
        data = self.root/'explicit-must-not-exist'
        with patch.object(package, '_replace_app') as mutation:
            with self.assertRaisesRegex(ValueError, 'Development bundle'):
                package.replace_app(self.app, self.root/'destination/Lagrangian.app', data_dir=data)
            mutation.assert_not_called()
        self.assertFalse(data.exists())

    def test_migration_rejects_before_registry_or_preflight(self):
        with patch.object(package, 'check_data_migration_preflight') as mutation:
            with self.assertRaisesRegex(ValueError, 'Development bundle'):
                package.migrate(argparse.Namespace(root=self.root/'absent-registry', app=self.app, dry_run=False))
            mutation.assert_not_called()

    def test_production_identity_contract_remains_default(self):
        import plistlib
        info = self.app/'Contents/Info.plist'
        info.write_bytes(plistlib.dumps(dict(CFBundleIdentifier=package.APP_ID, CFBundleExecutable=package.APP_EXECUTABLE)))
        self.manifest.pop('bundleIdentifier')
        (self.app/'Contents/Resources/release.json').write_text(json.dumps(self.manifest))
        with patch.object(package.subprocess, 'run', return_value=argparse.Namespace(stderr='Identifier='+package.APP_ID+'\n', returncode=0)):
            self.assertEqual(package.validate(self.app), self.manifest)


@unittest.skipUnless(sys.platform == 'darwin' and os.environ.get('FLOW_TEST_DEVELOPMENT_APP') and os.environ.get('FLOW_TEST_ENGINE'), 'Set explicit isolated development app and engine for packaging checks')
class DevelopmentBundleIntegrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = Path(os.environ['FLOW_TEST_DEVELOPMENT_APP']).resolve(strict=True)
        cls.engine = Path(os.environ['FLOW_TEST_ENGINE']).resolve(strict=True)
        cls.temp = tempfile.TemporaryDirectory(prefix='development-package-'); cls.addClassCleanup(cls.temp.cleanup)
        cls.root = Path(cls.temp.name).resolve()

    def test_signed_current_source_and_retained_inputs(self):
        manifest = package.validate(self.app, allow_development=True)
        self.assertEqual(manifest['sourceRevision'], package.capture(['git', '-C', ROOT, 'rev-parse', 'HEAD']))
        self.assertFalse(manifest['sourceDirty'])
        self.assertFalse(manifest['managementOnly'])
        self.assertNotEqual(manifest['bundleIdentifier'], package.APP_ID)
        self.assertEqual(manifest['signing'], 'ad-hoc')
        self.assertEqual(manifest['engineInputSHA256'], package.digest(self.engine))
        self.assertEqual(manifest['appBuild']['target'], 'arm64-apple-macosx13.0')
        self.assertIn('-swift-version', manifest['appBuild']['compilerArgv'])
        self.assertIn('-warnings-as-errors', manifest['appBuild']['compilerArgv'])
        for name, digest in manifest['appBuild']['sourceSHA256'].items(): self.assertEqual(package.digest(ROOT/name), digest)
        for name in ['NativeAppDesign.swift', 'NativeBrandMark.swift', 'NativeFloatingCapsule.swift']:
            self.assertEqual(manifest['appBuild']['compilerArgv'].count(str(ROOT/'apps/macos'/name)), 1)
        self.assertEqual(package.bundle_checksum(self.app), json.loads((self.app.parent/'release.json').read_text())['bundleChecksum'])
        with self.assertRaisesRegex(ValueError, 'Development bundle'): package.validate(self.app)

    def test_packaged_cli_uses_only_supported_isolated_data(self):
        isolated = self.root/'cli'
        argv = [str(package.executable(self.app)), '--dev-root', str(isolated)]
        result = subprocess.run([*argv, '--check-config'], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        result = subprocess.run([*argv, '--profiles'], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout), dict(schemaVersion=1, selectedID='', profiles=[]))
        self.assertFalse((isolated/'home/Library/LaunchAgents').exists())

    def test_bundled_standalone_manager_without_service_operations(self):
        delivery = self.app/'Contents/Resources/native-reader'
        env = dict(os.environ, HOME=str(self.root/'manager-home'), FLOW_READER_DATA_DIR=str(self.root/'reader-data'))
        result = subprocess.run([str(delivery/'reader-manager'), '--profiles'], env=env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout+result.stderr)
        self.assertEqual(json.loads(result.stdout), dict(schemaVersion=1, profiles=[]))
        self.assertFalse((self.root/'reader-data').exists())
        self.assertFalse((self.root/'manager-home/Library/LaunchAgents').exists())


@unittest.skipUnless(sys.platform == 'darwin' and os.environ.get('FLOW_TEST_ENGINE'), 'Set FLOW_TEST_ENGINE on macOS for integration checks')
class ExternalEngineBundle(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # The external engine treats /var and /private/var as different project roots.
        temp = tempfile.TemporaryDirectory(prefix='.flow-bundle-tests-'); cls.addClassCleanup(temp.cleanup)
        cls.root = Path(temp.name).resolve()
        cls.app = Path(os.environ['FLOW_TEST_APP']).resolve() if os.environ.get('FLOW_TEST_APP') else cls.root / 'built/Lagrangian.app'
        cls.engine = Path(os.environ['FLOW_TEST_ENGINE']).expanduser().resolve()
        cls.input_hash = package.digest(cls.engine)
        cls.env = {'FLOW_DEV_ROOT': str(cls.root),
                   'FLOW_DATA_DIR': str(cls.root / 'home/Library/Application Support/Lagrangian'),
                   'FLOW_LOG_DIR': str(cls.root / 'home/Library/Logs/Lagrangian')}
        cls.data = Path(cls.env['FLOW_DATA_DIR'])
        if os.environ.get('FLOW_TEST_APP'):
            package.validate(cls.app)
            return
        with patch.dict(os.environ, cls.env):
            package.build(argparse.Namespace(engine=cls.engine, output=cls.app, version='0.1.0', management_only=True, identity=os.environ.get('FLOW_TEST_SIGN_IDENTITY', '-')))

    def test_provenance_signature_and_isolated_copy(self):
        with patch.dict(os.environ, self.env):
            manifest = package.validate(self.app)
            self.assertEqual(manifest['engineSource'], 'external')
            self.assertIn('-warnings-as-errors', manifest['appBuild']['compilerArgv'])
            self.assertIn('arm64-apple-macosx13.0' if package.platform.machine() == 'arm64' else 'x86_64-apple-macosx13.0', manifest['appBuild']['compilerArgv'])
            self.assertEqual(manifest['appBuild']['environment']['TMPDIR'], os.environ['TMPDIR'])
            for relative, expected in manifest['appBuild']['sourceSHA256'].items():
                self.assertEqual(package.digest(ROOT / relative), expected)
            self.assertEqual(package.bundle_checksum(self.app), json.loads((self.app.parent / 'release.json').read_text())['bundleChecksum'])
            self.assertEqual(manifest['engineInputSHA256'], self.input_hash)
            self.assertEqual(manifest['engineVersion'], package.capture([self.engine, '--version']))
            destination = self.root / 'installed/Lagrangian.app'
            # Check relocated signed bytes without installer or service calls.
            shutil.copytree(self.app, destination, symlinks=True)
            self.assertEqual(package.bundle_checksum(destination), package.bundle_checksum(self.app))
            self.assertEqual(package.validate(destination)['engineSHA256'], manifest['engineSHA256'])
        self.assertEqual(package.digest(self.engine), self.input_hash)

    def test_dev_root_isolates_migration_and_cli_without_live_launchctl(self):
        isolated = self.root / 'cli-isolated'
        home = isolated / 'home'
        legacy = home / 'Library/Application Support/tinymist-flow'
        legacy.mkdir(parents=True)
        settings = {'schemaVersion': 1, 'selectedID': '', 'profiles': []}
        (legacy / 'profiles.json').write_text(json.dumps(settings))
        argv = [package.executable(self.app), '--dev-root', str(isolated)]
        result = subprocess.run([*argv, '--migrate-data'], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        destination = home / 'Library/Application Support/Lagrangian/profiles.json'
        self.assertEqual(json.loads(destination.read_text()), settings)
        self.assertTrue(legacy.is_symlink())
        result = subprocess.run([*argv, '--profiles'], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout), settings)
        for operation in (['--control', 'stop', 'fixture'], ['--login', 'off'], ['--status', 'fixture'], ['--background']):
            result = subprocess.run([*argv, *operation], capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('disabled with a dev root', result.stderr)
        self.assertFalse((home / 'Library/LaunchAgents').exists())

    def test_native_delivery_verifier_keeps_unfinished_runtime_gate_nonzero(self):
        report = self.root / 'native-delivery.json'
        result = subprocess.run([sys.executable, ROOT / 'scripts/verify-native-reader-app.py', self.app,
                                 '--output', report], capture_output=True, text=True)
        expected = 0 if package.validate(self.app).get('nativeDeliverySHA256') else 2
        self.assertEqual(result.returncode, expected, result.stdout + result.stderr)
        status = json.loads(report.read_text())
        self.assertEqual(status['integrity'], 'verified')
        self.assertEqual(status['status'], 'delivery-integrity-verified' if expected == 0 else 'runtime-delivery-blocked')
        self.assertEqual(status['exit'], expected)
        if expected == 0:
            result = subprocess.run([sys.executable, ROOT / 'scripts/verify-native-reader-app.py', self.app, '--acceptance'], capture_output=True, text=True)
            self.assertEqual(result.returncode, 2, result.stdout + result.stderr)

    def test_preview_delivers_both_themes_through_configured_origin(self):
        project = self.root / 'project'; project.mkdir()
        (project / 'main.typ').write_text('#let dark = sys.inputs.at("theme", default: "light") == "dark"\n'
                                        '#set page(width: 10cm, height: 10cm, fill: if dark { black } else { white })\n'
                                        '#set text(fill: if dark { white } else { black })\nFlow integration fixture\n')
        with socket.socket() as reservation:
            reservation.bind(('127.0.0.1', 0)); port = reservation.getsockname()[1]
        data = self.data; data.mkdir(parents=True, exist_ok=True)
        origin = 'https://preview.example'
        profile = {'id': 'fixture', 'name': 'Fixture', 'root': str(project), 'entry': 'main.typ', 'fonts': [],
                   'packages': '', 'port': port, 'publicURL': origin, 'label': 'com.example.flow.fixture'}
        (data / 'profiles.json').write_text(json.dumps({'schemaVersion': 1, 'selectedID': 'fixture', 'profiles': [profile]}))
        with (self.root / 'preview.log').open('w+') as log:
            child = subprocess.Popen([package.executable(self.app), '--serve', 'fixture'], env=dict(os.environ, **self.env),
                                     stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
            try:
                deadline = time.monotonic() + 30
                while time.monotonic() < deadline:
                    if child.poll() is not None:
                        log.seek(0); self.fail('Preview exited: ' + log.read()[-4000:])
                    try:
                        with urllib.request.urlopen(f'http://127.0.0.1:{port}/', timeout=1) as response:
                            html = response.read()
                        break
                    except OSError: time.sleep(.1)
                else: self.fail('Preview did not start')
                self.assertIn(b'preview-arg:systemTheme:true', html)
                light = document_frame(port, '/_theme/light', origin)
                dark = document_frame(port, '/_theme/dark', origin)
                self.assertNotEqual(hashlib.sha256(light).digest(), hashlib.sha256(dark).digest())
            finally:
                if child.poll() is None: os.killpg(child.pid, signal.SIGTERM)
                try: child.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    os.killpg(child.pid, signal.SIGKILL); child.wait()

    @unittest.skipUnless(os.environ.get('FLOW_TEST_SIGN_IDENTITY'), 'Set FLOW_TEST_SIGN_IDENTITY for persistent-certificate checks')
    def test_changed_bundle_reuses_saved_identity_and_designated_requirements(self):
        identity = os.environ['FLOW_TEST_SIGN_IDENTITY']
        changed = self.root / 'updated/Lagrangian.app'
        with patch.object(package, 'DATA', self.root / 'signing-data'), patch.dict(os.environ, FLOW_SIGN_IDENTITY=''):
            package.configure_signing(argparse.Namespace(identity=identity))
            configured_identity = package.resolve_signing_identity()
            package.build(argparse.Namespace(engine=self.engine, output=changed, version='0.1.1', management_only=True, identity=None))
        manifest = package.validate(changed)
        self.assertEqual(manifest['signing'], configured_identity)
        self.assertEqual(manifest['signingCertificateSHA256'], package.validate(self.app)['signingCertificateSHA256'])
        self.assertNotEqual(package.digest(package.executable(self.app)), package.digest(package.executable(changed)))
        for old, new in ((self.app, changed), (self.app / 'Contents/MacOS/flow-engine', changed / 'Contents/MacOS/flow-engine')):
            output = subprocess.check_output(['/usr/bin/codesign', '-d', '-r-', old], stderr=subprocess.STDOUT, text=True)
            requirement = output.split('designated => ', 1)[1].strip()
            self.assertNotIn('cdhash', requirement)
            subprocess.run(['/usr/bin/codesign', '--verify', '--strict', '-R', '=' + requirement, new], check=True, capture_output=True)
            output = subprocess.check_output(['/usr/bin/codesign', '-d', '-r-', new], stderr=subprocess.STDOUT, text=True)
            self.assertEqual(output.split('designated => ', 1)[1].strip(), requirement)


if __name__ == '__main__': unittest.main()
