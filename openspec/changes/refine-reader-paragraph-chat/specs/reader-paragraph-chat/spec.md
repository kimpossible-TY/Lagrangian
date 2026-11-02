## ADDED Requirements

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
