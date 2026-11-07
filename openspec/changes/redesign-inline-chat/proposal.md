## Why

The inline conversation gives configuration controls the same prominence as the question and leaves a large empty composer on phones. Reading, asking and following an answer need a clearer hierarchy.

## What changes

Redesign the paragraph conversation for narrow and wide screens: put connection settings in the conversation header, keep model selection secondary, use a compact auto-growing composer, and distinguish the source, questions, answers and response state. Retain the shared account dialog, paragraph anchoring, draft recovery and existing transport.

When the folded summary cannot fit in the margin, replace the former block-row
fallback with a compact logo-only annotation at the paragraph end. Preserve the
wide summary and the paragraph-local expanded capsule.

## Capabilities

### Modified Capabilities

- `reader-paragraph-chat`: presentation and interaction of inline conversations.

## Impact

HTML and terminal Reader chat presentation, browser tests and documentation. No provider, storage or source-authority changes.
