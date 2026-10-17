"""Reader lifecycle must reuse Flow inputs without taking over paged jobs."""

import json
from pathlib import Path
import plistlib
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from manage import ReaderManager


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
        with patch("manage.run", return_value=json.dumps({"profiles": [self.parent]})):
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

    def test_launch_plan_has_reader_only_arguments_and_inherited_fonts(self):
        profile = self.resolve()
        arguments = self.manager.arguments(profile)
        self.assertEqual(arguments[arguments.index("--root") + 1], self.parent["root"])
        self.assertEqual(arguments[arguments.index("--font-path") + 1], "fonts")
        self.assertEqual(arguments[arguments.index("--original-url") + 1], self.parent["publicURL"])
        self.assertNotIn("--allow-incomplete", arguments)
        agent = self.manager.agent(profile)
        self.assertTrue(agent["KeepAlive"])
        self.assertEqual(agent["ProgramArguments"], [str(self.manager.launcher), "--serve", "parent-reader"])
        self.assertNotEqual(agent["Label"], self.parent["label"])

    def test_unrelated_port_owner_cannot_be_stopped_or_replaced(self):
        profile = self.resolve()
        with patch.object(self.manager, "job_pid", return_value=None), patch("manage.run", return_value="123\n") as command:
            with self.assertRaisesRegex(ValueError, "Another process"):
                self.manager.control("start", profile)
            self.assertEqual(command.call_count, 1)
            self.assertEqual(command.call_args.args[0][0], "/usr/sbin/lsof")
        self.assertFalse(self.manager.agents.exists())

    def test_reader_will_not_take_over_an_unrelated_launch_agent(self):
        profile = self.resolve()
        self.manager.agents.mkdir()
        (self.manager.agents / (profile["label"] + ".plist")).write_bytes(plistlib.dumps({"ProgramArguments": ["/usr/bin/true"]}))
        with patch.object(self.manager, "job_pid", return_value=123), patch("manage.run") as command:
            with self.assertRaisesRegex(ValueError, "does not own"):
                self.manager.control("stop", profile)
            command.assert_not_called()


if __name__ == "__main__":
    unittest.main()
