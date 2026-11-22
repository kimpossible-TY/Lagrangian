"""Exercise a real clean-commit install and preservation on failed updates."""

import argparse
import hashlib
import io
import json
import os
from pathlib import Path
import shlex
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
            change_file = work / 'configured Flow data' / 'changes' / 'install-fixture.json'
            # repr embeds the fixture dictionary as Python data, without shell evaluation.
            flow.write_text(f"#!{sys.executable}\nimport json\nimport sys\n" +
                            f"profiles = {repr({'profiles': [parent]})}\n" +
                            f"plan = {repr({'environment': {'TINYMIST_PREVIEW_CHANGE_FILE': str(change_file)}})}\n" +
                            "print(json.dumps(plan if sys.argv[1] == '--launch-plan' else profiles))\n")
            flow.chmod(0o755)
            engine = work / "source-history-engine"
            engine.write_text(f"#!{sys.executable}\n" + r'''
import json
from pathlib import Path
import sys
if sys.argv[-1] == '--help':
    print('--root ROOT --change-file PATH')
else:
    assert sys.argv[1] == 'source-history'
    assert isinstance(json.load(sys.stdin)['sources'], list)
    path = Path(sys.argv[sys.argv.index('--change-file') + 1]).resolve()
    print(json.dumps({'path': str(path), 'sequence': 0}))
''')
            engine.chmod(0o755)
            if os.environ.get('FLOW_TEST_ENGINE'):
                engine = Path(os.environ['FLOW_TEST_ENGINE']).resolve(strict=True)
            args = argparse.Namespace(data=work / "installed", profile="install-fixture", port=25002,
                                      public_url="", development=True, flow_manager=flow,
                                      python=Path(sys.executable), compiler=Path(sys.executable), engine=engine, start=False)
            args.semantic_canvases = True
            extra_font = (work / "explicit Arial fixture.ttf").resolve()
            extra_font.write_bytes(b"font fixture")
            args.extra_fonts = [extra_font]
            with patch.object(installer, "__file__", source / "tools/flow-reader/install.py"):
                result = installer.install(args)
                manager = Path(result["manager"])
                profiles = json.loads(subprocess.check_output([manager, "--profiles"], text=True))
                self.assertEqual(profiles["profiles"][0]["root"], str(project))
                self.assertTrue(profiles["profiles"][0]["semanticCanvases"])
                self.assertEqual(profiles["profiles"][0]["fonts"], [str(extra_font)])
                release = args.data / "releases" / result["revision"] / "tools/flow-reader"
                self.verify_installed_delivery(release, engine)
                plan = json.loads(subprocess.check_output([manager, "--launch-plan", result['id']], text=True))
                self.assertEqual(Path(plan['arguments'][plan['arguments'].index('--engine') + 1]), engine.resolve())
                self.assertEqual(Path(plan['arguments'][plan['arguments'].index('--change-file') + 1]), change_file.resolve())
                args.semantic_canvases = None
                args.extra_fonts = None
                installer.install(args)
                self.assertTrue(json.loads((args.data / "config.json").read_text())["services"][0]["semanticCanvases"])
                self.assertEqual(json.loads((args.data / "config.json").read_text())["services"][0]["extraFonts"], [str(extra_font)])
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
                installed_marker.write_text("immutable source")
                # A compiler build is part of a new immutable release identity.
                browser = work / "generated browser compiler"
                browser.mkdir()
                (browser / "compiler.js").write_text("export default () => {};\n")
                (browser / "compiler_bg.wasm").write_bytes(b"\x00asm\x01\x00\x00\x00")
                files = {name: hashlib.sha256((browser / name).read_bytes()).hexdigest()
                         for name in ("compiler.js", "compiler_bg.wasm")}
                manifest = {"schemaVersion": 1, "files": files,
                            "engine": hashlib.sha256(json.dumps(files, sort_keys=True).encode()).hexdigest()}
                (browser / "manifest.json").write_text(json.dumps(manifest))
                args.browser_compiler = browser
                compiled = installer.install(args)
                self.assertNotEqual(compiled["release"], result["release"])
                delivery = args.data / "releases" / compiled["release"] / "tools/flow-reader/compiler-assets"
                self.assertEqual((delivery / "compiler_bg.wasm").read_bytes(), (browser / "compiler_bg.wasm").read_bytes())
                plan = json.loads(subprocess.check_output([manager, "--launch-plan", result['id']], text=True))
                self.assertEqual(Path(plan['arguments'][plan['arguments'].index('--browser-compiler') + 1]), delivery.resolve())
                args.browser_compiler = None
                self.assertEqual(installer.install(args)["release"], compiled["release"])
                saved = (args.data / "config.json").read_bytes()
                (delivery / "compiler_bg.wasm").write_bytes(b"changed")
                with self.assertRaisesRegex(ValueError, "do not match"):
                    installer.install(args)
                self.assertEqual((args.data / "config.json").read_bytes(), saved)

    def verify_installed_delivery(self, release, engine):
        """Exercise imports and HTTP from the archived layout, outside the checkout."""
        script = r"""
from http.server import ThreadingHTTPServer
import json
from pathlib import Path
import re
import sys
import tempfile
import threading
from urllib.parse import urljoin
from urllib.request import urlopen
from flow_reader.server import state
from flow_reader.server.http import handler_for
from flow_reader.server.assets import reader_assets
from flow_reader.services.source_history import SourceHistoryClient, source_snapshots
from flow_reader.compiler.project import Project

assert Path(state.__file__).resolve().is_relative_to(Path.cwd())
from flow_reader.services.paragraph_chat import ParagraphChat, DocumentTools
from flow_reader.services.chat_auth import ChatAuth
assert (Path(state.__file__).parents[1] / 'services/verify-id-token.mjs').is_file()
with tempfile.TemporaryDirectory() as temporary:
    root = Path(temporary).resolve()
    (root / 'main.typ').write_text('Installed source-history client')
    project = Project(root, Path('main.typ'), root / 'packages')
    history = SourceHistoryClient(project, engine=sys.argv[1], change_file=root / 'common.json')
    history.seed(source_snapshots(project, []))
    assert history.location.path == root / 'common.json'
from flow_reader.server.home import home_assets, handler_for_home
home = home_assets()
assert (Path(state.__file__).parents[2] / 'home.py').is_file()
assert home['/'].name == 'index.html' and home['/'].parent.name == 'home'
for path in home.values():
    assert path.is_file()
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
home_server = ThreadingHTTPServer(('127.0.0.1', 0), handler_for_home(None, None))
home_thread = threading.Thread(target=home_server.serve_forever, daemon=True)
home_thread.start()
try:
    origin = f'http://127.0.0.1:{home_server.server_port}'
    for route, path in home.items():
        with urlopen(origin + route) as response:
            assert response.read() == path.read_bytes(), route
finally:
    home_server.shutdown()
    home_server.server_close()
    home_thread.join()
"""
        result = json.loads(subprocess.check_output([sys.executable, "-c", script, str(engine)], cwd=release, text=True))
        self.assertGreater(result["assets"], 20)
        for entry in ("build.py", "serve.py", "focus.py", "edit-location.py"):
            subprocess.run([sys.executable, str(release / entry), "--help"],
                           cwd=release.parent.parent.parent, capture_output=True, check=True)
        node = shutil.which("node")
        if node:
            result = subprocess.check_output([node, str(release / "terminal.mjs"), "--help"],
                                             cwd=release.parent.parent.parent, text=True)
            self.assertIn("native terminal", result)
            # Presentation attaches through the archived HTML manager, never serve.py.
            script = ("const {attachmentArguments}=await import(process.argv[1]);"
                      "console.log(JSON.stringify(attachmentArguments({root:process.cwd()})));")
            arguments = json.loads(subprocess.check_output(
                [node, "--input-type=module", "-e", script,
                 (release / "terminal/service.mjs").as_uri()], cwd=release, text=True))
            self.assertEqual(Path(arguments[0]).resolve(), (release / "manage.py").resolve())
            self.assertEqual(arguments[1], '--attach')
            subprocess.run([sys.executable, *arguments[:2], '--help'], capture_output=True, check=True)


def _write_managed_release(releases, name, *, with_manifest=True):
    directory = releases / name
    directory.mkdir(parents=True, exist_ok=True)
    if with_manifest:
        (directory / "release.json").write_text(json.dumps({"revision": name}))
    return directory


def _write_launcher(data_dir, release_id):
    launcher = data_dir / "bin/flow-reader"
    launcher.parent.mkdir(parents=True, exist_ok=True)
    manage = data_dir / "releases" / release_id / "tools/flow-reader/manage.py"
    launcher.write_text(
        "#!/bin/sh\n"
        + installer.LAUNCHER_MARKER
        + f"export FLOW_READER_DATA_DIR={shlex.quote(str(data_dir.resolve()))}\n"
        + f"exec {shlex.quote(sys.executable)} {shlex.quote(str(manage))} \"$@\"\n"
    )
    launcher.chmod(0o755)
    return launcher


def _write_browser_compiler(directory, payload):
    directory.mkdir(parents=True, exist_ok=True)
    (directory / "compiler.js").write_text("export default () => {};\n")
    (directory / "compiler_bg.wasm").write_bytes(payload)
    files = {
        name: hashlib.sha256((directory / name).read_bytes()).hexdigest()
        for name in ("compiler.js", "compiler_bg.wasm")
    }
    manifest = {
        "schemaVersion": 1,
        "files": files,
        "engine": hashlib.sha256(json.dumps(files, sort_keys=True).encode()).hexdigest(),
    }
    (directory / "manifest.json").write_text(json.dumps(manifest))
    return directory


@unittest.skipUnless(sys.platform == "darwin", "Reader installation targets macOS")
class ReaderReleaseRetentionTests(unittest.TestCase):
    def _create_install_fixture(self, work, profile_ids=("one",)):
        source = work / "source"
        shutil.copytree(ROOT, source / "tools/flow-reader",
                        ignore=shutil.ignore_patterns("__pycache__"), symlinks=True)
        shutil.copytree(ROOT.parent / "reader-common", source / "tools/reader-common",
                        ignore=shutil.ignore_patterns("__pycache__"))
        marker = source / "tools/flow-reader/source.txt"
        marker.write_text("release-1")
        subprocess.run(["git", "init", "-q", str(source)], check=True)
        subprocess.run(["git", "-C", str(source), "add", "."], check=True)
        subprocess.run(["git", "-C", str(source), "-c", "user.name=Reader test", "-c",
                        "user.email=reader-test@example.invalid", "commit", "-qm", "r1"], check=True)
        project = work / "project"
        project.mkdir()
        (project / "main.typ").write_text("Fixture")
        (project / "packages").mkdir()
        parents = [
            {
                "id": pid,
                "name": f"Fixture {pid}",
                "root": str(project),
                "entry": "main.typ",
                "fonts": [],
                "packages": str(project / "packages"),
                "port": 25100 + idx,
                "publicURL": "",
                "label": f"com.example.reader-retention-{pid}",
            }
            for idx, pid in enumerate(profile_ids)
        ]
        flow = work / "flow-fixture"
        change_file = work / "configured Flow data" / "changes" / "fixture.json"
        flow.write_text(
            f"#!{sys.executable}\nimport json, sys\n"
            + f"profiles = {repr({'profiles': parents})}\n"
            + f"plan = {repr({'environment': {'TINYMIST_PREVIEW_CHANGE_FILE': str(change_file)}})}\n"
            + "print(json.dumps(plan if sys.argv[1] == '--launch-plan' else profiles))\n"
        )
        flow.chmod(0o755)
        engine = work / "source-history-engine"
        engine.write_text(f"#!{sys.executable}\nprint('--root ROOT --change-file PATH')\n")
        engine.chmod(0o755)
        return source, marker, flow, engine

    def _commit_marker(self, source, marker, text):
        marker.write_text(text)
        subprocess.run(["git", "-C", str(source), "add", str(marker.relative_to(source))], check=True)
        subprocess.run(["git", "-C", str(source), "-c", "user.name=Reader test", "-c",
                        "user.email=reader-test@example.invalid", "commit", "-qm", text], check=True)

    def _make_args(self, data, flow, engine, *, profile="one", port=25201, browser_compiler=None,
                   no_browser_compiler=False, start=False, no_prune=False):
        return argparse.Namespace(
            data=data,
            profile=profile,
            port=port,
            public_url="",
            development=True,
            flow_manager=flow,
            python=Path(sys.executable),
            compiler=Path(sys.executable),
            engine=engine,
            browser_compiler=browser_compiler,
            no_browser_compiler=no_browser_compiler,
            start=start,
            no_prune=no_prune,
        )

    def test_prune_keeps_active_and_one_rollback_without_and_with_browser_compiler(self):
        with tempfile.TemporaryDirectory(prefix="reader retention ") as temporary:
            work = Path(temporary)
            source, marker, flow, engine = self._create_install_fixture(work)
            data = work / "installed"
            releases = data / "releases"
            with patch.object(installer, "__file__", source / "tools/flow-reader/install.py"), \
                 patch.object(installer, "running_process_commands", return_value=[]):
                # Without browserCompiler: R1 -> R2 -> R3 keeps R3 + R2, prunes R1.
                r1 = installer.install(self._make_args(data, flow, engine))["release"]
                self.assertTrue((releases / r1).is_dir())
                self._commit_marker(source, marker, "release-2")
                r2 = installer.install(self._make_args(data, flow, engine))["release"]
                self.assertTrue((releases / r1).is_dir())
                self.assertTrue((releases / r2).is_dir())
                self.assertEqual(json.loads((data / installer.PREVIOUS_RELEASE_FILE).read_text())["release"], r1)

                self._commit_marker(source, marker, "release-3")
                r3 = installer.install(self._make_args(data, flow, engine))["release"]
                self.assertFalse((releases / r1).exists())
                self.assertTrue((releases / r2).is_dir())
                self.assertTrue((releases / r3).is_dir())

                # With browserCompiler: W1 -> W2 -> W3 keeps W3 + W2, prunes W1 and R2.
                w1_src = _write_browser_compiler(work / "wasm1", b"\x00asm\x01\x00\x00\x01")
                w2_src = _write_browser_compiler(work / "wasm2", b"\x00asm\x01\x00\x00\x02")
                w3_src = _write_browser_compiler(work / "wasm3", b"\x00asm\x01\x00\x00\x03")
                w1 = installer.install(self._make_args(data, flow, engine, browser_compiler=w1_src))["release"]
                self.assertFalse((releases / r2).exists())
                self.assertTrue((releases / r3).is_dir())
                self.assertTrue((releases / w1).is_dir())
                w2 = installer.install(self._make_args(data, flow, engine, browser_compiler=w2_src))["release"]
                self.assertFalse((releases / r3).exists())
                self.assertTrue((releases / w1).is_dir())
                self.assertTrue((releases / w2).is_dir())
                w3 = installer.install(self._make_args(data, flow, engine, browser_compiler=w3_src))["release"]
                self.assertFalse((releases / w1).exists())
                self.assertTrue((releases / w2).is_dir())
                self.assertTrue((releases / w3).is_dir())

                # Even if previous-release.json is absent, config.previous.json still protects w2.
                (data / installer.PREVIOUS_RELEASE_FILE).unlink()
                _write_managed_release(releases, "r-extra-stale")
                outcome = installer.prune_releases(data, process_commands=lambda: [])
                self.assertEqual(outcome["pruned"], ["r-extra-stale"])
                self.assertTrue((releases / w2).is_dir())
                self.assertTrue((releases / w3).is_dir())

    def test_two_service_same_release_install_without_no_prune_preserves_rollback(self):
        with tempfile.TemporaryDirectory(prefix="reader two-service ") as temporary:
            work = Path(temporary)
            source, marker, flow, engine = self._create_install_fixture(work, profile_ids=("one", "two"))
            data = work / "installed"
            releases = data / "releases"
            with patch.object(installer, "__file__", source / "tools/flow-reader/install.py"), \
                 patch.object(installer, "running_process_commands", return_value=[]):
                # Install R1 for both services (no browserCompiler).
                r1 = installer.install(self._make_args(data, flow, engine, profile="one", port=25201))["release"]
                installer.install(self._make_args(data, flow, engine, profile="two", port=25202))
                _write_managed_release(releases, "r-ancient")

                # Upgrade to R2 across 2 services WITHOUT --no-prune (simulating unmodified refresh-reader-engine.sh).
                self._commit_marker(source, marker, "release-2")
                r2_first = installer.install(self._make_args(data, flow, engine, profile="one", port=25201))["release"]
                self.assertFalse((releases / "r-ancient").exists())
                self.assertTrue((releases / r1).is_dir())
                self.assertTrue((releases / r2_first).is_dir())

                r2_second = installer.install(self._make_args(data, flow, engine, profile="two", port=25202))["release"]
                self.assertEqual(r2_first, r2_second)
                self.assertTrue((releases / r1).is_dir(), "Second same-release install must preserve R_old")
                self.assertTrue((releases / r2_second).is_dir())
                self.assertEqual(json.loads((data / installer.PREVIOUS_RELEASE_FILE).read_text())["release"], r1)

                # Subsequent upgrade to R3 prunes R1 while keeping R2 and R3.
                self._commit_marker(source, marker, "release-3")
                r3 = installer.install(self._make_args(data, flow, engine, profile="one", port=25201))["release"]
                self.assertFalse((releases / r1).exists())
                self.assertTrue((releases / r2_second).is_dir())
                self.assertTrue((releases / r3).is_dir())

                # Also verify seeding previous-release.json from config.previous.json on same-release re-install
                # when previous-release.json does not yet exist.
                w1_src = _write_browser_compiler(work / "wasm-seed", b"\x00asm\x01\x00\x00\x09")
                w1 = installer.install(self._make_args(data, flow, engine, profile="one", port=25201,
                                                       browser_compiler=w1_src))["release"]
                (data / installer.PREVIOUS_RELEASE_FILE).unlink()
                # Simulate config.previous.json pointing at r3 while active is w1.
                prev_cfg = json.loads((data / "config.previous.json").read_text())
                prev_cfg["browserCompiler"] = str(releases / r3 / "tools/flow-reader/compiler-assets")
                (data / "config.previous.json").write_text(json.dumps(prev_cfg))
                installer.install(self._make_args(data, flow, engine, profile="two", port=25202))
                self.assertTrue((releases / r3).is_dir())
                self.assertTrue((releases / w1).is_dir())
                self.assertEqual(json.loads((data / installer.PREVIOUS_RELEASE_FILE).read_text())["release"], r3)

    def test_historical_config_backup_does_not_pin_stale_release(self):
        with tempfile.TemporaryDirectory(prefix="reader historical ") as temporary:
            data = Path(temporary) / "reader"
            releases = data / "releases"
            _write_managed_release(releases, "r-active")
            _write_managed_release(releases, "r-prev")
            _write_managed_release(releases, "r-pre-refresh")
            _write_launcher(data, "r-active")
            (data / "config.json").write_text(json.dumps({"schemaVersion": 1, "services": []}))
            (data / installer.PREVIOUS_RELEASE_FILE).write_text(json.dumps({"schemaVersion": 1, "release": "r-prev"}))
            (data / "config.pre-engine-refresh.json").write_text(json.dumps({
                "schemaVersion": 1,
                "services": [],
                "browserCompiler": str(releases / "r-pre-refresh/tools/flow-reader/compiler-assets"),
            }))
            result = installer.prune_releases(data, process_commands=lambda: [])
            self.assertEqual(result["pruned"], ["r-pre-refresh"])
            self.assertFalse((releases / "r-pre-refresh").exists())
            self.assertTrue((releases / "r-active").is_dir())
            self.assertTrue((releases / "r-prev").is_dir())

    def test_install_failure_never_deletes_releases(self):
        with tempfile.TemporaryDirectory(prefix="reader fail-safe ") as temporary:
            work = Path(temporary)
            source, marker, flow, engine = self._create_install_fixture(work)
            data = work / "installed"
            releases = data / "releases"
            with patch.object(installer, "__file__", source / "tools/flow-reader/install.py"), \
                 patch.object(installer, "running_process_commands", return_value=[]):
                r1 = installer.install(self._make_args(data, flow, engine))["release"]
                obsolete = _write_managed_release(releases, "r-obsolete")

                # 1. Dirty commit failure.
                marker.write_text("dirty")
                with self.assertRaisesRegex(ValueError, "clean commit"):
                    installer.install(self._make_args(data, flow, engine))
                self.assertTrue(obsolete.is_dir())
                marker.write_text("release-1")

                # 2. Immutable release mismatch failure.
                installed_marker = releases / r1 / "tools/flow-reader/source.txt"
                installed_marker.write_text("tampered")
                with self.assertRaisesRegex(ValueError, "immutable release"):
                    installer.install(self._make_args(data, flow, engine))
                self.assertTrue(obsolete.is_dir())
                installed_marker.write_text("release-1")

                # 3. --launch-plan failure after swap.
                real_run = installer.run
                def fail_launch_plan(arguments, *a, **kw):
                    if "--launch-plan" in arguments:
                        raise ValueError("launch-plan failed")
                    return real_run(arguments, *a, **kw)
                with patch.object(installer, "run", side_effect=fail_launch_plan):
                    with self.assertRaisesRegex(ValueError, "launch-plan failed"):
                        installer.install(self._make_args(data, flow, engine))
                self.assertTrue(obsolete.is_dir())

                # 4. --start failure after --launch-plan.
                def fail_start(arguments, *a, **kw):
                    if "--control" in arguments:
                        raise ValueError("start failed")
                    return real_run(arguments, *a, **kw)
                with patch.object(installer, "run", side_effect=fail_start):
                    with self.assertRaisesRegex(ValueError, "start failed"):
                        installer.install(self._make_args(data, flow, engine, start=True))
                self.assertTrue(obsolete.is_dir())

    def test_running_process_protects_release_and_ps_failure_aborts_safely(self):
        with tempfile.TemporaryDirectory(prefix="reader live spaces ") as temporary:
            data = Path(temporary) / "Application Support" / "reader"
            releases = data / "releases"
            for name in ("r-active", "r-prev", "r-live-canonical", "r-live-raw", "r-stale"):
                _write_managed_release(releases, name)
            _write_launcher(data, "r-active")
            (data / "config.json").write_text(json.dumps({"schemaVersion": 1, "services": []}))
            (data / installer.PREVIOUS_RELEASE_FILE).write_text(json.dumps({"schemaVersion": 1, "release": "r-prev"}))

            # If ps inspection fails, abort safely without deleting anything.
            stderr = io.StringIO()
            with patch.object(sys, "stderr", stderr):
                aborted = installer.prune_releases(
                    data,
                    process_commands=lambda: (_ for _ in ()).throw(RuntimeError("ps unavailable")),
                )
            self.assertIn("skipped", aborted)
            self.assertEqual(aborted["pruned"], [])
            self.assertIn("ps unavailable", stderr.getvalue())
            self.assertTrue((releases / "r-stale").is_dir())

            # Running process command lines (with spaces in path) protect referenced releases.
            commands = [
                f"/usr/bin/python3 {releases.resolve()}/r-live-canonical/tools/flow-reader/serve.py --managed",
                f"/usr/bin/python3 {releases}/r-live-raw/tools/flow-reader/manage.py --serve one-reader",
            ]
            pruned = installer.prune_releases(data, process_commands=lambda: commands)
            self.assertEqual(pruned["pruned"], ["r-stale"])
            self.assertFalse((releases / "r-stale").exists())
            for kept in ("r-active", "r-prev", "r-live-canonical", "r-live-raw"):
                self.assertTrue((releases / kept).is_dir(), kept)

    def test_exclusions_symlinks_out_of_boundary_unmanaged_hidden_and_malformed_metadata(self):
        with tempfile.TemporaryDirectory(prefix="reader guards ") as temporary:
            root = Path(temporary)
            # 1. Symlink releases/ skips pruning safely and never touches target.
            external_releases = root / "external-releases"
            _write_managed_release(external_releases, "r-active")
            _write_managed_release(external_releases, "r-stale")
            symlink_data = root / "symlink-data"
            symlink_data.mkdir()
            (symlink_data / "releases").symlink_to(external_releases)
            _write_launcher(symlink_data, "r-active")
            (symlink_data / "config.json").write_text(json.dumps({"schemaVersion": 1, "services": []}))
            skipped = installer.prune_releases(symlink_data, process_commands=lambda: [])
            self.assertIn("skipped", skipped)
            self.assertTrue((external_releases / "r-stale").is_dir())

            # 2. Child exclusions: symlink child, unmanaged dir, regular file, hidden staging dir, out-of-boundary path.
            data = root / "reader"
            releases = data / "releases"
            _write_managed_release(releases, "r-active")
            _write_managed_release(releases, "r-stale")
            outside_target = _write_managed_release(root / "outside", "r-outside")
            (releases / "r-link").symlink_to(outside_target)
            _write_managed_release(releases, "unmanaged-dir", with_manifest=False)
            _write_managed_release(releases, ".install-staging", with_manifest=True)
            (releases / "stray-file.txt").write_text("keep")
            _write_launcher(data, "r-active")
            (data / "config.json").write_text(json.dumps({"schemaVersion": 1, "services": []}))

            # Out-of-boundary resolution guard verified directly even if entry is not a symlink.
            escaped_candidate = _write_managed_release(releases, "r-escape-test")
            real_resolve = Path.resolve
            def fake_resolve(path_self, *a, **kw):
                if path_self.name == "r-escape-test":
                    return outside_target.resolve()
                return real_resolve(path_self, *a, **kw)
            with patch.object(Path, "resolve", fake_resolve):
                result = installer.prune_releases(data, process_commands=lambda: [])
            self.assertEqual(result["pruned"], ["r-stale"])
            self.assertFalse((releases / "r-stale").exists())
            self.assertTrue((releases / "r-link").is_symlink())
            self.assertTrue(outside_target.is_dir())
            self.assertTrue(escaped_candidate.is_dir())
            self.assertTrue((releases / "unmanaged-dir").is_dir())
            self.assertTrue((releases / ".install-staging").is_dir())
            self.assertTrue((releases / "stray-file.txt").is_file())

            # 3. Malformed / missing active or rollback metadata aborts pruning safely.
            _write_managed_release(releases, "r-stale-2")
            malformed_cases = [
                ("config.json", "{not-json"),
                ("config.json", None),
                ("bin/flow-reader", "#!/bin/sh\necho unmanaged\n"),
                ("bin/flow-reader", "#!/bin/sh\n" + installer.LAUNCHER_MARKER + "exec '/unclosed\n"),
                ("bin/flow-reader", None),
                ("config.previous.json", "{bad-json"),
                (installer.PREVIOUS_RELEASE_FILE, "{}"),
                (installer.PREVIOUS_RELEASE_FILE, json.dumps({"schemaVersion": 1, "release": None})),
                (installer.PREVIOUS_RELEASE_FILE, json.dumps({"release": "../escape"})),
            ]
            saved_config = (data / "config.json").read_bytes()
            saved_launcher = (data / "bin/flow-reader").read_bytes()
            for rel_path, content in malformed_cases:
                target = data / rel_path
                if content is None:
                    target.unlink()
                else:
                    target.write_text(content)
                stderr = io.StringIO()
                with patch.object(sys, "stderr", stderr):
                    outcome = installer.prune_releases(data, process_commands=lambda: [])
                self.assertIn("skipped", outcome, rel_path)
                self.assertEqual(outcome["pruned"], [], rel_path)
                self.assertTrue((releases / "r-stale-2").is_dir(), rel_path)
                self.assertIn("Warning: skipping Reader release pruning", stderr.getvalue())
                # Restore clean files before next case.
                (data / "config.json").write_bytes(saved_config)
                (data / "bin/flow-reader").write_bytes(saved_launcher)
                (data / "config.previous.json").unlink(missing_ok=True)
                (data / installer.PREVIOUS_RELEASE_FILE).unlink(missing_ok=True)

    def test_nonfatal_oserror_during_prune_warns_and_does_not_fail_install(self):
        with tempfile.TemporaryDirectory(prefix="reader oserror ") as temporary:
            work = Path(temporary)
            source, _, flow, engine = self._create_install_fixture(work)
            data = work / "installed"
            releases = data / "releases"
            err_dir = _write_managed_release(releases, "r-err-1")
            ok_dir = _write_managed_release(releases, "r-ok-2")
            real_rmtree = shutil.rmtree
            def flaky_rmtree(path, *a, **kw):
                if Path(path).name == "r-err-1":
                    raise PermissionError("busy directory")
                return real_rmtree(path, *a, **kw)
            stderr = io.StringIO()
            with patch.object(installer, "__file__", source / "tools/flow-reader/install.py"), \
                 patch.object(installer, "running_process_commands", return_value=[]), \
                 patch.object(installer.shutil, "rmtree", side_effect=flaky_rmtree), \
                 patch.object(sys, "stderr", stderr):
                result = installer.install(self._make_args(data, flow, engine))
            self.assertIn("release", result)
            self.assertTrue((releases / result["release"]).is_dir())
            self.assertTrue(err_dir.is_dir())
            self.assertFalse(ok_dir.exists())
            self.assertIn("r-err-1", stderr.getvalue())
            self.assertIn("busy directory", stderr.getvalue())

    def test_no_prune_defers_and_prune_only_cli_prunes_cleanly(self):
        with tempfile.TemporaryDirectory(prefix="reader cli-prune ") as temporary:
            work = Path(temporary)
            source, _, flow, engine = self._create_install_fixture(work)
            data = work / "installed"
            releases = data / "releases"
            stale = _write_managed_release(releases, "r-deferred-stale")
            with patch.object(installer, "__file__", source / "tools/flow-reader/install.py"), \
                 patch.object(installer, "running_process_commands", return_value=[]):
                installed = installer.install(self._make_args(data, flow, engine, no_prune=True))
                self.assertTrue(stale.is_dir(), "--no-prune must defer pruning")

                stdout = io.StringIO()
                with patch.object(sys, "stdout", stdout):
                    installer.main(["--prune-only", "--data", str(data)])
                summary = json.loads(stdout.getvalue())
                self.assertEqual(summary["pruned"], ["r-deferred-stale"])
                self.assertIn(installed["release"], summary["kept"])
                self.assertFalse(stale.exists())

            # CLI validation preserves required --profile/--port and rejects conflicting flags.
            with patch.object(sys, "stderr", io.StringIO()):
                with self.assertRaises(SystemExit) as missing:
                    installer.main([])
                self.assertEqual(missing.exception.code, 2)
                with self.assertRaises(SystemExit) as conflict:
                    installer.main(["--prune-only", "--profile", "one"])
                self.assertEqual(conflict.exception.code, 2)

    def test_prune_releases_honors_env_data_dir_and_tilde_expansion(self):
        with tempfile.TemporaryDirectory(prefix="reader env-tilde ") as temporary:
            work = Path(temporary)
            # 1. FLOW_READER_DATA_DIR used when prune_releases() is called with no arguments
            # (for pruning, ps matching, and symlink guard), leaving DEFAULT_DATA untouched.
            default_data = work / "default-data"
            default_stale = _write_managed_release(default_data / "releases", "r-default-stale")
            _write_launcher(default_data, "r-default-active")
            _write_managed_release(default_data / "releases", "r-default-active")
            (default_data / "config.json").write_text(json.dumps({"schemaVersion": 1, "services": []}))

            env_data = work / "env-data"
            env_releases = env_data / "releases"
            for name in ("r-active", "r-prev", "r-live", "r-stale"):
                _write_managed_release(env_releases, name)
            _write_launcher(env_data, "r-active")
            (env_data / "config.json").write_text(json.dumps({"schemaVersion": 1, "services": []}))
            (env_data / installer.PREVIOUS_RELEASE_FILE).write_text(json.dumps({"schemaVersion": 1, "release": "r-prev"}))

            with patch.object(installer, "DEFAULT_DATA", default_data), \
                 patch.dict(os.environ, {"FLOW_READER_DATA_DIR": str(env_data)}):
                result = installer.prune_releases(
                    process_commands=lambda: [f"python3 {env_releases}/r-live/tools/flow-reader/serve.py"]
                )
            self.assertEqual(result["pruned"], ["r-stale"])
            self.assertFalse((env_releases / "r-stale").exists())
            for kept in ("r-active", "r-prev", "r-live"):
                self.assertTrue((env_releases / kept).is_dir(), kept)
            self.assertTrue(default_stale.is_dir(), "DEFAULT_DATA must remain untouched")

            # Symlink guard applies to FLOW_READER_DATA_DIR/releases, not DEFAULT_DATA/releases.
            external_releases = work / "external-env-releases"
            _write_managed_release(external_releases, "r-active")
            _write_managed_release(external_releases, "r-ext-stale")
            sym_env_data = work / "sym-env-data"
            sym_env_data.mkdir()
            (sym_env_data / "releases").symlink_to(external_releases)
            _write_launcher(sym_env_data, "r-active")
            (sym_env_data / "config.json").write_text(json.dumps({"schemaVersion": 1, "services": []}))
            with patch.object(installer, "DEFAULT_DATA", default_data), \
                 patch.dict(os.environ, {"FLOW_READER_DATA_DIR": str(sym_env_data)}):
                skipped = installer.prune_releases(process_commands=lambda: [])
            self.assertIn("skipped", skipped)
            self.assertTrue((external_releases / "r-ext-stale").is_dir())

            # 2. Passing a ~/... tilde path expands consistently across raw_data and ReaderManager.
            fake_home = work / "fake-home"
            tilde_data = fake_home / "reader-tilde"
            tilde_releases = tilde_data / "releases"
            for name in ("r-active", "r-live", "r-stale"):
                _write_managed_release(tilde_releases, name)
            _write_launcher(tilde_data, "r-active")
            (tilde_data / "config.json").write_text(json.dumps({"schemaVersion": 1, "services": []}))

            with patch.dict(os.environ, {"HOME": str(fake_home)}), \
                 patch.object(installer, "DEFAULT_DATA", default_data):
                res_tilde = installer.prune_releases(
                    "~/reader-tilde",
                    process_commands=lambda: [f"python3 {tilde_releases}/r-live/tools/flow-reader/serve.py"],
                )
            self.assertEqual(res_tilde["pruned"], ["r-stale"])
            self.assertFalse((tilde_releases / "r-stale").exists())
            self.assertTrue((tilde_releases / "r-active").is_dir())
            self.assertTrue((tilde_releases / "r-live").is_dir())

            # Tilde symlink guard also expands cleanly before checking is_symlink().
            sym_tilde_data = fake_home / "sym-reader-tilde"
            sym_tilde_data.mkdir()
            (sym_tilde_data / "releases").symlink_to(external_releases)
            _write_launcher(sym_tilde_data, "r-active")
            (sym_tilde_data / "config.json").write_text(json.dumps({"schemaVersion": 1, "services": []}))
            with patch.dict(os.environ, {"HOME": str(fake_home)}):
                skipped_tilde = installer.prune_releases("~/sym-reader-tilde", process_commands=lambda: [])
            self.assertIn("skipped", skipped_tilde)
            self.assertTrue((external_releases / "r-ext-stale").is_dir())

    def test_per_entry_inspect_oserror_warns_and_continues(self):
        with tempfile.TemporaryDirectory(prefix="reader inspect-oserror ") as temporary:
            data = Path(temporary) / "reader"
            releases = data / "releases"
            _write_managed_release(releases, "r-active")
            err_dir = _write_managed_release(releases, "r-err-inspect")
            ok_dir = _write_managed_release(releases, "r-ok-prune")
            _write_launcher(data, "r-active")
            (data / "config.json").write_text(json.dumps({"schemaVersion": 1, "services": []}))

            real_is_prunable = installer._is_prunable_release
            def flaky_is_prunable(entry, releases_resolved):
                if entry.name == "r-err-inspect":
                    raise PermissionError("cannot stat entry")
                return real_is_prunable(entry, releases_resolved)

            stderr = io.StringIO()
            with patch.object(installer, "_is_prunable_release", side_effect=flaky_is_prunable), \
                 patch.object(sys, "stderr", stderr):
                result = installer.prune_releases(data, process_commands=lambda: [])
            self.assertEqual(result["pruned"], ["r-ok-prune"])
            self.assertFalse(ok_dir.exists())
            self.assertTrue(err_dir.is_dir())
            self.assertIn("r-err-inspect", stderr.getvalue())
            self.assertIn("cannot stat entry", stderr.getvalue())
            self.assertEqual(len(result.get("errors", [])), 1)

    def test_install_rejects_symlink_or_non_dict_config_cleanly(self):
        with tempfile.TemporaryDirectory(prefix="reader bad-config ") as temporary:
            work = Path(temporary)
            source, _, flow, engine = self._create_install_fixture(work)
            data = work / "installed"
            data.mkdir()
            config_path = data / "config.json"

            with patch.object(installer, "__file__", source / "tools/flow-reader/install.py"):
                # Non-dict JSON config.json must raise ValueError, not AttributeError.
                config_path.write_text("[]")
                with self.assertRaisesRegex(ValueError, "JSON object"):
                    installer.install(self._make_args(data, flow, engine))

                # Symlinked config.json must be rejected cleanly with ValueError.
                config_path.unlink()
                real_cfg = work / "other-config.json"
                real_cfg.write_text(json.dumps({"schemaVersion": 1, "services": []}))
                config_path.symlink_to(real_cfg)
                with self.assertRaisesRegex(ValueError, "Invalid Reader configuration path"):
                    installer.install(self._make_args(data, flow, engine))

    def test_running_process_commands_error_paths_raise_runtime_error(self):
        with patch.object(
            installer.subprocess,
            "run",
            return_value=subprocess.CompletedProcess(["ps"], 1, stdout="", stderr="ps denied"),
        ):
            with self.assertRaisesRegex(RuntimeError, "ps denied"):
                installer.running_process_commands()

        with patch.object(
            installer.subprocess,
            "run",
            side_effect=subprocess.TimeoutExpired(["ps"], 10),
        ):
            with self.assertRaisesRegex(RuntimeError, "Could not inspect running processes"):
                installer.running_process_commands()

        with patch.object(
            installer.subprocess,
            "run",
            side_effect=OSError("ps missing"),
        ):
            with self.assertRaisesRegex(RuntimeError, "ps missing"):
                installer.running_process_commands()


if __name__ == "__main__":
    unittest.main()
