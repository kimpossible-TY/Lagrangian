"""Exercise real terminal ownership without requiring a browser installation.

Browser/document behavior is covered separately by terminal-browser.mjs. The page
stub here isolates raw input, signal cleanup, and the readable-stream lifecycle.
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


TERMINAL = Path(__file__).resolve().parents[1] / "terminal.mjs"
HOST = TERMINAL.parent / "terminal/host.mjs"
SERVICE = TERMINAL.parent / "terminal/service.mjs"
NODE = shutil.which("node")
PAGE_STUB = """
const { TerminalReader } = await import(process.argv[1]);
const page = {
  async setViewportSize() {},
  async evaluate() { return false; },
  async screenshot() {
    return Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg==', 'base64');
  },
};
await new TerminalReader({ protocol: 'iterm2' }, page).run();
"""


@unittest.skipUnless(pty is not None and NODE, "Requires a POSIX PTY and Node.js")
class TerminalLifetimeTests(unittest.TestCase):
    def run_terminal(self, stop, script=PAGE_STUB, trigger=b"\x1b]1337;File="):
        master, slave = pty.openpty()
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 80, 720, 432))
        before = termios.tcgetattr(slave)
        environment = os.environ.copy()
        environment.pop("TMUX", None)
        environment.pop("NVIM", None)
        process = subprocess.Popen(
            [NODE, "--input-type=module", "-e", script, HOST.as_uri()],
            stdin=slave, stdout=slave, stderr=slave, env=environment,
        )
        output = bytearray()
        stopped = False
        deadline = time.monotonic() + 8
        try:
            while process.poll() is None and time.monotonic() < deadline:
                if select.select([master], [], [], 0.1)[0]:
                    output.extend(os.read(master, 65536))
                    if trigger in output and not stopped:
                        stop(process, master)
                        stopped = True
            self.assertIsNotNone(process.poll(), "Reader must exit after releasing input")
            while select.select([master], [], [], 0.01)[0]:
                output.extend(os.read(master, 65536))
            self.assertEqual(process.returncode, 0, bytes(output[-2000:]))
            self.assertTrue(stopped)
            self.assertIn(b"\x1b[?1049l", output)
            self.assertIn(b"\x1b[?1006l", output)
            self.assertEqual(before, termios.tcgetattr(slave))
        finally:
            if process.poll() is None:
                process.kill()
            process.wait(timeout=3)
            os.close(master)
            os.close(slave)

    def test_quit_restores_terminal_and_releases_initially_idle_stdin(self):
        self.run_terminal(lambda _process, master: os.write(master, b"q"))

    def test_sigterm_restores_terminal(self):
        self.run_terminal(lambda process, _master: process.send_signal(signal.SIGTERM))

    def test_startup_cell_report_cannot_race_initial_browser_resize(self):
        script = """
const { TerminalReader } = await import(process.argv[1]);
let viewport;
let resizeCount = 0;
const page = {
  async setViewportSize(size) {
    const count = ++resizeCount;
    await new Promise(resolve => setTimeout(resolve, count === 1 ? 120 : 0));
    viewport = size;
  },
  async evaluate() { return false; },
  async screenshot() {
    return Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg==', 'base64');
  },
};
const terminal = new TerminalReader({ protocol: 'iterm2' }, page);
const stop = setTimeout(() => terminal.stop(), 350);
try { await terminal.run(); }
finally { clearTimeout(stop); }
if (resizeCount < 2 || terminal.size.width !== 560 || viewport.width !== terminal.size.width)
  throw new Error(`Initial browser resize raced the cell report: ${JSON.stringify({viewport, size: terminal.size, resizeCount})}`);
"""
        self.run_terminal(
            lambda _process, master: os.write(master, b"\x1b]1337;ReportCellSize=18;7;2\x07"),
            script=script, trigger=b"ReportCellSize\x07",
        )

    def test_capture_cannot_restore_an_old_viewport_over_a_cell_resize(self):
        script = """
const { TerminalReader } = await import(process.argv[1]);
let viewport;
let resizeCount = 0;
const page = {
  async setViewportSize(size) { resizeCount++; viewport = size; },
  async evaluate() { return false; },
  async screenshot() {
    const originalViewport = viewport;
    process.stdout.write('SNAPSHOT-START');
    await new Promise(resolve => setTimeout(resolve, 120));
    // Model a screenshot backend which restores metrics after taking a frame.
    viewport = originalViewport;
    return Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg==', 'base64');
  },
};
const terminal = new TerminalReader({ protocol: 'iterm2' }, page);
const stop = setTimeout(() => terminal.stop(), 550);
try { await terminal.run(); }
finally { clearTimeout(stop); }
if (resizeCount < 2 || terminal.size.width !== 560 || viewport.width !== terminal.size.width)
  throw new Error(`Screenshot restored an obsolete browser viewport: ${JSON.stringify({viewport, size: terminal.size, resizeCount})}`);
"""
        self.run_terminal(
            lambda _process, master: os.write(master, b"\x1b]1337;ReportCellSize=18;7;2\x07"),
            script=script, trigger=b"SNAPSHOT-START",
        )

    def test_owned_service_cleanup_stops_a_compiler_which_ignores_sigterm(self):
        with tempfile.TemporaryDirectory(prefix="terminal-process-group-") as temporary:
            temporary = Path(temporary)
            state = temporary / "processes.json"
            child_ready = temporary / "compiler.pid"
            interpreter = temporary / "fake-python"
            compiler = "import os,signal,time; from pathlib import Path; signal.signal(signal.SIGTERM, signal.SIG_IGN); Path(os.environ['FLOW_TEST_COMPILER_PID']).write_text(str(os.getpid())); time.sleep(300)"
            interpreter.write_text(
                "#!" + shutil.which("python3") + "\n"
                "import json,os,subprocess,sys,time\n"
                "from pathlib import Path\n"
                "child=subprocess.Popen([sys.executable,'-c'," + repr(compiler) + "])\n"
                "ready=Path(os.environ['FLOW_TEST_COMPILER_PID'])\n"
                "while not ready.exists(): time.sleep(0.01)\n"
                "Path(os.environ['FLOW_TEST_PROCESS_STATE']).write_text(json.dumps({'parent':os.getpid(),'child':child.pid}))\n"
                "print(json.dumps({'url':'http://127.0.0.1:23626/'}),flush=True)\n"
                "time.sleep(300)\n"
            )
            interpreter.chmod(0o700)
            environment = os.environ.copy()
            environment.update({
                "PYTHON": str(interpreter),
                "FLOW_TEST_PROCESS_STATE": str(state),
                "FLOW_TEST_COMPILER_PID": str(child_ready),
            })
            script = "const {startReader}=await import(process.argv[1]); const reader=await startReader({root:process.argv[2]}); await reader.close();"
            processes = {}
            try:
                result = subprocess.run(
                    [NODE, "--input-type=module", "-e", script, SERVICE.as_uri(), str(temporary)],
                    env=environment, capture_output=True, timeout=8,
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                processes = json.loads(state.read_text())
                deadline = time.monotonic() + 2
                while time.monotonic() < deadline:
                    status = subprocess.run(["ps", "-o", "stat=", "-p", str(processes["child"])], capture_output=True, text=True).stdout.strip()
                    if not status or status.startswith("Z"):
                        break
                    time.sleep(0.05)
                else:
                    self.fail("Owned compiler must stop even when it ignores SIGTERM")
            finally:
                if state.exists():
                    processes = json.loads(state.read_text())
                for pid in processes.values():
                    try:
                        os.kill(pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass

    def test_owned_service_exit_closes_browser_and_reports_the_failure(self):
        with tempfile.TemporaryDirectory(prefix="terminal-service-exit-") as temporary:
            temporary = Path(temporary)
            opened, closed = temporary / "opened", temporary / "closed"
            control = temporary / "owner"
            control.write_text("running")
            interpreter = temporary / "fake-python"
            interpreter.write_text(
                "#!" + shutil.which("python3") + "\n"
                "import json,os,time\nfrom pathlib import Path\n"
                "print(json.dumps({'url':'http://127.0.0.1:23626/'}),flush=True)\n"
                "while not Path(os.environ['FLOW_TEST_BROWSER_OPENED']).exists(): time.sleep(0.01)\n"
                "time.sleep(0.05)\n"
            )
            interpreter.chmod(0o700)
            browser = temporary / "playwright.mjs"
            browser.write_text("""
import { writeFile } from 'node:fs/promises';
let rejectNavigation;
let keepAlive;
const page = { async goto() {
  await new Promise((_resolve, reject) => {
    rejectNavigation = reject;
    keepAlive = setInterval(() => {}, 100);
  });
} };
const context = {
  pages() { return [page]; }, on() {},
  async close() {
    clearInterval(keepAlive);
    rejectNavigation?.(new Error('Browser closed'));
    await writeFile(process.env.FLOW_TEST_BROWSER_CLOSED, 'closed');
  },
};
export const chromium = { async launchPersistentContext() {
  await writeFile(process.env.FLOW_TEST_BROWSER_OPENED, 'opened');
  return context;
} };
""")
            environment = os.environ.copy()
            environment.update({
                "PYTHON": str(interpreter),
                "FLOW_TEST_BROWSER_OPENED": str(opened),
                "FLOW_TEST_BROWSER_CLOSED": str(closed),
            })
            result = subprocess.run([
                NODE, str(TERMINAL), "--root", str(temporary),
                "--snapshot", str(temporary / "unused.png"),
                "--profile", str(temporary / "profile"),
                "--playwright-module", str(browser),
                "--control-file", str(control),
            ], env=environment, capture_output=True, timeout=5)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn(b"Reader service exited unexpectedly", result.stderr)
            self.assertTrue(opened.exists())
            self.assertTrue(closed.exists())
            self.assertFalse(control.exists())

    def test_startup_failure_removes_editor_control_file(self):
        with tempfile.TemporaryDirectory(prefix="terminal-owner-") as temporary:
            control = Path(temporary) / "owner"
            control.write_text("owned")
            process = subprocess.run(
                [NODE, str(TERMINAL), "--control-file", str(control), "--root", temporary],
                stdin=subprocess.DEVNULL, capture_output=True, timeout=5,
            )
            self.assertNotEqual(process.returncode, 0)
            self.assertIn(b"native terminal pane", process.stderr)
            self.assertFalse(control.exists())


if __name__ == "__main__":
    unittest.main()
