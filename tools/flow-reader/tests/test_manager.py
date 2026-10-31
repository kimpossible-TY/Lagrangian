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
from flow_reader.services.manager import (
    LEGACY_LABEL_PREFIX,
    LABEL_PREFIX,
    ReaderManager,
    main,
)
from flow_reader.compiler.project import document_identity


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

    def test_document_resolution_is_exact_canonical_and_refuses_ambiguity(self):
        profile = self.resolve()
        root = Path(profile['root'])
        alias = self.root / 'project-alias'
        alias.symlink_to(root, target_is_directory=True)
        with patch.object(self.manager, 'profiles', return_value=[profile]):
            self.assertEqual(self.manager.match_document(alias, root / 'main.typ'), profile)
            for entry in ('other.typ', '../outside.typ'):
                with self.assertRaises(ValueError):
                    self.manager.match_document(root, entry)
            with self.assertRaisesRegex(ValueError, 'No managed'):
                self.manager.match_document(root, 'main.typ', 'other-reader')
        second = {**profile, 'id': 'second-reader'}
        with patch.object(self.manager, 'profiles', return_value=[profile, second]):
            with self.assertRaisesRegex(ValueError, 'Multiple'):
                self.manager.match_document(root, 'main.typ')
            self.assertEqual(self.manager.match_document(root, 'main.typ', second['id']), second)

    def attachment_state(self, profile):
        return {'service': {'pid': os.getpid(), 'startedAt': 12345}, 'editorAttachments': 1,
                'documentID': document_identity(profile['root'], profile['entry'])}

    def test_running_html_service_is_reused_without_launch_or_compile_settings(self):
        profile = self.resolve()
        state = self.attachment_state(profile)
        with patch.object(self.manager, 'match_document', return_value=profile), \
                patch.object(self.manager, 'job_pid', return_value=os.getpid()), \
                patch.object(self.manager, 'request', return_value=state), \
                patch.object(self.manager, 'control') as control, \
                patch.object(self.manager, 'arguments') as arguments:
            first = self.manager.attach(profile['root'], profile['entry'])
            self.assertEqual(first, self.manager.attach(profile['root'], profile['entry']))
            self.assertEqual(first['url'], 'http://127.0.0.1:24002/')
            self.assertEqual(first['service'], state['service'])
            control.assert_not_called()
            arguments.assert_not_called()

    def test_stopped_service_starts_only_through_its_normal_manager(self):
        profile = self.resolve()
        with patch.object(self.manager, 'match_document', return_value=profile), \
                patch.object(self.manager, 'job_pid', side_effect=[None, os.getpid()]), \
                patch.object(self.manager, 'request', return_value=self.attachment_state(profile)), \
                patch.object(self.manager, 'control') as control:
            self.manager.attach(profile['root'], profile['entry'])
            control.assert_called_once_with('start', profile)

    def test_attachment_rejects_wrong_process_document_or_old_protocol_without_fallback(self):
        profile = self.resolve()
        valid = self.attachment_state(profile)
        for state in ({**valid, 'documentID': 'wrong'},
                      {**valid, 'service': {**valid['service'], 'pid': os.getpid() + 1}},
                      {**valid, 'editorAttachments': None}):
            with patch.object(self.manager, 'match_document', return_value=profile), \
                    patch.object(self.manager, 'job_pid', return_value=os.getpid()), \
                    patch.object(self.manager, 'request', return_value=state), \
                    patch.object(self.manager, 'control') as control:
                with self.assertRaisesRegex(ValueError, 'match|upgrade'):
                    self.manager.attach(profile['root'], profile['entry'], editor_server='editor',
                                        nvim=sys.executable, owner_pid=os.getpid())
                control.assert_not_called()
        self.assertFalse((self.manager.data / 'documents').exists())

    def test_editor_attachment_is_confirmed_and_removed_on_handshake_failure(self):
        profile = self.resolve()
        state = self.attachment_state(profile)
        with patch.object(self.manager, 'match_document', return_value=profile), \
                patch.object(self.manager, 'job_pid', return_value=os.getpid()), \
                patch.object(self.manager, 'request', side_effect=[state, {'connected': True}]):
            plan = self.manager.attach(profile['root'], profile['entry'], editor_server='editor',
                                       nvim=sys.executable, owner_pid=os.getpid())
        path = Path(plan['attachmentFile'])
        self.assertTrue(path.is_file())
        self.assertEqual(json.loads(path.read_text())['service'], state['service'])
        path.unlink()
        with patch.object(self.manager, 'match_document', return_value=profile), \
                patch.object(self.manager, 'job_pid', return_value=os.getpid()), \
                patch.object(self.manager, 'request', side_effect=[state, {'connected': False}]):
            with self.assertRaisesRegex(ValueError, 'rejected'):
                self.manager.attach(profile['root'], profile['entry'], editor_server='editor',
                                    nvim=sys.executable, owner_pid=os.getpid())
        self.assertEqual(list(path.parent.iterdir()), [])

    def test_parent_launch_plan_pins_custom_record_independent_of_child_environment(self):
        data = self.root / 'custom Flow data'
        data.mkdir()
        alias = self.root / 'flow-data-alias'
        alias.symlink_to(data, target_is_directory=True)
        path = alias / 'changes' / 'parent.json'
        self.config['services'].append({'id': 'second-reader', 'parentID': 'parent', 'port': 24003})
        self.save()
        def dispatch(arguments):
            if arguments[1:] == ['--profiles']:
                return json.dumps({'profiles': [self.parent]})
            self.assertEqual(arguments[1:], ['--launch-plan', 'parent'])
            return json.dumps({'environment': {'TINYMIST_PREVIEW_CHANGE_FILE': str(path)}})
        with patch.dict(os.environ, {'FLOW_DATA_DIR': str(self.root / 'unrelated ambient data')}), \
                patch('flow_reader.services.manager.run', side_effect=dispatch) as command:
            profiles = self.manager.profiles()
        self.assertEqual(command.call_count, 2)
        for profile in profiles:
            self.assertEqual(profile['changeFile'], str(path.resolve()))
            arguments = self.manager.arguments(profile)
            self.assertEqual(arguments[arguments.index('--change-file') + 1], str(path.resolve()))
        self.assertNotIn('changeFile', self.config['services'][0])

    def test_parent_launch_plan_rejects_invalid_explicit_record_paths(self):
        for path in ('relative.json', '', None, []):
            responses = [json.dumps({'profiles': [self.parent]}),
                         json.dumps({'environment': {'TINYMIST_PREVIEW_CHANGE_FILE': path}})]
            with self.subTest(path=path), patch('flow_reader.services.manager.run', side_effect=responses):
                with self.assertRaisesRegex(ValueError, 'changeFile must be absolute'):
                    self.manager.profiles()

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
        self.assertEqual(agent["AssociatedBundleIdentifiers"], ["io.github.kimpossible-ty.lagrangian"])

    def test_reader_label_uses_new_identity_unless_legacy_job_exists(self):
        profile = self.resolve()
        self.assertEqual(profile["label"], LABEL_PREFIX + "parent-reader")
        legacy_job = self.manager.agents / (LEGACY_LABEL_PREFIX + "parent-reader.plist")
        legacy_job.parent.mkdir(parents=True, exist_ok=True)
        legacy_job.touch()
        self.assertEqual(self.resolve()["label"], LEGACY_LABEL_PREFIX + "parent-reader")

    def test_native_figure_setting_is_reader_only_and_boolean(self):
        self.config["services"][0]["semanticCanvases"] = True
        self.save()
        self.assertIn("--semantic-canvases", self.manager.arguments(self.resolve()))
        self.assertNotIn("semanticCanvases", self.parent)
        self.config["services"][0]["semanticCanvases"] = "true"
        self.save()
        with self.assertRaisesRegex(ValueError, "boolean"):
            self.resolve()

    def test_additional_fonts_are_reader_only_validated_and_preserve_inheritance(self):
        font = self.root / "Arial fixture.ttf"
        font.write_bytes(b"fixture")
        self.config["services"][0]["extraFonts"] = [str(font), "fonts"]
        self.save()
        profile = self.resolve()
        self.assertEqual(profile["fonts"], ["fonts", str(font)])
        self.assertEqual(self.parent["fonts"], ["fonts"])
        arguments = self.manager.arguments(profile)
        self.assertEqual([arguments[i + 1] for i, value in enumerate(arguments) if value == "--font-path"],
                         ["fonts", str(font)])
        font.unlink()
        with self.assertRaisesRegex(ValueError, "font directory is missing"):
            self.manager.arguments(profile)
        for invalid in ("fonts", [None], [""], [" "], ["fonts"] * 33):
            self.config["services"][0]["extraFonts"] = invalid
            self.save()
            with self.assertRaisesRegex(ValueError, "extraFonts"):
                self.resolve()

    def test_explicit_engine_and_flow_sibling_reach_the_owned_reader(self):
        profile = self.resolve()
        self.config['engine'] = sys.executable
        self.save()
        arguments = self.manager.arguments(profile)
        self.assertEqual(arguments[arguments.index('--engine') + 1], sys.executable)
        del self.config['engine']
        flow = self.root / 'app' / 'Lagrangian'
        flow.parent.mkdir()
        flow.write_text('fixture')
        flow.chmod(0o755)
        sibling = flow.with_name('flow-engine')
        sibling.write_text('fixture')
        sibling.chmod(0o755)
        self.config['flowManager'] = str(flow)
        self.save()
        arguments = self.manager.arguments(profile)
        self.assertEqual(arguments[arguments.index('--engine') + 1], str(sibling))
        with patch.dict(os.environ, {'FLOW_ENGINE_PATH': sys.executable}):
            arguments = self.manager.arguments(profile)
            self.assertEqual(arguments[arguments.index('--engine') + 1], sys.executable)
        self.config['engine'] = str(self.root / 'missing-engine')
        self.save()
        with self.assertRaisesRegex(ValueError, 'Missing executable: engine'):
            self.manager.arguments(profile)

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

    def test_reader_owns_agent_across_compatibility_symlink_but_rejects_other_reader(self):
        profile = self.resolve()
        self.manager.agents.mkdir(exist_ok=True)
        (self.manager.launcher.parent).mkdir(parents=True, exist_ok=True)
        self.manager.launcher.write_text("#!/bin/sh\n")
        self.manager.launcher.chmod(0o755)
        legacy_root = self.root / "legacy-reader"
        legacy_root.symlink_to(self.manager.data, target_is_directory=True)
        plist_path = self.manager.agents / (profile["label"] + ".plist")
        plist_path.write_bytes(plistlib.dumps({
            "Label": profile["label"],
            "ProgramArguments": [str(legacy_root / "bin/flow-reader"), "--serve", profile["id"]],
        }))
        self.assertTrue(self.manager.owns_agent(profile))
        with patch.object(self.manager, "job_pid", return_value=123), \
                patch("flow_reader.services.manager.run", return_value=""):
            self.manager.control("restart", profile)
        self.assertEqual(
            plistlib.loads(plist_path.read_bytes())["ProgramArguments"],
            [str(self.manager.launcher), "--serve", profile["id"]],
        )
        separate_root = self.root / "separate-reader/bin"
        separate_root.mkdir(parents=True)
        separate_launcher = separate_root / "flow-reader"
        separate_launcher.write_text("#!/bin/sh\n")
        plist_path.write_bytes(plistlib.dumps({
            "Label": profile["label"],
            "ProgramArguments": [str(separate_launcher), "--serve", profile["id"]],
        }))
        self.assertFalse(self.manager.owns_agent(profile))

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
