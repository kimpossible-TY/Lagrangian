"""Reader bundle packaging and fetch verification. These tests do not compile Rust.

A web-only edit stays outside the engine-input hash. The fetch helper is given
a fake gh and must refuse a bad checksum without writing the installed reader.
"""

import contextlib
import hashlib
import importlib.util
import io
import json
import os
import shutil
import subprocess
import sys
import tarfile
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


bundle = load('reader_bundle_under_test', ROOT / 'scripts/reader_bundle.py')
hashing = load('engine_input_hash_for_reader_bundle', ROOT / 'scripts/engine-input-hash.py')
sys.path.insert(0, str(ROOT / 'tools/flow-reader'))
installer = load('reader_install_for_bundle', ROOT / 'tools/flow-reader/install.py')


def git(root, *args, check=True):
    completed = subprocess.run(['git', '-C', str(root), *args], check=False, capture_output=True, text=True)
    if check and completed.returncode != 0:
        raise AssertionError(completed.stderr or completed.stdout)
    return completed


def commit_all(root, message='fixture'):
    git(root, 'add', '.')
    git(root, '-c', 'commit.gpgsign=false', '-c', 'user.name=Reader bundle test',
        '-c', 'user.email=reader-bundle@example.invalid', 'commit', '-qm', message)
    return git(root, 'rev-parse', 'HEAD').stdout.strip()


def write(path, text, mode=0o644):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)
    path.chmod(mode)


class Fixture(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.root = Path(self.directory.name) / 'src'
        self.root.mkdir()
        write(self.root / 'tools/flow-reader/install.py', 'print("install")\n')
        write(self.root / 'tools/flow-reader/manage.py', 'print("manage")\n')
        write(self.root / 'tools/flow-reader/web/app.js', 'export const web = 1\n')
        write(self.root / 'tools/flow-reader/terminal.mjs', '#!/usr/bin/env node\n', mode=0o755)
        write(self.root / 'tools/reader-common/shared.js', 'export const shared = 1\n')
        (self.root / 'tools/flow-reader/web/reader-common').symlink_to('../../reader-common')
        write(self.root / 'docs/note.md', 'not in the bundle\n')
        verifier = self.root / 'scripts/reader_bundle.py'
        verifier.parent.mkdir(parents=True)
        shutil.copy(ROOT / 'scripts/reader_bundle.py', verifier)
        git(self.root, 'init', '-q', '-b', 'main')
        self.sha = commit_all(self.root)
        self.output = Path(self.directory.name) / 'artifact'

    def tearDown(self):
        self.directory.cleanup()
        sys.modules.pop('reader_bundle_install', None)

    def package(self, root=None, sha=None, output=None):
        return bundle.package_reader_bundle(root or self.root, sha or self.sha, output or self.output)

    def manifest(self):
        return json.loads((self.output / 'reader-bundle.json').read_text())


class PackageTests(Fixture):
    def test_manifest_binds_head_sha_modes_symlink_and_is_stable(self):
        first = self.package()
        second = self.package(output=Path(self.directory.name) / 'again')
        self.assertEqual(first['headSha'], self.sha)
        self.assertEqual(first['bundleChecksum'], second['bundleChecksum'])
        self.assertEqual(first['archiveSHA256'], second['archiveSHA256'])
        self.assertEqual(
            hashlib.sha256((self.output / 'reader-bundle.tar').read_bytes()).hexdigest(),
            first['archiveSHA256'],
        )
        paths = {item['path']: item for item in first['files']}
        self.assertNotIn('docs/note.md', paths)
        self.assertEqual(paths['tools/flow-reader/terminal.mjs']['mode'], '100755')
        link = paths['tools/flow-reader/web/reader-common']
        self.assertEqual(link['mode'], '120000')
        self.assertEqual(link['target'], '../../reader-common')
        self.assertEqual(link['sha256'], hashlib.sha256(b'../../reader-common').hexdigest())
        names = sorted(path.name for path in self.output.iterdir())
        self.assertEqual(names, ['reader-bundle.json', 'reader-bundle.tar'])

    def test_worktree_edits_do_not_enter_the_bundle_and_a_new_commit_does(self):
        original = self.package()['bundleChecksum']
        (self.root / 'tools/flow-reader/web/app.js').write_text('export const web = "dirty"\n')
        (self.root / 'tools/flow-reader/web/untracked.js').write_text('nope\n')
        packaged = self.package(output=Path(self.directory.name) / 'dirty')
        self.assertEqual(packaged['bundleChecksum'], original)
        with tempfile.TemporaryDirectory() as temporary:
            staged = Path(temporary) / 'tree'
            bundle.materialize(packaged, Path(self.directory.name) / 'dirty' / 'reader-bundle.tar', staged)
            self.assertEqual((staged / 'tools/flow-reader/web/app.js').read_text(), 'export const web = 1\n')
            self.assertFalse((staged / 'tools/flow-reader/web/untracked.js').exists())
        write(self.root / 'tools/flow-reader/web/app.js', 'export const web = 2\n')
        new_sha = commit_all(self.root, 'web')
        changed = self.package(sha=new_sha, output=Path(self.directory.name) / 'web')
        self.assertNotEqual(changed['bundleChecksum'], original)
        self.assertEqual(changed['headSha'], new_sha)

    def test_rejects_a_head_sha_that_is_not_head_and_an_escaping_symlink(self):
        with self.assertRaisesRegex(ValueError, 'does not match headSha'):
            self.package(sha='ab' * 20)
        with self.assertRaisesRegex(ValueError, 'escapes'):
            bundle.link_stays_inside('tools/flow-reader/web/reader-common', '../../../../tmp/evil')
        self.assertEqual(
            bundle.link_stays_inside('tools/flow-reader/web/reader-common', '../../reader-common'),
            'tools/reader-common',
        )
        with self.assertRaisesRegex(ValueError, 'not a relative repo path'):
            bundle.validate_rel_path('../secrets')

    def test_round_trip_matches_git_archive_and_installs_from_the_bundle(self):
        manifest = self.package()
        payload = subprocess.check_output(
            ['git', '-C', str(self.root), 'archive', self.sha, 'tools/flow-reader', 'tools/reader-common'])
        with tempfile.TemporaryDirectory() as temporary:
            archived = Path(temporary) / 'archived'
            archived.mkdir()
            with tarfile.open(fileobj=io.BytesIO(payload)) as tar:
                tar.extractall(archived, filter='data')
            staged = Path(temporary) / 'staged'
            bundle.materialize(manifest, self.output / 'reader-bundle.tar', staged)
            release = Path(temporary) / 'release'
            release.mkdir()
            self.assertEqual(installer.stage_reader_sources(staged, release), self.sha)
            self.assertEqual(installer.reader_revision(staged), self.sha)
            self.assertEqual(tree_records(release), tree_records(archived))
            (staged / 'tools/flow-reader/web/app.js').write_text('tampered\n')
            with self.assertRaisesRegex(ValueError, 'SHA-256 mismatch'):
                installer.reader_revision(staged)

    def test_git_checkout_still_requires_a_clean_commit(self):
        with tempfile.TemporaryDirectory() as temporary:
            staging = Path(temporary) / 'staging'
            staging.mkdir()
            self.assertEqual(installer.stage_reader_sources(self.root, staging), self.sha)
            self.assertEqual((staging / 'tools/flow-reader/web/app.js').read_text(), 'export const web = 1\n')
            self.assertEqual(os.readlink(staging / 'tools/flow-reader/web/reader-common'), '../../reader-common')
            (self.root / 'tools/flow-reader/web/app.js').write_text('dirty\n')
            with self.assertRaisesRegex(ValueError, 'clean commit'):
                installer.reader_revision(self.root)


class FetchTests(Fixture):
    def fake(self, **kwargs):
        self.package()
        head = kwargs.pop('head_sha', self.sha)
        return FakeGH(self.output, head, **kwargs)

    def test_run_id_verifies_and_prints_only_the_staging_path(self):
        home = Path(self.directory.name) / 'home'
        dest = Path(self.directory.name) / 'stage'
        dest.mkdir()
        (dest / 'previous').write_text('old')
        sentinel = home / 'Library/Application Support/Lagrangian/reader/config.json'
        write(sentinel, 'installed reader\n')
        before = sentinel.read_bytes()
        fake = self.fake()
        stdout, stderr = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            code = bundle.main_fetch(
                ['--run-id', '42', '--repo', 'kimpossible-TY/Lagrangian', '--dest', str(dest)], gh=fake)
        self.assertEqual(code, 0)
        self.assertEqual(stdout.getvalue().strip(), str(dest.resolve()))
        self.assertIn('verified ' + self.sha, stderr.getvalue())
        self.assertFalse((dest / 'previous').exists())
        self.assertEqual((dest / 'tools/flow-reader/install.py').read_text(), 'print("install")\n')
        self.assertTrue((dest / 'tools/flow-reader/web/reader-common').is_symlink())
        self.assertEqual(sentinel.read_bytes(), before)
        self.assertFalse(any(call[:2] == ['run', 'list'] for call in fake.calls))
        self.assertFalse(any('install.py' in part for call in fake.calls for part in call))

    def test_head_sha_branch_nested_layout_and_stable_artifact_name(self):
        fake = self.fake(nested=True, fail_names={bundle.SHA_ARTIFACT_PREFIX + self.sha})
        dest = Path(self.directory.name) / 'by-sha'
        staged = bundle.fetch_reader_bundle(
            repo='kimpossible-TY/Lagrangian', head_sha=self.sha, dest=dest, gh=fake,
            home=Path(self.directory.name) / 'home')
        self.assertEqual(staged, dest.resolve())
        self.assertTrue(any('--commit' in call and self.sha in call for call in fake.calls))
        self.assertIn(bundle.STABLE_ARTIFACT, [call[call.index('--name') + 1] for call in fake.calls if '--name' in call])
        branch = self.fake()
        other = Path(self.directory.name) / 'by-branch'
        bundle.fetch_reader_bundle(
            repo='kimpossible-TY/Lagrangian', branch='main', head_sha=self.sha, dest=other, gh=branch,
            home=Path(self.directory.name) / 'home')
        self.assertTrue(any('--branch' in call and 'main' in call for call in branch.calls))

    def test_darwin_cache_is_outside_application_support(self):
        fake = self.fake()
        home = Path(self.directory.name) / 'mac-home'
        with patch.object(bundle.sys, 'platform', 'darwin'):
            staged = bundle.fetch_reader_bundle(
                repo='kimpossible-TY/Lagrangian', run_id='42', gh=fake, home=home)
        expected = home / 'Library/Caches/Lagrangian/reader-bundles' / self.sha
        self.assertEqual(staged, expected.resolve())
        self.assertTrue((staged / 'reader-bundle.json').is_file())
        self.assertFalse((home / 'Library/Application Support').exists())
        self.assertFalse((home / 'Applications').exists())

    def test_mismatch_refuses_without_touching_destination_or_installed_reader(self):
        cases = []
        good = self.package()
        tampered = Path(self.directory.name) / 'tampered-tar'
        shutil.copytree(self.output, tampered)
        blob = bytearray((tampered / 'reader-bundle.tar').read_bytes())
        blob[-1] ^= 0x01
        (tampered / 'reader-bundle.tar').write_bytes(blob)
        cases.append(tampered)
        bad_sum = Path(self.directory.name) / 'bad-sum'
        shutil.copytree(self.output, bad_sum)
        manifest = json.loads((bad_sum / 'reader-bundle.json').read_text())
        manifest['bundleChecksum'] = 'ab' * 32
        (bad_sum / 'reader-bundle.json').write_text(json.dumps(manifest))
        cases.append(bad_sum)
        extra = Path(self.directory.name) / 'extra'
        shutil.copytree(self.output, extra)
        extra_tar = Path(self.directory.name) / 'extra.tar'
        with tarfile.open(self.output / 'reader-bundle.tar', 'r') as source, \
                tarfile.open(extra_tar, 'w', format=tarfile.PAX_FORMAT) as target:
            for member in source.getmembers():
                extracted = source.extractfile(member) if member.isreg() else None
                target.addfile(member, extracted)
            info = tarfile.TarInfo('tools/flow-reader/web/extra.js')
            payload = b'extra\n'
            info.size = len(payload)
            info.mode = 0o644
            info.mtime = 0
            target.addfile(info, io.BytesIO(payload))
        manifest = json.loads((extra / 'reader-bundle.json').read_text())
        manifest['archiveSHA256'] = hashlib.sha256(extra_tar.read_bytes()).hexdigest()
        (extra / 'reader-bundle.json').write_text(json.dumps(manifest))
        (extra / 'reader-bundle.tar').write_bytes(extra_tar.read_bytes())
        cases.append(extra)
        home = Path(self.directory.name) / 'home'
        sentinel = home / 'Library/Application Support/Lagrangian/reader/releases/old'
        write(sentinel / 'keep.txt', 'installed\n')
        before = (sentinel / 'keep.txt').read_bytes()
        for artifact in cases:
            dest = Path(self.directory.name) / ('dest-' + artifact.name)
            dest.mkdir()
            (dest / 'keep').write_text('previous staging')
            fake = FakeGH(artifact, self.sha)
            stdout, stderr = io.StringIO(), io.StringIO()
            with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
                code = bundle.main_fetch(
                    ['--run-id', '42', '--repo', 'kimpossible-TY/Lagrangian', '--dest', str(dest)], gh=fake)
            self.assertEqual(code, 1, artifact.name)
            self.assertEqual(stdout.getvalue(), '')
            self.assertIn('reader-bundle:', stderr.getvalue())
            self.assertEqual((dest / 'keep').read_text(), 'previous staging')
            self.assertEqual((sentinel / 'keep.txt').read_bytes(), before)
        self.assertEqual(good['headSha'], self.sha)

    def test_wrong_run_missing_selector_and_installed_destination_are_refused(self):
        home = Path(self.directory.name) / 'home'
        sentinel = home / 'Library/Application Support/Lagrangian/reader/config.json'
        write(sentinel, 'installed\n')
        fake = self.fake(head_sha='cd' * 20)
        dest = Path(self.directory.name) / 'wrong-sha'
        with self.assertRaisesRegex(ValueError, 'headSha mismatch'):
            bundle.fetch_reader_bundle(repo='kimpossible-TY/Lagrangian', run_id='42', dest=dest, gh=fake, home=home)
        self.assertFalse(dest.exists())
        self.assertEqual(sentinel.read_text(), 'installed\n')
        other = FakeGH(self.output, self.sha, workflow='Other')
        with self.assertRaisesRegex(ValueError, 'not a flow-engine'):
            bundle.fetch_reader_bundle(repo='kimpossible-TY/Lagrangian', run_id='42', dest=dest, gh=other, home=home)
        self.assertFalse(any(call[:2] == ['run', 'download'] for call in other.calls))
        failed = FakeGH(self.output, self.sha, conclusion='failure')
        with self.assertRaisesRegex(ValueError, 'not a successful'):
            bundle.fetch_reader_bundle(repo='kimpossible-TY/Lagrangian', run_id='42', dest=dest, gh=failed, home=home)
        stdout, stderr = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            code = bundle.main_fetch([], gh=fake)
        self.assertEqual(code, 2)
        self.assertEqual(stdout.getvalue(), '')
        forbidden = home / 'Library/Application Support/Lagrangian/reader/staging'
        quiet = FakeGH(self.output, self.sha)
        with self.assertRaisesRegex(ValueError, 'installed application data'):
            bundle.fetch_reader_bundle(
                repo='kimpossible-TY/Lagrangian', run_id='42', dest=forbidden, gh=quiet, home=home)
        self.assertEqual(quiet.calls, [])
        self.assertEqual(sentinel.read_text(), 'installed\n')
        with patch.object(bundle.shutil, 'which', return_value=None):
            with self.assertRaisesRegex(ValueError, 'does not install the reader'):
                bundle.fetch_reader_bundle(repo='kimpossible-TY/Lagrangian', run_id='42', dest=dest)


class ContractTests(unittest.TestCase):
    def test_reader_sources_stay_out_of_the_engine_input_hash(self):
        script = (ROOT / 'scripts/engine-input-hash.py').read_text()
        self.assertNotIn('flow-reader', script)
        self.assertNotIn('reader-bundle', script)
        self.assertFalse(hashing.include(Path('tools/flow-reader/web/reader.css')))
        self.assertFalse(hashing.include(Path('tools/flow-reader/web/app.js')))
        self.assertFalse(hashing.include(Path('tools/flow-reader/install.py')))
        self.assertFalse(hashing.include(Path('scripts/reader_bundle.py')))
        self.assertFalse(hashing.include(Path('scripts/package-reader-bundle.py')))
        self.assertFalse(hashing.include(Path('scripts/fetch-reader-bundle.py')))
        self.assertFalse(hashing.include(Path('.github/workflows/flow-engine.yml')))
        self.assertTrue(hashing.include(Path('scripts/flow-app.py')))

    def test_workflow_publishes_the_reader_bundle_on_hit_and_miss(self):
        workflow = (ROOT / '.github/workflows/flow-engine.yml').read_text()
        self.assertIn('name: flow-engine-darwin-arm64', workflow)
        self.assertNotIn('name: flow-engine-darwin-arm64-', workflow)
        self.assertIn('name: reader-bundle-${{ github.sha }}', workflow)
        self.assertIn('name: flow-reader-bundle', workflow)
        self.assertIn('scripts/package-reader-bundle.py', workflow)
        self.assertIn('scripts/engine-input-hash.py', workflow)
        for name in ('Package the reader bundle', 'Upload reader bundle', 'Upload stable reader bundle'):
            block = step_block(workflow, name)
            self.assertNotIn('\n        if:', block)
            self.assertNotIn('engine_cache.outputs.hit', block)
        self.assertIn('if: steps.engine_cache.outputs.hit != \'true\'', workflow)

    def test_real_checkout_packages_when_the_verifier_is_committed(self):
        listed = git(ROOT, 'ls-files', 'scripts/reader_bundle.py', check=False).stdout.strip()
        if listed != 'scripts/reader_bundle.py':
            self.skipTest('reader bundle script is not committed yet')
        sha = git(ROOT, 'rev-parse', 'HEAD').stdout.strip()
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / 'artifact'
            manifest = bundle.package_reader_bundle(ROOT, sha, output)
            staged = Path(temporary) / 'staged'
            bundle.materialize(manifest, output / 'reader-bundle.tar', staged)
            self.assertEqual(os.readlink(staged / 'tools/flow-reader/web/reader-common'), '../../reader-common')
            self.assertTrue((staged / 'tools/flow-reader/install.py').is_file())
            self.assertTrue((staged / 'tools/flow-reader/manage.py').is_file())
            self.assertTrue(any(item['path'].startswith('tools/flow-reader/web/') for item in manifest['files']))
            release = Path(temporary) / 'release'
            release.mkdir()
            self.assertEqual(installer.stage_reader_sources(staged, release), sha)


class FakeGH:
    def __init__(self, artifact, head_sha, run_id=42, fail_names=(), nested=False,
                 workflow='Flow engine', conclusion='success', head_branch='main'):
        self.artifact = artifact
        self.head_sha = head_sha
        self.run_id = int(run_id)
        self.fail_names = set(fail_names)
        self.nested = nested
        self.workflow = workflow
        self.conclusion = conclusion
        self.head_branch = head_branch
        self.calls = []

    def __call__(self, args):
        self.calls.append(list(args))
        if args[:2] == ['repo', 'view']:
            return json.dumps({'nameWithOwner': 'kimpossible-TY/Lagrangian'})
        if args[:2] == ['run', 'list']:
            return json.dumps([{
                'databaseId': self.run_id,
                'headSha': self.head_sha,
                'conclusion': 'success',
                'createdAt': '2026-11-01T00:00:00Z',
                'url': 'https://example.test/runs/' + str(self.run_id),
                'headBranch': self.head_branch,
                'workflowName': self.workflow,
            }])
        if args[:2] == ['run', 'view']:
            return json.dumps({
                'databaseId': self.run_id,
                'headSha': self.head_sha,
                'conclusion': self.conclusion,
                'status': 'completed',
                'url': 'https://example.test/runs/' + str(self.run_id),
                'headBranch': self.head_branch,
                'workflowName': self.workflow,
            })
        if args[:2] == ['run', 'download']:
            name = args[args.index('--name') + 1]
            if name in self.fail_names:
                raise RuntimeError('gh run download failed: not found ' + name)
            dest = Path(args[args.index('--dir') + 1])
            if self.nested:
                dest = dest / name
            dest.mkdir(parents=True, exist_ok=True)
            for item in Path(self.artifact).iterdir():
                shutil.copy2(item, dest / item.name)
            return ''
        raise AssertionError(args)


def step_block(workflow, name):
    marker = '- name: ' + name
    start = workflow.index(marker)
    rest = workflow[start:]
    nxt = rest.find('\n      - ', len(marker))
    return rest if nxt == -1 else rest[:nxt]


def tree_records(root):
    records = {}
    root = Path(root)
    for dirpath, dirnames, filenames in os.walk(root, followlinks=False):
        current = Path(dirpath)
        kept = []
        for name in dirnames:
            path = current / name
            if path.is_symlink():
                records[path.relative_to(root).as_posix()] = ('link', os.readlink(path))
            else:
                kept.append(name)
        dirnames[:] = kept
        for name in filenames:
            path = current / name
            relative = path.relative_to(root).as_posix()
            if path.is_symlink():
                records[relative] = ('link', os.readlink(path))
            else:
                records[relative] = ('file', path.read_bytes(), path.stat().st_mode & 0o777)
    return records


if __name__ == '__main__':
    unittest.main()
