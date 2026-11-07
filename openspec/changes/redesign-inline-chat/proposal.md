## Why

The inline conversation gives configuration controls the same prominence as the question and leaves a large empty composer on phones. Reading, asking and following an answer need a clearer hierarchy.

## What changes

Redesign the paragraph conversation for narrow and wide screens: put connection settings in the conversation header, keep model selection secondary, use a compact auto-growing composer, and distinguish the source, questions, answers and response state. Retain the shared account dialog, paragraph anchoring, draft recovery and existing transport.

Use the same compact logo-only annotation at the paragraph end on every screen.
An open conversation occupies a 360–420px capsule beside its paragraph only when
nearby whitespace is sufficient and collision-free, with at most 24px of right-margin spill; otherwise it follows the
paragraph. Preserve the controls, draft, caret and conversation scroll during
resize, and retain a still-valid position to avoid unnecessary movement.

## Capabilities

### Modified Capabilities

- `reader-paragraph-chat`: presentation and interaction of inline conversations.

## Impact

HTML and terminal Reader chat presentation, browser tests and documentation. No provider, storage or source-authority changes.
