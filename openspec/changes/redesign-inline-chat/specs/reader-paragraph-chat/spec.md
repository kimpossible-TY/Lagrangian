## ADDED Requirements

### Requirement: Compact inline conversation

The paragraph conversation SHALL present its source, transcript and composer in a clear reading hierarchy at narrow and wide viewports. An expanded conversation SHALL have a distinct floating capsule surface, with its contents sharing that surface without nested cards.

#### Scenario: Asking on a narrow viewport

- **WHEN** a reader opens a conversation on a narrow screen
- **THEN** the composer, model choice, send action and account access remain visible and usable without horizontal overflow
- **AND** the empty composer occupies a compact single-line height.

#### Scenario: Folded conversation

- **WHEN** the conversation is folded
- **THEN** it appears as the same small ChatGPT-logo-only annotation at the end of the associated paragraph on every screen, without a separate block row or visible summary
- **AND** it retains hover, focus, pressed and forced-colors states.

#### Scenario: Compact annotation interaction

- **WHEN** a compact annotation is activated by keyboard or touch
- **THEN** the conversation expands beside its paragraph when sufficient collision-free local whitespace is available, or below the paragraph otherwise, and closing returns focus to that annotation
- **AND** its visual body is 28 by 24 CSS pixels within a 44 by 44 CSS pixel target.

#### Scenario: Adaptive open conversation

- **WHEN** an open conversation has sufficient nearby whitespace
- **THEN** it appears in a 360–420 CSS pixel side capsule without covering source content, annotations or another open capsule
- **AND** its right edge extends at most 24 CSS pixels into the right margin and the source reading column is not narrowed to create that space
- **AND** it remains within 160 CSS pixels of its paragraph annotation instead of escaping to distant outside-column space.

#### Scenario: Local whitespace before inline fallback

- **WHEN** the immediate paragraph-side position is occupied
- **THEN** the reader searches nearby obstacle-edge positions within 160 CSS pixels of its annotation, preferring the shortest displacement and retaining a still-valid previous relative position
- **AND** expanded capsules may use empty space inside the reading column together with the adjoining margin, without covering source text, equations, numbers or annotations
- **AND** below-paragraph placement is used when nearby candidates cannot fit.

#### Scenario: Continuous resize

- **WHEN** an open conversation changes between side and below-paragraph placement
- **THEN** the same panel and annotation remain mounted with draft, model, caret, focus and transcript scroll retained
- **AND** a still-valid placement is retained to avoid unnecessary movement
- **AND** reduced-motion users receive the same usable layout without spatial animation.

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
