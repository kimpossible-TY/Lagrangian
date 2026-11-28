"""Additive native adapter. Publication, source writes and conversations keep their owners."""
from contextlib import closing
import hashlib
import json
import sqlite3
from urllib.parse import parse_qs
from uuid import UUID

from flow_reader.document.native_document import import_accepted_document, SUPPORTED_CAPABILITIES, NativeImportError
from flow_reader.document.passages import normalized, locate_passages
from flow_reader.errors import RevisionChanged
from flow_reader.services.accepted_snapshot import AcceptedSnapshot
from flow_reader.services.source_highlight import MAX_SELECTION_SEGMENTS

MAX_DOCUMENT = 64 * 1024 * 1024
MAX_ASSET = 16 * 1024 * 1024
MAX_ASSETS = 64 * 1024 * 1024
MAX_CHAT = 2 * 1024 * 1024


def service_id(service):
    # The existing owner supplies both process and incarnation, never PID alone.
    if (not isinstance(service, dict) or type(service.get("pid")) is not int
            or type(service.get("startedAt")) is not int):
        raise ValueError("Invalid service incarnation")
    return f'reader:{service["pid"]}:{service["startedAt"]}'


def import_bounded_document(bundle, *, document_id, service_id):
    """Apply the native expanded-document and asset budgets before caching."""
    result = import_accepted_document(bundle, document_id=document_id, service_id=service_id, generation=0)
    if len(json.dumps(result.document, ensure_ascii=False, separators=(",", ":")).encode()) > MAX_DOCUMENT:
        raise ValueError("Native document limit")
    if any(len(data) > MAX_ASSET for data in result.assets.values()) or sum(map(len, result.assets.values())) > MAX_ASSETS:
        raise ValueError("Native asset limit")
    return result


def uuid(value):
    if not isinstance(value, str) or str(UUID(value)) != value.lower():
        raise ValueError("Invalid request identity")
    return str(UUID(value))


class NativeReaderService:
    def __init__(self, state):
        self.state = state
        self.cached = None  # One complete accepted revision, never an independent source store.
        from flow_reader.services.native_editor_actions import NativeEditorActions
        with state.lock:
            if not hasattr(state, "_native_editor_actions"):
                state._native_editor_actions = NativeEditorActions(state)
        self.editor_actions = state._native_editor_actions

    def editor(self, request, connected=lambda: True):
        result = self.editor_actions.handle(self, request, connected)
        # Only bounded states and correlation IDs cross the private owner boundary.
        return self.envelope(request, **result, receiptID=request.get("receiptID"),
                             inputID=request.get("inputID"),
                             selectionTicket=(request.get("selection") or {}).get("ticket"),
                             consentID=request.get("consentID"), sequence=request.get("sequence"))

    def target(self, request, *, current=True):
        state = self.state
        if (request.get("documentID") != state.document_id
                or request.get("serviceID") != service_id(state.focus.service)):
            raise RevisionChanged("Native target changed")
        if current and request.get("revision") != state.revision:
            raise RevisionChanged("Native revision changed")
        generation = request.get("generation")
        if type(generation) is not int or not 0 <= generation < 2**53:
            raise ValueError("Invalid generation")
        for key in ("requestID", "viewID"):
            uuid(request.get(key))
        capabilities = request.get("capabilities")
        if (type(request.get("schemaVersion")) is not int or request["schemaVersion"] != 1
                or not isinstance(capabilities, list) or any(not isinstance(c, str) for c in capabilities)
                or len(set(capabilities)) != len(capabilities) or "semantic-tree-v1" not in capabilities
                or set(capabilities) - SUPPORTED_CAPABILITIES):
            raise ValueError("Unsupported native contract")

    def snapshot(self, request):
        self.target(request)
        snapshot = AcceptedSnapshot.capture(self.state, request["revision"])
        if snapshot is None or not snapshot.current(self.state):
            raise RevisionChanged("Accepted native inputs changed")
        self.negotiated(snapshot, request)
        return snapshot

    def imported(self, snapshot):
        key = (snapshot.revision, snapshot.inputs, service_id(self.state.focus.service))
        if self.cached is None or self.cached[0] != key:
            result = import_bounded_document(snapshot.bundle, document_id=self.state.document_id, service_id=key[2])
            self.cached = key, result
        return self.cached[1]

    def negotiated(self, snapshot, request):
        # Cache identity is accepted input, independent of client capability/order.
        # Recheck every request, including assets and actions on a warm cache.
        imported = self.imported(snapshot)
        if not set(imported.document["requiredCapabilities"]).issubset(request["capabilities"]):
            raise NativeImportError("unsupported-required-capability")
        return imported

    def query(self, query):
        fields = parse_qs(query, strict_parsing=True)
        required = {"documentID", "serviceID", "revision", "generation", "schemaVersion", "capabilities", "requestID", "viewID"}
        if set(fields) != required or any(len(v) != 1 for v in fields.values()):
            raise ValueError("Invalid native query")
        request = {k: v[0] for k, v in fields.items()}
        request.update(generation=int(request["generation"]), schemaVersion=int(request["schemaVersion"]),
                       capabilities=request["capabilities"].split(","))
        return request

    def asset(self, query, identifier):
        with self.state.lock:
            request = self.query(query)
            snapshot = self.snapshot(request)
            imported = self.negotiated(snapshot, request)
            if identifier not in imported.assets:
                return None
            descriptor = next(a for a in imported.document["assets"] if a["id"] == identifier)
            if not snapshot.current(self.state):
                raise RevisionChanged("Native asset changed")
            return imported.assets[identifier], descriptor["mime"]

    def document(self, query):
        request = self.query(query)
        with self.state.lock:
            snapshot = self.snapshot(request)
            imported = self.negotiated(snapshot, request)
            document = {**imported.document, "generation": request["generation"]}
            data = json.dumps(document, ensure_ascii=False, separators=(",", ":")).encode()
            if len(data) > MAX_DOCUMENT:
                raise ValueError("Native document limit")
            if not snapshot.current(self.state):
                raise RevisionChanged("Native publication changed")
            # Existing immutable revision-bound delivery, including sanitized inline SVG.
            self.state.asset_snapshots[snapshot.revision] = {**snapshot.bundle.assets, **imported.assets}
            return data, self.binding(snapshot)

    def binding(self, snapshot):
        return hashlib.sha256(snapshot.inputs.encode()).hexdigest()

    def envelope(self, request, **result):
        return {**{k: request[k] for k in ("documentID", "serviceID", "revision", "requestID", "viewID", "generation")}, **result}

    def fragments(self, request, snapshot):
        """Offsets identify accepted display scalars only; never authorize source offsets."""
        selection = request.get("selection")
        if not isinstance(selection, dict):
            raise ValueError("Missing selection")
        uuid(selection.get("ticket"))
        fragments = selection.get("fragments")
        if not isinstance(fragments, list) or not 1 <= len(fragments) <= 32:
            raise ValueError("Invalid fragments")
        blocks = self.imported(snapshot).document["blocks"]
        indices = {b["id"]: i for i, b in enumerate(blocks)}
        previous, result = -1, []
        for fragment in fragments:
            if not isinstance(fragment, dict):
                raise ValueError("Invalid fragment")
            index = indices.get(fragment.get("blockID"), -1)
            if index <= previous:
                raise ValueError("Invalid fragment order")
            previous = index
            block = blocks[index]
            units, exact = fragment.get("rangeUTF16"), fragment.get("exact")
            if (not isinstance(units, list) or len(units) != 2 or any(type(x) is not int for x in units)
                    or not isinstance(exact, str) or not 0 <= units[0] < units[1] <= block["rangeUTF16"][1]):
                raise ValueError("Invalid display range")
            raw = block["canonicalText"].encode("utf-16-le")
            try:
                observed = raw[units[0]*2:units[1]*2].decode("utf-16-le")
            except UnicodeError:
                raise ValueError("Invalid scalar boundary") from None
            if observed != exact or not exact.strip() or len(exact) > 8000:
                raise ValueError("Invalid exact scalars")
            # Use a unique existing passage carrier. Tables/groups can have multiple
            # carriers: report unmapped instead of guessing a passage/source range.
            carriers = []
            def visit(node):
                if node.get("passageKey"):
                    carriers.append(node)
                for child in node["children"]:
                    visit(child)
            visit(block)
            candidates = [n for n in carriers if n["rangeUTF16"][0] <= units[0] < units[1] <= n["rangeUTF16"][1]]
            if len(candidates) != 1:
                return None
            carrier = candidates[0]
            # PassageIndex deliberately excludes SVG/annotations and normalizes
            # whitespace. Require agreement rather than inventing those offsets.
            passage = next((p for p in snapshot.bundle.passages if p["key"] == carrier["passageKey"]), None)
            if not passage or normalized(carrier["canonicalText"]) != passage["text"]:
                return None
            before = raw[carrier["rangeUTF16"][0]*2:units[0]*2].decode("utf-16-le")
            after = raw[units[1]*2:carrier["rangeUTF16"][1]*2].decode("utf-16-le")
            segments, position = [], units[0]
            def math_nodes(node):
                if node["kind"] == "math":
                    yield node
                for child in node["children"]:
                    yield from math_nodes(child)
            for node in math_nodes(block):
                first, last = node["rangeUTF16"]
                start, end = max(first, units[0]), min(last, units[1])
                if start >= end:
                    continue
                if position < start:
                    segments.append({"text": raw[position*2:start*2].decode("utf-16-le")})
                segments.append({"text": raw[start*2:end*2].decode("utf-16-le"), "math": True,
                                 "complete": first == start and last == end})
                position = end
            if position < units[1]:
                segments.append({"text": raw[position*2:units[1]*2].decode("utf-16-le")})
            if len(segments) > MAX_SELECTION_SEGMENTS:
                return None
            result.append({"key": carrier["passageKey"], "exact": exact, "segments": segments,
                           "prefix": normalized(before)[-120:], "suffix": normalized(after)[:120]})
        if sum(len(p["exact"]) for p in result) > 8000:
            raise ValueError("Selection limit")
        return result

    def receipt(self, request):
        # Query only. A missing/unfinished receipt never dispatches a highlight.
        self.target(request, current=False)
        identifier = uuid(request.get("receiptID"))
        path = self.state.selection.receipts.path
        if not path.exists():
            return {"status": "unknown"}
        with closing(sqlite3.connect(path.as_uri() + "?mode=ro", uri=True, timeout=2)) as db:
            row = db.execute("SELECT service,result FROM receipts WHERE id=?", (identifier,)).fetchone()
        if not row or row[0] != json.dumps(self.state.focus.service, sort_keys=True):
            return {"status": "unknown"}
        return json.loads(row[1]) if row[1] else {"status": "uncertain"}

    def action(self, request):
        operation = request.get("operation")
        # Preserve existing edit-lock -> publication-lock order. Never reverse it.
        with self.state.selection.edit_lock:
            if operation == "receipt":
                result = self.receipt(request)
                return self.envelope(request, status=result["status"])
            if operation == "last-change":
                self.state.refresh_shared_change()
                with self.state.lock:
                    snapshot = self.snapshot(request)
                    if request.get("inputID") != self.binding(snapshot):
                        raise RevisionChanged("Native input changed")
                    change = snapshot.bundle.manifest.get("lastChange")
                    if (not change or change.get("revision") != snapshot.revision
                            or snapshot.bundle.manifest["anchors"].get(change.get("target")) != change.get("section")):
                        return self.envelope(request, status="unmapped")
                    return self.envelope(request, status="located", anchor=change["target"])
            if operation not in {"excerpt", "locate", "highlight"}:
                raise ValueError("Unknown native operation")
            with self.state.lock:
                snapshot = self.snapshot(request)
                if request.get("inputID") != self.binding(snapshot):
                    raise RevisionChanged("Native input binding changed")
                fragments = self.fragments(request, snapshot)
            if fragments is None:
                return self.envelope(request, status="unmapped")
            if operation == "highlight":
                # A native view must explicitly bind an editor attachment, or explicitly
                # opt into the existing configured editor. Never silently bypass it.
                if "editorAttachment" not in request:
                    return self.envelope(request, status="editor-mismatch")
                intent = {"requestID": uuid(request.get("receiptID")), "documentID": self.state.document_id,
                          "service": self.state.focus.service, "revision": snapshot.revision,
                          "fragments": fragments, "editorAttachment": request["editorAttachment"]}
                result = self.state.highlight_intent(intent)
            elif operation == "excerpt":
                result = self.state.source_text(snapshot.revision, fragments)
            else:
                result = self.state.source(snapshot.revision, fragments)
                if result.get("status") == "located":
                    with self.state.lock:
                        if not snapshot.current(self.state):
                            raise RevisionChanged("Source changed")
                        locations = locate_passages(snapshot.bundle.passages, fragments)
                        if any(p["state"] != "located" for p in locations):
                            result = {"status": "ambiguous"}
                        else:
                            result = {"status": "located", "anchor": locations[0].get("id") or locations[0]["key"]}
            # Do not echo source paths, source hashes, editor addresses or exceptions.
            return self.envelope(request, **{k: v for k, v in result.items() if k in {"status", "text", "anchor"}})

    def chat(self, request):
        operation = request.get("operation")
        if operation not in {"list", "open", "draft", "send", "cancel", "events"}:
            raise ValueError("Unknown native chat operation")
        with self.state.lock:
            snapshot = self.snapshot(request)
            if request.get("inputID") != self.binding(snapshot):
                raise RevisionChanged("Native input binding changed")
            fragments = self.fragments(request, snapshot) if operation == "open" else None
        chat = self.state.paragraph_chat
        payload = {k: request[k] for k in ("conversationID", "version", "messageID", "question", "model", "draft") if k in request}
        payload.update(documentID=self.state.document_id, service=self.state.focus.service, revision=snapshot.revision)
        if operation == "open":
            if fragments is None:
                raise ValueError("Unmapped paragraph")
            payload["fragments"] = fragments
            result = chat.open(payload)
        elif operation in {"list", "events"}:
            result = chat.list(payload)
        else:
            payload["conversationID"] = uuid(payload.get("conversationID"))
            if operation == "send":
                payload["messageID"] = uuid(payload.get("messageID"))
            result = chat.mutate(payload, operation)
        records = [{k: r[k] for k in ("conversation_id", "version", "sequence", "draft", "status", "progress")} |
                   {"attachment": {k: v for k, v in r["attachment"].items() if k in {"state", "key", "section"}}} |
                   {"thread": [{k: m[k] for k in ("id", "role", "text", "status")} for m in r["thread"]]}
                   for r in result["conversations"]]
        output = self.envelope(request, conversations=records)
        if len(json.dumps(output).encode()) > MAX_CHAT:
            raise ValueError("Native chat limit")
        return output
