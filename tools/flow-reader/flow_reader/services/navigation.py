"""Bidirectional saved-source navigation against the accepted document snapshot."""
from flow_reader.compiler.inputs import source_signature
from flow_reader.services.change_history import input_fingerprint
from flow_reader.services.source_mapping import source_location, cursor_location


class SavedSourceNavigation:
    def __init__(self, state):
        self.state = state

    def resolve(self, revision, operation, *arguments):
        """Resolve navigation only against an unchanged accepted saved snapshot."""
        with self.state.lock:
            if not self.state.bundle or revision != self.state.revision or self.state.compiling:
                return {"status": "stale", "revision": self.state.revision}
            bundle = self.state.bundle
            dependencies = set(self.state.accepted_dependencies)
            stamp, inputs = self.state.source_stamp, self.state.accepted_inputs
        def fresh():
            return (revision == self.state.revision and not self.state.compiling
                    and stamp == source_signature(self.state.project, dependencies)
                    and inputs == input_fingerprint(self.state.project, dependencies))
        try:
            if not fresh():
                return {"status": "stale", "revision": self.state.revision}
            result = operation(self.state.project, dependencies, bundle, *arguments)
            if not fresh():
                return {"status": "stale", "revision": self.state.revision}
        except OSError:
            return {"status": "stale", "revision": self.state.revision}
        return {**result, "revision": revision}

    def source(self, revision, fragments):
        return self.resolve(revision, source_location, fragments)

    def cursor(self, revision, path, line, column):
        return self.resolve(revision, cursor_location, path, line, column)
