"""Exercise a real clean-commit install and preservation on failed updates."""

import argparse
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
import install as installer


@unittest.skipUnless(sys.platform == "darwin", "Reader installation targets macOS")
class ReaderInstallTests(unittest.TestCase):
    def test_clean_release_works_and_rejected_updates_preserve_installed_files(self):
        with tempfile.TemporaryDirectory(prefix="reader install spaces ") as temporary:
            work = Path(temporary)
            source = work / "source"
            shutil.copytree(ROOT, source / "tools/flow-reader", ignore=shutil.ignore_patterns("__pycache__"))
            marker = source / "tools/flow-reader/source.txt"
            marker.write_text("immutable source")
            subprocess.run(["git", "init", "-q", str(source)], check=True)
            subprocess.run(["git", "-C", str(source), "add", "."], check=True)
            subprocess.run(["git", "-C", str(source), "-c", "user.name=Reader test", "-c",
                            "user.email=reader-test@example.invalid", "commit", "-qm", "fixture"], check=True)
            project = work / "project"
            project.mkdir()
            (project / "main.typ").write_text("Fixture")
            (project / "packages").mkdir()
            parent = {"id": "install-fixture", "name": "Fixture", "root": str(project), "entry": "main.typ",
                      "fonts": [], "packages": str(project / "packages"), "port": 25001, "publicURL": "",
                      "label": "com.example.reader-install-fixture-paged"}
            flow = work / "flow-fixture"
            # repr embeds the fixture dictionary as Python data, without shell evaluation.
            flow.write_text(f"#!{sys.executable}\nimport json\nprint(json.dumps({repr({'profiles': [parent]})}))\n")
            flow.chmod(0o755)
            args = argparse.Namespace(data=work / "installed", profile="install-fixture", port=25002,
                                      public_url="", development=True, flow_manager=flow,
                                      python=Path(sys.executable), compiler=Path(sys.executable), start=False)
            args.semantic_canvases = True
            with patch.object(installer, "__file__", source / "tools/flow-reader/install.py"):
                result = installer.install(args)
                manager = Path(result["manager"])
                profiles = json.loads(subprocess.check_output([manager, "--profiles"], text=True))
                self.assertEqual(profiles["profiles"][0]["root"], str(project))
                self.assertTrue(profiles["profiles"][0]["semanticCanvases"])
                args.semantic_canvases = None
                installer.install(args)
                self.assertTrue(json.loads((args.data / "config.json").read_text())["services"][0]["semanticCanvases"])
                config = (args.data / "config.json").read_bytes()
                launcher = manager.read_bytes()
                marker.write_text("uncommitted source")
                with self.assertRaisesRegex(ValueError, "clean commit"):
                    installer.install(args)
                self.assertEqual((args.data / "config.json").read_bytes(), config)
                self.assertEqual(manager.read_bytes(), launcher)
                marker.write_text("immutable source")
                installed_marker = args.data / "releases" / result["revision"] / "tools/flow-reader/source.txt"
                installed_marker.write_text("modified installation")
                with self.assertRaisesRegex(ValueError, "immutable release"):
                    installer.install(args)
                self.assertEqual(manager.read_bytes(), launcher)
                self.assertEqual((args.data / "config.json").read_bytes(), config)


if __name__ == "__main__":
    unittest.main()
