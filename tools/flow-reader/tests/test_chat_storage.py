"""Isolated source-exclusion and pre-creation checks; no account credentials."""
from contextlib import ExitStack, redirect_stderr
import io
import os
from pathlib import Path
import stat
import subprocess
import sys
import tempfile
import unittest
import unicodedata
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from flow_reader.services.chat_storage import private_directory, private_file, read_json, write_json
from flow_reader.server import cli as home


class ChatStorageBoundaryTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="chat-storage-boundary-")
        self.addCleanup(self.temporary.cleanup)
        self.work = Path(self.temporary.name).resolve()
        self.repository = self.work / "repository"
        subprocess.run(["git", "init", "--quiet", str(self.repository)], check=True,
                       stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)

    def test_git_root_and_descendants_rejected_before_creation_or_chmod(self):
        existing = self.repository / "existing"
        existing.mkdir(mode=0o755)
        for path in (self.repository, existing, self.repository / "new" / "chat"):
            with self.subTest(kind=path.name):
                before = stat.S_IMODE(path.stat().st_mode) if path.exists() else None
                with self.assertRaisesRegex(ValueError, "outside.*repositor"):
                    private_directory(path)
                self.assertEqual(stat.S_IMODE(path.stat().st_mode) if path.exists() else None, before)
        self.assertFalse((self.repository / "new").exists())

    def test_real_worktree_git_file_is_rejected(self):
        subprocess.run(["git", "-C", str(self.repository), "-c", "user.name=Fixture",
                        "-c", "user.email=fixture@example.invalid", "commit", "--quiet", "--allow-empty", "-m", "fixture"],
                       check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        worktree = self.work / "worktree"
        subprocess.run(["git", "-C", str(self.repository), "worktree", "add", "--quiet", "--detach", str(worktree)],
                       check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        self.assertTrue((worktree / ".git").is_file())
        with self.assertRaisesRegex(ValueError, "outside.*repositor"):
            private_directory(worktree / "chat")
        self.assertFalse((worktree / "chat").exists())

    def test_home_dotfiles_worktree_allows_default_private_data(self):
        home_root = self.work / "home"
        home_root.mkdir()
        for git_file in (False, True):
            with self.subTest(git_file=git_file):
                marker = home_root / ".git"
                if git_file:
                    marker.rmdir()
                    marker.write_text("gitdir: /fixture/dotfiles.git\n")
                else:
                    marker.mkdir()
                target = home_root / "Library/Application Support/Lagrangian/paragraph-chat"
                with patch.object(Path, "home", return_value=home_root):
                    directory = private_directory(target)
                    self.assertEqual(directory, target.resolve())
                    self.assertEqual(stat.S_IMODE(directory.stat().st_mode), 0o700)
                    # Explicit source roots take precedence over the exemption.
                    with self.assertRaisesRegex(ValueError, "outside the source project"):
                        private_directory(home_root / "source-chat", home_root)
                self.assertFalse((home_root / "source-chat").exists())

    def test_home_exemption_checks_resolved_nearest_worktree_not_symlink_spelling(self):
        home_root = self.work / "home"
        home_root.mkdir()
        (home_root / ".git").mkdir()
        nested = home_root / "projects" / "nested"
        nested.mkdir(parents=True)
        (nested / ".git").write_text("gitdir: /fixture/worktree.git\n")
        external_alias = self.work / "home-alias"
        external_alias.symlink_to(home_root, target_is_directory=True)
        project_alias = home_root / "project-alias"
        project_alias.symlink_to(self.repository, target_is_directory=True)
        with patch.object(Path, "home", return_value=external_alias):
            allowed = private_directory(external_alias / "Library" / "chat")
            self.assertEqual(allowed, home_root / "Library" / "chat")
            for target in (nested / "chat", external_alias / "projects/nested/chat",
                           project_alias / "chat", external_alias / "project-alias/chat"):
                with self.subTest(path=target):
                    with self.assertRaisesRegex(ValueError, "outside.*repositor"):
                        private_directory(target)
                    self.assertFalse(target.resolve().exists())

    def test_relative_dotdot_and_ancestor_alias_into_git_are_rejected(self):
        alias = self.work / "source-alias"
        alias.symlink_to(self.repository, target_is_directory=True)
        with self.assertRaises(ValueError):
            private_directory(alias / "chat")
        previous = Path.cwd()
        try:
            os.chdir(self.repository)
            with self.assertRaises(ValueError):
                private_directory(Path("missing") / ".." / "chat")
        finally:
            os.chdir(previous)
        self.assertFalse((self.repository / "missing").exists())
        self.assertFalse((self.repository / "chat").exists())

    def test_explicit_non_git_project_and_alias_are_still_excluded(self):
        source = self.work / "plain-source"
        source.mkdir()
        alias = self.work / "plain-alias"
        alias.symlink_to(source, target_is_directory=True)
        for path in (source / "chat", alias / "chat"):
            with self.assertRaisesRegex(ValueError, "outside the source project"):
                private_directory(path, source)
        self.assertFalse((source / "chat").exists())

    def test_filesystem_equivalent_non_git_source_paths_are_excluded(self):
        pairs = [("SourceBundle", "sourcebundle"), ("CaféBundle", unicodedata.normalize("NFD", "CaféBundle"))]
        for actual, alternative in pairs:
            with self.subTest(form=actual):
                source = self.work / actual
                source.mkdir()
                alias = self.work / alternative
                if not alias.exists():
                    continue  # These are distinct directories on this filesystem.
                self.assertTrue(alias.samefile(source))
                with self.assertRaisesRegex(ValueError, "outside the source project"):
                    private_directory(alias / "chat", source)
                self.assertFalse((source / "chat").exists())

    def test_external_storage_and_parent_alias_preserve_private_records(self):
        external = self.work / "private"
        external.mkdir()
        alias = self.work / "private-alias"
        alias.symlink_to(external, target_is_directory=True)
        directory = private_directory(alias / "chat", self.repository)
        self.assertEqual(directory.resolve(), external / "chat")
        self.assertEqual(stat.S_IMODE(directory.stat().st_mode), 0o700)
        record = directory / "fixture.json"
        write_json(record, {"fixture": True})
        self.assertEqual(read_json(record, {}), {"fixture": True})
        self.assertEqual(stat.S_IMODE(record.stat().st_mode), 0o600)
        os.close(private_file(directory / "fixture.lock"))
        leaf = self.work / "leaf-alias"
        leaf.symlink_to(directory, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, "symlink"):
            private_directory(leaf)

    def assert_home_rejects_before_sinks(self, target, reader_root=None):
        with ExitStack() as stack:
            stack.enter_context(patch.object(sys, "argv", ["serve.py", "--managed", "--chat-data", str(target)]))
            stack.enter_context(patch.object(home.signal, "signal"))
            stack.enter_context(patch.object(home, "ReaderManager"))
            if reader_root is not None:
                stack.enter_context(patch.object(home, "READER_ROOT", reader_root))
            sinks = [stack.enter_context(patch.object(home, name)) for name in
                     ("claim_host", "ChatAuth", "write_json", "ThreadingHTTPServer")]
            sinks[0].side_effect = AssertionError("storage validation must precede private-file sinks")
            errors = stack.enter_context(redirect_stderr(io.StringIO()))
            with self.assertRaises(SystemExit) as exited:
                home.main()
            self.assertEqual(exited.exception.code, 2)
            self.assertNotIn(str(target), errors.getvalue())
            for sink in sinks:
                sink.assert_not_called()
        self.assertFalse(target.exists())

    def test_home_rejects_git_storage_before_auth_capability_or_server(self):
        self.assert_home_rejects_before_sinks(self.repository / "new-chat")

    def test_home_rejects_filesystem_equivalent_bundle_before_sinks(self):
        pairs = [("SourceBundle", "sourcebundle"), ("CaféBundle", unicodedata.normalize("NFD", "CaféBundle"))]
        for actual, alternative in pairs:
            with self.subTest(form=actual):
                bundle = self.work / actual
                bundle.mkdir()
                alias = self.work / alternative
                if not alias.exists():
                    continue
                self.assert_home_rejects_before_sinks(alias / "chat", bundle / "tools" / "flow-reader")

    def test_home_rejects_non_git_reader_bundle_storage(self):
        bundle = self.work / "source-bundle"
        self.assert_home_rejects_before_sinks(bundle / "chat", bundle / "tools" / "flow-reader")


if __name__ == "__main__":
    unittest.main()
