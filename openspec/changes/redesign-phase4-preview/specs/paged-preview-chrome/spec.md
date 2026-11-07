## ADDED Requirements

### Requirement: Paged preview chrome follows Reader appearance

The paged preview SHALL present chrome using the Reader palette while preserving document rendering and existing controls.

#### Scenario: Theme and accessibility preferences

- **WHEN** the preview uses light or dark appearance
- **THEN** chrome uses matching Reader tokens and legible control states
- **AND** reduced transparency and motion have usable fallbacks
- **AND** document page geometry remains unchanged
