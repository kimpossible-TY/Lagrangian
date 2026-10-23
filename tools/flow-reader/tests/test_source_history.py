"""Thin engine-client contracts and actual HTML-only shared source history."""

import json
import os
from dataclasses import replace
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from flow_reader.compiler.project import Project
from flow_reader.services.source_history import SourceHistoryClient, resolve_engine, source_snapshots
from flow_reader.services.edit_location import SharedEditLocation
from flow_reader.server.state import ReaderState


class CompletedHelper:
    """Completed transport fixture; communicate retains the real client protocol."""

    def __init__(self, result, communication=None):
        self.returncode = result.returncode
        self.output = result.stdout, result.stderr
        self.communication = communication

    def communicate(self, payload=None, timeout=None):
        if self.communication is not None:
            self.communication.update(input=payload, timeout=timeout)
        return self.output


class SourceHistoryClientTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        self.entry = self.root / "main.typ"
        self.entry.write_bytes('한글 original.\r\n'.encode())
        self.project = Project(self.root, Path("main.typ"), self.root / "packages")
        self.record = self.root / "common.json"
        self.responses = []

    def run_engine(self, arguments, **kwargs):
        communication = {}
        self.responses.append((arguments, communication))
        output = '--root ROOT --change-file PATH' if arguments[-1] == '--help' else json.dumps({
            'path': str(self.record), 'sequence': 0})
        return CompletedHelper(subprocess.CompletedProcess(arguments, 0, output, ''), communication)

    def test_command_passes_identity_exact_snapshots_and_observe_only_transactions(self):
        with patch('flow_reader.services.source_history.subprocess.Popen', side_effect=self.run_engine):
            client = SourceHistoryClient(self.project, engine=sys.executable, change_file=self.record)
            client.seed(source_snapshots(self.project, []))
            client.observe()
        self.assertEqual(len(self.responses), 4)
        for arguments, options in self.responses[1:]:
            self.assertEqual(arguments[arguments.index('--root') + 1], str(self.root))
            self.assertEqual(arguments[arguments.index('--entry') + 1], 'main.typ')
            self.assertEqual(arguments[arguments.index('--change-file') + 1], str(self.record))
            self.assertEqual(options['timeout'], 20)
        self.assertEqual(json.loads(self.responses[1][1]['input']), {'sources': []})
        self.assertEqual(json.loads(self.responses[2][1]['input']), {'sources': [{
            'filepath': str(self.entry), 'text': '한글 original.\r\n'}]})
        self.assertEqual(json.loads(self.responses[3][1]['input']), {'sources': []})
        self.assertEqual(client.location.path, self.record)

    def test_missing_capability_failure_is_actionable_and_never_uses_compiler(self):
        with patch('flow_reader.services.source_history.subprocess.Popen', return_value=
                   CompletedHelper(subprocess.CompletedProcess([], 2, '', 'unknown command source-history'))):
            with self.assertRaisesRegex(ValueError, 'source-history support'):
                SourceHistoryClient(self.project, engine=sys.executable, change_file=self.record)
        with patch.dict(os.environ, {'FLOW_ENGINE_PATH': str(self.root / 'missing-engine')}):
            with self.assertRaisesRegex(ValueError, '--engine PATH'):
                resolve_engine()

    def test_explicit_engine_precedes_environment_and_invalid_response_is_rejected(self):
        with patch.dict(os.environ, {'FLOW_ENGINE_PATH': str(self.root / 'missing-engine')}):
            self.assertEqual(resolve_engine(sys.executable), str(Path(sys.executable).resolve()))
        for output in ('null', '{}', json.dumps({'path': 'relative.json', 'sequence': 0}),
                       json.dumps({'path': str(self.record), 'sequence': True}),
                       json.dumps({'path': str(self.root / 'other.json'), 'sequence': 0})):
            results = [CompletedHelper(subprocess.CompletedProcess([], 0, '--change-file PATH', '')),
                       CompletedHelper(subprocess.CompletedProcess([], 0, output, ''))]
            with self.subTest(output=output), patch('flow_reader.services.source_history.subprocess.Popen', side_effect=results):
                with self.assertRaisesRegex(ValueError, 'Invalid source-history engine response'):
                    SourceHistoryClient(self.project, engine=sys.executable, change_file=self.record)

    def test_ambiguous_profile_selection_does_not_start_a_writer(self):
        data = self.root / 'flow'
        data.mkdir()
        profile = {'id': 'first', 'root': str(self.root), 'entry': 'main.typ'}
        (data / 'profiles.json').write_text(json.dumps({'schemaVersion': 1, 'profiles': [
            profile, {**profile, 'id': 'second'}]}))
        with patch('flow_reader.services.source_history.subprocess.Popen') as run:
            with self.assertRaisesRegex(ValueError, 'ambiguous'):
                SourceHistoryClient(self.project, engine=sys.executable, data=data)
            run.assert_not_called()


class SourceHistoryLifetimeTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        (self.root / 'main.typ').write_text('A saved source')
        self.project = Project(self.root, Path('main.typ'), self.root / 'packages')
        self.record = self.root / 'common.json'
        self.record.write_text('Untouched record')
        self.started = self.root / 'started.pid'
        self.block = self.root / 'block'
        self.launches = self.root / 'launches'
        self.engine = self.root / 'blocking-engine'
        self.engine.write_text(f'#!{sys.executable}\n' + f'''
import json
import os
from pathlib import Path
import signal
import sys
import time
root = Path({str(self.root)!r})
with (root / 'launches').open('a') as output:
    output.write(str(os.getpid()) + '\\n')
if sys.argv[-1] == '--help':
    print('--root ROOT --change-file PATH')
else:
    json.load(sys.stdin)
    if (root / 'block').exists():
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        (root / 'started.pid').write_text(str(os.getpid()))
        while True:
            time.sleep(1)
    print(json.dumps({{'path': str(root / 'common.json'), 'sequence': 0}}))
''')
        self.engine.chmod(0o755)

    def wait_started(self):
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            if self.started.exists():
                return int(self.started.read_text())
            threading.Event().wait(.01)
        self.fail('Owned source-history helper did not start')

    def assert_exited(self, pid):
        with self.assertRaises(ProcessLookupError):
            os.kill(pid, 0)

    def test_client_and_reader_close_reap_blocked_observation_and_registration(self):
        for registration in (False, True):
            with self.subTest(registration=registration):
                self.block.unlink(missing_ok=True)
                self.started.unlink(missing_ok=True)
                client = SourceHistoryClient(self.project, engine=str(self.engine), change_file=self.record)
                self.addCleanup(client.close)
                state = ReaderState(self.project, self.root / 'output', '', False, source_history=client)
                self.addCleanup(state.close)
                self.block.touch()
                errors = []
                def operate():
                    try:
                        if registration:
                            client.seed(source_snapshots(self.project, []))
                        else:
                            client.observe()
                    except ValueError as error:
                        errors.append(str(error))
                worker = threading.Thread(target=operate)
                worker.start()
                pid = self.wait_started()
                started = time.monotonic()
                (state.close if registration else client.close)()
                self.assertLess(time.monotonic() - started, 3)
                worker.join(2)
                self.assertFalse(worker.is_alive())
                self.assertEqual(errors, ['Source-history client is closed'])
                self.assert_exited(pid)
                launches = self.launches.read_bytes()
                with self.assertRaisesRegex(ValueError, 'client is closed'):
                    client.observe()
                self.assertEqual(self.launches.read_bytes(), launches)
                self.assertEqual(self.record.read_text(), 'Untouched record')

    def test_sigterm_during_cli_startup_reaps_helper_before_client_is_returned(self):
        self.block.touch()
        process = subprocess.Popen([
            sys.executable, str(ROOT / 'serve.py'), '--root', str(self.root),
            '--package-path', str(self.root), '--output', str(self.root / 'output'),
            '--original-url', 'http://127.0.0.1:1/', '--engine', str(self.engine),
            '--change-file', str(self.record)], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            pid = self.wait_started()
            process.terminate()
            stdout, stderr = process.communicate(timeout=5)
            self.assertEqual(process.returncode, 0, stderr)
            self.assertEqual(stdout, '')
            self.assertNotIn('Traceback', stderr)
            self.assert_exited(pid)
            self.assertEqual(self.record.read_text(), 'Untouched record')
        finally:
            if process.poll() is None:
                process.kill()
                process.communicate(timeout=5)


class SharedSourceHistoryIntegrationTests(unittest.TestCase):
    def setUp(self):
        engine = os.environ.get('FLOW_TEST_ENGINE')
        if not engine:
            self.skipTest('Set FLOW_TEST_ENGINE to a source-history capable Flow engine')
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        self.entry = self.root / 'main.typ'
        self.entry.write_text('#include "part.typ"')
        self.part = self.root / 'part.typ'
        self.part.write_text('Original included paragraph.')
        self.project = Project(self.root, Path('main.typ'), self.root / 'packages', compiler='missing')
        self.record = self.root / 'common.json'
        self.engine = engine

    def state(self, name):
        history = SourceHistoryClient(self.project, engine=self.engine, change_file=self.record)
        output = self.root / name
        output.mkdir()
        state = ReaderState(self.project, output, '', False, source_history=history)
        self.addCleanup(state.close)
        return state

    def compile(self, state, accepted=True):
        def compiler(_project, output):
            output.mkdir(exist_ok=True)
            body = self.part.read_text()
            report = {'revision': body, 'exitCode': 0 if accepted else 1,
                      'contentGatePassed': accepted, 'dependencies': [str(self.part)]}
            (output / 'report.json').write_text(json.dumps(report))
            (output / 'document.html').write_text(f'<html><body><p id="part">{body}</p></body></html>')
            return report
        with patch('flow_reader.server.state.compile_project', side_effect=compiler):
            state.compile()

    def test_html_only_save_failed_compile_restart_and_other_outputs_share_one_edit(self):
        state = self.state('first-output')
        self.compile(state)
        self.assertEqual(state.shared_edit.read()['status'], 'empty')
        self.part.write_text('한글 changed included paragraph.')
        self.compile(state)
        edit = state.shared_edit.read()
        self.assertEqual(edit['status'], 'located')
        self.assertEqual(edit['path'], str(self.part))
        self.assertEqual(state.bundle.manifest['lastChange']['target'], 'part')
        token = edit['token']
        self.part.write_text('// comment\n한글 changed included paragraph.')
        self.compile(state)
        self.assertEqual(state.shared_edit.read()['token'], token)
        previous_revision = state.revision
        self.part.write_text('Failed but saved source edit.')
        self.compile(state, False)
        failed = state.shared_edit.read()
        self.assertEqual(failed['status'], 'located')
        self.assertNotEqual(failed['token'], token)
        self.assertEqual(state.revision, previous_revision)
        restarted = self.state('other-output')
        self.compile(restarted)
        self.assertEqual(restarted.shared_edit.read()['token'], failed['token'])
        self.assertEqual(restarted.bundle.manifest['lastChange']['token'], failed['token'])
        self.assertEqual(SharedEditLocation(self.root, self.entry, self.record).read(), failed)
        self.assertFalse((state.output / 'last-change.json').exists())
        self.assertFalse((restarted.output / 'last-change.json').exists())

    def test_standalone_default_lookup_finds_same_record_without_creating_or_updating_it(self):
        data = self.root / 'flow-data'
        with patch.dict(os.environ, {'FLOW_DATA_DIR': str(data)}):
            location = SharedEditLocation(self.root, self.entry)
            location.discover_engine_record(self.engine)
            self.assertIsNotNone(location.path)
            self.assertFalse(location.path.exists())
            self.assertFalse(data.exists())
            client = SourceHistoryClient(self.project, engine=self.engine)
            self.assertEqual(client.location.path, location.path)
            client.seed(source_snapshots(self.project, [str(self.part)]))
            self.part.write_text('Standalone default path edited paragraph.')
            client.observe()
            before = location.path.read_bytes()
            resolved = json.loads(subprocess.check_output([
                sys.executable, str(ROOT / 'edit-location.py'), '--root', str(self.root),
                '--engine', self.engine], text=True))
            self.assertEqual(resolved, client.location.read())
            self.assertEqual(resolved['status'], 'located')
            self.assertEqual(location.path.read_bytes(), before)

    def test_actual_compiler_discovers_dependency_and_publishes_shared_edit(self):
        packages = os.environ.get('FLOW_READER_PACKAGES')
        compiler = os.environ.get('FLOW_READER_TYPST') or shutil.which('typst')
        if not packages or not compiler:
            self.skipTest('Set FLOW_READER_PACKAGES and optionally FLOW_READER_TYPST')
        self.project = replace(self.project, packages=Path(packages), compiler=compiler)
        state = self.state('compiled-output')
        state.compile()
        self.assertTrue(state.report['contentGatePassed'], state.report)
        self.assertIn(str(self.part), state.dependencies)
        self.assertEqual(state.shared_edit.read()['status'], 'empty')
        self.part.write_text('한글 actual compiler saved paragraph.')
        state.compile()
        self.assertTrue(state.report['contentGatePassed'], state.report)
        edit = state.shared_edit.read()
        self.assertEqual(edit['status'], 'located')
        self.assertEqual(edit['path'], str(self.part))
        self.assertEqual(state.public()['changeToken'], edit['token'])
        target = state.bundle.manifest['lastChange']['target']
        self.assertIn(target, state.bundle.manifest['anchors'])
        previous_revision = state.revision
        self.part.write_text('#unknown-history-fixture-function()')
        state.compile()
        self.assertFalse(state.report['contentGatePassed'])
        self.assertEqual(state.revision, previous_revision)
        self.assertNotEqual(state.shared_edit.read()['token'], edit['token'])

    def test_actual_html_only_note_insertion_body_and_title_edits_publish_container(self):
        packages = os.environ.get('FLOW_READER_PACKAGES')
        compiler = os.environ.get('FLOW_READER_TYPST') or shutil.which('typst')
        if not packages or not compiler:
            self.skipTest('Set FLOW_READER_PACKAGES and optionally FLOW_READER_TYPST')
        self.project = replace(self.project, packages=Path(packages), compiler=compiler)
        prefix = '#import "@local/math-blocks:0.2.0": note\nBefore the note.\n\n'
        self.part.write_text(prefix + 'After the note.')
        state = self.state('notes-output')
        state.compile()
        self.assertTrue(state.report['contentGatePassed'], state.report)
        previous = None
        for title, body in (('Green functions 0', 'Unwrapped Green function version 5.'),
                            ('Green functions 0', 'Unwrapped Green function version 6.'),
                            ('Green functions 1', 'Unwrapped Green function version 6.')):
            self.part.write_text(prefix + f'#note(title: "{title}")[{body}]\n\nAfter the note.')
            state.compile()
            self.assertTrue(state.report['contentGatePassed'], state.report)
            edit = state.shared_edit.read()
            hint = state.bundle.manifest['lastChange']
            self.assertEqual(edit['status'], 'located')
            self.assertIsNotNone(hint, (title, edit, state.bundle.navigation_ranges))
            self.assertEqual(hint['token'], edit['token'])
            self.assertNotEqual(hint['token'], previous)
            self.assertTrue(hint['target'].startswith('reader-callout-'))
            previous = hint['token']

    def test_actual_trailing_paragraph_deletion_reveals_survivor_and_whitespace_retains_edit(self):
        packages = os.environ.get('FLOW_READER_PACKAGES')
        compiler = os.environ.get('FLOW_READER_TYPST') or shutil.which('typst')
        if not packages or not compiler:
            self.skipTest('Set FLOW_READER_PACKAGES and optionally FLOW_READER_TYPST')
        self.project = replace(self.project, packages=Path(packages), compiler=compiler)
        self.part.write_text('Before.\n\nDelete.\n')
        state = self.state('deletion-output')
        state.compile()
        self.assertTrue(state.report['contentGatePassed'], state.report)
        self.part.write_text('Before.\n\n')
        state.compile()
        self.assertTrue(state.report['contentGatePassed'], state.report)
        edit = state.shared_edit.read()
        self.assertEqual(edit['status'], 'located')
        hint = state.bundle.manifest['lastChange']
        self.assertIsNotNone(hint, edit)
        self.assertEqual(hint['token'], edit['token'])
        passage = next(passage for passage in state.bundle.passages if passage['id'] == hint['target'])
        self.assertEqual(passage['text'], 'Before.')
        sequence = json.loads(self.record.read_text())['source_history']['sequence']
        self.part.write_text('Before.\n\n \n')
        state.compile()
        self.assertTrue(state.report['contentGatePassed'], state.report)
        self.assertEqual(state.shared_edit.read()['token'], edit['token'])
        self.assertEqual(state.bundle.manifest['lastChange']['token'], edit['token'])
        self.assertEqual(json.loads(self.record.read_text())['source_history']['sequence'], sequence)

    def test_comment_inserted_at_edit_start_rebases_shared_word_without_new_sequence(self):
        self.part.write_text('Old body.')
        client = SourceHistoryClient(self.project, engine=self.engine, change_file=self.record)
        self.addCleanup(client.close)
        client.seed(source_snapshots(self.project, [str(self.part)]))
        self.part.write_text('New body.')
        client.observe()
        original = client.location.read()
        self.assertEqual(original['status'], 'located')
        self.assertEqual((original['start'], original['end']), (0, 3))
        sequence = json.loads(self.record.read_text())['source_history']['sequence']
        self.part.write_text('// Comment\nNew body.')
        client.observe()
        edit = SharedEditLocation(self.root, self.entry, self.record).read()
        self.assertEqual(edit['status'], 'located')
        self.assertEqual((edit['line'], edit['column']), (2, 0))
        self.assertEqual((edit['start'], edit['end']), (11, 14))
        self.assertEqual(self.part.read_text()[edit['start']:edit['end']], 'New')
        self.assertEqual(edit['token'], original['token'])
        self.assertEqual(json.loads(self.record.read_text())['source_history']['sequence'], sequence)


if __name__ == '__main__':
    unittest.main()
