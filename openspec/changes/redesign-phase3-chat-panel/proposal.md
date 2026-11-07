## Why

Paragraph conversations need the shared Reader design language and concise, readable folded summaries.

## What Changes

Restyle chat controls and transcript with Phase 1 roles, and remove paired bold delimiters from plain-text summaries before truncation.

## Capabilities

### Modified Capabilities

- `reader-paragraph-chat`: conversation presentation and folded summary text.

## Impact

HTML chat CSS, shared summary policy and tests. Existing DOM, anchoring and Reader geometry remain intact.

## Non-goals

Reading and math layout, Reader chrome, PDF preview, chat positioning and transport.
