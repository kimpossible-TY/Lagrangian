"""Required real Chromium + Neovim TUI leg of terminal-browser.mjs."""
import argparse
import json
import os
from pathlib import Path
import re
import tempfile

from test_neovim_view import EditorTTY, NODE, ROOT


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("root", "entry", "address"):
        parser.add_argument("--" + name, required=True)
    parser.add_argument('--url')
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="reader-browser-view-") as temporary:
        work = Path(temporary).resolve()
        editor = EditorTTY(
            work, command=[NODE, str(ROOT / "tools/flow-reader/terminal.mjs")],
            entry=Path(args.entry), address=args.address,
            reader_options={"root": args.root, "entry": args.entry, "profile": str(work / "browser"),
                            **({"url": args.url} if args.url else {})},
            environment={'PYTHON': os.environ.get('PYTHON', 'python3')},
        )
        try:
            result = editor.lua_rpc("{require('tinymist.reader').start()}")
            assert result == [True], result
            editor.pump_until(lambda: b'\x1bP0;1;0q"1;1;500;580' in editor.output, timeout=35)
            before = len(re.findall(rb'\x1bP0;1;0q"1;1;', editor.output))
            # The real browser page changes its image after keyboard scrolling.
            editor.pump(0.1)
            os.write(editor.master, b"j")
            editor.pump_until(lambda: len(re.findall(rb'\x1bP0;1;0q"1;1;', editor.output)) > before, timeout=10)
            assert editor.lua_rpc("require('tinymist.reader').cursor().path") == str(Path(args.entry).resolve())
            source, view = editor.lua_rpc("vim.api.nvim_list_wins()")
            position, width = editor.lua_rpc("{vim.api.nvim_win_get_position(0),vim.api.nvim_win_get_width(0)}")
            divider, row = position[1], position[0] + 4
            source_width = editor.lua_rpc("vim.api.nvim_win_get_width(" + str(source) + ")")
            editor.output.clear()
            editor.mouse(0, divider, row)
            editor.mouse(32, divider + 8, row)
            editor.mouse(0, divider + 8, row, release=True)
            assert editor.lua_rpc("vim.api.nvim_win_get_width(" + str(source) + ")") == source_width + 8
            assert editor.lua_rpc("vim.api.nvim_win_get_width(" + str(view) + ")") == width - 8
            prefix = f'\x1b7\x1b[1;{divider+9}H\x1b[?80l\x1bP0;1;0q"1;1;{(width-8)*10};580'.encode()
            editor.pump_until(lambda: prefix in editor.output, timeout=15)
            # Width controls remain in Reader input mode after the native drag.
            editor.lua_rpc("(function() vim.api.nvim_set_current_win(" + str(view) + "); vim.cmd.startinsert(); return true end)()")
            os.write(editor.master, b"\x17=")
            editor.pump_until(lambda: editor.lua_rpc("vim.api.nvim_win_get_width(" + str(view) + ")") == width)
            assert editor.lua_rpc("vim.fn.mode()") == "t"
            os.write(editor.master, b"q")
            editor.pump_until(lambda: len(editor.lua_rpc("vim.api.nvim_list_wins()")) == 1, timeout=10)
            assert editor.lua_rpc("vim.api.nvim_buf_get_name(0)") == str(Path(args.entry).resolve())
            print(json.dumps({"started": True, "sixelViewport": [500, 580], "input": True, "source": True, "resized": True, "stopped": True}))
        finally:
            editor.close()


if __name__ == "__main__":
    main()
