"""Durable at-most-once receipts for explicit, revision-bound highlight intents."""
from contextlib import closing
import hashlib
import json
import re
import sqlite3


class HighlightReceipts:
    def __init__(self, path):
        self.path = path

    def run(self, request, service, execute):
        identifier = request.get("requestID")
        if not isinstance(identifier, str) or not re.fullmatch(r"[A-Za-z0-9_-]{16,80}", identifier):
            raise ValueError("Invalid highlight request identity")
        encoded = json.dumps(request, sort_keys=True, separators=(",", ":"))
        if len(encoded.encode()) > 262144:
            raise ValueError("Highlight intent is too large")
        digest = hashlib.sha256(encoded.encode()).hexdigest()
        session = json.dumps(service, sort_keys=True)
        self.path.parent.mkdir(parents=True, exist_ok=True)
        with closing(sqlite3.connect(self.path, timeout=10)) as connection:
            connection.execute("PRAGMA synchronous=FULL")
            connection.execute("CREATE TABLE IF NOT EXISTS receipts "
                               "(id TEXT PRIMARY KEY, digest TEXT NOT NULL, service TEXT NOT NULL, result TEXT)")
            with connection:
                connection.execute("BEGIN IMMEDIATE")
                previous = connection.execute("SELECT digest, result FROM receipts WHERE id=?", (identifier,)).fetchone()
                if previous:
                    if previous[0] != digest:
                        raise ValueError("Highlight identity was reused for different content")
                    # A crash may have occurred before or after the source write.
                    # Never replay an unfinished receipt or claim it was saved.
                    return (json.loads(previous[1]) if previous[1] else
                            {"status": "uncertain", "revision": request.get("revision")})
                if connection.execute("SELECT COUNT(*) FROM receipts").fetchone()[0] >= 10000:
                    # Old service identities can no longer authorize source writes.
                    connection.execute("DELETE FROM receipts WHERE service<>?", (session,))
                    if connection.execute("SELECT COUNT(*) FROM receipts").fetchone()[0] >= 10000:
                        return {"status": "receipt-limit", "revision": request.get("revision")}
                connection.execute("INSERT INTO receipts VALUES (?, ?, ?, NULL)", (identifier, digest, session))
            result = execute()
            with connection:
                connection.execute("UPDATE receipts SET result=? WHERE id=?",
                                   (json.dumps(result), identifier))
            return result
