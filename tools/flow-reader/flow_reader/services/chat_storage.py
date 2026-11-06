"""Private host storage shared by paragraph history and its OAuth registration."""
from contextlib import contextmanager
import fcntl
import json
import os
from pathlib import Path
import stat
import tempfile


DEFAULT_CHAT_DATA = Path.home() / "Library/Application Support/Lagrangian/paragraph-chat"


def inside_source(path, source):
    source = Path(source).resolve()
    if path.is_relative_to(source):
        return True
    # resolve() does not recover on-disk spelling on case-insensitive or
    # normalization-insensitive filesystems. Compare existing ancestors by
    # identity before creating any missing descendants.
    for parent in (path, *path.parents):
        try:
            if parent.samefile(source):
                return True
        except FileNotFoundError:
            continue
    return False


def private_directory(path, project_root=None):
    path = Path(path).expanduser().absolute()
    if path.is_symlink():
        raise ValueError("Chat storage cannot be a symlink")
    # Resolve parent aliases before validation and keep using that same path.
    # This permits normal macOS temporary-directory aliases without routing
    # private-file creation through a mutable alias into a source checkout.
    path = path.resolve()
    if project_root and inside_source(path, project_root):
        raise ValueError("Chat storage must be outside the source project")
    # .git is a directory in ordinary checkouts and a file in worktrees and
    # submodules. Inspect the destination too; reject before mkdir or chmod.
    git_root = next((parent for parent in (path, *path.parents) if (parent / ".git").exists()), None)
    # A dotfiles worktree at $HOME must not exclude ordinary private app data.
    # The nearest worktree still wins, so nested projects remain protected.
    if git_root is not None and git_root != Path.home().resolve():
        raise ValueError("Chat storage must be outside Git repositories")
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
