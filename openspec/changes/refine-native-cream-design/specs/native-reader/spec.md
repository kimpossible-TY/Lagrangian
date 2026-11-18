## ADDED Requirements

### Requirement: Native design preserves content and effect authority
Native cream design SHALL apply only to chrome and selection presentation.
Document, mathematical, answer and Original PDF font/color/geometry SHALL retain
their existing renderers. Selection freshness, held replacement, source/editor
operations, conversation history, authentication and explicit Send SHALL retain
their current owners. A presentation control SHALL NOT create new effect authority.

#### Scenario: Reader and conversation chrome adoption
- **WHEN** reader and conversation chrome adopt shared design components
- **THEN** accepted content, selection, native paint and current/requested/failure status contracts remain intact
- **AND** a failed mode request retains failure precedence including UI7-C1

#### Scenario: Selection capsule and question composer
- **WHEN** a selection capsule is opened, dismissed, moved or invalidated
- **THEN** its anchor and focus follow the existing current selection and view lifetime
- **AND** opening or preparing a question does not send inference before explicit Send, including unavailable permission or offline states

#### Scenario: Bounded source-component evidence
- **WHEN** NA18 tests paint standalone components in hidden windows or bitmaps
- **THEN** original-logo, contrast, font and semantic-control results are recorded as component evidence
- **AND** reader body/PDF preservation, real selection capsule, foreground input, accessibility use and full reader acceptance remain separately unverified until exercised


### Requirement: Pending recovery feedback precedes mode restrictions
Native recovery presentation SHALL distinguish pending preparation, failure with
retained content and accepted recovery using the existing Session state. Loading
and failure SHALL precede generic recovered-copy restrictions without enabling
source, chat, mode switching or disabled live refresh.

#### Scenario: Gated recovery preparation fails
- **WHEN** a valid snapshot is pending asynchronous preparation and that preparation fails
- **THEN** primary status first describes preparing and then failure with retained previous content
- **AND** explicit retry/cancel use the existing recovery owner with no new live request
- **AND** successful recovered-copy mode refusal and live selection/refresh behavior remain intact

### Requirement: Ask remains local until explicit Send
Opening a question composer SHALL retain its exact current selection/context and
SHALL NOT resolve account operations, create a remote conversation, save a server
draft or send inference before explicit Send. Explicit Send SHALL reuse existing
account/model, authorization and message UUID/unknown-effect owners.

#### Scenario: Open edit cancel and denied Send
- **WHEN** a user opens Ask, edits or dismisses its local composer
- **THEN** no remote request is sent and dismissal retains the selection with focus return
- **WHEN** explicit Send encounters stale selection, offline state or denied account permission
- **THEN** the existing owner refuses dispatch without creating new authority


### Requirement: Initial Send preserves the clicked intent
Initial conversation preparation SHALL bind the click-time question, text and
model edit intent and current selection. Changes during asynchronous preparation
SHALL require another explicit Send while preserving the latest visible draft.
An opened conversation MAY be adopted without automatically sending either the
old or replacement question. Normal Send UUID/receipt/unknown-effect policy SHALL
remain with its existing owner.

#### Scenario: Edit while account or open response waits
- **WHEN** question A is explicitly submitted and the question or selected model changes during account or conversation preparation
- **THEN** no question is sent automatically and the latest draft remains visible without endless busy state
- **AND** a second explicit Send sends that current question once through the existing owner

### Requirement: Stale selection retains the unsent composer
Selection changes and old acknowledgments SHALL NOT implicitly dispose an unsent
composer. The previous draft SHALL remain visible and Send SHALL be disabled with
a selection-mismatch explanation until an explicitly valid context is chosen.

#### Scenario: New selection while a local question is unsent
- **WHEN** the user edits a local question and selects a different passage or an old acknowledgment arrives
- **THEN** that same unsent composer and exact draft remain visible
- **AND** its stale Send cannot dispatch or authorize the new selection

### Requirement: Capsule avoids occupied document content
Capsule overlays SHALL use actual read-only renderer used bounds and SHALL avoid
selected and unselected body content, mathematical objects, search hits and primary
controls. Unknown geometry or insufficient verified empty space SHALL use a separate
layout dock. Original PDF presentation MAY conservatively use the dock exclusively.

#### Scenario: Short phrase in a filled native viewport
- **WHEN** only the first short phrase of a viewport filled with actual native text is selected
- **THEN** the capsule avoids the actual used body/selection/control bounds or occupies a separate dock outside the document viewport
- **AND** narrow-window, enlarged-label, scrolling, resizing and focus behavior remain available without changing body authority
