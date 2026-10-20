"""Verify the integration gate cannot report skipped coverage as success."""

import contextlib
import importlib.util
import io
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location("reader_test_runner", ROOT / "scripts/test-reader-services.py")
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)


class ReaderTestRunnerTests(unittest.TestCase):
    def run_gate(self, *, required, skipped=False, failed=False, empty=False):
        result = unittest.TestResult()
        result.testsRun = 0 if empty else 1
        if skipped:
            result.skipped.append(("compiler fixture", "missing compiler"))
        if failed:
            result.failures.append(("service fixture", "failure"))
        with tempfile.TemporaryDirectory() as packages:
            arguments = ["test-reader-services.py"] + (["--require-integration"] if required else [])
            with patch.object(runner.sys, "argv", arguments), \
                    patch.dict(os.environ, {"FLOW_READER_PACKAGES": packages}), \
                    patch.object(runner.unittest.defaultTestLoader, "discover"), \
                    patch.object(runner.unittest.TextTestRunner, "run", return_value=result), \
                    contextlib.redirect_stderr(io.StringIO()):
                return runner.main()

    def test_optional_skip_and_complete_required_suite_succeed(self):
        self.assertEqual(self.run_gate(required=False, skipped=True), 0)
        self.assertEqual(self.run_gate(required=True), 0)

    def test_required_skip_failure_and_empty_suite_fail(self):
        self.assertEqual(self.run_gate(required=True, skipped=True), 1)
        self.assertEqual(self.run_gate(required=False, failed=True), 1)
        self.assertEqual(self.run_gate(required=True, empty=True), 1)

    def test_missing_required_packages_fail_before_discovery(self):
        with patch.object(runner.sys, "argv", ["test-reader-services.py", "--require-integration"]), \
                patch.dict(os.environ, {}, clear=True), \
                patch.object(runner.unittest.defaultTestLoader, "discover") as discover, \
                contextlib.redirect_stderr(io.StringIO()), \
                self.assertRaises(SystemExit) as error:
            runner.main()
        self.assertEqual(error.exception.code, 2)
        discover.assert_not_called()
