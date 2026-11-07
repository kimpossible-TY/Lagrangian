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
