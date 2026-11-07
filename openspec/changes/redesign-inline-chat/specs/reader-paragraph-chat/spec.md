## ADDED Requirements

### Requirement: Compact inline conversation

The paragraph conversation SHALL present its source, transcript and composer in a clear reading hierarchy at narrow and wide viewports. Reading content and the composer SHALL use the Reader page surface without stacked glass cards.

#### Scenario: Asking on a narrow viewport

- **WHEN** a reader opens a conversation on a narrow screen
- **THEN** the composer, model choice, send action and account access remain visible and usable without horizontal overflow
- **AND** the empty composer occupies a compact single-line height.

#### Scenario: Folded conversation

- **WHEN** the conversation is folded
- **THEN** it remains identifiable as a control with hover, focus, pressed and forced-colors states.

#### Scenario: Composing a longer question

- **WHEN** the question grows across multiple lines
- **THEN** the input expands up to its limit and remains scrollable beyond it.

#### Scenario: Response in progress

- **WHEN** an answer is generating
- **THEN** its interruption control remains available.

#### Scenario: Keyboard and account access

- **WHEN** the reader opens and closes account settings
- **THEN** focus returns to the triggering control and each conversation uses the same account dialog.

### Requirement: Reading continuity

The redesigned presentation SHALL retain paragraph attachment, accessible question context, selection safety, draft recovery, partial answer visibility, and message state. It SHALL support light and dark themes, reduced transparency, visible focus and 44 CSS pixel touch controls.

#### Scenario: Response streaming

- **WHEN** an answer streams or fails
- **THEN** its content and status remain associated with the originating paragraph and its interrupt or recovery action remains available.
