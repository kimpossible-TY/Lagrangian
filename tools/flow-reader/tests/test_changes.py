"""HTML delegates saved-source observation and retains accepted navigation guards."""

import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from flow_reader.compiler.project import Project
from flow_reader.compiler.inputs import source_signature
from flow_reader.services.edit_location import SharedEditLocation
from flow_reader.server.state import ReaderState


class RecordingHistory:
    def __init__(self, project, path):
        self.location = SharedEditLocation(project.root, project.entry, path)
        self.events = []

    def observe(self):
        self.events.append("observe")

    def seed(self, sources):
        self.events.append(sources)

    def close(self):
        pass


class SharedHistoryPublicationTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve() / "project"
        self.root.mkdir()
        self.entry = self.root / "main.typ"
        self.entry.write_text('Before accepted edit.')
        self.output = self.root / "output"
        self.output.mkdir()
        self.project = Project(self.root, Path("main.typ"), self.root / "packages", compiler="missing")
        self.history = RecordingHistory(self.project, self.root / "common.json")
        self.state = ReaderState(self.project, self.output, "", False, source_history=self.history)
        self.addCleanup(self.state.close)

    def result(self, accepted=True):
        report = {"revision": "body", "exitCode": 0 if accepted else 1,
                  "contentGatePassed": accepted, "dependencies": [str(self.entry)]}
        (self.output / "report.json").write_text(json.dumps(report))
        (self.output / "document.html").write_text('<html><body><p id="body">Before accepted edit.</p></body></html>')
        return report

    def test_observation_precedes_compilation_and_failed_compile_does_not_seed(self):
        report = self.result(False)
        def compile_saved(*_args):
            self.assertEqual(self.history.events, ["observe"])
            return report
        with patch("flow_reader.server.state.compile_project", side_effect=compile_saved):
            self.state.compile()
        self.assertEqual(self.history.events, ["observe"])
        self.assertIsNone(self.state.revision)
        self.assertFalse((self.output / "last-change.json").exists())

    def test_accepted_snapshot_registers_exact_local_sources_without_visual_history(self):
        self.entry.write_bytes(b'Before accepted edit.\r\n')
        imported = self.root / "part.typ"
        imported.write_text("Imported paragraph")
        outside = self.root.parent / "outside" / "not-an-input.typ"
        outside.parent.mkdir()
        outside.write_text("A real file outside this project")
        self.state.dependencies.update([str(imported), str(outside)])
        self.result()
        self.state.load_result(source_signature(self.project, self.state.dependencies))
        sources = self.history.events[-1]
        self.assertEqual({source["filepath"] for source in sources}, {str(self.entry), str(imported)})
        self.assertEqual(sources[0]["text"], 'Before accepted edit.\r\n')
        self.assertIsNone(self.state.bundle.manifest["lastChange"])
        self.assertFalse((self.output / "last-change.json").exists())
        revision, document = self.state.revision, self.state.document
        self.entry.write_text("Failed saved edit")
        self.result(False)
        self.state.load_result(source_signature(self.project, self.state.dependencies))
        self.assertEqual(len(self.history.events), 1)
        self.assertEqual((self.state.revision, self.state.document), (revision, document))

    def test_sources_changed_during_registration_cannot_publish(self):
        self.result()
        def concurrent_save(_sources):
            self.entry.write_text("Newer save during registration")
        self.history.seed = concurrent_save
        with self.assertRaisesRegex(ValueError, "Sources changed"):
            self.state.load_result(source_signature(self.project))
        self.assertIsNone(self.state.revision)

    def test_read_only_state_does_not_invent_output_chronology(self):
        state = ReaderState(self.project, self.output, "", False, change_file=self.root / "common.json")
        self.addCleanup(state.close)
        for text in ("First output", "Different output"):
            self.result()
            (self.output / "document.html").write_text(f'<html><body><p id="body">{text}</p></body></html>')
            state.load_result(source_signature(self.project))
            self.assertIsNone(state.bundle.manifest["lastChange"])
        self.assertFalse((self.output / "last-change.json").exists())


if __name__ == "__main__":
    unittest.main()
