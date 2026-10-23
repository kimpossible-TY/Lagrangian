"""Delegate saved-source history to the project's shared engine owner."""

import json
from pathlib import Path
import subprocess
import threading
import time

from flow_reader.compiler.inputs import MAX_SOURCE_BYTES, source_paths
from flow_reader.services.edit_location import SharedEditLocation, resolve_engine


def source_snapshots(project, dependencies):
    """Capture bounded local compiler sources without normalizing their bytes."""
    result, size = [], 0
    for path in source_paths(project, dependencies):
        if len(result) == 256:
            break
        with path.open("rb") as stream:
            content = stream.read(MAX_SOURCE_BYTES + 1)
        if size + len(content) > MAX_SOURCE_BYTES:
            continue
        result.append({"filepath": str(path), "text": content.decode("utf-8")})
        size += len(content)
    return result


class SourceHistoryClient:
    """One-shot transactions share Rust policy, persistence and writer locking."""

    def __init__(self, project, *, engine=None, change_file=None, data=None):
        self.project = project
        self._lock = threading.Lock()
        self._active = set()
        self._closed = False
        self.engine = resolve_engine(engine)
        self.location = SharedEditLocation(project.root, project.entry, change_file, data)
        if self.location.discovery in {"invalid", "ambiguous"}:
            raise ValueError("Cannot select common source history: " + self.location.discovery)
        help_result = self._run(["source-history", "--help"])
        if "--change-file" not in help_result:
            raise ValueError("The selected engine lacks source-history support; rebuild the Flow "
                             "engine and pass --engine PATH")
        self.observe()

    def _run(self, arguments, payload=None):
        try:
            with self._lock:
                if self._closed:
                    raise ValueError("Source-history client is closed")
                process = subprocess.Popen([self.engine, *arguments], stdin=subprocess.PIPE,
                                           stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
                self._active.add(process)
            try:
                stdout, stderr = process.communicate(payload, timeout=20)
            except BaseException:
                # This also covers SIGTERM/KeyboardInterrupt during construction.
                # The caller may never receive the client to dispose it itself.
                try:
                    process.kill()
                    process.communicate(timeout=1)
                except (OSError, subprocess.SubprocessError):
                    # Preserve the original interruption even if the helper's
                    # pipes or process disappear during concurrent disposal.
                    pass
                raise
            finally:
                with self._lock:
                    self._active.discard(process)
        except (OSError, subprocess.SubprocessError) as error:
            raise ValueError(f"Could not run the source-history engine: {error}") from error
        if self._closed:
            raise ValueError("Source-history client is closed")
        if process.returncode:
            reason = stderr.strip() or stdout.strip() or "Command failed"
            raise ValueError(f"Source-history engine failed: {reason}. "
                             "Use a Flow engine with source-history support (--engine PATH)")
        return stdout

    def close(self):
        """Cancel and reap only helpers created by this client, including lock waiters."""
        with self._lock:
            self._closed = True
            processes = list(self._active)
        for process in processes:
            if process.poll() is None:
                process.terminate()
        deadline = time.monotonic() + 1
        pending = []
        for process in processes:
            try:
                process.wait(timeout=max(0, deadline - time.monotonic()))
            except subprocess.TimeoutExpired:
                pending.append(process)
        for process in pending:
            process.kill()
        for process in pending:
            process.wait(timeout=1)

    def _update(self, sources):
        arguments = ["source-history", "--root", str(self.project.root.resolve()),
                     "--entry", self.project.relative_entry()]
        if self.location.path:
            arguments.extend(["--change-file", str(self.location.path)])
        response = self._run(arguments, json.dumps({"sources": sources}, ensure_ascii=False))
        try:
            result = json.loads(response)
            path, sequence = Path(result["path"]), result["sequence"]
            if (not path.is_absolute() or type(sequence) is not int or not 0 <= sequence <= 2**64 - 1
                    or self.location.path is not None and path.resolve() != self.location.path):
                raise ValueError("Invalid source-history response")
        except (ValueError, KeyError, TypeError) as error:
            raise ValueError("Invalid source-history engine response") from error
        if self.location.path is None:
            self.location = SharedEditLocation(self.project.root, self.project.entry, path)
        return result

    def observe(self):
        return self._update([])

    def seed(self, sources):
        return self._update(sources)
