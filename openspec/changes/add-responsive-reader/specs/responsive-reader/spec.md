## ADDED Requirements

### Requirement: Parallel reading outputs
The system SHALL produce a reflowable HTML reading view from the same saved Typst source as the existing paged view. Existing PDF export and the running paged endpoint SHALL remain available.

#### Scenario: Mobile entry
- **WHEN** a phone opens the configured reading entry after rollout
- **THEN** it receives the responsive reader and can explicitly open the original paged view
- **AND** the user's explicit view preference is respected

### Requirement: Mathematical fidelity
The reader MUST retain mathematical symbols and decorations, equation and theorem numbers, cross references, footnotes, and annotation meaning. Unsupported constructs MUST use faithful alternative rendering or produce a visible diagnostic, never silently disappear.

#### Scenario: PDE annotations
- **WHEN** a document contains mannot or scoped mathematical annotations
- **THEN** marked terms remain associated with their annotation content after reflow

### Requirement: Responsive readable content
The reader SHALL reflow ordinary text at 320–768 CSS px and the user's font size without whole-document horizontal scrolling. Multi-panel figures SHALL support narrow layouts. Oversize indivisible mathematics MAY use local scrolling or expansion.

#### Scenario: Font or orientation change
- **WHEN** a reader enlarges text or rotates the device
- **THEN** paragraphs reflow, labels remain readable, and the same logical passage stays in view

### Requirement: Revision-aware updates
The reader SHALL expose the compiled revision and compilation state, retain the last successful output on compilation failure, and preserve reading anchors and selections across updates.

#### Scenario: Failed source edit
- **WHEN** a saved edit fails to compile
- **THEN** the last valid document remains usable with an explicit stale/error status
- **AND** a successful subsequent compilation updates the reader without losing its logical reading position

### Requirement: Independent serving boundary
Flow SHALL own reader compilation and project settings. Tail Hosting SHALL expose and monitor the reader endpoint without taking ownership of document rendering or duplicating the service lifecycle.

#### Scenario: Independent Reader lifecycle
- **WHEN** the Reader is started, stopped, restarted, or recovered after an unexpected exit
- **THEN** only its own managed process and LaunchAgent are affected
- **AND** the original paged service remains available
- **AND** a new Reader start resolves the current parent Flow project settings

#### Scenario: Compile monitoring
- **WHEN** Tail Hosting checks the Reader
- **THEN** it distinguishes HTTP reachability from the Reader's reported compile and content-validation result
- **AND** serving the last accepted revision after a failed save is reported as a compile failure
