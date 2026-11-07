## 1. Contract and capture

- [x] Add static selector checks and a negative contract test to the Node runner.
- [x] Check dynamic and conditional selectors on rendered fixtures.
- [x] Capture the theme, viewport, and page matrix and write report-only pixel diffs.

## 2. Documentation and verification

- [x] Document local baselines, metadata, commands, and report interpretation.
- [x] Capture on the unsandboxed Mac: the first attempt hit CSP; enabling test-only `bypassCSP` allowed a successful capture.
- [x] Repeat capture and comparison on the unsandboxed Mac after stabilization (d12832fa): baseline regenerated, then two consecutive compares with 0 changed pixels in all 12 captures.
- [x] Stabilize capture: chat focus and pointer hover, or rendering still settling after fonts load, are suspected causes of the 1,353-pixel chat differences; transient scrollbars or paint timing may explain the two home pixels. The clock and inventory timestamp were already pinned. Blur focus, move the pointer, hide scrollbars, wait for network idle, MathJax startup, fonts, image decoding and two animation frames. The repeat comparison passed; the individual root cause was not isolated.

## 3. Run records

Chrome attempts by environment:
- Sandboxed agent (codex workspace-write): Chrome launch aborts with SIGABRT; capture not possible there.
- Unsandboxed Mac, 64fd3a94 and earlier: `page.addStyleTag` blocked by CSP `style-src 'self'`; fixed with test-only `bypassCSP`. Then 9/12 matched run-to-run (desktop chat light/dark 1,353 px, desktop dark home 2 px).
- Unsandboxed Mac, d12832fa: Chrome 156.0.8078.80, Playwright 1.65.0; 2 consecutive compares, 0 diffs in all 12 captures.

Verification at d12832fa: Node reader suite 298 pass / 0 fail / 0 skipped (architecture and lint-config included); ESLint clean on changed files; OpenSpec strict valid; `git diff --check` clean. Python flow-app: 139 ran, 7 skipped, 1 failure `test_reader_bundle...test_wrong_run_missing_selector_and_installed_destination_are_refused`, which fails identically on a clean origin/main worktree (pre-existing).
