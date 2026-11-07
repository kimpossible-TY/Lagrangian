## Implementation

- [x] Redesign the inline conversation hierarchy and compact composer while preserving the shared settings dialog and per-conversation model selection.
- [x] Integrate the concurrent draft-recovery and localized progress changes through `b3856727` without overwriting their source.
- [x] Verify narrow and wide browser interactions, streaming, interruption, focus, theme and screen captures using isolated fixture data.
- [x] Run focused reader tests, lint and OpenSpec validation; record remaining device coverage.

Chromium fixture: 46 checks and zero page errors, including interruption,
shared settings focus, narrow layout and composer growth. Shared and HTML Node
suites: 315 passed, one skipped. Reader ESLint and both affected OpenSpec
validations pass. Reviewed light and dark 390px and desktop captures from the
isolated baseline harness. Physical iPhone/Safari and live inference remain
unverified; viewport-only captures do not establish real keyboard behavior.
