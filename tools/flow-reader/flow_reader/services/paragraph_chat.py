"""Accepted-snapshot paragraph conversations; host history is authoritative."""
from contextlib import contextmanager
from copy import deepcopy
import hashlib
import json
import os
import sqlite3
import threading
import time
import uuid

from flow_reader.errors import RevisionChanged
from flow_reader.services.accepted_snapshot import AcceptedSnapshot
from flow_reader.services.chat_auth import ChatAuth, ChatProviderError
from flow_reader.services.chat_provider import ResponsesProvider
from flow_reader.services.chat_storage import DEFAULT_CHAT_DATA, private_directory, private_file
from flow_reader.services.codex_context import selected_text, source_context
from flow_reader.services.source_mapping import source_location


def digest(text):
    return hashlib.sha256(text.encode()).hexdigest()


def model_context(context):
    """Only document data, never private source paths, enters model history."""
    return {field: context.get(field) for field in ("documentID", "revision", "selection", "paragraph")}


class ConversationStore:
    def __init__(self, directory):
        self.path = directory / "history.sqlite3"
        os.close(private_file(self.path))
        with self.transaction() as db:
            db.execute("CREATE TABLE IF NOT EXISTS conversations (id TEXT PRIMARY KEY, document TEXT NOT NULL, record TEXT NOT NULL)")
            db.execute("CREATE INDEX IF NOT EXISTS chat_document ON conversations(document)")

    @contextmanager
    def transaction(self):
        db = sqlite3.connect(self.path, timeout=10)
        try:
            db.execute("BEGIN IMMEDIATE")
            yield db
            db.commit()
        finally:
            db.close()

    @staticmethod
    def read(db, document_id, conversation_id=None):
        rows = db.execute("SELECT record FROM conversations WHERE document=?" +
                          (" AND id=?" if conversation_id else "") + " ORDER BY rowid",
                          (document_id, conversation_id) if conversation_id else (document_id,))
        return [json.loads(row[0]) for row in rows]

    @staticmethod
    def save(db, record):
        db.execute("INSERT INTO conversations VALUES (?, ?, ?) ON CONFLICT(id) DO UPDATE SET record=excluded.record",
                   (record["conversation_id"], record["document_id"], json.dumps(record, ensure_ascii=False)))


def anchor_evidence(passages, key, source=None):
    index = next(index for index, part in enumerate(passages) if part["key"] == key)
    passage = passages[index]
    return {"key": key, "paragraph": passage["text"],
            "before": digest(passages[index - 1]["text"]) if index else None,
            "after": digest(passages[index + 1]["text"]) if index + 1 < len(passages) else None,
            "source": source}


def attach(record, passages, revision):
    evidence = record["anchor_evidence"]
    candidates = []
    for index, passage in enumerate(passages):
        if passage["text"] != evidence["paragraph"]:
            continue
        before = digest(passages[index - 1]["text"]) if index else None
        after = digest(passages[index + 1]["text"]) if index + 1 < len(passages) else None
        score = int(before == evidence["before"]) + int(after == evidence["after"])
        if revision == record["revision"] and passage["key"] == evidence["key"]:
            score += 4
        if score:
            candidates.append((score, passage))
    best = max((score for score, _part in candidates), default=0)
    matches = [part for score, part in candidates if score == best]
    if len(matches) != 1:
        return {"state": "unresolved", "reason": "ambiguous" if matches else "missing"}
    return {"state": "attached", "key": matches[0]["key"], "section": matches[0]["section"],
            "evidence": "paragraph+adjacent-context"}


class DocumentTools:
    def __init__(self, document_id, snapshot, fresh):
        self.document_id, self.snapshot, self.fresh = document_id, snapshot, fresh
        self.calls = 0
        self.characters = 0

    def __call__(self, name, arguments):
        self.calls += 1
        if not self.fresh():
            raise RevisionChanged("Document changed during tool use")
        if (self.calls > 24 or self.characters > 96000 or not isinstance(arguments, dict)
                or arguments.get("documentID") != self.document_id
                or arguments.get("revision") != self.snapshot.revision):
            raise ValueError("Document-tool identity or budget mismatch")
        offset, limit = arguments.get("offset"), arguments.get("limit")
        if type(offset) is not int or offset < 0 or type(limit) is not int or limit < 1:
            raise ValueError("Invalid pagination")
        passages = self.snapshot.bundle.passages
        if name == "search_current_document":
            query = arguments.get("query")
            if (set(arguments) != {"documentID", "revision", "query", "offset", "limit"}
                    or not isinstance(query, str) or not 1 <= len(query) <= 160 or limit > 20):
                raise ValueError("Invalid document query")
            matches = []
            total = 0
            for part in passages:
                start = part["text"].casefold().find(query.casefold())
                if start < 0:
                    continue
                if offset <= total < offset + limit:
                    matches.append({"key": part["key"], "excerpt": part["text"][max(0, start - 100):start + 300]})
                total += 1
            result = {"matches": matches, "nextOffset": offset + limit if total > offset + limit else None}
        elif name == "read_passage":
            key = arguments.get("key")
            if set(arguments) != {"documentID", "revision", "key", "offset", "limit"} or not isinstance(key, str):
                raise ValueError("Invalid passage key")
            if not key:
                if limit > 20:
                    raise ValueError("Passage-list page limit is 20")
                result = {"passages": [{"key": p["key"], "preview": p["text"][:120]}
                                       for p in passages[offset:offset + limit]],
                          "nextOffset": offset + limit if offset + limit < len(passages) else None}
            else:
                if limit > 8000:
                    raise ValueError("Passage read limit is 8000 characters")
                part = next((p for p in passages if p["key"] == key), None)
                if not part:
                    raise ValueError("Unknown accepted passage")
                text = part["text"]
                result = {"key": key, "text": text[offset:offset + limit],
                          "nextOffset": offset + limit if offset + limit < len(text) else None}
        else:
            raise ValueError("Unsupported document tool")
        self.characters += len(json.dumps(result))
        if self.characters > 96000:
            raise ValueError("Document-tool character budget exceeded")
        return {"documentID": self.document_id, "revision": self.snapshot.revision, **result}


class ParagraphChat:
    def __init__(self, state, *, directory=None, provider=None):
        self.state = state
        self.directory = private_directory(directory or DEFAULT_CHAT_DATA, state.project.root)
        self.store = ConversationStore(self.directory)
        self.auth = provider.auth if provider else ChatAuth(self.directory)
        self.provider = provider or ResponsesProvider(self.auth)
        self.jobs = {}
        self.lock = threading.RLock()
        self.closed = False

    def snapshot(self, request):
        with self.state.lock:
            if (request.get("documentID") != self.state.document_id or
                    request.get("service") != self.state.focus.service):
                raise RevisionChanged("Reader service or document changed")
            snapshot = AcceptedSnapshot.capture(self.state, request.get("revision"))
            if not snapshot or not snapshot.current(self.state):
                raise RevisionChanged("Accepted document or source changed")
            return snapshot

    def fresh(self, snapshot):
        with self.state.lock:
            return not self.closed and snapshot.current(self.state)

    def list(self, request):
        snapshot = self.snapshot(request)
        with self.store.transaction() as db:
            records = self.store.read(db, self.state.document_id)
            for record in records:
                if record["status"] == "streaming" and not self.owner_alive(record):
                    record.update(status="interrupted", progress="Reader stopped before completion")
                    for message in record["thread"]:
                        if message["status"] == "streaming":
                            message["status"] = "interrupted"
                    self.store.save(db, record)
        return self.envelope(snapshot, records)

    @staticmethod
    def owner_alive(record):
        if time.time() - record.get("heartbeat", 0) > 120:
            return False
        try:
            owner = record.get("owner", 0)
            if not isinstance(owner, int) or owner <= 0:
                return False
            os.kill(owner, 0)
            return True
        except (OSError, ValueError):
            return False

    def envelope(self, snapshot, records):
        if not self.fresh(snapshot):
            raise RevisionChanged("Accepted document changed")
        return {"documentID": self.state.document_id, "revision": snapshot.revision,
                "service": self.state.focus.service,
                "conversations": [{**{k: v for k, v in record.items() if k not in {"owner", "heartbeat"}},
                    "attachment": attach(record, snapshot.bundle.passages, snapshot.revision)} for record in records]}

    def open(self, request):
        snapshot = self.snapshot(request)
        fragments = request.get("fragments")
        quote, locations = selected_text(snapshot.bundle, fragments)
        if locations[0]["state"] != "located":
            raise ValueError("Select an unambiguous paragraph")
        # The first selected paragraph owns a passage spanning several blocks.
        key = locations[0]["key"]
        location = source_location(self.state.project, snapshot.dependencies, snapshot.bundle, fragments)
        source = source_context(location)
        if not self.fresh(snapshot):
            raise RevisionChanged("Selected source changed")
        with self.lock, self.store.transaction() as db:
            records = self.store.read(db, self.state.document_id)
            record = next((r for r in records if attach(r, snapshot.bundle.passages, snapshot.revision).get("key") == key), None)
            context = {"documentID": self.state.document_id, "revision": snapshot.revision,
                       "selection": quote, "source": source,
                       "paragraph": next(p["text"] for p in snapshot.bundle.passages if p["key"] == key),
                       "fragments": [{field: part.get(field, "") for field in ("key", "exact", "prefix", "suffix")}
                                     for part in fragments]}
            if not record:
                record = {"conversation_id": str(uuid.uuid4()), "document_id": self.state.document_id,
                          "revision": snapshot.revision, "quote": quote,
                          "context": context,
                          "anchor_evidence": anchor_evidence(snapshot.bundle.passages, key, source),
                          "thread": [], "draft": "", "status": "idle", "progress": "", "version": 0,
                          "sequence": 0}
                self.store.save(db, record)
            elif context != record["context"]:
                if record["status"] == "streaming" and self.owner_alive(record):
                    raise ValueError("Wait for the current response or interrupt it, then reselect the passage")
                record.update(quote=quote, context=context, version=record["version"] + 1)
                self.store.save(db, record)
        return self.envelope(snapshot, [record])

    def mutate(self, request, operation):
        snapshot = self.snapshot(request)
        identifier = request.get("conversationID")
        if not isinstance(identifier, str):
            raise ValueError("Expected a conversation identity")
        with self.lock, self.store.transaction() as db:
            records = self.store.read(db, self.state.document_id, identifier)
            if not records:
                raise ValueError("Conversation does not belong to this document")
            record = records[0]
            if operation == "send" and isinstance(request.get("messageID"), str):
                previous = next((m for m in record["thread"] if m["id"] == request["messageID"]), None)
                if previous:
                    if previous["role"] != "user" or previous["text"] != request.get("question"):
                        raise ValueError("Message identity was reused for a different question")
                    return self.envelope(snapshot, [record])
            if request.get("version") != record["version"]:
                raise RevisionChanged("Conversation changed in another view; reload history")
            if operation == "cancel":
                if identifier in self.jobs:
                    self.jobs[identifier]["cancel"].set()
                record.update(status="interrupted", progress="Response interrupted")
                for message in record["thread"]:
                    if message["status"] == "streaming":
                        message["status"] = "interrupted"
            elif operation == "draft":
                draft = request.get("draft")
                if not isinstance(draft, str) or len(draft) > 8000:
                    raise ValueError("Question limit is 8000 characters")
                record["draft"] = draft
            elif operation == "send":
                message_id = request.get("messageID")
                if record["status"] == "streaming" and self.owner_alive(record):
                    raise ValueError("A response is already in progress")
                if attach(record, snapshot.bundle.passages, snapshot.revision)["state"] != "attached":
                    raise ValueError("Reselect a current paragraph before sending")
                if record["context"].get("revision") != snapshot.revision:
                    raise RevisionChanged("Reselect the passage in the current revision before sending")
                question, model = request.get("question"), request.get("model")
                if not isinstance(question, str) or not 1 <= len(question.strip()) <= 8000:
                    raise ValueError("Write a question of at most 8000 characters")
                if not isinstance(model, str) or not 1 <= len(model) <= 120:
                    raise ValueError("Choose an available ChatGPT model")
                if not isinstance(message_id, str) or not 1 <= len(message_id) <= 80:
                    raise ValueError("Expected a message identity")
                # Retry is idempotent even after an HTTP acknowledgment was lost.
                record["draft"] = question
                record["thread"].extend([
                    {"id": message_id, "role": "user", "text": question, "status": "completed",
                     "revision": snapshot.revision, "context": deepcopy(record["context"])},
                    {"id": str(uuid.uuid4()), "role": "assistant", "text": "", "status": "streaming", "revision": snapshot.revision}])
                record.update(status="streaming", progress="Connecting…", owner=os.getpid(), heartbeat=time.time())
                event = threading.Event()
                job = {"cancel": event, "message": record["thread"][-1]["id"]}
                self.jobs[identifier] = job
            else:
                raise ValueError("Unknown conversation action")
            record["version"] += 1
            self.store.save(db, record)
        if operation == "send":
            thread = threading.Thread(target=self.run, args=(identifier, snapshot, record, job, model), daemon=True)
            job["thread"] = thread
            thread.start()
        return self.envelope(snapshot, [record])

    def run(self, identifier, snapshot, record, job, model):
        def cancelled():
            return job["cancel"].is_set() or not self.fresh(snapshot)
        def update(status=None, event=None):
            with self.lock, self.store.transaction() as db:
                current = self.store.read(db, self.state.document_id, identifier)[0]
                message = next(m for m in current["thread"] if m["id"] == job["message"])
                if message["status"] != "streaming":
                    return
                if event:
                    if event["type"] == "delta":
                        if len(message["text"]) + len(event["text"]) > 80000:
                            raise ChatProviderError("Response exceeded the Reader limit")
                        message["text"] += event["text"]
                    else:
                        current["progress"] = event["text"]
                if status:
                    current["status"] = message["status"] = status
                    if status == "completed" and current["draft"] == record["draft"]:
                        current["draft"] = ""
                current["heartbeat"] = time.time()
                current["sequence"] = current.get("sequence", 0) + 1
                # Streaming never changes the optimistic mutation version.
                self.store.save(db, current)
        try:
            if cancelled():
                raise RevisionChanged("Accepted document changed")
            history = [{"role": m["role"], "content":
                        json.dumps({"question": m["text"], "context": model_context(m.get("context", {
                            "revision": m["revision"], "selection": "Original selection unavailable"}))}, ensure_ascii=False)
                        if m["role"] == "user" else m["text"]}
                       for m in record["thread"][:-1] if m["status"] == "completed"]
            if sum(len(m["content"]) for m in history) > 120000:
                raise ChatProviderError("Conversation context limit reached; history is preserved")
            # Paths and source excerpts are private validation evidence, not tool authority.
            context = model_context(record["thread"][-2]["context"])
            tools = DocumentTools(self.state.document_id, snapshot, lambda: self.fresh(snapshot))
            for event in self.provider.run(model=model, history=history, context=context,
                    document_id=self.state.document_id, revision=snapshot.revision,
                    call_tool=tools, cancelled=cancelled):
                if cancelled():
                    raise RevisionChanged("Accepted document changed")
                update(event=event)
            if cancelled():
                raise RevisionChanged("Accepted document changed")
            update(status="completed", event={"type": "progress", "text": "Completed"})
        except (ChatProviderError, RevisionChanged) as error:
            update(status="interrupted" if cancelled() else "failed",
                   event={"type": "progress", "text": str(error)})
        except Exception:
            # Never echo transport exceptions, credentials or document bodies into logs.
            update(status="failed", event={"type": "progress", "text": "Response failed. Your question is saved; retry when ready."})
        finally:
            with self.lock:
                if self.jobs.get(identifier) is job:
                    del self.jobs[identifier]

    def close(self):
        with self.lock:
            self.closed = True
            for identifier, job in self.jobs.items():
                job["cancel"].set()
                with self.store.transaction() as db:
                    records = self.store.read(db, self.state.document_id, identifier)
                    if records:
                        record = records[0]
                        record.update(status="interrupted", progress="Reader closed before completion")
                        for message in record["thread"]:
                            if message["status"] == "streaming":
                                message["status"] = "interrupted"
                        self.store.save(db, record)
        self.auth.close()
