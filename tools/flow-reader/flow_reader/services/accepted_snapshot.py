"""Accepted saved-source identity shared by selection and editor actions."""

from dataclasses import dataclass

from flow_reader.compiler.inputs import input_fingerprint, source_signature
from flow_reader.document.sections import SectionBundle


@dataclass(frozen=True)
class AcceptedSnapshot:
    """An action's accepted document and copied source-validation inputs."""

    revision: str
    bundle: SectionBundle
    dependencies: frozenset[str]
    source_stamp: tuple
    inputs: str

    @classmethod
    def capture(cls, state, revision):
        """Capture accepted inputs while the caller holds the publication lock."""
        if not state.bundle or revision != state.revision or state.compiling:
            return None
        return cls(revision, state.bundle, frozenset(state.accepted_dependencies),
                   state.source_stamp, state.accepted_inputs)

    def current(self, state):
        """Keep in-flight actions bound to their original revision and sources."""
        return (self.revision == state.revision and not state.compiling
                and self.source_stamp == source_signature(state.project, self.dependencies)
                and self.inputs == input_fingerprint(state.project, self.dependencies))
