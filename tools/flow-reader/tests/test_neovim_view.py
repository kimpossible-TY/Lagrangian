"""Exercise the same-connection Neovim TUI through a disposable POSIX PTY.

This terminal emulator fixture answers real capability/geometry probes and records
the native image stream. Actual HTML/browser actions have a separate fixture.
"""

import json
import os
from pathlib import Path
import select
import shutil
import signal
import subprocess
import tempfile
import time
import unittest

try:
    import fcntl
    import pty
    import struct
    import termios
except ImportError:
    pty = None

ROOT = Path(__file__).resolve().parents[3]
NVIM = shutil.which("nvim")
NODE = shutil.which("node")
PYTHON = shutil.which("python3")


class EditorTTY:
    def __init__(self, work, command=None, probe=None, entry=None, address=None, reader_options=None):
        self.work = work
        self.output = bytearray()
        self.cell = (10, 20)
        self.answer_geometry = True
        self.answer_graphics = True
        self.source = entry or work / "source.typ"
        if entry is None:
            self.source.write_text("Hello source.\nSecond line.\n")
        self.address = address or str(work / "editor.sock")
        init = work / "init.lua"
        opts = {
            "root": str(work), "entry": str(self.source), "auto_open": False,
            "command": command or [NODE, str(work / "host.mjs")],
        }
        opts.update(reader_options or {})
        init.write_text(
            "vim.opt.rtp:append(" + json.dumps(str(ROOT / "editors/neovim")) + ")\n"
            "require('tinymist.reader').setup(vim.json.decode(" + self.lua(json.dumps(opts)) + "))\n"
            + (probe or "")
        )
        (work / "host.mjs").write_text("""
import { appendFileSync } from 'node:fs';
import { TerminalReader } from HOST;
import { EditorTransport } from TRANSPORT;
import { parseArguments } from OPTIONS;
const options = parseArguments(process.argv.slice(2));
const log = data => appendFileSync(LOG, JSON.stringify(data)+'\\n');
const page = {
  async setViewportSize(size) { log({viewport:size}); },
  async evaluate() { return false; },
  async screenshot() { return Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==','base64'); },
  keyboard: { async insertText(text) {log({text});}, async press(key) {log({key});} },
  mouse: { async move(x,y) {log({move:[x,y]});}, async down() {log({down:true});},
    async up() {log({up:true});}, async wheel(x,y) {log({wheel:[x,y]});} },
};
const reader = new TerminalReader({protocol:options.protocol, 'control-file':options['control-file']}, page, new EditorTransport());
await reader.run();
log({stopped:true});
""".replace("HOST", json.dumps((ROOT / "tools/flow-reader/terminal/host.mjs").as_uri()))
            .replace("TRANSPORT", json.dumps((ROOT / "tools/flow-reader/terminal/editor-transport.mjs").as_uri()))
            .replace("OPTIONS", json.dumps((ROOT / "tools/flow-reader/terminal/options.mjs").as_uri()))
            .replace("LOG", json.dumps(str(work / "input.jsonl"))))
        self.master, self.slave = pty.openpty()
        self.before = termios.tcgetattr(self.slave)
        self.resize(100, 32, signal_editor=False)

        def session():
            os.setsid()
            fcntl.ioctl(self.slave, termios.TIOCSCTTY, 0)

        env = {key: value for key, value in os.environ.items() if key not in
               ("TMUX", "NVIM", "SSH_TTY", "ITERM_SESSION_ID", "WT_SESSION", "TERM_PROGRAM")}
        env["TERM"] = "xterm-256color"
        env["PYTHON"] = PYTHON
        env["XDG_STATE_HOME"] = str(work / "state")
        self.process = subprocess.Popen(
            [NVIM, "-u", str(init), "-i", "NONE", "-n", "--listen", self.address, "--", str(self.source)],
            stdin=self.slave, stdout=self.slave, stderr=self.slave, env=env, preexec_fn=session,
        )
        self.pump_until(lambda: Path(self.address).exists())
        self.pump(0.25)

    @staticmethod
    def lua(value):
        return "'" + value.replace("'", "''") + "'"

    def rpc(self, expression):
        child = subprocess.Popen(
            [NVIM, "--server", self.address, "--remote-expr", expression],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        )
        deadline = time.monotonic() + 6
        while child.poll() is None and time.monotonic() < deadline:
            self.pump(0.01)
        if child.poll() is None:
            child.kill()
            out, err = child.communicate(timeout=1)
            raise AssertionError("Editor RPC timed out: " + expression + "\n" + repr(self.output[-1800:]))
        out, err = child.communicate(timeout=1)
        if child.returncode:
            raise AssertionError(err.decode())
        return out.decode().strip()

    def lua_rpc(self, expression):
        return json.loads(self.rpc("json_encode(luaeval(" + self.lua(expression) + "))"))

    def pump(self, duration=0.05):
        deadline = time.monotonic() + duration
        while time.monotonic() < deadline:
            if not select.select([self.master], [], [], max(0, deadline - time.monotonic()))[0]:
                break
            data = os.read(self.master, 1048576)
            self.output.extend(data)
            # Queries are short atomic writes in these fixtures; fragments are
            # accumulated to avoid depending on PTY read boundaries.
            self.requests = getattr(self, "requests", b"") + data
            queries = [
                (b"\x1b[5n", b"\x1b[0n"),
                (b"\x1b[c", b"\x1b[?62;4c" if self.answer_graphics else b"\x1b[?62c"),
                (b"\x1b[?80$p", b"\x1b[?80;1$y"),
                (b"\x1b]11;?", b"\x1b]11;rgb:0000/0000/0000\x1b\\"),
                (b"\x1b]10;?", b"\x1b]10;rgb:ffff/ffff/ffff\x1b\\"),
            ]
            if self.answer_geometry:
                queries.append((b"\x1b[16t", f"\x1b[6;{self.cell[1]};{self.cell[0]}t".encode()))
            for query, reply in queries:
                while query in self.requests:
                    self.requests = self.requests.replace(query, b"", 1)
                    os.write(self.master, reply)
            self.requests = self.requests[-512:]

    def pump_until(self, predicate, timeout=6):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            self.pump(0.025)
            if predicate():
                return
            if self.process.poll() is not None:
                break
        raise AssertionError("Neovim TUI did not make progress: " + repr(self.output[-1800:]))

    def resize(self, columns, rows, signal_editor=True):
        # Deliberately lie about ioctl pixels like Windows OpenSSH: only the
        # terminal's CSI response is authoritative for SIXEL placement.
        fcntl.ioctl(self.slave, termios.TIOCSWINSZ, struct.pack("HHHH", rows, columns, 640, 480))
        if signal_editor:
            self.process.send_signal(signal.SIGWINCH)

    def events(self):
        log = self.work / "input.jsonl"
        return [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []

    def close(self):
        if self.process.poll() is None:
            try:
                self.rpc("execute('qa!')")
            except (AssertionError, subprocess.SubprocessError):
                pass
        if self.process.poll() is None:
            self.process.terminate()
        os.close(self.master)
        os.close(self.slave)
        try:
            self.process.wait(timeout=2)
        except subprocess.TimeoutExpired:
            self.process.kill()
            self.process.wait(timeout=2)


@unittest.skipUnless(pty is not None and NVIM and NODE and PYTHON, "Requires POSIX PTY, Neovim 0.12, Node and Python")
class NeovimViewTests(unittest.TestCase):
    def setUp(self):
        version = subprocess.check_output([NVIM, "--version"], text=True).splitlines()[0]
        if tuple(map(int, version.split("v", 1)[1].split(".")[:2])) < (0, 12):
            self.skipTest("Internal view requires Neovim 0.12")
        self.directory = tempfile.TemporaryDirectory(prefix="reader-view-")
        self.editor = EditorTTY(Path(self.directory.name).resolve())

    def tearDown(self):
        self.editor.close()
        self.directory.cleanup()

    def start(self):
        result = self.editor.lua_rpc("{require('tinymist.reader').start()}")
        self.assertEqual(result, [True])
        self.editor.pump_until(lambda: b'\x1bP0;1;0q"1;1;' in self.editor.output)

    def test_start_input_source_jump_resize_stop_and_restart(self):
        e = self.editor
        self.start()
        windows = e.lua_rpc("vim.api.nvim_list_wins()")
        self.assertEqual(len(windows), 2)
        view = e.lua_rpc("vim.api.nvim_get_current_win()")
        geometry = e.lua_rpc("{vim.api.nvim_win_get_position(0),vim.api.nvim_win_get_width(0),vim.api.nvim_win_get_height(0)}")
        prefix = f"\x1b7\x1b[{geometry[0][0]+1};{geometry[0][1]+1}H\x1b[?80l\x1bP".encode()
        self.assertIn(prefix, e.output)
        self.assertIn(b"\x1b[?80h\x1b8", e.output)
        self.assertIn({"viewport": {"width": geometry[1]*10, "height": (geometry[2]-1)*20}}, e.events())
        cursor = e.lua_rpc("require('tinymist.reader').cursor()")
        self.assertEqual(cursor["path"], str(e.source))
        e.pump(0.1)
        os.write(e.master, "한\x1b[200~h q\x1b[201~\x1b[A".encode())
        e.pump_until(lambda: {"key": "ArrowUp"} in e.events())
        self.assertIn({"text": "한"}, e.events())
        self.assertIn({"text": "h q"}, e.events())
        # Actual terminal mouse events must reach browser coordinates, including
        # the first click while source has focus.
        e.lua_rpc("(function() vim.cmd.stopinsert(); vim.api.nvim_set_current_win(" + str(windows[0]) + "); return true end)()")
        e.pump(0.1)
        column, row = geometry[0][1] + 3, geometry[0][0] + 3
        # Neovim coalesces coordinates for mouse reports delivered in one input
        # batch. Exercise a real timed gesture across input-processing cycles.
        for report in [f"\x1b[<0;{column};{row}M", f"\x1b[<32;{column+3};{row}M", f"\x1b[<0;{column+3};{row}m"]:
            os.write(e.master, report.encode())
            e.pump(0.06)
        e.pump_until(lambda: {"up": True} in e.events())
        self.assertIn({"down": True}, e.events())
        self.assertIn({"move": [25, 50]}, e.events())
        result = e.lua_rpc("require('tinymist.reader').jump {path=" + e.lua(str(e.source)) + ",line=2,column=3,source_hash=vim.fn.sha256('Hello source.\\nSecond line.\\n')}")
        self.assertEqual(result, "jumped")
        self.assertNotEqual(e.lua_rpc("vim.api.nvim_get_current_win()"), view)
        self.assertEqual(e.lua_rpc("vim.bo[vim.api.nvim_win_get_buf(" + str(view) + ")].buftype"), "terminal")
        e.cell = (8, 16)
        e.resize(120, 36)
        e.pump_until(lambda: any(event.get("viewport", {}).get("height") == 33*16 for event in e.events()))
        self.assertTrue(e.lua_rpc("require('tinymist.reader').stop()"))
        self.assertEqual(len(e.lua_rpc("vim.api.nvim_list_wins()")), 1)
        self.assertEqual(e.source.read_text(), "Hello source.\nSecond line.\n")
        self.assertIn({"stopped": True}, e.events())
        e.output.clear()
        self.start()
        os.write(e.master, b"q")
        e.pump_until(lambda: len(e.lua_rpc("vim.api.nvim_list_wins()")) == 1)

    def test_missing_geometry_resumes_tui_and_preserves_editor(self):
        e = self.editor
        before = termios.tcgetattr(e.slave)
        e.answer_geometry = False
        result = e.lua_rpc("{require('tinymist.reader').start()}")
        self.assertEqual(result[0], False)
        self.assertIn("cell", result[1])
        self.assertEqual(len(e.lua_rpc("vim.api.nvim_list_wins()")), 1)
        self.assertEqual(before, termios.tcgetattr(e.slave))
        os.write(e.master, b"j")
        e.pump_until(lambda: e.lua_rpc("vim.api.nvim_win_get_cursor(0)[1]") == 2)

    def test_closed_reader_window_disposes_host_and_preserves_dirty_source(self):
        e = self.editor
        self.start()
        source = e.lua_rpc("vim.api.nvim_list_wins()[1]")
        e.lua_rpc("(function() vim.api.nvim_buf_set_lines(vim.api.nvim_win_get_buf(" + str(source) + "),0,1,false,{'Unsaved'}); vim.api.nvim_win_close(0,true); return true end)()")
        e.pump_until(lambda: {"stopped": True} in e.events())
        self.assertTrue(e.lua_rpc("vim.bo.modified"))
        self.assertEqual(e.lua_rpc("vim.api.nvim_get_current_line()"), "Unsaved")
        self.assertEqual(e.source.read_text(), "Hello source.\nSecond line.\n")

    def test_probe_crash_resumes_only_its_tui_and_leaves_input_usable(self):
        e = self.editor
        wrapper = e.work / "crashed-probe"
        wrapper.write_text(f"#!{PYTHON}\nimport os,sys,signal\nos.kill(int(sys.argv[2]),signal.SIGSTOP)\nos._exit(9)\n")
        wrapper.chmod(0o755)
        result = e.lua_rpc("(function() vim.env.PYTHON=" + e.lua(str(wrapper)) + "; return {require('tinymist.reader').start()} end)()")
        self.assertEqual(result[0], False)
        self.assertIn("measurement failed", result[1])
        os.write(e.master, b"j")
        e.pump_until(lambda: e.lua_rpc("vim.api.nvim_win_get_cursor(0)[1]") == 2)

    def test_hidden_view_clears_images_and_stop_keeps_another_tab_focused(self):
        e = self.editor
        self.start()
        e.pump(0.8)
        e.output.clear()
        e.pump(0.8)
        self.assertNotIn(b"\x1bP0;1;0q", e.output, "Idle views must not retransmit unchanged images")
        os.write(e.master, b"\x1c\x0e\x0c") # Terminal-normal mode, then full redraw.
        e.pump_until(lambda: b"\x1bP0;1;0q" in e.output)
        e.lua_rpc("(function() vim.cmd.stopinsert(); vim.cmd.tabnew(); return true end)()")
        current = e.lua_rpc("vim.api.nvim_get_current_win()")
        e.pump(0.35)
        e.output.clear()
        e.pump(0.6)
        self.assertNotIn(b"\x1bP0;1;0q", e.output)
        self.assertTrue(e.lua_rpc("require('tinymist.reader').stop()"))
        self.assertEqual(current, e.lua_rpc("vim.api.nvim_get_current_win()"))

    def test_overlapping_float_hides_images_until_its_border_is_removed(self):
        e = self.editor
        self.start()
        floating = e.lua_rpc("vim.api.nvim_open_win(vim.api.nvim_create_buf(false,true),false,{relative='editor',row=0,col=48,width=1,height=2,border='single'})")
        e.pump(0.6)
        e.output.clear()
        e.pump(0.6)
        self.assertNotIn(b"\x1bP0;1;0q", e.output)
        e.lua_rpc("(function() vim.api.nvim_win_close(" + str(floating) + ",true); return true end)()")
        e.pump_until(lambda: b"\x1bP0;1;0q" in e.output)

    def test_split_failure_preserves_source_and_releases_startup_state(self):
        e = self.editor
        e.lua_rpc("(function() vim.o.winwidth=100; vim.o.winminwidth=100; return true end)()")
        result = e.lua_rpc("{require('tinymist.reader').start()}")
        self.assertEqual(result[0], False)
        self.assertIn("create its view", result[1])
        self.assertEqual(len(e.lua_rpc("vim.api.nvim_list_wins()")), 1)
        self.assertEqual(e.lua_rpc("vim.api.nvim_buf_get_name(0)"), str(e.source))
        e.lua_rpc("(function() vim.o.winminwidth=1; vim.o.winwidth=20; return true end)()")
        self.start()

    def test_replacing_reader_buffer_preserves_its_new_window_and_unsaved_text(self):
        e = self.editor
        self.start()
        window = e.lua_rpc("vim.api.nvim_get_current_win()")
        replacement = e.lua_rpc("(function() vim.cmd.stopinsert(); local buf=vim.api.nvim_create_buf(true,false); vim.api.nvim_buf_set_lines(buf,0,-1,false,{'Replacement work'}); vim.api.nvim_win_set_buf(0,buf); return buf end)()")
        e.pump_until(lambda: {"stopped": True} in e.events())
        self.assertEqual(e.lua_rpc("vim.api.nvim_get_current_win()"), window)
        self.assertEqual(e.lua_rpc("vim.api.nvim_get_current_buf()"), replacement)
        self.assertTrue(e.lua_rpc("vim.bo.modified"))
        self.assertEqual(e.lua_rpc("vim.api.nvim_get_current_line()"), "Replacement work")
        self.assertEqual(len(e.lua_rpc("vim.api.nvim_list_wins()")), 2)


if __name__ == "__main__":
    unittest.main()
