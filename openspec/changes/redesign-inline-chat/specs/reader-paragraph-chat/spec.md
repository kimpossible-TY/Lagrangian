## ADDED Requirements

### Requirement: Compact inline conversation

The paragraph conversation SHALL present its source, transcript and composer in a clear reading hierarchy at narrow and wide viewports. An expanded conversation SHALL have a distinct floating capsule surface, with its contents sharing that surface without nested cards.

#### Scenario: Asking on a narrow viewport

- **WHEN** a reader opens a conversation on a narrow screen
- **THEN** the composer, model choice, send action and account access remain visible and usable without horizontal overflow
- **AND** the empty composer occupies a compact single-line height.

#### Scenario: Folded conversation

- **WHEN** the conversation is folded
- **THEN** it appears as a rounded one-line summary bubble in eligible margin space
- **AND** when margin space is insufficient it becomes a small ChatGPT-logo-only annotation at the end of the associated paragraph, without a separate block row
- **AND** it retains hover, focus, pressed and forced-colors states.

#### Scenario: Compact annotation interaction

- **WHEN** a compact annotation is activated by keyboard or touch
- **THEN** the conversation expands below its paragraph and closing returns focus to that annotation
- **AND** its visual body is 28 by 24 CSS pixels within a 44 by 44 CSS pixel target.

#### Scenario: Canonical source text

- **WHEN** a paragraph has a compact chat annotation
- **THEN** selection, copying, source matching and model context exclude the annotation.

#### Scenario: Resize and disposal

- **WHEN** the viewport changes, the paragraph unmounts, its anchor becomes unresolved or the controller is disposed
- **THEN** the annotation changes placement or is removed with its owning conversation without leaving duplicate or stale controls.

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

### Requirement: Default model and concise controls

New conversations SHALL default to GPT-6 Luna with xhigh reasoning when it is available. Explicit model selections SHALL remain available and an unavailable model SHALL NOT be silently misrepresented.

#### Scenario: Luna response

- **WHEN** GPT-6 Luna is selected
- **THEN** each Responses request, including tool continuations, specifies xhigh reasoning.

#### Scenario: New conversation

- **WHEN** the model catalog contains GPT-6 Luna and there is no saved selection
- **THEN** it is selected without requiring a separate selection step.

#### Scenario: Compact composition

- **WHEN** a conversation is displayed
- **THEN** redundant instructional labels are visually removed while accessible names and important status remain available.
