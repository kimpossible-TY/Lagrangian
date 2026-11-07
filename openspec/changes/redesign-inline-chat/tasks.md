## Implementation

- [x] Implement the responsive logo annotation, document asset provenance and verify selection, focus, resizing and cleanup in an isolated browser.

- [x] Redesign the inline conversation hierarchy and compact composer while preserving the shared settings dialog and per-conversation model selection.
- [x] Integrate the concurrent draft-recovery and localized progress changes through `b3856727` without overwriting their source.
- [x] Verify narrow and wide browser interactions, streaming, interruption, focus, theme and screen captures using isolated fixture data.
- [x] Run focused reader tests, lint and OpenSpec validation; record remaining device coverage.
- [x] Restore the folded summary bubble from the original contract and verify collapsed/expanded screenshots and placement. Chromium: 51 checks passed, including exact one-third/two-thirds margin placement, collision avoidance, mobile fallback, keyboard/touch activation and focus return; contrast and strict OpenSpec checks pass. Refreshed the 390px comparison captures and visually checked the folded bubble.

Chromium fixture: 46 checks and zero page errors, including interruption,
shared settings focus, narrow layout and composer growth. Shared and HTML Node
suites: 315 passed, one skipped. Reader ESLint and both affected OpenSpec
validations pass. Reviewed light and dark 390px and desktop captures from the
isolated baseline harness. Physical iPhone/Safari and live inference remain
unverified; viewport-only captures do not establish real keyboard behavior.

The subsequent Apple-design review removes stacked glass surfaces from reading
content and the composer, and adds a visible input underline and pressed/forced
colors states. The 49-check isolated Chromium interaction fixture passed on
Chrome 156.0.8078.80 / Playwright 1.65.0, including mobile geometry, keyboard
focus, streaming and interruption. Light and dark viewport captures were
reviewed. Web-interface guidance was audited against pinned revision
`434b7f91364665f2f733b310ec54809bf8f37937`, SHA-256
`d246b026f4f29b5823a9cc857f9edf3d2507002e055e32040cadeaf3b38e0234`.
Device Safari, VoiceOver and native motion remain unverified.

Following the requested correction, expanded conversations use a single
floating surface with a boundary and shadow; contents and composer remain
unboxed inside it. The 49-check Chromium fixture, surface contrast checks and
strict OpenSpec validation pass; 390px light and dark captures were inspected.

Default model follow-up: a new conversation selects `gpt-6-luna` when present;
Luna Responses and tool-continuation requests explicitly send `xhigh` reasoning.
The browser fixture checks the displayed default and existing selection; the
local fake provider verifies reasoning in multiple requests. Redundant composer
and status labels are visually hidden while retaining accessible semantics.
Live SIWC entitlement and real model inference remain unverified.

Compact annotation follow-up: the 28x24 logo bubble reserves a 44x44 inline
target at its paragraph end, while eligible margins retain the summary. The
60-check Chromium fixture passes with zero page errors, including copy exclusion,
keyboard focus transfer, paragraph remounting, wide layouts without spare margin
space and numbered-equation placement. The 320, 390, 768, 959, 960, 1280 and
1440px layout matrix passes without horizontal overflow. Refreshed and inspected
light/dark collapsed captures and narrow/wide expanded captures. Shared/HTML Node
tests: 315 passed, one skipped; the isolated installed-layout test passes.
Full reader ESLint, strict OpenSpec validation and diff checks pass. Physical
iPhone Safari and VoiceOver remain unverified; no live services were changed.
