## ADDED Requirements

### Requirement: Clear streaming composer
After a question is accepted, the composer SHALL avoid duplicating the submitted
question while the answer streams, preserving it for recovery on failure or
interruption without overwriting a new follow-up draft. Known provider progress
SHALL be presented in Korean.

#### Scenario: Interrupted response
- **WHEN** an accepted response is interrupted and no new draft was entered
- **THEN** the submitted question is available in the composer for retry.

#### Scenario: Follow-up typed during streaming
- **WHEN** the reader types a different draft while the answer is streaming
- **THEN** that draft remains intact when the answer finishes or fails.

#### Scenario: Rejected send and document update
- **WHEN** sending a question is rejected or its captured document revision is old
- **THEN** a visible recovery notice remains through ordinary rerenders
- **AND** stale context requires explicit reselection before Send is enabled
- **AND** the draft and earlier question contexts remain intact.

### Requirement: Document-inline conversation typography
Expanded conversations SHALL remain below their source paragraph, preserve the
Reader paper/ink/accent tokens and reading size, and distinguish current quote,
literal question, formatted answer and follow-up composer. Original question
selection/revision SHALL remain accessible in a details control. Collapse,
keyboard focus, mobile inline fallback and desktop collision avoidance MUST remain.

#### Scenario: Streaming and immutable question context
- **WHEN** a later answer streams after selecting another subpassage
- **THEN** each earlier question retains its original accessible context
- **AND** partial, failed, interrupted and unknown states are not shown as complete.

### Requirement: Safe formatted answers
Answers SHALL render Markdown with an explicit DOM allowlist, no raw HTML and no
remote images. Supported TeX SHALL reuse local MathJax base+AMS without dynamic
extension loading; unsupported/invalid/incomplete math SHALL retain source.
Late formatting MUST NOT paint a newer document or message.

#### Scenario: Model markup and late typesetting
- **WHEN** an answer includes executable markup, unsafe links or a stale math result
- **THEN** it cannot execute, fetch embedded content or replace newer content.

### Requirement: Shared account controls
Account/token management SHALL remain owned by the independent Homepage. One
shared read-only connection dialog SHALL be reachable from each composer and
link to that configured Homepage. Document auth MUST remain status/models-only;
host proof and credential mutation controls MUST NOT appear in the document.

#### Scenario: Settings from two paragraph conversations
- **WHEN** either composer opens account settings
- **THEN** it opens the same dialog and closing returns focus to that composer
- **AND** no per-paragraph credential input or automatic auth/model request is added.
