"""Compile and exercise the production preview in isolated, nonactivating AppKit fixtures."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]


class PreviewSourceManifest(unittest.TestCase):
    def test_preview_is_registered_once_under_native(self):
        manifest = json.loads((ROOT / 'apps/macos/sources.json').read_text())
        preview = 'NativeCrossProjectPreviewPopover.swift'
        self.assertIn(preview, manifest['native'])
        self.assertEqual(sum(names.count(preview) for names in manifest.values()), 1)


@unittest.skipUnless(sys.platform == 'darwin', 'AppKit tests require macOS')
class CrossProjectPreview(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        temp = tempfile.TemporaryDirectory(prefix='cross-project-preview-tests-')
        cls.addClassCleanup(temp.cleanup)
        cls.executable = Path(temp.name) / 'preview-tests'
        manifest = json.loads((ROOT / 'apps/macos/sources.json').read_text())
        result = subprocess.run([
            '/usr/bin/swiftc', '-swift-version', '5', '-warnings-as-errors',
            *[ROOT / 'apps/macos' / name for group in ('core', 'native') for name in manifest[group]],
            ROOT / 'tests/flow-app/native-reader-app/CrossProjectPreviewTests.swift',
            '-o', cls.executable,
        ], capture_output=True, text=True, timeout=300)
        if result.returncode != 0 or result.stderr:
            raise RuntimeError(result.stdout + result.stderr)

    def scenario(self, name):
        result = subprocess.run([self.executable, name], capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_icon_only_control_header_snippet_and_accessibility(self):
        self.scenario('content')

    def test_button_and_body_clicks_emit_identical_target_once_each(self):
        self.scenario('activation')

    def test_compact_layout_and_floating_surface_in_both_themes(self):
        self.scenario('layout')

    def test_reader_geometry_snapshot_and_location_restoration(self):
        self.scenario('reader')


if __name__ == '__main__':
    unittest.main()
