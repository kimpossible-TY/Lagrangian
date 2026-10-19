"""Exercise the portable Tail Hosting adapter in an isolated copy, never live."""

import importlib.machinery
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch


class FocusBridgeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        source = os.environ.get("TAIL_HOSTING_SOURCE")
        if not source:
            raise unittest.SkipTest("Set TAIL_HOSTING_SOURCE to check the companion patch")
        cls.temporary = tempfile.TemporaryDirectory()
        cls.addClassCleanup(cls.temporary.cleanup)
        root = Path(cls.temporary.name)
        (root / "bin").mkdir()
        target = root / "bin/tail-hosting"
        target.write_bytes((Path(source) / "bin/tail-hosting").read_bytes())
        adapter = Path(__file__).resolve().parents[3] / "apps/macos/tail-hosting-reader-focus.patch"
        result = subprocess.run(["patch", "-p1", "--batch", "--forward", "-i", str(adapter)], cwd=root,
                                capture_output=True)
        if result.returncode:
            # A deployed source already includes this adapter. Verify that exact
            # reverse patch in the copy; never modify the installed source.
            target.write_bytes((Path(source) / "bin/tail-hosting").read_bytes())
            subprocess.run(["patch", "-p1", "--batch", "--reverse", "--dry-run", "-i", str(adapter)],
                           cwd=root, check=True, capture_output=True)
        loader = importlib.machinery.SourceFileLoader("reader_hosting_fixture", str(target))
        spec = importlib.util.spec_from_loader(loader.name, loader)
        cls.hosting = importlib.util.module_from_spec(spec)
        loader.exec_module(cls.hosting)

    def setUp(self):
        self.paged = {"id": "doc", "name": "Paged", "kind": "typst-always-preview",
                      "projectRoot": "/projects/doc", "entrypoint": "main.typ",
                      "launchAgentLabel": "paged", "focusFile": "/runtime/paged.json"}
        self.reader = {**self.paged, "id": "doc-reader", "name": "Reader", "kind": "typst-reader",
                       "launchAgentLabel": "reader", "managerBinary": "/reader/manager",
                       "focusFile": "/runtime/reader.json",
                       "ingress": {"port": 23627, "path": "/"}}
        self.arguments = SimpleNamespace(list=False, preview=None, project=None, document=None, url=None)

    def test_listing_and_explicit_service_filters_keep_reader_and_paged_separate(self):
        h = self.hosting
        registry = {"services": [self.paged, self.reader]}
        self.arguments.list = True
        result = h.resolve_focus(registry, self.arguments)
        self.assertEqual([p["reader_kind"] for p in result["previews"]], ["paged", "html"])
        self.assertNotEqual(*[p["focus_file"] for p in result["previews"]])
        self.arguments.list = False
        self.arguments.project = "/projects/doc"
        self.assertEqual(h.resolve_focus(registry, self.arguments)["status"], "ambiguous")
        self.arguments.preview = "doc-reader"
        with patch.object(h, "read_focus", return_value={"status": "selected"}) as read:
            result = h.resolve_focus(registry, self.arguments)
            read.assert_called_once_with(self.reader)
        self.assertEqual(result["preview"]["reader_kind"], "html")

    def test_reader_uses_manager_validation_without_paged_record_fallback(self):
        h = self.hosting
        verified = {"status": "unmapped", "selection": {"text": "α"},
                    "selection_usable": True, "source": None}
        with patch.object(h, "require", return_value=json.dumps(verified)) as command:
            self.assertEqual(h.read_focus(self.reader), verified)
        command.assert_called_once_with(["/reader/manager", "--focus", "doc-reader"])
        with self.assertRaisesRegex(ValueError, "managerBinary"):
            h.read_focus(self.reader | {"managerBinary": None})


if __name__ == "__main__":
    unittest.main()
