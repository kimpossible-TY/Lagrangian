## Why

Readers need a quick way back to the shared Homepage without losing the status logo's existing controls.

## What Changes

- Add a rightward logo swipe and a keyboard-accessible Homepage link to the shared HTML Reader.
- Keep logo click for the status popover and long press or Shift+Enter for refresh.

## Capabilities

### New Capabilities

- `reader-logo-home`: Navigation from the HTML Reader logo to the shared Homepage.

### Modified Capabilities

None.

## Impact

HTML Reader gesture handling, chrome, and tests; no paged preview changes.

## Non-goals

Changing refresh behavior or adding a logo to the `/p/<id>/` preview frontend.
