"""Neovim owns final writes to verified source without overwriting dirty buffers."""
import json
import os
from pathlib import Path
import subprocess
import tempfile


UNSPECIFIED_EDITOR = object()


def vim_string(value):
    """Quote a literal without Vim expression or shell interpolation."""
    return "'" + value.replace("'", "''") + "'"


class NeovimEditor:
    """Deliver a compiler-verified replacement to a fixed local Neovim server."""

    def __init__(self, address, executable="nvim"):
        if not isinstance(address, str) or not address or "\0" in address:
            raise ValueError("Expected a Neovim server address")
        self.address = address
        self.executable = executable

    def write(self, path, original, updated):
        payload = {"path": str(path), "original": original.decode("utf-8"),
                   "updated": updated.decode("utf-8")}
        # Whole source files can exceed the OS argument-size limit. A private
        # temporary JSON file also keeps document contents out of process args.
        descriptor, temporary = tempfile.mkstemp(prefix="flow-reader-edit-", suffix=".json")
        try:
            with os.fdopen(descriptor, "w", encoding="utf-8") as request:
                json.dump(payload, request, ensure_ascii=False)
            # Close before Neovim opens the file: Windows does not share an open
            # NamedTemporaryFile with another process using its default flags.
            expression = (
                "luaeval(" + vim_string("require('tinymist.reader').apply_edit(_A)")
                + ", json_decode(join(readfile(" + vim_string(temporary) + "), '')))"
            )
            try:
                result = subprocess.run(
                    [self.executable, "--server", self.address, "--remote-expr", expression],
                    capture_output=True, text=True, timeout=10, check=False,
                )
            except (OSError, subprocess.TimeoutExpired):
                return "error"
        finally:
            Path(temporary).unlink(missing_ok=True)
        status = result.stdout.strip()
        if result.returncode or status not in {
            "highlighted", "modified", "stale", "unsupported", "error",
        }:
            return "error"
        return status
