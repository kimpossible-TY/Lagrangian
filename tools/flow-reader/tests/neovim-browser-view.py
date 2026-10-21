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
    for name in ("root", "entry", "address", "url"):
        parser.add_argument("--" + name, required=True)
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="reader-browser-view-") as temporary:
        work = Path(temporary).resolve()
        editor = EditorTTY(
            work, command=[NODE, str(ROOT / "tools/flow-reader/terminal.mjs")],
            entry=Path(args.entry), address=args.address,
            reader_options={"root": args.root, "url": args.url, "profile": str(work / "browser")},
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
            os.write(editor.master, b"q")
            editor.pump_until(lambda: len(editor.lua_rpc("vim.api.nvim_list_wins()")) == 1, timeout=10)
            assert editor.lua_rpc("vim.api.nvim_buf_get_name(0)") == str(Path(args.entry).resolve())
            print(json.dumps({"started": True, "sixelViewport": [500, 580], "input": True, "source": True, "stopped": True}))
        finally:
            editor.close()


if __name__ == "__main__":
    main()
