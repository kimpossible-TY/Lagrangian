"""Neovim owns final writes to verified source without overwriting dirty buffers."""
import json
import hashlib
import math
import time
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

    def release_native(self, token):
        """Local manager-only retirement; no HTTP path or arbitrary file input."""
        if not isinstance(token, str) or not re.fullmatch(r"[0-9a-f]{64}", token):
            raise ValueError("Invalid native attachment token")
        if not self.directory.exists():
            return False
        self.private(self.directory, directory=True)
        path = self.directory / (token + ".json")
        if not path.exists():
            return False
        self.private(path)
        if path.stat().st_size > 16384:
            raise ValueError("Native registration exceeds its bound")
        record = json.loads(path.read_text())
        if (record.get("documentID") != self.document_id or record.get("nativeJumpOnly") is not True):
            raise ValueError("Not this document's native registration")
        path.unlink()
        return True

    def descriptor(self, token):
        """Export only an existing local registration's four chooser fields."""
        if not isinstance(token, str) or not re.fullmatch(r"[0-9a-f]{64}", token):
            raise ValueError("Invalid editor token")
        self.private(self.directory, directory=True)
        path = self.directory / (token + ".json")
        self.private(path)
        if path.stat().st_size > 16384:
            raise ValueError("Editor registration exceeds its bound")
        service = json.loads(path.read_text()).get("service")
        # Descriptor export identifies the existing editor, independently of a
        # future Reader incarnation. Reuse record() with that registered service.
        record = EditorAttachments(self.directory.parent, self.document_id, service).record(token)
        if not record or not record.get("controlFile"):
            raise ValueError("Live explicit editor registration required")
        self.private(Path(record["controlFile"]))
        return {key: record[key] for key in ("address", "executable", "ownerPID", "controlFile")}

    def resolve(self, token):
        record = self.record(token)
        # Native movement consent grants no source-write capability. Existing
        # terminal registrations retain their schema and write behavior.
        return NeovimEditor(record["address"], record["executable"]) if record and not record.get("nativeJumpOnly") else None

    def register(self, address, executable, owner_pid, control_file=None, *, jump_only=False, operation=None):
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
        if operation is not None:
            if not jump_only or operation.document_id != self.document_id or operation.output != self.directory.parent:
                raise ValueError("Operation does not own this native registration")
        self.directory.mkdir(mode=0o700, parents=True, exist_ok=True)
        self.private(self.directory, directory=True)
        token = operation.reserved_token() if operation is not None else secrets.token_hex(32)
        if os.path.lexists(self.directory / (token + ".json")):
            raise FileExistsError("Preserve existing editor registration")
        active = 0
        for path in self.directory.glob("*.json"):
            if re.fullmatch(r"[0-9a-f]{64}", path.stem):
                if self.record(path.stem):
                    active += 1
                else:
                    path.unlink(missing_ok=True)
        if active >= 32:
            raise ValueError("Too many active editor attachments")
        path = self.directory / (token + ".json")
        record = {"documentID": self.document_id, "service": self.service,
                  "address": address, "executable": str(Path(executable).resolve()),
                  "ownerPID": owner_pid, "controlFile": control_file}
        if jump_only:
            record["nativeJumpOnly"] = True
        if operation is not None:
            record["nativeOperation"] = operation.identifier
        data = json.dumps(record, sort_keys=True, separators=(",", ":")).encode()
        staging = self.directory / (".native-" + operation.identifier if operation else ".registration-" + token)
        descriptor = os.open(staging, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
        try:
            with os.fdopen(descriptor, "wb") as stream:
                stream.write(data); stream.flush(); os.fsync(stream.fileno())
                identity = os.fstat(stream.fileno())
            if operation is not None:
                # The complete bytes and inode are durable in intent BEFORE
                # publication. A killed partial file is never a registration.
                operation.prepare(data, identity)
            os.link(staging, path, follow_symlinks=False)  # exclusive publication, never replace
            NativeEditorOperation.sync_directory(self.directory)
        finally:
            staging.unlink(missing_ok=True)
        return token, path



class NativeEditorOperation:
    """Private local issuance journal. Callers serialize methods with manager.lock.

    A caller knows identifier before attach. Tombstones prevent late issuance;
    recovery never needs a live service or source file, only the exact binding.
    Journals are retained (no background pruning/retry or replay-permitting eviction).
    """
    KEYS = {"version", "operation", "root", "entry", "readerID", "state", "token",
            "profileID", "documentID", "deadline", "recordSHA256", "recordIdentity"}

    def __init__(self, data, identifier, root, entry, reader_id=None):
        if not isinstance(identifier, str) or not re.fullmatch(r"[0-9a-f]{64}", identifier):
            raise ValueError("Invalid native operation")
        if any(not isinstance(v, str) or not Path(v).is_absolute() or len(v.encode()) > 4096 or "\0" in v for v in (root, entry)):
            raise ValueError("Invalid native operation target")
        if reader_id is not None and (not isinstance(reader_id, str) or not re.fullmatch(r"[a-z0-9][a-z0-9-]{0,63}", reader_id)):
            raise ValueError("Invalid native reader ID")
        self.data = Path(data); self.directory = self.data / "native-editor-operations"
        self.identifier = identifier; self.path = self.directory / (identifier + ".json")
        self.binding = dict(version=2, operation=identifier, root=root, entry=entry, readerID=reader_id)

    @staticmethod
    def sync_directory(path):
        fd = os.open(path, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        try: os.fsync(fd)
        finally: os.close(fd)

    def read(self):
        EditorAttachments.private(self.directory, directory=True)
        EditorAttachments.private(self.path)
        if self.path.stat().st_size > 16384: raise ValueError("Native operation exceeds bound")
        value = json.loads(self.path.read_bytes())
        if not isinstance(value, dict) or type(value.get("version")) is not int or value["version"] not in {1, 2}:
            raise ValueError("Invalid native operation version")
        expected = dict(self.binding)
        keys = self.KEYS | {"documentRoot", "documentEntry"} if value["version"] == 2 else self.KEYS
        if value["version"] == 1:
            # Compatibility only: old records never captured caller spelling.
            # No migration/scan or guessed alias binding is authorized.
            import unicodedata
            expected.update(version=1, root=unicodedata.normalize("NFC", str(Path(expected["root"]).resolve())),
                            entry=unicodedata.normalize("NFC", str(Path(expected["entry"]).resolve())))
        if (set(value) != keys or any(value.get(k) != v for k, v in expected.items())
                or type(value["state"]) is not str
                or value["state"] not in {"reserved", "prepared", "issued", "cancelled"}
                or type(value["deadline"]) not in {int, float} or not math.isfinite(value["deadline"])):
            raise ValueError("Native operation binding changed")
        for name, pattern in [("token", r"[0-9a-f]{64}"), ("documentID", r"[0-9a-f]{24}"),
                              ("profileID", r"[a-z0-9][a-z0-9-]{0,63}"), ("recordSHA256", r"[0-9a-f]{64}")]:
            if value[name] is not None and (not isinstance(value[name], str) or not re.fullmatch(pattern, value[name])):
                raise ValueError("Invalid native operation record")
        identity = value["recordIdentity"]
        if identity is not None and (not isinstance(identity, list) or len(identity) != 2 or any(type(n) is not int or n < 0 for n in identity)):
            raise ValueError("Invalid native registration identity")
        if (value["token"] is None) != (value["profileID"] is None) or (value["profileID"] is None) != (value["documentID"] is None):
            raise ValueError("Incomplete native operation binding")
        if (value["recordSHA256"] is None) != (identity is None):
            raise ValueError("Incomplete registration fingerprint")
        if value["token"] is None:
            if value["state"] != "cancelled" or value["deadline"] != 0 or identity is not None:
                raise ValueError("Invalid pre-issuance cancellation tombstone")
        elif value["deadline"] <= 0:
            raise ValueError("Missing native issuance deadline")
        if value["state"] in {"prepared", "issued"} and identity is None:
            raise ValueError("Missing native publication fingerprint")
        if value["state"] == "reserved" and identity is not None:
            raise ValueError("Unexpected native publication fingerprint")
        if value["version"] == 2:
            actual = [value["documentRoot"], value["documentEntry"]]
            if value["token"] is None:
                if actual != [None, None]: raise ValueError("Invalid unissued document binding")
            else:
                if any(not isinstance(p, str) or not Path(p).is_absolute() or len(p.encode()) > 4096 or "\0" in p for p in actual):
                    raise ValueError("Missing validated document binding")
                try: Path(actual[1]).relative_to(actual[0])
                except ValueError: raise ValueError("Invalid validated document scope") from None
        return value

    def write(self, value, *, exclusive=False):
        self.directory.mkdir(mode=0o700, parents=True, exist_ok=True)
        EditorAttachments.private(self.directory, directory=True)
        if os.path.lexists(self.path): EditorAttachments.private(self.path)
        data = json.dumps(value, sort_keys=True, separators=(",", ":")).encode()
        if len(data) > 16384: raise ValueError("Native operation exceeds bound")
        fd, temporary = tempfile.mkstemp(prefix=".intent-", dir=self.directory)
        temporary = Path(temporary)
        try:
            with os.fdopen(fd, "wb") as stream:
                stream.write(data)
                stream.flush(); os.fsync(stream.fileno())
            if exclusive: os.link(temporary, self.path, follow_symlinks=False)
            else: os.replace(temporary, self.path)
            self.sync_directory(self.directory)
        finally: temporary.unlink(missing_ok=True)

    def reserve(self, profile_id, document_id, deadline, *, document_root=None, document_entry=None):
        if type(deadline) not in {int, float} or not math.isfinite(deadline) or not 0 < deadline - time.time() <= 7:
            raise ValueError("Native preparation deadline expired or invalid")
        if (not isinstance(profile_id, str) or not isinstance(document_id, str)
                or not re.fullmatch(r"[a-z0-9][a-z0-9-]{0,63}", profile_id) or not re.fullmatch(r"[0-9a-f]{24}", document_id)):
            raise ValueError("Invalid native document binding")
        value = dict(self.binding, state="reserved", token=secrets.token_hex(32), profileID=profile_id,
                     documentID=document_id, deadline=deadline, recordSHA256=None, recordIdentity=None,
                     documentRoot=document_root if document_root is not None else self.binding["root"],
                     documentEntry=document_entry if document_entry is not None else self.binding["entry"])
        self.write(value, exclusive=True)  # an existing tombstone/intent is never reused

    def current(self):
        value = self.read()
        if value["state"] == "cancelled" or time.time() >= value["deadline"]:
            raise ValueError("Native operation cancelled or expired")
        return value

    @property
    def output(self):
        output = self.data / "documents" / self.read()["profileID"]
        if any(path.is_symlink() for path in [self.data, self.data / "documents", output]):
            raise ValueError("Native operation output cannot be a symlink")
        return output

    @property
    def document_id(self): return self.read()["documentID"]

    def reserved_token(self):
        value = self.current()
        if value["state"] != "reserved": raise ValueError("Native operation already issued")
        return value["token"]

    def prepare(self, data, identity):
        value = self.current()
        if value["state"] != "reserved": raise ValueError("Native operation already prepared")
        value.update(state="prepared", recordSHA256=hashlib.sha256(data).hexdigest(), recordIdentity=[identity.st_dev, identity.st_ino])
        self.write(value)

    def verify_registration(self, value, path):
        EditorAttachments.private(path)
        info = path.stat()
        if (info.st_size > 16384 or [info.st_dev, info.st_ino] != value["recordIdentity"]
                or hashlib.sha256(path.read_bytes()).hexdigest() != value["recordSHA256"]):
            raise ValueError("Preserve replaced native registration")
        record = json.loads(path.read_bytes())
        if (record.get("nativeOperation") != self.identifier or record.get("nativeJumpOnly") is not True
                or record.get("documentID") != value["documentID"]):
            raise ValueError("Not this operation's native registration")

    def issued(self):
        value = self.current()
        if value["state"] != "prepared": raise ValueError("Native operation not prepared")
        self.verify_registration(value, self.output / "editor-attachments" / (value["token"] + ".json"))
        value["state"] = "issued"; self.write(value)

    def cancel(self):
        if not os.path.lexists(self.path):
            self.write(dict(self.binding, state="cancelled", token=None, profileID=None,
                            documentID=None, deadline=0, recordSHA256=None, recordIdentity=None,
                            documentRoot=None, documentEntry=None), exclusive=True)
        value = self.read()
        value["state"] = "cancelled"
        self.write(value)  # durable revocation precedes deletion, even if deletion fails
        if value["token"] is None: return False
        directory = self.output / "editor-attachments"
        if not directory.exists(): return False
        EditorAttachments.private(directory, directory=True)
        target = directory / (value["token"] + ".json")
        released = False
        if os.path.lexists(target):
            self.verify_registration(value, target)
            released = EditorAttachments(self.output, value["documentID"], {}).release_native(value["token"])
        staging = directory / (".native-" + self.identifier)
        if os.path.lexists(staging):
            EditorAttachments.private(staging); staging.unlink()
        self.sync_directory(directory)
        return released


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

    def jump(self, location, current):
        """Only an existing private attachment may supply this editor/location.

        Keep source coordinates out of argv, and reuse the terminal Lua owner.
        An interrupted RPC has an unknown effect; it must never be dispatched again.
        """
        payload = {key: location[key] for key in ("path", "source_hash", "line", "column")}
        descriptor, temporary = tempfile.mkstemp(prefix="flow-reader-jump-", suffix=".json")
        try:
            with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
                json.dump(payload, stream, ensure_ascii=False)
            expression = ("luaeval(" + vim_string("require('tinymist.reader').jump(_A)")
                          + ", json_decode(join(readfile(" + vim_string(temporary) + "), '')))")
            if not current():
                return "stale"
            try:
                result = subprocess.run([self.executable, "--server", self.address, "--remote-expr", expression],
                                        capture_output=True, text=True, timeout=2.5, check=False)
            except (OSError, subprocess.TimeoutExpired):
                return "unknown"
            status = result.stdout.strip()
            if result.returncode or status not in {"jumped", "modified", "stale", "error"}:
                return "unknown"
            return status
        finally:
            Path(temporary).unlink(missing_ok=True)

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
