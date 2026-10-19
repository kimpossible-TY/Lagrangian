"""Explicit selection actions against a single accepted document snapshot."""
import threading
from flow_reader.compiler.inputs import source_signature
from flow_reader.document.passages import locate_passages
from flow_reader.errors import RevisionChanged
from flow_reader.services.change_history import input_fingerprint
from flow_reader.services.source_highlight import StaleSelection, apply_highlight
from flow_reader.services.source_mapping import source_location
from flow_reader.services.editor_sync import UNSPECIFIED_EDITOR
from flow_reader.services.codex_context import selected_text, source_context


class SelectionActions:
    def __init__(self, state):
        self.state = state
        self.edit_lock = threading.Lock()

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

    def highlight(self, revision, fragments, expected_editor=UNSPECIFIED_EDITOR):
        with self.edit_lock:
            def editor_matches():
                return (expected_editor is UNSPECIFIED_EDITOR
                        or isinstance(expected_editor, str) and bool(expected_editor)
                        and expected_editor == self.state.editor_server and self.state.editor is not None)
            if not editor_matches():
                return {"status": "editor-mismatch", "revision": self.state.revision}
            with self.state.lock:
                if not self.state.bundle or revision != self.state.revision or self.state.compiling:
                    return {"status": "stale", "revision": self.state.revision}
                bundle = self.state.bundle
                dependencies = set(self.state.accepted_dependencies)
                stamp, inputs = self.state.source_stamp, self.state.accepted_inputs
            def fresh():
                if (revision != self.state.revision or self.state.compiling
                        or stamp != source_signature(self.state.project, dependencies)
                        or inputs != input_fingerprint(self.state.project, dependencies)):
                    raise StaleSelection("The selected document or its sources have changed")
            writer = None
            if self.state.editor is not None or expected_editor is not UNSPECIFIED_EDITOR:
                def writer(path, original, updated):
                    if not editor_matches() or self.state.editor is None:
                        return "editor-mismatch"
                    return self.state.editor.write(path, original, updated)
            try:
                fresh()
                result = apply_highlight(self.state.project, self.state.output, bundle, dependencies,
                                         fragments, fresh,
                                         writer=writer)
            except StaleSelection:
                result = "stale"
            except OSError:
                result = "error"
            return {"status": result, "revision": revision}

    def inputs_current(self):
        return (bool(self.state.bundle) and not self.state.compiling
                and self.state.source_stamp == source_signature(self.state.project, self.state.accepted_dependencies)
                and self.state.accepted_inputs == input_fingerprint(self.state.project, self.state.accepted_dependencies))

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
