"""Engine-input hash and retained-artifact selection. These tests do not compile Rust.

A comment-only edit of this file is outside the engine-input hash, so a later
flow-engine run can republish the previous artifact without running Cargo.
"""

import importlib.util
import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


hashing = load('engine_input_hash', ROOT / 'scripts/engine-input-hash.py')
reuse = load('reuse_engine_artifact', ROOT / 'scripts/reuse-engine-artifact.py')


def write(path: Path, text: str):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)


class EngineInputHashTests(unittest.TestCase):
    def setUp(self):
        import tempfile
        self.directory = tempfile.TemporaryDirectory()
        self.root = Path(self.directory.name)
        write(self.root / 'crates/demo/src/lib.rs', 'fn demo() {}\n')
        write(self.root / 'crates/demo/Cargo.toml', '[package]\nname = "demo"\n')
        write(self.root / 'Cargo.lock', '# lock\n')
        write(self.root / 'rust-toolchain.toml', 'channel = "1.92"\n')
        write(self.root / 'scripts/flow-app.py', 'print("build")\n')
        write(self.root / 'scripts/stage-tinymist-assets.mjs', 'export {}\n')
        write(self.root / 'scripts/build.mjs', 'export {}\n')
        write(self.root / 'scripts/builders.mjs', 'export {}\n')
        write(self.root / 'package.json', '{}\n')
        write(self.root / 'yarn.lock', '# yarn\n')
        write(self.root / 'locales/tinymist-rt.toml', 'key = "value"\n')
        write(self.root / 'tools/typst-preview-frontend/src/main.ts', 'export const preview = 1\n')
        write(self.root / 'vendor/typst/library/hello.typ', '= Hello\n')
        write(self.root / 'docs/guide.md', '# Guide\n')
        write(self.root / 'openspec/changes/demo/spec.md', '# Spec\n')
        write(self.root / 'README.md', '# Readme\n')

    def tearDown(self):
        self.directory.cleanup()

    def digest(self, system='Darwin', machine='arm64'):
        return hashing.digest(self.root, system, machine)[0]

    def test_digest_is_stable_and_covers_runner_identity(self):
        first = self.digest()
        second = self.digest()
        self.assertEqual(first, second)
        self.assertEqual(len(first), 64)
        self.assertNotEqual(first, self.digest(machine='x86_64'))
        self.assertNotEqual(first, self.digest(system='Linux'))

    def test_engine_inputs_change_the_digest(self):
        original = self.digest()
        write(self.root / 'crates/demo/src/lib.rs', 'fn demo() { let _ = 1; }\n')
        self.assertNotEqual(original, self.digest())
        write(self.root / 'crates/demo/src/lib.rs', 'fn demo() {}\n')
        write(self.root / 'Cargo.lock', '# lock changed\n')
        self.assertNotEqual(original, self.digest())
        write(self.root / 'Cargo.lock', '# lock\n')
        write(self.root / 'vendor/typst/library/hello.typ', '= Goodbye\n')
        self.assertNotEqual(original, self.digest())
        write(self.root / 'vendor/typst/library/hello.typ', '= Hello\n')
        write(self.root / 'tools/typst-preview-frontend/src/main.ts', 'export const preview = 2\n')
        self.assertNotEqual(original, self.digest())
        write(self.root / 'tools/typst-preview-frontend/src/main.ts', 'export const preview = 1\n')
        write(self.root / 'scripts/flow-app.py', 'print("rebuild")\n')
        self.assertNotEqual(original, self.digest())

    def test_docs_markdown_tests_and_generated_assets_do_not_change_the_digest(self):
        original = self.digest()
        write(self.root / 'docs/guide.md', '# Edited\n')
        write(self.root / 'docs/extra.typ', '= Extra\n')
        write(self.root / 'openspec/changes/demo/spec.md', '# Edited\n')
        write(self.root / 'README.md', '# Edited\n')
        write(self.root / 'crates/demo/README.md', '# Crate\n')
        write(self.root / 'tools/typst-preview-frontend/src/main.test.ts', 'throw new Error("no")\n')
        write(self.root / 'tools/reader-common/tests/policy.mjs', 'export {}\n')
        write(self.root / 'apps/macos/main.swift', 'print("swift")\n')
        write(self.root / 'crates/tinymist-assets/src/typst-preview.html', '<p>generated</p>\n')
        write(self.root / 'crates/tinymist-assets/src/tinymist-rt.toml', 'generated = true\n')
        self.assertEqual(original, self.digest())

    def test_workflow_keeps_the_fetch_engine_artifact_name(self):
        workflow = (ROOT / '.github/workflows/flow-engine.yml').read_text()
        self.assertIn('name: flow-engine-darwin-arm64', workflow)
        self.assertIn('paths-ignore:', workflow)
        self.assertIn('docs/**', workflow)
        self.assertIn('openspec/**', workflow)
        self.assertNotIn('name: flow-engine-darwin-arm64-', workflow)
        package = (ROOT / 'scripts/flow-app.py').read_text()
        self.assertIn("ENGINE_ARTIFACT = 'flow-engine-darwin-arm64'", package)


class ReuseSelectionTests(unittest.TestCase):
    def artifacts(self, mapping):
        def artifacts_for(run_id):
            return mapping[run_id]
        return artifacts_for

    def test_selects_the_newest_retained_match_and_skips_the_current_run(self):
        digest = 'a' * 64
        marker = reuse.marker_name(digest)
        runs = [
            {'databaseId': 1, 'createdAt': '2026-10-01T00:00:00Z', 'conclusion': 'success', 'url': 'https://example.test/1'},
            {'databaseId': 2, 'createdAt': '2026-10-02T00:00:00Z', 'conclusion': 'success', 'url': 'https://example.test/2'},
            {'databaseId': 3, 'createdAt': '2026-10-03T00:00:00Z', 'conclusion': 'success', 'url': 'https://example.test/3'},
        ]
        mapping = {
            '1': {marker: False, reuse.ENGINE_ARTIFACT: False},
            '2': {marker: False, reuse.ENGINE_ARTIFACT: False},
            '3': {marker: False, reuse.ENGINE_ARTIFACT: False},
        }
        selected = reuse.select_source_run(runs, digest, self.artifacts(mapping), current_run_id='3')
        self.assertEqual(selected['databaseId'], 2)

    def test_skips_expired_artifacts_and_different_hashes(self):
        digest = 'b' * 64
        marker = reuse.marker_name(digest)
        runs = [
            {'databaseId': 4, 'createdAt': '2026-10-04T00:00:00Z', 'conclusion': 'success'},
            {'databaseId': 5, 'createdAt': '2026-10-05T00:00:00Z', 'conclusion': 'success'},
        ]
        mapping = {
            '4': {marker: False, reuse.ENGINE_ARTIFACT: False},
            '5': {marker: True, reuse.ENGINE_ARTIFACT: False, reuse.marker_name('c' * 64): False},
        }
        selected = reuse.select_source_run(runs, digest, self.artifacts(mapping))
        self.assertEqual(selected['databaseId'], 4)
        self.assertIsNone(reuse.select_source_run(runs, 'd' * 64, self.artifacts(mapping)))

    def test_verify_payload_accepts_the_fetch_engine_layout(self):
        import tempfile
        with tempfile.TemporaryDirectory() as directory:
            payload = Path(directory)
            engine = payload / 'flow-engine'
            engine.write_bytes(b'engine-bytes')
            digest = __import__('hashlib').sha256(b'engine-bytes').hexdigest()
            (payload / 'flow-engine.sha256').write_text(digest + '  flow-engine\n')
            (payload / 'release.json').write_text(json.dumps({
                'engineInputSHA256': digest,
                'engineBuild': {'target': 'aarch64-apple-darwin', 'profile': 'flow-release'},
            }))
            (payload / 'Lagrangian.app').mkdir()
            self.assertEqual(reuse.verify_payload(payload), digest)
            (payload / 'flow-engine.sha256').write_text(('e' * 64) + '  flow-engine\n')
            with self.assertRaises(ValueError):
                reuse.verify_payload(payload)


if __name__ == '__main__':
    unittest.main()

class FreshApplicationCacheBoundaryTests(unittest.TestCase):
    """Execute production reuse/build boundaries with tiny platform-tool fixtures.

    This is a local cache simulation. Swift/codesign and Cargo are not executed.
    The actual signed .app is exercised by the required installed-layout suite.
    """
    def test_workflow_builds_current_app_after_both_engine_paths(self):
        workflow = (ROOT / '.github/workflows/flow-engine.yml').read_text()
        names = ['Prepare portable native dependencies', 'Stage current backend and runtime on hit and miss',
                 'Build current native app on hit and miss', 'Stage the engine artifact']
        for name in names:
            block = workflow.split('- name: ' + name, 1)[1].split('\n      - ', 1)[0]
            self.assertNotIn('if: steps.engine_cache', block)
        self.assertIn('build-engine-input --jobs', workflow)
        self.assertNotIn('build --build-engine', workflow)
        self.assertIn('--engine dist/engine-input/flow-engine', workflow)
        upload=workflow.split('- name: Upload Apple Silicon flow engine',1)[1].split('- name: Upload engine input hash',1)[0]
        self.assertIn('native-delivery-artifact.tar',upload)
        self.assertIn('native-delivery-artifact.json',upload)
        self.assertIn('compression-level: 0',upload)

    def test_cache_hit_discards_previous_app_and_rejects_corrupt_engine(self):
        import hashlib
        import shutil
        import tempfile
        from unittest.mock import patch
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve(); cached = root / 'cached'; cached.mkdir()
            engine = b'same-engine'
            (cached / 'flow-engine').write_bytes(engine)
            checksum = hashlib.sha256(engine).hexdigest()
            (cached / 'flow-engine.sha256').write_text(checksum)
            (cached / 'release.json').write_text(json.dumps({'engineInputSHA256':checksum,
                'engineBuild':{'target':reuse.ENGINE_TARGET, 'profile':reuse.ENGINE_PROFILE}}))
            write(cached / 'Lagrangian.app/Contents/MacOS/Lagrangian', 'stale cached application')
            def gh(args, repo_cwd=None):
                shutil.copytree(cached, Path(args[-1])); return ''
            destination = root / 'engine-input'
            with patch.object(reuse, '_gh', gh):
                self.assertEqual(reuse.download_payload('fixture/repo', '1', destination), checksum)
                self.assertEqual(sorted(p.name for p in destination.iterdir()), ['flow-engine','flow-engine.sha256','release.json'])
                (cached / 'flow-engine').write_bytes(b'corrupt')
                with self.assertRaises(ValueError):
                    reuse.download_payload('fixture/repo','2',destination)
                self.assertEqual((destination / 'flow-engine').read_bytes(), engine)

    def test_archived_cache_hit_reuses_only_engine_and_rejects_raw_tamper(self):
        import hashlib, shutil, tempfile
        from unittest.mock import patch
        import native_delivery_artifact as transport
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory).resolve();payload=root/'payload';payload.mkdir()
            data=b'previous-engine';digest=hashlib.sha256(data).hexdigest()
            (payload/'flow-engine').write_bytes(data)
            (payload/'flow-engine.sha256').write_text(digest)
            (payload/'release.json').write_text(json.dumps({'engineInputSHA256':digest,'engineBuild':{'target':reuse.ENGINE_TARGET,'profile':reuse.ENGINE_PROFILE}}))
            write(payload/'Lagrangian.app/Contents/MacOS/Lagrangian','old app is never reused')
            wrapper=root/'archive';transport.pack(payload,wrapper,repository='fixture/repo',run_id='1',head='a'*40)
            def gh(args,repo_cwd=None):shutil.copytree(wrapper,Path(args[-1]));return ''
            dest=root/'engine-input'
            with patch.object(reuse,'_gh',gh):
                self.assertEqual(reuse.download_payload('fixture/repo','1',dest,head='a'*40),digest)
                self.assertEqual({p.name for p in dest.iterdir()},{'flow-engine','flow-engine.sha256','release.json'})
                self.assertEqual((dest/'flow-engine').stat().st_mode&0o777,0o755)
                with self.assertRaises(ValueError):reuse.download_payload('fixture/repo','1',dest,head='b'*40)
                self.assertEqual((dest/'flow-engine').read_bytes(),data)
                with (wrapper/transport.ARCHIVE).open('ab') as stream:stream.write(b'tamper')
                with self.assertRaises(ValueError):reuse.download_payload('fixture/repo','1',dest)
                self.assertEqual((dest/'flow-engine').read_bytes(),data)

    def test_relative_dest_lands_at_absolute_path_and_symlink_dest_is_rejected(self):
        import hashlib
        import os
        import shutil
        import tempfile
        from unittest.mock import patch
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            cached = root / 'cached'
            cached.mkdir()
            engine = b'relative-dest-engine'
            (cached / 'flow-engine').write_bytes(engine)
            checksum = hashlib.sha256(engine).hexdigest()
            (cached / 'flow-engine.sha256').write_text(checksum)
            (cached / 'release.json').write_text(json.dumps({'engineInputSHA256': checksum,
                'engineBuild': {'target': reuse.ENGINE_TARGET, 'profile': reuse.ENGINE_PROFILE}}))
            write(cached / 'Lagrangian.app/Contents/MacOS/Lagrangian', 'stale cached application')
            def gh(args, repo_cwd=None):
                shutil.copytree(cached, Path(args[-1]))
                return ''
            previous = os.getcwd()
            os.chdir(root)
            try:
                destination = Path('dist/engine-input')
                with patch.object(reuse, '_gh', gh):
                    self.assertEqual(reuse.download_payload('fixture/repo', '1', destination), checksum)
                    landed = destination.absolute()
                    self.assertEqual(landed, root / 'dist/engine-input')
                    self.assertFalse(landed.is_symlink())
                    self.assertEqual(sorted(p.name for p in landed.iterdir()), ['flow-engine', 'flow-engine.sha256', 'release.json'])
                    self.assertEqual((landed / 'flow-engine').read_bytes(), engine)
                    real = root / 'elsewhere'
                    real.mkdir()
                    link = Path('dist/engine-link')
                    link.symlink_to(real)
                    with self.assertRaises(ValueError) as caught:
                        reuse.download_payload('fixture/repo', '1', link)
                    self.assertEqual(str(caught.exception), 'output path/symlink')
                    self.assertTrue(link.is_symlink())
                    self.assertEqual(list(real.iterdir()), [])
                    self.assertEqual((landed / 'flow-engine').read_bytes(), engine)
            finally:
                os.chdir(previous)

    def test_main_absolutizes_relative_engine_artifact_dir(self):
        import io
        import os
        import tempfile
        from contextlib import redirect_stderr
        from unittest.mock import patch
        digest = 'a' * 64
        match = {'databaseId': 9, 'headSha': 'b' * 40, 'url': 'https://example.test/9'}
        received = []

        def download_payload(repo, run_id, dest, *, head=None):
            received.append(dest)
            return digest

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            previous = os.getcwd()
            os.chdir(root)
            try:
                env = {
                    'GITHUB_REPOSITORY': 'fixture/repo',
                    'ENGINE_INPUT_HASH': digest,
                    'ENGINE_REUSE_BRANCHES': 'main',
                    'ENGINE_ARTIFACT_DIR': 'dist/engine-input',
                }
                with patch.dict(os.environ, env), \
                        patch.object(reuse, 'list_successful_runs', return_value=[match]), \
                        patch.object(reuse, 'select_source_run', return_value=match), \
                        patch.object(reuse, 'download_payload', side_effect=download_payload), \
                        patch.object(reuse, 'set_output'), \
                        patch.object(reuse, 'summarize'), \
                        redirect_stderr(io.StringIO()):
                    reuse.main()
                self.assertEqual(len(received), 1)
                dest = received[0]
                expected = (root / 'dist/engine-input').absolute()
                self.assertTrue(dest.is_absolute())
                self.assertEqual(dest, expected)
                self.assertEqual(dest, Path('dist/engine-input').absolute())
            finally:
                os.chdir(previous)

    def test_publish_verified_accepts_relative_output_and_rejects_symlink(self):
        import os
        import tempfile
        delivery = load('publish_verified_relative', ROOT / 'scripts/stage-native-reader-delivery.py')
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            candidate = root / 'candidate'
            candidate.mkdir()
            (candidate / 'marker').write_text('ready\n')
            previous = os.getcwd()
            os.chdir(root)
            try:
                output = Path('dist/published')
                delivery.publish_verified(candidate, output, lambda _path: None)
                landed = output.absolute()
                self.assertEqual(landed, root / 'dist/published')
                self.assertFalse(landed.is_symlink())
                self.assertEqual((landed / 'marker').read_text(), 'ready\n')
                self.assertFalse(candidate.exists())
                held = root / 'held'
                held.mkdir()
                (held / 'marker').write_text('kept\n')
                other = root / 'other'
                other.mkdir()
                (other / 'marker').write_text('blocked\n')
                link = Path('dist/linked')
                link.symlink_to(held)
                with self.assertRaises(ValueError) as caught:
                    delivery.publish_verified(other, link, lambda _path: None)
                self.assertEqual(str(caught.exception), 'output path/symlink')
                self.assertTrue(link.is_symlink())
                self.assertTrue(other.exists())
                self.assertEqual((held / 'marker').read_text(), 'kept\n')
                self.assertEqual((landed / 'marker').read_text(), 'ready\n')
            finally:
                os.chdir(previous)

    def test_hit_and_miss_build_current_swift_resources_backend_and_helper(self):
        import argparse
        import hashlib
        import shutil
        import tempfile
        from unittest.mock import patch
        package = load('fresh_app_cache_fixture', ROOT / 'scripts/flow-app.py')
        runtime_owner = package.delivery_module()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve(); repo = root / 'checkout'; repo.mkdir()
            write(repo / 'apps/macos/sources.json', json.dumps({'core':['main.swift'],'native':[],'app':[]}))
            write(repo / 'apps/macos/main.swift','current Swift')
            write(repo / 'assets/branding/lagrangian.png','current resource')
            write(repo / 'LICENSE','Apache fixture')
            write(repo / 'scripts/flow-app.py', (ROOT / 'scripts/flow-app.py').read_text())
            engine = root / 'engine-input/flow-engine'; write(engine,'same engine bytes')
            payload = root / 'delivery'; payload.mkdir()
            write(payload / 'backend.py','current backend')
            write(payload / 'helper.mjs','current helper')
            write(payload / 'delivery-manifest.json','fixture manifest')
            write(payload / 'runtime/runtime-manifest.json', json.dumps({'source': {'sourceSHA': '1' * 40}}))
            revision = ['1' * 40]
            policy_checks, copied_development = [], []
            def source_binding(_):
                return {str(p.relative_to(repo)): package.digest(p) for p in repo.rglob('*') if p.is_file()}
            class Delivery:
                @staticmethod
                def read(path): return runtime_owner.read(path)
                @staticmethod
                def bundle_runtime_policy(manifest, head, identity, *, development=False):
                    policy_checks.append((head, identity, development))
                    return runtime_owner.bundle_runtime_policy(manifest, head, identity, development=development)
                @staticmethod
                def copy_signed(source, output, identity, *, development=False):
                    runtime_owner.bundle_runtime_policy(Delivery.read(source/'runtime/runtime-manifest.json'), revision[0], identity, development=development)
                    copied_development.append(development)
                    shutil.copytree(source, output, symlinks=True)
                    return Delivery.verify(source)
                @staticmethod
                def source_binding(path): return source_binding(path)
                @staticmethod
                def image_info(path, root):
                    return {'path':str(path.relative_to(root)),'sha256':package.digest(path),'minOS':'13.0','dependencies':[],'resolved':[],'rpaths':[]}
                @staticmethod
                def verify(path):
                    return {'sourceRevision':revision[0], 'sourceFiles':source_binding(repo),
                            'engineInputSHA256':package.digest(engine), 'signing':'ad-hoc',
                            'payloadSHA256':package.bundle_checksum(payload), 'runtimeManifestSHA256':package.digest(payload/'runtime/runtime-manifest.json'),
                            'entrypoints':{'runtime':'runtime'}, 'capabilities':{'fixture':True}}
            def capture(argv, **kwargs):
                args = list(map(str, argv))
                if args[:2] == ['git','-C']:
                    return revision[0] if 'rev-parse' in args else ''
                return 'fixture platform tool'
            def run(argv, **kwargs):
                args = list(map(str, argv))
                if args[0] == '/usr/bin/swiftc':
                    Path(args[-1]).write_text(hashlib.sha256(b''.join(Path(p).read_bytes() for p in args if p.endswith('.swift'))).hexdigest())
                elif args[0] == '/usr/bin/iconutil':
                    Path(args[-1]).write_bytes((repo/'assets/branding/lagrangian.png').read_bytes())
                elif args[0] != '/usr/bin/sips' and args[0] not in ('/usr/bin/codesign','/usr/bin/xattr'):
                    raise AssertionError('Unexpected platform/Rust operation: ' + str(args))
            original_engine = package.digest(engine)
            provenance=root/'engine-input/release.json'
            provenance.write_text(json.dumps({'engineInputSHA256':original_engine,'engineBuild':{'target':reuse.ENGINE_TARGET,'profile':reuse.ENGINE_PROFILE},'sourceRevision':'old application','engineInputProvenance':{'retained':{'old':'recursive app metadata'}}}))
            results=[]
            with patch.object(package,'ROOT',repo), patch.object(package,'__file__',str(repo/'scripts/flow-app.py')), patch.object(package,'delivery_module',return_value=Delivery), patch.object(package,'capture',capture), patch.object(package,'run',run), patch.object(package,'validate',return_value={}):
                for index, mutation in enumerate([None,'swift','resource','backend','helper']):
                    if mutation:
                        target={'swift':repo/'apps/macos/main.swift','resource':repo/'assets/branding/lagrangian.png','backend':payload/'backend.py','helper':payload/'helper.mjs'}[mutation]
                        target.write_text('updated '+mutation); revision[0]=str(index+1)*40
                    write(payload / 'runtime/runtime-manifest.json', json.dumps({'source': {'sourceSHA': revision[0]}}))
                    output=root/str(index)/'Lagrangian.app'
                    args=argparse.Namespace(identity='-',version='0.1.0',delivery=payload,engine_provenance=provenance)
                    manifest=package.build_bundle(args,output,engine,'fixture prebuilt')
                    self.assertEqual(manifest['sourceRevision'],revision[0])
                    self.assertEqual(manifest['engineInputSHA256'],original_engine)
                    self.assertNotIn('sourceRevision',manifest['engineInputProvenance']['retained'])
                    self.assertNotIn('engineInputProvenance',manifest['engineInputProvenance']['retained'])
                    self.assertEqual((output/'Contents/Resources/native-reader/backend.py').read_bytes(),(payload/'backend.py').read_bytes())
                    self.assertEqual((output/'Contents/Resources/native-reader/helper.mjs').read_bytes(),(payload/'helper.mjs').read_bytes())
                    results.append(package.bundle_checksum(output))
                self.assertEqual(len(set(results)),5)
                self.assertEqual(package.digest(engine),original_engine)
                # Same production build boundary is called after hit or miss;
                # cache acquisition supplies only engine bytes/provenance.
                self.assertFalse(any((root/str(i)/'Lagrangian.app').is_symlink() for i in range(5)))
                self.assertEqual(policy_checks, [(str(i)*40, '-', False) for i in range(1,6)])
                self.assertEqual(copied_development, [False]*5)
