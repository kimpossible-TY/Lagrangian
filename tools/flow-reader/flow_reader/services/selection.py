"""Explicit selection actions against a single accepted document snapshot."""
import threading
from flow_reader.document.passages import locate_passages
from flow_reader.errors import RevisionChanged
from flow_reader.services.accepted_snapshot import AcceptedSnapshot
from flow_reader.services.source_highlight import StaleSelection, apply_highlight
from flow_reader.services.source_mapping import source_location
from flow_reader.services.editor_sync import UNSPECIFIED_EDITOR
from flow_reader.services.codex_context import selected_text, source_context
from flow_reader.services.highlight_receipts import HighlightReceipts


class SelectionActions:
    def __init__(self, state):
        self.state = state
        self.edit_lock = threading.RLock()
        self.receipts = HighlightReceipts(state.output / "highlight-receipts.sqlite3")

    def highlight_intent(self, request):
        """Receipts survive lost acknowledgments; existing validation owns writes."""
        def execute():
            if (request.get("documentID") != self.state.document_id
                    or request.get("service") != self.state.focus.service):
                return {"status": "stale", "revision": self.state.revision}
            return self.highlight(request.get("revision"), request.get("fragments"),
                                  request.get("editorServer", UNSPECIFIED_EDITOR),
                                  request.get("editorAttachment", UNSPECIFIED_EDITOR))
        with self.edit_lock:
            return self.receipts.run(request, self.state.focus.service, execute)

    def locate(self, revision, fragments):
        with self.state.lock:
            if not self.state.bundle or revision != self.state.revision:
                raise RevisionChanged("The document revision has changed")
            bundle = self.state.bundle
        results = locate_passages(bundle.passages, fragments)
        with self.state.lock:
            if revision != self.state.revision:
                raise RevisionChanged("The document revision has changed")
        return {"revision": revision, "locations": results}

    def highlight(self, revision, fragments, expected_editor=UNSPECIFIED_EDITOR,
                  editor_attachment=UNSPECIFIED_EDITOR):
        with self.edit_lock:
            attached = editor_attachment is not UNSPECIFIED_EDITOR
            editor = (self.state.editor_attachments.resolve(editor_attachment) if attached
                      else self.state.editor)
            def editor_matches():
                if attached:
                    current = self.state.editor_attachments.resolve(editor_attachment)
                    return (editor is not None and current is not None
                            and (current.address, current.executable) == (editor.address, editor.executable)
                            and (expected_editor is UNSPECIFIED_EDITOR or expected_editor == editor.address))
                return (expected_editor is UNSPECIFIED_EDITOR
                         or isinstance(expected_editor, str) and bool(expected_editor)
                         and expected_editor == self.state.editor_server and self.state.editor is not None)
            if not editor_matches():
                return {"status": "editor-mismatch", "revision": self.state.revision}
            with self.state.lock:
                snapshot = AcceptedSnapshot.capture(self.state, revision)
                if snapshot is None:
                    return {"status": "stale", "revision": self.state.revision}
            def fresh():
                if not snapshot.current(self.state):
                    raise StaleSelection("The selected document or its sources have changed")
            writer = None
            if attached or editor is not None or expected_editor is not UNSPECIFIED_EDITOR:
                def writer(path, original, updated):
                    if not editor_matches() or editor is None:
                        return "editor-mismatch"
                    return editor.write(path, original, updated)
            try:
                fresh()
                result = apply_highlight(self.state.project, self.state.output, snapshot.bundle, snapshot.dependencies,
                                         fragments, fresh,
                                         writer=writer)
            except StaleSelection:
                result = "stale"
            except OSError:
                result = "error"
            return {"status": result, "revision": revision}

    def inputs_current(self):
        snapshot = AcceptedSnapshot.capture(self.state, self.state.revision)
        return snapshot is not None and snapshot.current(self.state)

    def save_focus(self, revision, fragments, service, viewer_id):
        """Save explicit context without editing source or requesting compilation."""
        if (not isinstance(revision, str) or not 1 <= len(revision) <= 64
                or type(viewer_id) is not int or not 0 < viewer_id < 2 ** 53):
            raise ValueError("Expected a rendered revision and viewer identity")
        with self.state.lock:
            if service != self.state.focus.service or revision != self.state.revision or not self.inputs_current():
                return self.state.focus.record("stale", revision, self.state.revision, viewer_id=viewer_id)
            text, locations = selected_text(self.state.bundle, fragments)
            location = source_location(self.state.project, self.state.accepted_dependencies, self.state.bundle, fragments)
            try:
                source = source_context(location)
            except (OSError, ValueError):
                if not self.inputs_current():
                    return self.state.focus.record("stale", revision, self.state.revision, viewer_id=viewer_id)
                raise
            if not self.inputs_current():
                return self.state.focus.record("stale", revision, self.state.revision, viewer_id=viewer_id)
            start, end = locations[0], locations[-1]
            return self.state.focus.record(
                "selected" if source else "unmapped", revision, self.state.revision,
                selection={"text": text, "fragments": [
                    {name: part.get(name, "") for name in ("key", "exact", "prefix", "suffix")}
                    for part in fragments]}, source=source,
                position={"start": {"key": start["key"], "section": start["section"], "offset": start["start"]},
                          "end": {"key": end["key"], "section": end["section"], "offset": end["end"]},
                          "offset_unit": "normalized_unicode"}, viewer_id=viewer_id)

    def read_focus(self):
        with self.state.lock:
            return self.state.focus.read(self.state.revision, self.inputs_current())
