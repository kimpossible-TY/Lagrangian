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

## 4. Mobile capture stabilization

- [x] Wait for the Reader's ready logo, completion timer, and fixture equation composition; reset the Reader capture to the top.
- [x] Require two identical screenshots with bounded retries and record retry counts; reject unstable baseline updates.
- [x] Test the retry and failure paths without Chrome.
- [x] Repeatedly compare captures on an unsandboxed Mac: after regenerating the baseline (main 181b419e + this fix, Chrome 156.0.8078.80, Playwright 1.65.0), 5 consecutive compares had 0 changed pixels in all 12 captures. Before the fix, mobile Reader differed by 15 px in 2 of 5 runs. The race fixes are effective together; the single root cause was not isolated.

The harness formerly waited for `aria-busy=false`, but Reader clears that before its next-frame activity transition. Its math renderer separately schedules per-formula MathJax conversion after a debounce; startup alone does not await that conversion. Those are concrete capture races, especially relevant to narrow layouts, but the reported 15-pixel difference has not been isolated to either without browser evidence. The logo's completion marker expires after 1.6 seconds; animation suppression does not wait for that state transition. Toolbar visibility changes on a tap, not a scroll timer. The fixture contains no canvas or images; reading-position restoration and font completion can move content, so the Reader capture resets scroll after composition and waits for fonts. The clock is installed but runs, allowing these timers to complete.
