## 1. Contract and capture

- [x] Add static selector checks and a negative contract test to the Node runner.
- [x] Check dynamic and conditional selectors on rendered fixtures.
- [x] Capture the theme, viewport, and page matrix and write report-only pixel diffs.

## 2. Documentation and verification

- [x] Document local baselines, metadata, commands, and report interpretation.
- [x] Capture on the unsandboxed Mac: the first attempt hit CSP; enabling test-only `bypassCSP` allowed a successful capture.
- [ ] Repeat capture and comparison on the unsandboxed Mac after stabilization. The sandboxed agent's Chrome launch aborted with SIGABRT, so capture cannot be verified there.
- [x] Stabilize capture: chat focus and pointer hover, or rendering still settling after fonts load, are suspected causes of the 1,353-pixel chat differences; transient scrollbars or paint timing may explain the two home pixels. The clock and inventory timestamp were already pinned. Blur focus, move the pointer, hide scrollbars, wait for network idle, MathJax startup, fonts, image decoding and two animation frames. These causes remain unconfirmed until a repeat comparison.
