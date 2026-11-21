"""Bounded native jump coordination; mapping, attachments and Lua keep authority.

No source writer or HTTP registration. Coordinates/registration records never leave
this owner. Persist uncertainty BEFORE RPC so duplicate UUIDs cannot redispatch.
"""
from contextlib import closing
import hashlib
import json
import os
from pathlib import Path
import sqlite3
import threading
import time
from uuid import UUID

from flow_reader.errors import RevisionChanged
from flow_reader.services.editor_sync import EditorAttachments, NeovimEditor


def identifier(value):
    if not isinstance(value, str) or str(UUID(value)) != value:
        raise ValueError("Invalid editor identity")
    return value


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


class NativeEditorActions:
    def __init__(self, state):
        self.state = state
        self.lock = threading.RLock()
        self.views = {}
        self.pending = {}
        self.path = state.output / "native-editor-receipts.sqlite3"

    def database(self):
        self.path.parent.mkdir(parents=True, exist_ok=True)
        descriptor = os.open(self.path, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600) if not self.path.exists() else None
        if descriptor is not None:
            os.close(descriptor)
        EditorAttachments.private(self.path)
        db = sqlite3.connect(self.path, timeout=2)
        db.execute("CREATE TABLE IF NOT EXISTS jumps (id TEXT PRIMARY KEY, binding TEXT NOT NULL, status TEXT NOT NULL)")
        if "registration" not in {row[1] for row in db.execute("PRAGMA table_info(jumps)")}:
            # Old receipts prove no registration lifetime. Retain their UUIDs to
            # prevent replay, but never adopt their old successful status.
            db.execute("ALTER TABLE jumps ADD COLUMN registration TEXT")
            db.commit()
        return db

    @staticmethod
    def binding(request):
        # Bind the entire accepted selection and explicit consent/attachment, not
        # just an untrusted ticket. Digests are private, never returned to the UI.
        keys = ("documentID", "serviceID", "revision", "inputID", "viewID", "generation", "requestID",
                "selection", "editorAttachment", "consentID", "sequence", "receiptID")
        return digest({key: request.get(key) for key in keys})

    def view_binding(self, request):
        return digest({key: request.get(key) for key in ("documentID", "serviceID", "revision", "inputID", "viewID",
            "generation", "requestID", "selection", "editorAttachment", "consentID", "sequence")})

    @staticmethod
    def view_owner(request):
        return digest({key: request.get(key) for key in
                       ("documentID", "serviceID", "viewID", "editorAttachment", "consentID")})

    def registration(self, request):
        record = self.state.editor_attachments.record(request.get("editorAttachment"))
        # Native consent always names a local controller lifetime. Legacy terminal
        # registrations remain readable, but cannot implicitly opt native views in.
        if (not record or record.get("nativeJumpOnly") is not True or not record.get("controlFile")
                or record["service"] != self.state.focus.service):
            return None
        try:
            path = self.state.editor_attachments.directory / (request["editorAttachment"] + ".json")
            control = Path(record["controlFile"])
            EditorAttachments.private(control)
            stamps = tuple((info.st_dev, info.st_ino, info.st_mtime_ns, info.st_ctime_ns,
                            info.st_size, info.st_uid, info.st_mode)
                           for info in (path.stat(), control.stat(), os.stat(record["executable"])))
            return record, stamps
        except (OSError, ValueError):
            return None

    def active(self, request):
        view = self.views.get(request["viewID"])
        return view is not None and not view["closed"] and view["binding"] == self.view_binding(request)

    def source(self, native, request):
        # Retain existing edit-lock -> publication-lock ordering at the caller.
        with self.state.lock:
            snapshot = native.snapshot(request)
            if request.get("inputID") != native.binding(snapshot):
                raise RevisionChanged("Native input changed")
            fragments = native.fragments(request, snapshot)
        if fragments is None:
            return snapshot, fragments, {"status": "unmapped"}
        return snapshot, fragments, self.state.source(snapshot.revision, fragments)

    def handle(self, native, request, connected=lambda: True):
        native.target(request)
        operation = request.get("operation")
        if operation not in {"sync", "prepare", "jump", "receipt", "close", "revoke"}:
            raise ValueError("Unknown editor operation")
        identifier(request.get("consentID"))
        sequence = request.get("sequence")
        if type(sequence) is not int or not 0 < sequence < 2**53:
            raise ValueError("Invalid editor sequence")
        # Do not accept coordinates or new executable/address/registration fields.
        allowed = {"schemaVersion", "capabilities", "documentID", "serviceID", "revision", "inputID", "viewID",
                   "generation", "requestID", "operation", "consentID", "sequence", "selection", "editorAttachment", "receiptID"}
        if set(request) - allowed:
            raise ValueError("Invalid editor fields")
        with self.lock:
            if operation in {"sync", "close", "revoke"}:
                old = self.views.get(request["viewID"])
                if old and (old["owner"] != self.view_owner(request) or old["closed"]
                            or sequence <= old["sequence"] or request["generation"] < old["generation"]):
                    return {"status": "stale"}
                if old is None and len(self.views) >= 128:
                    return {"status": "unavailable"}
                if old is None and self.registration(request) is None:
                    return {"status": "unavailable"}
                # Revoke the old actionable selection before validating a newer
                # one. A failed/over-limit selection must not preserve old work.
                self.views[request["viewID"]] = {"closed": operation == "close", "sequence": sequence,
                    "generation": request["generation"], "binding": None, "owner": self.view_owner(request)}
                for key in list(self.pending):
                    if self.pending[key]["request"]["viewID"] == request["viewID"]:
                        del self.pending[key]
                if operation == "sync":
                    if self.registration(request) is None:
                        return {"status": "unavailable"}
                    with self.state.lock:
                        snapshot = native.snapshot(request)
                        if request.get("inputID") != native.binding(snapshot):
                            raise RevisionChanged("Native input changed")
                        if request.get("selection") is not None:
                            native.fragments(request, snapshot)
                self.views[request["viewID"]] = {"closed": operation == "close", "sequence": sequence,
                    "generation": request["generation"], "binding": self.view_binding(request), "owner": self.view_owner(request)}
                return {"status": "closed" if operation in {"close", "revoke"} else "ready"}

            receipt = identifier(request.get("receiptID"))
            binding = self.binding(request)
            with closing(self.database()) as db:
                row = db.execute("SELECT binding,status,registration FROM jumps WHERE id=?", (receipt,)).fetchone()
                if row and row[0] != binding:
                    return {"status": "unknown" if operation == "receipt" else "refused"}
                registration = self.registration(request)
                if row and (row[2] is None or registration is None or row[2] != digest(registration)):
                    # The effect may already have occurred. A different live
                    # registration at the same token cannot confirm it, nor may
                    # duplicate prepare/jump dispatch into the replacement editor.
                    db.execute("UPDATE jumps SET status='unknown' WHERE id=?", (receipt,))
                    db.commit()
                    return {"status": "unknown"}
                if not self.active(request) or registration is None:
                    # An invalidated receipt binding cannot prove that an earlier
                    # RPC had no effect. Do not clear the client's uncertain state.
                    return {"status": "unknown" if operation == "receipt" else "stale"}
                if operation == "receipt" or row:
                    status = row[1] if row else "unknown"
                    # Recheck accepted inputs before accepting an old effect receipt.
                    with self.state.lock:
                        snapshot = native.snapshot(request)
                        if request.get("inputID") != native.binding(snapshot):
                            raise RevisionChanged("Native input changed")
                    return {"status": status}
                if operation == "prepare":
                    self.pending = {k: v for k, v in self.pending.items() if v["expires"] > time.monotonic()}
                    if len(self.pending) >= 128:
                        return {"status": "unavailable"}
                    snapshot, fragments, location = self.source(native, request)
                    if location.get("status") != "located":
                        return {"status": location.get("status", "unmapped")}
                    self.pending[receipt] = {"request": dict(request), "binding": binding, "snapshot": snapshot,
                        "location": location, "registration": self.registration(request), "expires": time.monotonic() + 10}
                    return {"status": "ready"}
                pending = self.pending.pop(receipt, None)
                if not pending or pending["binding"] != binding or pending["expires"] <= time.monotonic() or not connected():
                    return {"status": "stale"}
                if db.execute("SELECT count(*) FROM jumps").fetchone()[0] >= 4096:
                    return {"status": "unavailable"}
                # No automatic redispatch, even if RPC or persistence later fails.
                db.execute("INSERT INTO jumps (id,binding,status,registration) VALUES (?,?,?,?)",
                           (receipt, binding, "unknown", digest(pending["registration"])))
                db.commit()

        # Sync/close may revoke work queued for the effect gate. Final validation
        # and RPC are serialized; cancellation after dispatch cannot promise rollback.
        with self.state.selection.edit_lock:
            with self.lock, self.state.lock:
                def current():
                    return (self.active(request) and connected() and pending["snapshot"].current(self.state)
                            and self.registration(request) == pending["registration"])
                if not current():
                    status = "stale"
                else:
                    snapshot, fragments, location = self.source(native, request)
                    if location != pending["location"]:
                        status = "stale"
                    else:
                        record = pending["registration"][0]
                        status = NeovimEditor(record["address"], record["executable"]).jump(location, current)
                        if not current():
                            status = "unknown"
                with closing(self.database()) as db:
                    db.execute("UPDATE jumps SET status=? WHERE id=?", (status, receipt))
                    db.commit()
                return {"status": status}
