"""Common source history is read once under the same identity/byte contract."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from flow_reader.services.edit_location import SharedEditLocation, MAX_RECORD_BYTES
from flow_reader.services.source_mapping import edit_location
from flow_reader.compiler.project import Project
from flow_reader.compiler.inputs import source_signature
from flow_reader.document.sections import split_document
from flow_reader.server.state import ReaderState


class SharedEditTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        self.entry = self.root / 'main.typ'
        self.entry.write_text('#include "part.typ"\n')
        self.part = self.root / 'part.typ'
        self.source = 'First paragraph.\r\n\n마지막 수정 paragraph.\n'
        self.part.write_bytes(self.source.encode())
        (self.root / 'history').mkdir()
        self.record_path = self.root / 'history/changes.json'
        self.record = {
            'schema_version': 2, 'project': json.dumps([str(self.root), str(self.entry)]),
            'variants': {}, 'source_history': {
                'sequence': 7, 'sources': {str(self.part): self.source},
                'latest': {'filepath': str(self.part), 'source_hash': 'a' * 32,
                           'range': {'start': len('First paragraph.\r\n\n마지막 '.encode()),
                                     'end': len(self.source.encode()) - 1}}}}
        self.save()
        self.reader = SharedEditLocation(self.root, self.entry, self.record_path)
        self.project = Project(self.root, self.entry, self.root / 'packages')

    def save(self):
        self.record_path.write_text(json.dumps(self.record))

    def test_unicode_crlf_position_cli_and_read_only_bytes(self):
        before = self.record_path.read_bytes()
        result = self.reader.read()
        self.assertEqual(result['status'], 'located')
        self.assertEqual((result['line'], result['column']), (3, len('마지막 '.encode())))
        self.assertEqual(result['source_hash'], hashlib.sha256(self.source.encode()).hexdigest())
        cli = json.loads(subprocess.check_output([
            sys.executable, str(ROOT / 'edit-location.py'), '--root', str(self.root),
            '--change-file', str(self.record_path)], text=True))
        self.assertEqual(cli, result)
        self.assertEqual(self.record_path.read_bytes(), before)

    def test_stale_wrong_project_and_invalid_ranges_do_not_navigate(self):
        self.part.write_text('A different source')
        self.assertEqual(self.reader.read()['status'], 'stale')
        self.part.write_bytes(self.source.encode())
        self.record['project'] = json.dumps([str(self.root), str(self.part)])
        self.save()
        self.assertEqual(self.reader.read()['status'], 'wrong-project')
        self.record['project'] = json.dumps([str(self.root), str(self.entry)])
        for bounds in ({'start': 1, 'end': 9999}, {'start': True, 'end': 2},
                       {'start': len('First paragraph.\r\n\n'.encode()) + 1, 'end': 30}):
            self.record['source_history']['latest']['range'] = bounds
            self.save()
            self.assertEqual(self.reader.read()['status'], 'invalid')
        for content in ('null', '[]', '{broken', ' ' * (MAX_RECORD_BYTES + 1)):
            self.record_path.write_text(content)
            self.assertEqual(self.reader.read()['status'], 'invalid')

    def test_exact_profile_discovery_and_ambiguity(self):
        data = self.root / 'flow'
        (data / 'changes').mkdir(parents=True)
        (data / 'changes/project.json').write_bytes(self.record_path.read_bytes())
        profile = {'id': 'project', 'root': str(self.root), 'entry': 'main.typ'}
        settings = {'schemaVersion': 1, 'profiles': [profile]}
        (data / 'profiles.json').write_text(json.dumps(settings))
        self.assertEqual(SharedEditLocation(self.root, self.entry, data=data).read(), self.reader.read())
        self.assertEqual(SharedEditLocation(self.root, self.part, data=data).read()['status'], 'unavailable')
        settings['profiles'].append({**profile, 'id': 'duplicate'})
        (data / 'profiles.json').write_text(json.dumps(settings))
        self.assertEqual(SharedEditLocation(self.root, self.entry, data=data).read()['status'], 'ambiguous')

    def test_mapping_uses_source_range_and_rejects_repeated_output(self):
        bundle = split_document('<html><body><p id="a">First</p><p id="b">Changed</p></body></html>', 'r')
        edit = self.reader.read()
        span = {'path': str(self.part), 'source_hash': edit['source_hash'],
                'start': edit['start'] + 1, 'end': edit['end']}
        bundle.passages[1]['source_ranges'] = [span]
        self.assertEqual(edit_location(self.project, [str(self.part)], bundle, edit)['key'], bundle.passages[1]['key'])
        bundle.passages[0]['source_ranges'] = [span]
        self.assertEqual(edit_location(self.project, [str(self.part)], bundle, edit)['status'], 'ambiguous')

    def test_late_common_record_updates_metadata_without_changing_revision(self):
        output = self.root / 'output'
        output.mkdir()
        html = '<html><body><p id="first">First paragraph.</p><p id="last">마지막 수정 paragraph.</p></body></html>'
        (output / 'document.html').write_text(html)
        (output / 'report.json').write_text(json.dumps({'revision': 'body', 'exitCode': 0, 'contentGatePassed': True}))
        self.record_path.unlink()
        state = ReaderState(self.project, output, '', False, change_file=self.record_path)
        self.addCleanup(state.close)
        state.dependencies.add(str(self.part))
        state.load_result(source_signature(self.project, state.dependencies))
        revision = state.revision
        self.assertIsNone(state.bundle.manifest['lastChange'])
        self.save()
        public = state.public()
        self.assertEqual(state.revision, revision)
        self.assertEqual(public['changeToken'], self.reader.read()['token'])
        manifest = json.loads(state.manifest_json)
        self.assertEqual(manifest['lastChange']['target'], 'last')
        self.assertEqual(manifest['lastChange']['revision'], revision)
        self.record['source_history']['latest']['range']['start'] = 9999
        self.save()
        self.assertIsNone(state.public()['changeToken'])
        self.assertIsNone(json.loads(state.manifest_json)['lastChange'])


if __name__ == '__main__':
    unittest.main()
