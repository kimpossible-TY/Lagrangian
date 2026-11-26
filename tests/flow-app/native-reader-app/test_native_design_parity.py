"""Self-contained offscreen reader integration; no external lock or live services."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]


@unittest.skipUnless(sys.platform == 'darwin', 'AppKit requires macOS')
class NativeDesignParityTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        temp = tempfile.TemporaryDirectory(prefix='native-design-parity-')
        cls.addClassCleanup(temp.cleanup)
        cls.output = Path(temp.name)
        cls.binary = cls.output / 'parity'
        registry = json.loads((ROOT / 'apps/macos/sources.json').read_text())
        sources = [ROOT / 'apps/macos' / name for group in ('core', 'native', 'app')
                   for name in registry[group] if name != 'main.swift']
        cache = cls.output / 'module-cache'
        cache.mkdir()
        cls.environment = dict(os.environ, CLANG_MODULE_CACHE_PATH=str(cache), SWIFT_MODULECACHE_PATH=str(cache))
        command = ['swiftc', '-parse-as-library', '-swift-version', '5', '-warnings-as-errors',
                   '-target', 'arm64-apple-macosx13.0', '-module-cache-path', str(cache),
                   *map(str, sources), str(Path(__file__).with_name('NativeDesignParityTests.swift')), '-o', str(cls.binary)]
        result = subprocess.run(command, cwd=ROOT, env=cls.environment, capture_output=True, text=True, timeout=240)
        if result.returncode:
            raise RuntimeError(result.stdout + result.stderr)

    def scenario(self, name):
        output = self.output / name
        output.mkdir()
        result = subprocess.run([str(self.binary), str(output), name], cwd=ROOT, env=self.environment,
                                capture_output=True, text=True, timeout=45)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('assertions; offscreen AppKit only', result.stdout)

    def test_outline_drawer_and_active_section(self): self.scenario('drawer')
    def test_centered_pass_through_notifications(self): self.scenario('notifications')
    def test_brand_mode_morph_and_toolbar(self): self.scenario('toolbar')
    def test_bottom_capsule_ticket_focus_and_review(self): self.scenario('capsule')
    def test_document_end_existing_review(self): self.scenario('review-existing')
    def test_document_end_first_strike(self): self.scenario('review-added')
    def test_document_end_offset_selection(self): self.scenario('review-offset')
    def test_tall_selection_avoidance(self): self.scenario('tall-selection')
    def test_pending_refresh_local_strike(self): self.scenario('pending-strike')
    def test_keyboard_pdf_selection_and_immutable_ink(self): self.scenario('keyboard-pdf')
