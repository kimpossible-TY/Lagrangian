## Why

Readers need a quick way back to the shared Homepage without losing the status logo's existing controls.

## What Changes

- Add a 500 ms logo hold and rightward swipe and a keyboard-accessible Homepage link to the shared HTML Reader.
- Keep logo click for the status popover and Shift+Enter or a popover button for refresh.

## Capabilities

### New Capabilities

- `reader-logo-home`: Navigation from the HTML Reader logo to the shared Homepage.

### Modified Capabilities

- `reader-status-logo`: Use long-press (hold) or a rightward swipe for home, and the popover button or Shift+Enter for refresh.

## Impact

HTML Reader gesture handling, chrome, and tests; no paged preview changes.

## Non-goals

Adding a logo to the `/p/<id>/` preview frontend.
