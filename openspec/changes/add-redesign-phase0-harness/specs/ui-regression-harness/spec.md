## ADDED Requirements

### Requirement: Selector contract

The harness SHALL check static shell hooks in the Homepage and Reader HTML and check generated and conditional hooks only after rendering isolated fixtures.

#### Scenario: Missing static hook

- **WHEN** a required static hook is removed from an in-memory shell copy
- **THEN** the contract check reports a failure

#### Scenario: Rendered conversation

- **WHEN** a fixture opens a paragraph conversation
- **THEN** the harness checks the rendered panel and its controls in context

### Requirement: Reproducible visual evidence

The harness SHALL capture Homepage, Reader, and open paragraph chat at desktop and mobile viewport sizes in light and dark themes with isolated fixture data, pinned browser settings, disabled motion, and loaded fonts.

#### Scenario: Compare captures

- **WHEN** captures are compared to existing local baselines
- **THEN** the harness writes pixel difference evidence and environment metadata without failing on differences
- **AND** harness errors result in a nonzero exit status

#### Scenario: Mobile viewport

- **WHEN** the mobile capture is reviewed
- **THEN** it is identified as a viewport-only capture and not a real iOS device test

### Requirement: Settled fixture capture

The harness SHALL wait for the fixture Reader's ready activity state and completed visible equation composition before capturing, and SHALL require two consecutive identical screenshots within a bounded retry limit.

#### Scenario: Stable capture

- **WHEN** consecutive screenshots match
- **THEN** the report records the number of retries and compares or saves the stable capture

#### Scenario: Unstable capture

- **WHEN** screenshots do not stabilize within the retry limit
- **THEN** the report marks the capture unstable, the run fails, and no baselines are updated
