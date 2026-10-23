"""Foreground browser leases with bounded waits and native execution fallback."""
import base64
from dataclasses import dataclass, replace
import secrets
import threading
import time

from flow_reader.compiler.execution import CompileResult, local_compile
from flow_reader.compiler.snapshot import capture_snapshot, SnapshotUnavailable

MAX_OUTPUT = 64 * 1024 * 1024


@dataclass
class Job:
    snapshot: object
    deadline: float
    worker: str | None = None
    lease: str | None = None
    result: CompileResult | None = None
    failed: bool = False


class BrowserCompilePool:
    """One owner for worker readiness, task leases and result consumption.

    Publication/source locks are never held here. Callers retain their existing
    source freshness and content gates after execution returns.
    """
    def __init__(self, project, dependencies, engine, *, fallback=local_compile,
                 heartbeat_timeout=8, clock=time.monotonic):
        self.project = project
        self.dependencies = dependencies
        self.engine = engine
        self.fallback = fallback
        self.heartbeat_timeout = heartbeat_timeout
        self.clock = clock
        self.condition = threading.Condition()
        self.workers = {}
        self.jobs = {}
        self.closed = False
        self.completed = 0
        self.fallbacks = 0

    def _expire(self):
        stale = [token for token, seen in self.workers.items()
                 if self.clock() - seen >= self.heartbeat_timeout]
        for token in stale:
            self.workers.pop(token, None)
            for job in self.jobs.values():
                if job.worker == token:
                    job.worker = job.lease = None

    def _available(self):
        busy = {job.worker for job in self.jobs.values() if job.worker}
        return self.workers.keys() - busy

    def available(self):
        with self.condition:
            self._expire()
            return not self.closed and bool(self._available())

    def register(self, engine):
        with self.condition:
            self._expire()
            if self.closed or engine != self.engine or len(self.workers) >= 4:
                raise ValueError("Compiler unavailable or incompatible")
            token = secrets.token_urlsafe(24)
            self.workers[token] = self.clock()
            self.condition.notify_all()
            return {"worker": token, "heartbeatSeconds": self.heartbeat_timeout / 3}

    def heartbeat(self, worker):
        with self.condition:
            self._expire()
            if worker not in self.workers:
                raise ValueError("Compiler worker lease expired")
            self.workers[worker] = self.clock()
            self.condition.notify_all()

    def release(self, worker):
        with self.condition:
            self.workers.pop(worker, None)
            for job in self.jobs.values():
                if job.worker == worker:
                    job.worker = job.lease = None
            self.condition.notify_all()

    def poll(self, worker):
        with self.condition:
            self.heartbeat(worker)
            if any(job.worker == worker for job in self.jobs.values()):
                return None
            for identifier, job in self.jobs.items():
                if job.worker is None and job.result is None and not job.failed and job.deadline > self.clock():
                    job.worker, job.lease = worker, secrets.token_urlsafe(24)
                    return {"job": identifier, "lease": job.lease, "snapshot": job.snapshot.wire(),
                            "timeoutMs": max(1, int((job.deadline - self.clock()) * 1000))}
            return None

    def submit(self, worker, identifier, lease, payload):
        with self.condition:
            self._expire()
            job = self.jobs.get(identifier)
            if (worker not in self.workers or not lease or job is None or job.worker != worker or job.lease != lease or
                    job.deadline <= self.clock() or job.result is not None or job.failed):
                return {"accepted": False}
            try:
                if not isinstance(payload, dict):
                    raise ValueError("Expected compiler result object")
                if payload.get("identity") != job.snapshot.identity:
                    raise ValueError("Compiler snapshot mismatch")
                code, diagnostics, artifact = payload.get("returncode"), payload.get("stderr"), payload.get("artifact")
                names = payload.get("dependencies")
                if (type(code) is not int or not isinstance(diagnostics, str) or len(diagnostics) > 1048576
                        or not isinstance(artifact, str) or len(artifact) > (MAX_OUTPUT + 2) // 3 * 4
                        or not isinstance(names, list) or len(names) > 8192
                        or any(not isinstance(name, str) for name in names)):
                    raise ValueError("Invalid compiler result")
                data = base64.b64decode(artifact, validate=True)
                if len(data) > MAX_OUTPUT or code != 0 or not data:
                    raise ValueError("Compilation failed or result too large")
                dependencies = job.snapshot.dependencies(names)
                job.result = CompileResult(code, diagnostics, data, dependencies, 0)
            except (ValueError, TypeError, SnapshotUnavailable):
                job.failed = True
            self.condition.notify_all()
            return {"accepted": not job.failed}

    def execute(self, snapshot, timeout):
        with self.condition:
            self._expire()
            if self.closed or not self._available() or len(self.jobs) >= 4:
                return None
            started = self.clock()
            identifier = secrets.token_urlsafe(24)
            job = self.jobs[identifier] = Job(snapshot, started + timeout)
            self.condition.notify_all()
            try:
                while not job.result and not job.failed and not self.closed:
                    self._expire()
                    remaining = job.deadline - self.clock()
                    if remaining <= 0 or not self.workers:
                        break
                    self.condition.wait(min(remaining, self.heartbeat_timeout / 3))
                if job.result:
                    self.completed += 1
                    return replace(job.result, elapsed_seconds=self.clock() - started)
                return None
            finally:
                del self.jobs[identifier]
                self.condition.notify_all()

    def __call__(self, request):
        # All executors share this portable environment, including native fallback.
        request = replace(request, system_fonts=False,
                          timestamp=request.timestamp if request.timestamp is not None else int(time.time()))
        with self.condition:
            if self.closed:
                raise OSError("Browser compiler pool is closing")
        if self.available():
            try:
                snapshot = capture_snapshot(request, self.project, self.dependencies(), self.engine)
                result = self.execute(snapshot, request.timeout)
                if result is not None:
                    return result
            except (OSError, SnapshotUnavailable):
                pass
            self.fallbacks += 1
        with self.condition:
            if self.closed:
                raise OSError("Browser compiler pool is closing")
        return self.fallback(request)

    def close(self):
        with self.condition:
            self.closed = True
            self.workers.clear()
            self.condition.notify_all()
