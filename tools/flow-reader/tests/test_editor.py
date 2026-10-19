"""Exercise conservative source navigation and the editor-owned write boundary."""

from http.server import ThreadingHTTPServer
import json
import hashlib
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from unittest.mock import patch
from urllib.error import HTTPError
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from flow_reader.compiler.project import Project
from flow_reader.services.change_history import input_fingerprint
from flow_reader.services.editor_sync import NeovimEditor, vim_string
from flow_reader.services.source_mapping import literal_blocks
from flow_reader.document.sections import split_document
from flow_reader.server.state import ReaderState
from flow_reader.server.http import handler_for
from flow_reader.compiler.inputs import source_signature


class EditorNavigationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        work = Path(self.temporary.name).resolve()
        self.root = work / "project"
        self.root.mkdir()
        self.packages = work / "packages"
        self.packages.mkdir()
        self.output = work / "output"
        self.output.mkdir()
        self.entry = self.root / "main.typ"

    def state(self, source, body, dependencies=(), editor_server=None):
        self.entry.write_text(source, encoding="utf-8")
        project = Project(self.root, Path("main.typ"), self.packages, compiler="missing-compiler")
        state = ReaderState(project, self.output, "https://example.test/paged/", False,
                            editor_server=editor_server)
        state.bundle = split_document(f"<html><head></head><body>{body}</body></html>", "accepted")
        state.revision = "accepted"
        state.accepted_dependencies = set(map(str, dependencies))
        state.source_stamp = source_signature(project, state.accepted_dependencies)
        state.accepted_inputs = input_fingerprint(project, state.accepted_dependencies)
        return state

    def fragment(self, state, exact, ordinal=0):
        passage = state.bundle.passages[ordinal]
        start = passage["text"].index(exact)
        return {"key": passage["key"], "exact": exact,
                "prefix": passage["text"][:start][-64:],
                "suffix": passage["text"][start + len(exact):][:64]}

    def test_literal_unicode_quotes_multiline_and_heading_positions(self):
        state = self.state('= 시작\n\n첫 줄 한글 and "quoted" prose.\nSecond line.\n',
                           '<h1 id="heading">시작</h1><p>첫 줄 한글 and “quoted” prose. Second line.</p>')
        result = state.source(state.revision, [self.fragment(state, "한글", 1)])
        self.assertEqual(result, {"status": "located", "revision": state.revision,
                                 "path": str(self.entry), "line": 3,
                                 "source_hash": hashlib.sha256(self.entry.read_bytes()).hexdigest(),
                                 "column": len("첫 줄 ".encode())})
        quoted = state.source(state.revision, [self.fragment(state, "“quoted”", 1)])
        self.assertEqual(quoted["column"], len("첫 줄 한글 and ".encode()))
        cursor = state.cursor(state.revision, str(self.entry), 3, len("첫 줄 한".encode()))
        self.assertEqual(cursor["status"], "located")
        self.assertEqual(cursor["exact"], "첫 줄 한글 and “quoted” prose. Second line.")
        self.assertEqual(cursor["key"], state.bundle.passages[1]["key"])
        heading = state.source(state.revision, [self.fragment(state, "시작")])
        self.assertEqual((heading["line"], heading["column"]), (1, 2))
        self.assertEqual(state.cursor(state.revision, str(self.entry), 1, 0)["key"],
                         state.bundle.passages[0]["key"])

    def test_duplicate_source_and_duplicate_rendered_blocks_are_ambiguous(self):
        state = self.state("Same paragraph.\n\nSame paragraph.", "<p>Same paragraph.</p>")
        self.assertEqual(state.source(state.revision, [self.fragment(state, "paragraph")])["status"],
                         "ambiguous")
        state = self.state("Same paragraph.", "<p>Same paragraph.</p><p>Same paragraph.</p>")
        self.assertEqual(state.cursor(state.revision, str(self.entry), 1, 0)["status"], "ambiguous")

    def test_transparent_source_highlights_keep_navigation_and_original_byte_offsets(self):
        body = '<p>첫 한글 selected words after.</p>'
        state = self.state("첫 한글 selected words after.", body)
        before = state.source(state.revision, [self.fragment(state, "selected words")])
        self.assertEqual(before["column"], len("첫 한글 ".encode()))
        for name in ("highlight", "highlighted"):
            source = f"첫 한글 #{name}[selected words] after."
            state = self.state(source, body)
            result = state.source(state.revision, [self.fragment(state, "words")])
            self.assertEqual(result["status"], "located")
            expected = len(f"첫 한글 #{name}[selected ".encode())
            self.assertEqual((result["line"], result["column"]), (1, expected))
            for column in (len("첫 ".encode()), len("첫 한글 ".encode()), expected):
                cursor = state.cursor(state.revision, str(self.entry), 1, column)
                self.assertEqual(cursor["status"], "located")
                self.assertEqual(cursor["exact"], "첫 한글 selected words after.")
            result = state.source(state.revision, [self.fragment(state, "after.")])
            self.assertEqual(result["column"], len(f"첫 한글 #{name}[selected words] ".encode()))
        state = self.state("#highlight[첫 한글 selected words after.]", body)
        self.assertEqual(state.cursor(state.revision, str(self.entry), 1, 0)["status"], "located")
        state = self.state("첫 #highlight[한글 selected\nwords] after.", body)
        result = state.source(state.revision, [self.fragment(state, "words")])
        self.assertEqual((result["status"], result["line"], result["column"]), ("located", 2, 0))
        for source in ("#other[selected words]", "#highlight[$selected words$]",
                       "#highlight[#other[selected words]]", '#let x = "#highlight[selected words]"',
                       '#let x = [\n#highlight[selected words]\n]'):
            state = self.state(source, "<p>selected words</p>")
            self.assertEqual(state.source(state.revision, [self.fragment(state, "selected words")])["status"],
                             "unmapped")

    def test_math_code_macros_raw_comments_and_formatted_blocks_are_unmapped(self):
        for source in (
            '#let value = "Hidden words."\n#value',
            '#let value = [\n\nHidden words.\n\n]\n#value',
            '#let value = "\n\nHidden words.\n\n"\n#value',
            '```\n\nHidden words.\n\n```',
            '/* nested /* comment */\n\nHidden words.\n\n*/',
            '$\n\nHidden words.\n\n$',
            '*Hidden words.*',
            '#let value =\n\n"Hidden words."',
        ):
            with self.subTest(source=source):
                state = self.state(source, "<p>Hidden words.</p>")
                result = state.source(state.revision, [self.fragment(state, "Hidden words.")])
                self.assertEqual(result["status"], "unmapped")
        state = self.state("Plain words.", "<p>Plain words.</p>")
        fragment = self.fragment(state, "Plain words.")
        fragment["segments"] = [{"text": "Plain words.", "math": True, "complete": True}]
        self.assertEqual(state.source(state.revision, [fragment])["status"], "unmapped")

    def test_paths_are_limited_to_accepted_workspace_dependencies(self):
        included = self.root / "chapter.typ"
        included.write_text("Included text.")
        unknown = self.root / "unknown.typ"
        unknown.write_text("Included text.")
        outside = self.root.parent / "outside.typ"
        outside.write_text("Included text.")
        state = self.state('#include "chapter.typ"', "<p>Included text.</p>",
                           dependencies=(included, outside))
        self.assertEqual(state.source(state.revision, [self.fragment(state, "Included")])["path"],
                         str(included))
        self.assertEqual(state.cursor(state.revision, str(included), 1, 0)["status"], "located")
        for path in (unknown, outside):
            self.assertEqual(state.cursor(state.revision, str(path), 1, 0)["status"], "unmapped")

    def test_changed_same_size_source_revision_and_compile_reject_stale_navigation(self):
        state = self.state("Before text.", "<p>Before text.</p>")
        fragment = self.fragment(state, "text")
        self.assertEqual(state.source("old", [fragment])["status"], "stale")
        state.compiling = True
        self.assertEqual(state.cursor(state.revision, str(self.entry), 1, 0)["status"], "stale")
        state.compiling = False
        self.entry.write_text("After! text.")
        self.assertEqual(state.source(state.revision, [fragment])["status"], "stale")
        self.assertEqual(state.cursor(state.revision, str(self.entry), 1, 0)["status"], "stale")

    def test_cursor_validation_rejects_non_boundary_utf8_and_invalid_coordinates(self):
        state = self.state("한글 prose.", "<p>한글 prose.</p>")
        for line, column in ((0, 0), (1, -1), (2, 0), (1, 100), (1, 1), (True, 0)):
            with self.subTest(line=line, column=column), self.assertRaises(ValueError):
                state.cursor(state.revision, str(self.entry), line, column)
        with self.assertRaises(ValueError):
            state.cursor(state.revision, "../main.typ", 1, 0)

    def test_post_navigation_uses_origin_checks_and_never_accepts_editor_target(self):
        state = self.state("Plain text.", "<p>Plain text.</p>", editor_server="configured-server")
        self.assertEqual(state.public()["editorServer"], "configured-server")
        server = ThreadingHTTPServer(("127.0.0.1", 0), handler_for(state))
        worker = threading.Thread(target=server.serve_forever, daemon=True)
        worker.start()
        base = f"http://127.0.0.1:{server.server_port}"
        def request(path, payload, origin=None):
            headers = {"Content-Type": "application/json"}
            if origin:
                headers["Origin"] = origin
            return Request(base + path, json.dumps(payload).encode(), headers)
        try:
            payload = {"revision": state.revision, "fragments": [self.fragment(state, "text")],
                       "editorServer": "request-must-not-select-server"}
            with urlopen(request("/api/source", payload)) as response:
                self.assertEqual(json.load(response)["status"], "located")
            self.assertEqual(state.editor.address, "configured-server")
            with self.assertRaises(HTTPError) as wrong:
                urlopen(request("/api/source", payload, "https://other.test"))
            self.assertEqual(wrong.exception.code, 403)
            wrong.exception.close()
            payload = {"revision": state.revision, "path": str(self.entry), "line": 1, "column": 0}
            with urlopen(request("/api/cursor", payload)) as response:
                self.assertEqual(json.load(response)["status"], "located")
        finally:
            server.shutdown()
            server.server_close()
            worker.join()

    def test_same_origin_standalone_restart_rejects_old_editor_highlight_request(self):
        state = self.state("Plain text.", "<p>Plain text.</p>", editor_server="editor-address")
        server = ThreadingHTTPServer(("127.0.0.1", 0), handler_for(state))
        worker = threading.Thread(target=server.serve_forever, daemon=True)
        worker.start()
        base = f"http://127.0.0.1:{server.server_port}"
        try:
            # A terminal page can retain this identity while another Reader
            # process later occupies the same stable origin and revision.
            prior = json.load(urlopen(base + "/api/state"))
            restarted = self.state("Plain text.", "<p>Plain text.</p>")
            self.assertEqual(prior["revision"], restarted.revision)
            server.RequestHandlerClass = handler_for(restarted)
            for expected in (prior["editorServer"], None, ""):
                payload = {"revision": prior["revision"], "editorServer": expected,
                           "fragments": [self.fragment(restarted, "text")]}
                request = Request(base + "/api/highlight", json.dumps(payload).encode(),
                                  {"Content-Type": "application/json"})
                with patch("flow_reader.services.selection.apply_highlight") as apply:
                    with urlopen(request) as response:
                        self.assertEqual(json.load(response)["status"], "editor-mismatch")
                    apply.assert_not_called()
                self.assertEqual(self.entry.read_text(), "Plain text.")
        finally:
            server.shutdown()
            server.server_close()
            worker.join()

    def test_editor_identity_is_rechecked_at_final_verified_writer(self):
        state = self.state("Plain text.", "<p>Plain text.</p>", editor_server="editor-address")
        fragment = self.fragment(state, "text")
        def verified(*arguments, writer):
            state.editor_server = "different-editor"
            return writer(self.entry, b"Plain text.", b"Plain #highlight[text].")
        with patch.object(state.editor, "write", return_value="highlighted") as write:
            with patch("flow_reader.services.selection.apply_highlight", side_effect=verified):
                result = state.highlight(state.revision, [fragment], expected_editor="editor-address")
            self.assertEqual(result["status"], "editor-mismatch")
            write.assert_not_called()
        self.assertEqual(self.entry.read_text(), "Plain text.")


class NeovimWriterTests(unittest.TestCase):
    def test_private_json_payload_modified_rejection_and_fixed_process_arguments(self):
        editor = NeovimEditor("configured-server", executable="/Applications/Neovim bin/nvim")
        source = '한글 "quoted"\n$(never execute)\n'
        temporary_paths = []
        def invoke(argv, **options):
            self.assertEqual(argv[:4], ["/Applications/Neovim bin/nvim", "--server",
                                       "configured-server", "--remote-expr"])
            self.assertNotIn(source, argv[-1])
            self.assertNotIn("shell", options)
            match = re.search(r"readfile\('([^']+)'\)", argv[-1])
            self.assertIsNotNone(match)
            path = Path(match.group(1))
            temporary_paths.append(path)
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)
            self.assertEqual(json.loads(path.read_text()), {
                "path": "/project/odd'file.typ", "original": source, "updated": source + "new",
            })
            return subprocess.CompletedProcess(argv, 0, "modified\n", "")
        with patch("flow_reader.services.editor_sync.subprocess.run", side_effect=invoke):
            result = editor.write(Path("/project/odd'file.typ"), source.encode(), (source + "new").encode())
        self.assertEqual(result, "modified")
        self.assertTrue(all(not path.exists() for path in temporary_paths))
        self.assertEqual(vim_string("a'b\\c"), "'a''b\\c'")

    def test_failed_or_unknown_rpc_responses_never_claim_success(self):
        writer = NeovimEditor("server")
        for result in (subprocess.CompletedProcess([], 1, "highlighted", "failed"),
                       subprocess.CompletedProcess([], 0, "unexpected", "")):
            with patch("flow_reader.services.editor_sync.subprocess.run", return_value=result):
                self.assertEqual(writer.write(Path("/x.typ"), b"before", b"after"), "error")
        for error in (OSError("not found"), subprocess.TimeoutExpired("nvim", 10)):
            temporary_paths = []
            def fail(argv, **options):
                match = re.search(r"readfile\('([^']+)'\)", argv[-1])
                path = Path(match.group(1))
                temporary_paths.append(path)
                # The payload is closed and readable by a second opener before
                # the RPC begins, including on Windows.
                with path.open("r", encoding="utf-8") as stream:
                    self.assertEqual(json.load(stream)["original"], "before")
                raise error
            with patch("flow_reader.services.editor_sync.subprocess.run", side_effect=fail):
                self.assertEqual(writer.write(Path("/x.typ"), b"before", b"after"), "error")
            self.assertEqual(len(temporary_paths), 1)
            self.assertFalse(temporary_paths[0].exists())

    @unittest.skipUnless(shutil.which("nvim"), "Neovim is needed for local RPC integration")
    def test_real_neovim_rpc_rejects_dirty_buffer_then_saves_verified_edit(self):
        module = ROOT.parents[1] / "editors/neovim"
        if not (module / "lua/tinymist/reader.lua").is_file():
            self.skipTest("Optional Neovim module is unavailable")
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "한글'file.typ"
            source.write_text("Original 한글.\n")
            socket = root / "editor.sock"
            setup = "lua vim.opt.rtp:append(" + json.dumps(str(module)) + "); require('tinymist.reader').setup({auto_open=false, root=" + json.dumps(str(root)) + "})"
            process = subprocess.Popen(["nvim", "--headless", "--clean", "--listen", str(socket),
                                        "-c", setup, str(source)], stdout=subprocess.DEVNULL,
                                       stderr=subprocess.DEVNULL)
            try:
                deadline = time.monotonic() + 5
                while not socket.exists() and process.poll() is None and time.monotonic() < deadline:
                    time.sleep(.02)
                self.assertTrue(socket.exists(), "Neovim RPC socket did not start")
                def evaluate(expression):
                    return subprocess.run(["nvim", "--server", str(socket), "--remote-expr", expression],
                                          capture_output=True, text=True, check=True, timeout=5)
                evaluate("luaeval('vim.api.nvim_buf_set_lines(0, 0, -1, false, {\"Unsaved contents.\"})')")
                writer = NeovimEditor(str(socket))
                self.assertEqual(writer.write(source, b"Original \xed\x95\x9c\xea\xb8\x80.\n", b"Verified edit.\n"),
                                 "modified")
                self.assertEqual(source.read_text(), "Original 한글.\n")
                self.assertIn("Unsaved contents.", evaluate("getline(1)").stdout)
                evaluate("luaeval('vim.cmd(\"edit!\")')")
                self.assertEqual(writer.write(source, "Original 한글.\n".encode(), b"Verified edit.\n"),
                                 "highlighted")
                self.assertEqual(source.read_text(), "Verified edit.\n")
                self.assertIn("Verified edit.", evaluate("getline(1)").stdout)
            finally:
                process.terminate()
                process.wait(timeout=5)


if __name__ == "__main__":
    unittest.main()
