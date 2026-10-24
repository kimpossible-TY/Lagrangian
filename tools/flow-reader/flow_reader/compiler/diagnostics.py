"""Explicit device checks: pinned leases, immutable reference inputs, no fallback."""
from dataclasses import replace
import hashlib
from pathlib import Path
import secrets
import tempfile
import threading
import time

from flow_reader.compiler.audit import normalize_content
from flow_reader.compiler.build import compile_project
from flow_reader.compiler.execution import CompileRequest, local_compile
from flow_reader.compiler.inputs import source_signature
from flow_reader.compiler.snapshot import capture_snapshot, SnapshotUnavailable


def reference_compile(snapshot, compiler):
    """Run the native reference on the exact captured bytes, not live sources."""
    with tempfile.TemporaryDirectory(prefix="flow-device-reference-") as temporary:
        root = Path(temporary)
        for item in snapshot.files:
            path = root / item.path.lstrip("/")
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(item.content)
        fonts = []
        for index, item in enumerate(snapshot.fonts):
            path = root / f"font-{index}.ttf"
            path.write_bytes(item.content)
            fonts.append(path)
        (root / "workspace").mkdir(exist_ok=True)
        (root / "packages").mkdir(exist_ok=True)
        return local_compile(CompileRequest(
            compiler, root / "workspace", root / "packages", snapshot.target,
            entry=root / snapshot.entry.lstrip("/"), fonts=tuple(fonts),
            inputs=snapshot.inputs, system_fonts=False, timestamp=snapshot.timestamp))


class CompilerDiagnostics:
    def __init__(self, state, *, reference=reference_compile):
        self.state = state
        self.reference = reference
        self.lock = threading.Lock()

    def start(self, worker, mode):
        if mode not in {"quick", "document"}:
            raise ValueError("invalid-test")
        pool = self.state.compiler_pool
        with pool.condition:
            device = pool.ready_device(worker)
            if not self.lock.acquire(blocking=False):
                raise ValueError("test-already-running")
            event = pool.record(executor="diagnostic", purpose=mode, status="running",
                                device=device)
        threading.Thread(target=self._run, args=(worker, mode, event), daemon=True).start()
        return {"id": event["id"]}

    def _run(self, worker, mode, event):
        state, started = self.state, time.monotonic()
        pool = state.compiler_pool
        try:
            with state.lock:
                dependencies = set(state.accepted_dependencies)
                revision, stamp = state.revision, state.source_stamp
                if mode == "document" and (not revision or state.compiling):
                    raise ValueError("document-not-ready")
            if mode == "document" and source_signature(state.project, state.dependencies) != stamp:
                raise ValueError("source-changed")

            def execute(request):
                request = replace(request, system_fonts=False, timestamp=int(time.time()))
                snapshot = capture_snapshot(request, state.project,
                                            dependencies if mode == "document" else (), pool.engine)
                with pool.condition:
                    event.update(stage="device", snapshot=snapshot.identity[:12])
                outcome = {}
                result = pool.execute(snapshot, 90, worker=worker, purpose="test-" + mode, outcome=outcome)
                if result is None:
                    with pool.condition:
                        event["termination"] = {key: outcome[key] for key in
                                                ("status", "reason", "elapsedSeconds") if key in outcome}
                    raise ValueError("device-did-not-finish")
                with pool.condition:
                    event.update(stage="reference", deviceSeconds=round(result.elapsed_seconds, 3))
                reference = self.reference(snapshot, state.project.compiler)
                if reference.returncode != 0 or not reference.artifact:
                    raise ValueError("reference-failed")
                actual = normalize_content(result.artifact.decode("utf-8"))
                expected = normalize_content(reference.artifact.decode("utf-8"))
                if actual != expected:
                    raise ValueError("output-mismatch")
                with pool.condition:
                    event["outputHash"] = hashlib.sha256(actual.encode()).hexdigest()[:12]
                return result

            if mode == "quick":
                execute(CompileRequest(state.project.compiler, state.project.root, state.project.packages,
                                       "html", source=f"Flow device check {secrets.token_hex(8)}: #(6 * 7)"))
            else:
                with tempfile.TemporaryDirectory(prefix="flow-device-document-") as temporary:
                    report = compile_project(replace(state.project, execute=execute), Path(temporary),
                                             map_sources=False)
                if not report["contentGatePassed"]:
                    raise ValueError("content-rejected")
                with state.lock:
                    if state.revision != revision or source_signature(state.project, state.dependencies) != stamp:
                        raise ValueError("source-changed")
                event["revision"] = revision[:12]
            with pool.condition:
                event.update(status="passed", stage="complete")
        except Exception as error:
            known = {"device-not-ready", "document-not-ready", "source-changed", "device-did-not-finish",
                     "reference-failed", "output-mismatch", "content-rejected"}
            reason = ("snapshot-unavailable" if isinstance(error, SnapshotUnavailable) else
                      str(error) if str(error) in known else "check-failed")
            with pool.condition:
                event.update(status="failed", reason=reason, errorType=type(error).__name__)
        finally:
            with pool.condition:
                event["elapsedSeconds"] = round(time.monotonic() - started, 3)
            self.lock.release()
