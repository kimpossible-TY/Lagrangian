"""Coalesce saved-source changes without changing service ownership."""
from flow_reader.compiler.inputs import source_signature

def watch(state, stopped):
    previous = state.watch_stamp
    while not stopped.wait(1):
        current = source_signature(state.project, state.dependencies)
        if current == previous:
            continue
        # Coalesce saves; a change made during compilation is picked up next time.
        if stopped.wait(.5):
            return
        stable = source_signature(state.project, state.dependencies)
        if stable != current:
            continue
        state.compile()
        previous = state.watch_stamp or stable
