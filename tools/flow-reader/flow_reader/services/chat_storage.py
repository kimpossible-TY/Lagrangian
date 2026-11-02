"""Private host storage shared by paragraph history and its OAuth registration."""
from contextlib import contextmanager
import fcntl
import json
import os
from pathlib import Path
import stat
import tempfile


DEFAULT_CHAT_DATA = Path.home() / "Library/Application Support/Lagrangian/paragraph-chat"


def private_directory(path, project_root=None):
    path = Path(path).expanduser().absolute()
    if project_root and path.resolve().is_relative_to(Path(project_root).resolve()):
        raise ValueError("Chat storage must be outside the source project")
    if path.is_symlink():
        raise ValueError("Chat storage cannot be a symlink")
    path.mkdir(parents=True, exist_ok=True, mode=0o700)
    info = path.stat()
    if info.st_uid != os.getuid():
        raise ValueError("Chat storage must belong to this user")
    path.chmod(0o700)
    return path


def private_file(path):
    """Reject symlinks and files belonging to another host user."""
    fd = os.open(path, os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600)
    info = os.fstat(fd)
    if info.st_uid != os.getuid() or not stat.S_ISREG(info.st_mode):
        os.close(fd)
        raise ValueError("Invalid private chat file")
    os.fchmod(fd, 0o600)
    return fd


@contextmanager
def file_lock(path):
    with os.fdopen(private_file(path), "a+b") as handle:
        fcntl.flock(handle, fcntl.LOCK_EX)
        yield


def read_json(path, default):
    if not path.exists():
        return default
    with os.fdopen(private_file(path), "r", encoding="utf-8") as handle:
        return json.load(handle)


def write_json(path, data):
    fd, temporary = tempfile.mkstemp(prefix=".chat-", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(data, handle, ensure_ascii=False)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, path)
    finally:
        Path(temporary).unlink(missing_ok=True)
