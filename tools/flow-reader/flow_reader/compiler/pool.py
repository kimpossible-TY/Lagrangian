"""Foreground browser leases with bounded waits and native execution fallback."""
import base64
from collections import deque
from dataclasses import dataclass, replace
import secrets
import re
import threading
import time

from flow_reader.compiler.execution import CompileResult, local_compile
from flow_reader.compiler.snapshot import capture_snapshot, SnapshotUnavailable

RELEASE_REASONS = {"page-hidden", "page-exit", "offline", "disabled", "disposed",
                   "transport-error", "worker-error", "compile-error", "client-timeout", "released"}

PROGRESS_PHASES = {"ready", "received", "fonts", "files", "evaluating", "output", "sending-result"}


def checked_progress(value):
    if value is None:
        return None
    if not isinstance(value, dict) or not isinstance(value.get("phase"), str) or value["phase"] not in PROGRESS_PHASES:
        raise ValueError("Invalid compiler progress")
    result = {"phase": value["phase"]}
    for key, limit in (("phaseSequence", 2 ** 31 - 1), ("wasmMemoryBytes", 2 ** 32), ("roundTripMs", 300000), ("timerLagMs", 300000)):
        if key in value:
            number = value[key]
            if type(number) is not int or not 0 <= number <= limit:
                raise ValueError("Invalid compiler metric")
            result[key] = number
    return result


def checked_recovery(value):
    if value is None:
        return None
    if (not isinstance(value, dict) or not isinstance(value.get("previousDevice"), str)
            or not re.fullmatch(r"[0-9a-f]{8}", value["previousDevice"])
            or not isinstance(value.get("mode"), str) or value["mode"] not in {"same-page", "page-restart"}
            or not isinstance(value.get("reason"), str) or value["reason"] not in RELEASE_REASONS | {"unreported"}):
        raise ValueError("Invalid compiler recovery")
    result = {key: value[key] for key in ("previousDevice", "mode", "reason")}
    if value.get("progress") is not None:
        result["progress"] = checked_progress(value["progress"])
    return result


MAX_OUTPUT = 64 * 1024 * 1024


@dataclass
class Job:
    snapshot: object
    deadline: float
    worker: str | None = None
    lease: str | None = None
    result: CompileResult | None = None
    failed: bool = False
    target: str | None = None
    record: dict | None = None


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
        self.worker_info = {}
        self.worker_progress = {}
        self.history = deque(maxlen=64)

    def record(self, **values):
        with self.condition:
            event = {"id": secrets.token_hex(6), "at": time.time(), **values}
            self.history.append(event)
            return event

    def status(self):
        with self.condition:
            self._expire()
            return {"workers": [dict(self.worker_info[token],
                                     lastSeenSeconds=round(self.clock() - seen, 1),
                                     busy=any(job.worker == token for job in self.jobs.values()),
                                     **self._evidence(token))
                                for token, seen in self.workers.items()],
                    "history": [dict(event) for event in reversed(self.history)]}

    def ready_device(self, worker):
        with self.condition:
            self._expire()
            if self.closed or worker not in self._available():
                raise ValueError("device-not-ready")
            return dict(self.worker_info[worker])

    def _evidence(self, token):
        result = {"heartbeatTimeoutSeconds": self.heartbeat_timeout}
        if token in self.workers:
            result["lastHeartbeatAgeSeconds"] = round(self.clock() - self.workers[token], 3)
        if token in self.worker_progress:
            progress, changed = self.worker_progress[token]
            result.update(lastProgress=dict(progress), phaseAgeSeconds=round(self.clock() - changed, 3))
        return result

    def _remove_worker(self, token, reason="heartbeat-lost"):
        device = self.worker_info.get(token)
        evidence = self._evidence(token)
        if device:
            self.record(executor="browser", purpose="connection", status="disconnected",
                        device=dict(device), reason=reason, **evidence)
        self.workers.pop(token, None)
        self.worker_info.pop(token, None)
        self.worker_progress.pop(token, None)
        for job in self.jobs.values():
            if job.target == token:
                job.failed = True
                job.record.update(status="disconnected", reason=reason, **evidence)
            if job.worker == token:
                job.worker = job.lease = None

    def _expire(self):
        stale = [token for token, seen in self.workers.items()
                 if self.clock() - seen >= self.heartbeat_timeout]
        for token in stale:
            self._remove_worker(token)

    def _available(self):
        busy = {job.worker for job in self.jobs.values() if job.worker}
        return self.workers.keys() - busy

    def available(self):
        with self.condition:
            self._expire()
            return not self.closed and bool(self._available())

    def register(self, engine, name="Browser", recovery=None, diagnostics_version=0):
        if type(diagnostics_version) is not int or not 0 <= diagnostics_version <= 1:
            raise ValueError("Invalid diagnostics version")
        recovery = checked_recovery(recovery)
        with self.condition:
            self._expire()
            if not isinstance(name, str) or not 1 <= len(name.strip()) <= 40 or any(ord(c) < 32 for c in name):
                raise ValueError("Invalid device name")
            if self.closed or engine != self.engine or len(self.workers) >= 4:
                raise ValueError("Compiler unavailable or incompatible")
            token = secrets.token_urlsafe(24)
            self.workers[token] = self.clock()
            self.worker_info[token] = {"id": secrets.token_hex(4), "name": name.strip(), "diagnosticsVersion": diagnostics_version}
            if recovery:
                evidence = {**recovery, "device": dict(self.worker_info[token])}
                for event in self.history:
                    if (event.get("executor") == "diagnostic" and "termination" in event
                            and event.get("device", {}).get("id") == recovery["previousDevice"]):
                        event["recovery"] = evidence
                self.record(executor="browser", purpose="connection", status="reconnected", **evidence)
            self.condition.notify_all()
            return {"worker": token, "device": dict(self.worker_info[token]),
                    "heartbeatSeconds": self.heartbeat_timeout / 3}

    def heartbeat(self, worker, progress=None):
        progress = checked_progress(progress)
        with self.condition:
            self._expire()
            if worker not in self.workers:
                raise ValueError("Compiler worker lease expired")
            self.workers[worker] = self.clock()
            old = self.worker_progress.get(worker)
            if progress is not None and (old is None or progress.get("phaseSequence", 0) >= old[0].get("phaseSequence", 0)):
                changed = self.clock() if old is None or old[0]["phase"] != progress["phase"] else old[1]
                self.worker_progress[worker] = (progress, changed)
                for job in self.jobs.values():
                    if job.worker == worker:
                        job.record.update(self._evidence(worker))
            self.condition.notify_all()

    def release(self, worker, reason="released"):
        if not isinstance(reason, str) or reason not in RELEASE_REASONS:
            raise ValueError("Invalid release reason")
        with self.condition:
            self._remove_worker(worker, reason)
            self.condition.notify_all()

    def poll(self, worker):
        with self.condition:
            self.heartbeat(worker)
            if any(job.worker == worker for job in self.jobs.values()):
                return None
            for identifier, job in self.jobs.items():
                if (job.worker is None and job.result is None and not job.failed and
                        job.deadline > self.clock() and job.target in (None, worker)):
                    job.worker, job.lease = worker, secrets.token_urlsafe(24)
                    for key in ("lastProgress", "lastHeartbeatAgeSeconds", "phaseAgeSeconds", "heartbeatTimeoutSeconds"):
                        job.record.pop(key, None)
                    job.record.update(status="working", device=dict(self.worker_info[worker]),
                                      **self._evidence(worker))
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
                job.result = CompileResult(code, diagnostics, data, dependencies, 0,
                                           executor="browser")
            except (ValueError, TypeError, SnapshotUnavailable):
                job.failed = True
                job.record["status"] = "invalid-result"
            self.condition.notify_all()
            return {"accepted": not job.failed}

    def execute(self, snapshot, timeout, *, worker=None, purpose="compile", outcome=None):
        with self.condition:
            self._expire()
            if worker is not None:
                self.ready_device(worker)
            if self.closed or not self._available() or len(self.jobs) >= 4:
                return None
            started = self.clock()
            identifier = secrets.token_urlsafe(24)
            event = self.record(executor="browser", purpose=purpose, status="queued",
                                snapshot=snapshot.identity[:12])
            job = self.jobs[identifier] = Job(snapshot, started + timeout, target=worker, record=event)
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
                    event["status"] = "result-received"
                    return replace(job.result, elapsed_seconds=self.clock() - started)
                if event["status"] not in {"invalid-result", "disconnected"}:
                    event["status"] = "timeout" if self.workers else "disconnected"
                return None
            finally:
                event["elapsedSeconds"] = round(self.clock() - started, 3)
                if outcome is not None:
                    outcome.update(event)
                del self.jobs[identifier]
                self.condition.notify_all()

    def __call__(self, request):
        # All executors share this portable environment, including native fallback.
        request = self.prepare_request(request)
        with self.condition:
            if self.closed:
                raise OSError("Browser compiler pool is closing")
        reason = "no-ready-device"
        if self.available():
            try:
                snapshot = capture_snapshot(request, self.project, self.dependencies(), self.engine)
                result = self.execute(snapshot, request.timeout, purpose=request.purpose)
                if result is not None:
                    return result
                reason = "browser-unfinished"
            except (OSError, SnapshotUnavailable):
                reason = "snapshot-unavailable"
            self.fallbacks += 1
        with self.condition:
            if self.closed:
                raise OSError("Browser compiler pool is closing")
        return self._execute_fallback(request, reason)

    @staticmethod
    def prepare_request(request):
        """Freeze portable inputs once so a rejected result retries identically."""
        return replace(request, system_fonts=False,
                       timestamp=request.timestamp if request.timestamp is not None else int(time.time()))

    def fallback_after_rejection(self, request):
        """Retry a browser result rejected by Python's authoritative content gate."""
        with self.condition:
            if self.closed:
                raise OSError("Browser compiler pool is closing")
            self.fallbacks += 1
        return self._execute_fallback(request, "browser-output-rejected")

    def _execute_fallback(self, request, reason):
        with self.condition:
            if self.closed:
                raise OSError("Browser compiler pool is closing")
        event = self.record(executor="server", purpose=request.purpose, status="working", reason=reason)
        started = self.clock()
        try:
            result = self.fallback(request)
            event["status"] = "result-received" if result.returncode == 0 else "failed"
            return result
        except Exception:
            event["status"] = "failed"
            raise
        finally:
            event["elapsedSeconds"] = round(self.clock() - started, 3)

    def close(self):
        with self.condition:
            self.closed = True
            self.workers.clear()
            self.worker_info.clear()
            self.worker_progress.clear()
            self.condition.notify_all()
