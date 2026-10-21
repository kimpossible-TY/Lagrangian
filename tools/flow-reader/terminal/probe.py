"""Measure the attached Neovim TUI's terminal without racing its input decoder.

Neovim 0.12 consumes CSI 16t replies. Only the editor's identified parent TUI
is paused during this bounded probe; both this helper and Lua resume it on exit.
"""

import argparse
import base64
import json
import os
import re
import select
import signal
import stat
import subprocess
import termios
import time


def process_field(pid, field):
    return subprocess.check_output(
        ["ps", "-p", str(pid), "-o", field + "="], text=True, timeout=1,
    ).strip()


def interrupted(_signal, _frame):
    raise InterruptedError("Terminal measurement was interrupted")


def probe(tui_pid, protocol=None, timeout=0.8):
    # The client is identified by nvim_get_chan_info, never by a process search.
    # Check ancestry again immediately before signalling to avoid stale identities.
    if int(process_field(os.getppid(), "ppid")) != tui_pid:
        raise ValueError("The terminal client must own this Neovim editor")
    terminal = process_field(tui_pid, "tty")
    if terminal in ("", "?", "??", "-"):
        raise ValueError("The Neovim TUI has no terminal device")
    terminal = "/dev/" + terminal.removeprefix("/dev/")
    if not stat.S_ISCHR(os.stat(terminal).st_mode):
        raise ValueError("The TUI terminal is not a character device")
    descriptor = os.open(terminal, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
    previous = termios.tcgetattr(descriptor)
    paused = False
    try:
        for name in ("SIGTERM", "SIGINT", "SIGHUP"):
            signal.signal(getattr(signal, name), interrupted)
        for name in ("SIGTTOU", "SIGTTIN"):
            signal.signal(getattr(signal, name), signal.SIG_IGN)
        os.kill(tui_pid, signal.SIGSTOP)
        paused = True
        if previous[3] & (termios.ICANON | termios.ECHO):
            raise ValueError("The Neovim TUI has not entered raw input mode; retry after startup")
        # Keep the TUI's existing raw settings unchanged. Even a hard-killed
        # helper cannot leave a new termios configuration behind.
        stopped_by = time.monotonic() + 0.3
        while "T" not in process_field(tui_pid, "state"):
            if time.monotonic() >= stopped_by:
                raise ValueError("The TUI input client could not be paused for measurement")
            time.sleep(0.005)
        os.write(descriptor, (
            b"\x1b[?80$p\x1b[16t\x1b]1337;ReportCellSize\x07"
            b"\x1b_Gi=39732,a=q,t=d,f=24,s=1,v=1;AAAA\x1b\\\x1b[c"
        ))
        data = b""
        deadline = time.monotonic() + timeout
        dimensions = None
        selected = protocol
        display_mode = None
        while time.monotonic() < deadline:
            remaining = deadline - time.monotonic()
            if not select.select([descriptor], [], [], max(0, remaining))[0]:
                break
            data += os.read(descriptor, 65536)
            if len(data) > 1048576:
                raise ValueError("Terminal response exceeds the measurement limit")
            cell = re.search(rb"\x1b\[6;(\d+);(\d+)t", data)
            logical = re.search(rb"\x1b\]1337;ReportCellSize=([\d.]+);([\d.]+)(?:;[\d.]+)?(?:\x07|\x1b\\)", data)
            if logical:
                dimensions = (float(logical[2]), float(logical[1]))
            elif cell:
                dimensions = (int(cell[2]), int(cell[1]))
            mode = re.search(rb"\x1b\[\?80;([0-4])\$y", data)
            if mode:
                display_mode = int(mode[1])
            attributes = re.search(rb"\x1b\[\?([\d;]+)c", data)
            if not protocol:
                if re.search(rb"\x1b_Gi=39732;OK\x1b\\", data):
                    selected = "kitty"
                else:
                    if attributes and b"4" in attributes[1].split(b";")[1:]:
                        selected = "sixel"
            # DA1 is queried last. Its complete reply also drains earlier
            # responses before the TUI resumes its own escape decoder.
            if selected and dimensions and attributes and (selected != "sixel" or display_mode is not None):
                break
        if not selected:
            raise ValueError("The terminal did not advertise SIXEL or Kitty graphics; use a graphics-capable Windows Terminal")
        if not dimensions or not (1 <= dimensions[0] <= 200 and 1 <= dimensions[1] <= 400):
            raise ValueError("The terminal did not report its character-cell size; check terminal/SSH graphics support")
        if selected == "sixel" and display_mode not in (1, 2, 4):
            raise ValueError("The terminal did not report a supported SIXEL cursor placement mode")
        # Preserve typed input while consuming only complete terminal reports.
        remainder = re.sub(rb"\x1b\[[\d;?]*[cnt]", b"", data)
        remainder = re.sub(rb"\x1b\[\?\d+;\d+\$y", b"", remainder)
        remainder = re.sub(rb"\x1b(?:\][^\x07]*?(?:\x07|\x1b\\)|[P_].*?\x1b\\)", b"", remainder, flags=re.S)
        return {"protocol": selected, "cellWidth": dimensions[0], "cellHeight": dimensions[1],
                "sixelDisplay": display_mode == 1,
                "input": base64.b64encode(remainder).decode("ascii")}
    finally:
        try:
            termios.tcsetattr(descriptor, termios.TCSANOW, previous)
        finally:
            os.close(descriptor)
            if paused:
                os.kill(tui_pid, signal.SIGCONT)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("tui_pid", type=int)
    parser.add_argument("--protocol", choices=("sixel", "kitty", "iterm2"))
    args = parser.parse_args()
    try:
        print(json.dumps(probe(args.tui_pid, args.protocol)))
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        print(json.dumps({"error": str(error)}))
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
