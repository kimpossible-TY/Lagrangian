"""A successful graph replaces stale installed paths; failures retain watch inputs."""
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from flow_reader.compiler.project import Project
from flow_reader.server.state import ReaderState


class DependencyRetirementTests(unittest.TestCase):
    def test_success_retires_previous_release_and_failure_keeps_watch_inputs(self):
        for code in (0, 1):
            with self.subTest(exitCode=code), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                entry = root / "main.typ"
                entry.write_text("Document")
                output = root / "output"
                output.mkdir()
                retired = str(root.parent / "old-reader-release/package.typ")
                (output / "report.json").write_text(json.dumps({"dependencies": [retired]}))
                state = ReaderState(Project(root, Path("main.typ"), root), output, "", False)
                try:
                    report = {"exitCode": code, "dependencies": [str(entry)]}
                    with patch("flow_reader.server.state.compile_project", return_value=report) as compile_call, \
                            patch.object(state, "load_result") as publish:
                        state.compile()
                    self.assertEqual(compile_call.call_count, 2 if code == 0 else 1)
                    self.assertEqual(retired in state.dependencies, code != 0)
                    self.assertIn(str(entry), state.dependencies)
                    publish.assert_called_once()
                finally:
                    state.close()


if __name__ == "__main__":
    unittest.main()
