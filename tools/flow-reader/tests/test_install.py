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
            shutil.copytree(ROOT, source / "tools/flow-reader", ignore=shutil.ignore_patterns("__pycache__"), symlinks=True)
            shutil.copytree(ROOT.parent / "reader-common", source / "tools/reader-common",
                            ignore=shutil.ignore_patterns("__pycache__"))
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
                release = args.data / "releases" / result["revision"] / "tools/flow-reader"
                self.verify_installed_delivery(release)
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

    def verify_installed_delivery(self, release):
        """Exercise imports and HTTP from the archived layout, outside the checkout."""
        script = r"""
from http.server import ThreadingHTTPServer
import json
from pathlib import Path
import re
import threading
from urllib.parse import urljoin
from urllib.request import urlopen
from flow_reader.server import state
from flow_reader.server.http import handler_for
from flow_reader.server.assets import reader_assets

assert Path(state.__file__).resolve().is_relative_to(Path.cwd())
assets = reader_assets()
assert any(name.startswith('/reader-common/') for name in assets)
server = ThreadingHTTPServer(('127.0.0.1', 0), handler_for(None))
thread = threading.Thread(target=server.serve_forever, daemon=True)
thread.start()
origin = f'http://127.0.0.1:{server.server_port}'
try:
    for route, (path, content_type) in assets.items():
        with urlopen(origin + route) as response:
            assert response.read() == path.read_bytes(), route
            assert response.headers['Content-Type'] == content_type, route
        if path.suffix == '.js':
            for dependency in re.findall(r"(?:from\s*|import\s*\()['\"]([^'\"]+)['\"]", path.read_text()):
                if dependency.startswith('.'):
                    target = urljoin(route, dependency)
                    assert target in assets, (route, target)
    print(json.dumps({'assets': len(assets)}))
finally:
    server.shutdown()
    server.server_close()
    thread.join()
"""
        result = json.loads(subprocess.check_output([sys.executable, "-c", script], cwd=release, text=True))
        self.assertGreater(result["assets"], 20)
        for entry in ("build.py", "serve.py", "focus.py", "terminal/probe.py"):
            subprocess.run([sys.executable, str(release / entry), "--help"],
                           cwd=release.parent.parent.parent, capture_output=True, check=True)
        node = shutil.which("node")
        if node:
            result = subprocess.check_output([node, str(release / "terminal.mjs"), "--help"],
                                             cwd=release.parent.parent.parent, text=True)
            self.assertIn("native terminal", result)
            # The split service adapter must resolve the archived Python launcher.
            script = ("const {serverArguments}=await import(process.argv[1]);"
                      "console.log(JSON.stringify(serverArguments({root:process.cwd()})));")
            arguments = json.loads(subprocess.check_output(
                [node, "--input-type=module", "-e", script,
                 (release / "terminal/service.mjs").as_uri()], cwd=release, text=True))
            self.assertEqual(Path(arguments[0]).resolve(), (release / "serve.py").resolve())


if __name__ == "__main__":
    unittest.main()
