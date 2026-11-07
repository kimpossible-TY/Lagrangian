# Proposal: Refine Chat UI And Add Dashboard Card

## Why
The reader paragraph-chat collapsed summary currently displays raw LaTeX math delimiters instead of plain text, and the composer model selection resets after sending. Additionally, users need a direct navigation link to the Tail Dashboard from the Homepage aside.

## What Changes
- Convert LaTeX math delimiters in collapsed one-line summaries to plain text using safe DOM text assignment.
- Preserve model selection per conversation across sends and document updates, falling back cleanly when models disappear.
- Add an entry panel in Homepage aside linking to Tail Dashboard.

## Capabilities
### New Capabilities
- `chat-ui-dashboard-card`: Presentation refinements for paragraph chat summaries, model preservation, and Homepage Tail Dashboard entry card.

### Modified Capabilities
None.

## Impact
HTML reader web features and homepage layout only. No compiler, editor, backend protocol, or credential changes.
