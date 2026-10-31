"""Engine-input hash and retained-artifact selection. These tests do not compile Rust."""

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
