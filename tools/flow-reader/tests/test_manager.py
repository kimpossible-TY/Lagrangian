"""Reader lifecycle must reuse Flow inputs without taking over paged jobs."""

import json
import io
from contextlib import redirect_stdout
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from flow_reader.services.manager import ReaderManager, main


class ReaderManagerTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        project = self.root / "project with spaces"
        project.mkdir()
        (project / "main.typ").write_text("A document")
        (project / "fonts").mkdir()
        packages = self.root / "packages"
        packages.mkdir()
        self.parent = {"id": "parent", "name": "My document", "root": str(project), "entry": "main.typ",
                       "fonts": ["fonts"], "packages": str(packages), "port": 24001,
                       "publicURL": "https://example.ts.net:24001/", "label": "com.example.original"}
        self.manager = ReaderManager(self.root / "reader", self.root / "agents")
        self.manager.data.mkdir()
        self.config = {"schemaVersion": 1, "flowManager": sys.executable, "python": sys.executable,
                       "compiler": sys.executable, "services": [{"id": "parent-reader", "parentID": "parent",
                       "port": 24002, "publicURL": "https://example.ts.net:24002/"}]}
        self.save()

    def save(self):
        (self.manager.data / "config.json").write_text(json.dumps(self.config))

    def resolve(self):
        with patch("flow_reader.services.manager.run", return_value=json.dumps({"profiles": [self.parent]})):
            return self.manager.profiles()[0]

    def test_parent_settings_are_resolved_afresh_and_paged_identity_is_preserved(self):
        first = self.resolve()
        self.assertEqual(first["originalURL"], self.parent["publicURL"])
        self.assertEqual(first["root"], self.parent["root"])
        self.assertNotEqual(first["label"], self.parent["label"])
        self.parent["entry"] = "changed.typ"
        second = self.resolve()
        self.assertEqual(second["entry"], "changed.typ")
        self.assertNotIn("root", self.config["services"][0])

    def test_reader_port_cannot_reuse_any_parent_port(self):
        self.config["services"][0]["port"] = self.parent["port"]
        self.save()
        with self.assertRaisesRegex(ValueError, "port conflicts"):
            self.resolve()

    def test_reader_focus_file_is_separate_from_parent_and_reaches_launch_plan(self):
        self.parent["focusFile"] = str(self.root / "paged-focus.json")
        profile = self.resolve()
        self.assertNotEqual(profile["focusFile"], self.parent["focusFile"])
        arguments = self.manager.arguments(profile)
        self.assertEqual(arguments[arguments.index("--focus-file") + 1], profile["focusFile"])
        for invalid in (self.parent["focusFile"], "relative.json"):
            self.config["services"][0]["focusFile"] = invalid
            self.save()
            with self.assertRaisesRegex(ValueError, "focusFile"):
                self.resolve()

    def test_focus_command_uses_live_pid_and_configured_document(self):
        profile = self.resolve()
        with patch("flow_reader.services.manager.ReaderManager", return_value=self.manager), \
                patch.object(self.manager, "profile", return_value=profile), \
                patch.object(self.manager, "job_pid", return_value=123), \
                patch("flow_reader.services.codex_context.read_reader", return_value={"selection_usable": True}) as read, \
                redirect_stdout(io.StringIO()) as output:
            main(["--focus", profile["id"]])
        self.assertTrue(json.loads(output.getvalue())["selection_usable"])
        read.assert_called_once_with("http://127.0.0.1:24002/", expected_pid=123,
                                     project=profile["root"],
                                     document=Path(profile["root"]) / profile["entry"])

    def test_launch_plan_has_reader_only_arguments_and_inherited_fonts(self):
        profile = self.resolve()
        arguments = self.manager.arguments(profile)
        self.assertEqual(arguments[arguments.index("--root") + 1], self.parent["root"])
        self.assertEqual(arguments[arguments.index("--font-path") + 1], "fonts")
        self.assertEqual(arguments[arguments.index("--original-url") + 1], self.parent["publicURL"])
        self.assertNotIn("--allow-incomplete", arguments)
        self.assertNotIn("--semantic-canvases", arguments)
        agent = self.manager.agent(profile)
        self.assertTrue(agent["KeepAlive"])
        self.assertEqual(agent["ProgramArguments"], [str(self.manager.launcher), "--serve", "parent-reader"])
        self.assertNotEqual(agent["Label"], self.parent["label"])

    def test_native_figure_setting_is_reader_only_and_boolean(self):
        self.config["services"][0]["semanticCanvases"] = True
        self.save()
        self.assertIn("--semantic-canvases", self.manager.arguments(self.resolve()))
        self.assertNotIn("semanticCanvases", self.parent)
        self.config["services"][0]["semanticCanvases"] = "true"
        self.save()
        with self.assertRaisesRegex(ValueError, "boolean"):
            self.resolve()

    def test_unrelated_port_owner_cannot_be_stopped_or_replaced(self):
        profile = self.resolve()
        with patch.object(self.manager, "job_pid", return_value=None), patch("flow_reader.services.manager.run", return_value="123\n") as command:
            with self.assertRaisesRegex(ValueError, "Another process"):
                self.manager.control("start", profile)
            self.assertEqual(command.call_count, 1)
            self.assertEqual(command.call_args.args[0][0], "/usr/sbin/lsof")
        self.assertFalse(self.manager.agents.exists())

    def test_reader_will_not_take_over_an_unrelated_launch_agent(self):
        profile = self.resolve()
        self.manager.agents.mkdir()
        (self.manager.agents / (profile["label"] + ".plist")).write_bytes(plistlib.dumps({"ProgramArguments": ["/usr/bin/true"]}))
        with patch.object(self.manager, "job_pid", return_value=123), patch("flow_reader.services.manager.run") as command:
            with self.assertRaisesRegex(ValueError, "does not own"):
                self.manager.control("stop", profile)
            command.assert_not_called()

    def test_stop_waits_for_launchd_to_remove_the_terminating_job(self):
        profile = self.resolve()
        target = f"gui/{os.getuid()}/{profile['label']}"
        with patch.object(self.manager, "job_pid", return_value=123), \
                patch.object(self.manager, "owns_agent", return_value=True), \
                patch("flow_reader.services.manager.run", side_effect=["", "", "state = terminating", "pid = 123", ""]) as command, \
                patch("flow_reader.services.manager.time.sleep") as sleep:
            self.manager.control("stop", profile)
        self.assertEqual([call.args[0][1] for call in command.call_args_list],
                         ["disable", "bootout", "print", "print", "print"])
        self.assertEqual(command.call_args.args[0][-1], target)
        self.assertEqual(sleep.call_count, 2)

    def test_a_stuck_stop_is_reported_without_restarting_or_signalling_other_processes(self):
        profile = self.resolve()
        with patch.object(self.manager, "job_pid", return_value=123), \
                patch.object(self.manager, "owns_agent", return_value=True), \
                patch("flow_reader.services.manager.run", return_value="state = terminating") as command, \
                patch("flow_reader.services.manager.time.monotonic", side_effect=[0, 11]):
            with self.assertRaisesRegex(ValueError, "finished stopping"):
                self.manager.control("stop", profile)
        self.assertEqual([call.args[0][1] for call in command.call_args_list],
                         ["disable", "bootout", "print"])


class ReaderCommandTests(unittest.TestCase):
    def test_launcher_reports_invalid_arguments_and_missing_configuration_without_traceback(self):
        with tempfile.TemporaryDirectory() as temporary:
            environment = {**os.environ, "FLOW_READER_DATA_DIR": temporary,
                           "PYTHONDONTWRITEBYTECODE": "1"}
            for arguments, message in (([], "Commands:"), (["--profiles"], "config.json")):
                with self.subTest(arguments=arguments):
                    result = subprocess.run([sys.executable, str(ROOT / "manage.py"), *arguments],
                                            cwd=temporary, env=environment, text=True,
                                            capture_output=True, check=False)
                    self.assertEqual(result.returncode, 1)
                    self.assertEqual(result.stdout, "")
                    self.assertIn(message, result.stderr)
                    self.assertNotIn("Traceback", result.stderr)
                    self.assertEqual(len(result.stderr.splitlines()), 1)


if __name__ == "__main__":
    unittest.main()
