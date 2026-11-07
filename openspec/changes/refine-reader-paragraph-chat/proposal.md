# Refine paragraph conversations

## Why
The current conversation flattens questions, answers and internal revision data
into plain text and repeats host account controls beneath every paragraph.
The user approved a document-inline redesign on 2026-11-02.

## What changes
Keep collapsed margin summaries, collision fallback and paragraph-local expansion.
Separate quote, question, answer and follow-up composition; put original question
context in accessible details. Render safe Markdown and base/AMS math without raw
HTML or new provider capabilities. Expose one shared read-only connection dialog linking to the independent
Homepage account settings, included as an explicit integration prerequisite.
After local dogfooding, reduce composer height, avoid duplicating a submitted
question during streaming, and present provider progress in Korean. Keep rejected
request notices visible across rerenders and explain required reselection before
sending from an older document context.

## Impact
HTML and terminal browser presentation only. No source changes, history schema,
authentication authority, provider, live credentials or inference changes.
