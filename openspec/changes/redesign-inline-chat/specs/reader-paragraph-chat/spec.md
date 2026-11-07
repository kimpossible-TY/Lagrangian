## ADDED Requirements

### Requirement: Compact inline conversation

The paragraph conversation SHALL present its source, transcript and composer in a clear reading hierarchy at narrow and wide viewports. The composer SHALL start compact and grow with its contents to a bounded scrollable height. Model selection SHALL remain available and account settings SHALL be available in the conversation header. The response interruption control SHALL remain available during generation.

#### Scenario: Asking on a narrow viewport

- **WHEN** a reader opens a conversation on a narrow screen
- **THEN** the composer, model choice, send action and account access remain visible and usable without horizontal overflow
- **AND** the empty composer occupies a compact single-line height.

#### Scenario: Composing a longer question

- **WHEN** the question grows across multiple lines
- **THEN** the input expands up to its limit and remains scrollable beyond it.

#### Scenario: Keyboard and account access

- **WHEN** the reader opens and closes account settings
- **THEN** focus returns to the triggering control and each conversation uses the same account dialog.

### Requirement: Reading continuity

The redesigned presentation SHALL retain paragraph attachment, accessible question context, selection safety, draft recovery, partial answer visibility, and message state. It SHALL support light and dark themes, reduced transparency, visible focus and 44 CSS pixel touch controls.

#### Scenario: Response streaming

- **WHEN** an answer streams or fails
- **THEN** its content and status remain associated with the originating paragraph and its interrupt or recovery action remains available.
