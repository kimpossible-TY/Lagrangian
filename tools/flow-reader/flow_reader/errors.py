"""Reader domain errors shared by service and transport boundaries."""

class RevisionChanged(ValueError):
    """A view request must be retried against the latest compiled snapshot."""
