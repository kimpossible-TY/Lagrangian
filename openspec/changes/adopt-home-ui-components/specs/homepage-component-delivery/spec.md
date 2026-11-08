## ADDED Requirements

### Requirement: Locally delivered document components
The Homepage SHALL present a responsive document library using locally delivered component assets and retain all safe reader destinations.

#### Scenario: Document selection on a narrow screen
- **WHEN** a document has a safe preferred destination
- **THEN** its full name is a wrapping primary link, with its actual status and other safe destinations accessible nearby

#### Scenario: Local delivery
- **WHEN** the Homepage is served from an installed reader
- **THEN** its component assets and their dependencies are available from explicit local routes without external requests
