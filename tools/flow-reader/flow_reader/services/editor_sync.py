"""Neovim owns final writes to verified source without overwriting dirty buffers."""
import json
import os
from pathlib import Path
import re
import secrets
import shutil
import stat
import subprocess
import tempfile


UNSPECIFIED_EDITOR = object()


class EditorAttachments:
    """Local registration, opaque HTTP references, service/owner-bound writes."""

    def __init__(self, output, document_id, service):
        self.directory = Path(output) / "editor-attachments"
        self.document_id = document_id
        self.service = service

    @staticmethod
    def private(path, directory=False):
        info = path.lstat()
        expected = stat.S_ISDIR if directory else stat.S_ISREG
        if (not expected(info.st_mode) or info.st_uid != os.getuid()
                or info.st_mode & 0o077):
            raise ValueError("Editor attachment storage must be private and locally owned")

    def record(self, token):
        if not isinstance(token, str) or not re.fullmatch(r"[0-9a-f]{64}", token):
            return None
        try:
            self.private(self.directory, directory=True)
            path = self.directory / (token + ".json")
            self.private(path)
            if path.stat().st_size > 16384:
                return None
            record = json.loads(path.read_text())
            if (not isinstance(record, dict) or record.get("documentID") != self.document_id
                    or record.get("service") != self.service or type(record.get("ownerPID")) is not int
                    or not 0 < record["ownerPID"] < 2 ** 31):
                return None
            os.kill(record["ownerPID"], 0)
            if record.get("controlFile") and not Path(record["controlFile"]).is_file():
                return None
            if (not isinstance(record.get("address"), str) or not record["address"] or "\0" in record["address"]
                    or not isinstance(record.get("executable"), str)
                    or not Path(record["executable"]).is_absolute()
                    or not os.access(record["executable"], os.X_OK)):
                return None
            return record
        except (OSError, ValueError, TypeError):
            return None

    def resolve(self, token):
        record = self.record(token)
        return NeovimEditor(record["address"], record["executable"]) if record else None

    def register(self, address, executable, owner_pid, control_file=None):
        # Called only by the local manager. No HTTP registration or executable input.
        NeovimEditor(address, executable)
        executable = shutil.which(executable)
        if not executable:
            raise ValueError("Neovim executable is unavailable")
        if type(owner_pid) is not int or not 0 < owner_pid < 2 ** 31:
            raise ValueError("Expected a live terminal host PID")
        os.kill(owner_pid, 0)
        if control_file:
            control_file = str(Path(control_file).resolve(strict=True))
            if not Path(control_file).is_file():
                raise ValueError("Editor control file is unavailable")
        self.directory.mkdir(mode=0o700, parents=True, exist_ok=True)
        self.private(self.directory, directory=True)
        active = 0
        for path in self.directory.glob("*.json"):
            if re.fullmatch(r"[0-9a-f]{64}", path.stem):
                if self.record(path.stem):
                    active += 1
                else:
                    path.unlink(missing_ok=True)
        if active >= 32:
            raise ValueError("Too many active editor attachments")
        token = secrets.token_hex(32)
        path = self.directory / (token + ".json")
        record = {"documentID": self.document_id, "service": self.service,
                  "address": address, "executable": str(Path(executable).resolve()),
                  "ownerPID": owner_pid, "controlFile": control_file}
        descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(descriptor, "w") as stream:
            json.dump(record, stream)
        return token, path


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
