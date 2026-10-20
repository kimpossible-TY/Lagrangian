"""Bidirectional saved-source navigation against the accepted document snapshot."""
from flow_reader.services.accepted_snapshot import AcceptedSnapshot
from flow_reader.services.source_mapping import source_location, cursor_location


class SavedSourceNavigation:
    def __init__(self, state):
        self.state = state

    def resolve(self, revision, operation, *arguments):
        """Resolve navigation only against an unchanged accepted saved snapshot."""
        with self.state.lock:
            snapshot = AcceptedSnapshot.capture(self.state, revision)
            if snapshot is None:
                return {"status": "stale", "revision": self.state.revision}
        try:
            if not snapshot.current(self.state):
                return {"status": "stale", "revision": self.state.revision}
            result = operation(self.state.project, snapshot.dependencies, snapshot.bundle, *arguments)
            if not snapshot.current(self.state):
                return {"status": "stale", "revision": self.state.revision}
        except OSError:
            return {"status": "stale", "revision": self.state.revision}
        return {**result, "revision": revision}

    def source(self, revision, fragments):
        return self.resolve(revision, source_location, fragments)

    def cursor(self, revision, path, line, column):
        return self.resolve(revision, cursor_location, path, line, column)
