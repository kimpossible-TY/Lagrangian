# Verification

The UI change is local on feat/reader-paragraph-chat-redesign. Homepage prerequisite
498b1491 is integrated locally; its independent account authority and read-only
document status/catalog contract are retained. No application install/restart,
push, live sign-in or model inference was performed.

- Node HTML/shared policy and architecture tests: 276 passed, zero skipped.
- Reader services: 296 passed, 58 optional integration tests skipped. Compiler,
  source-history, physical devices and live OAuth/inference are not verified by
  those skips. Existing install/static-delivery tests verify the new manifest.
- Chromium paragraph-chat fixture: 40 checks, zero page errors, with local fake
  OAuth/provider only. Covers immutable question context and revision evidence,
  reselection, duplicate send and lost acknowledgment, streaming/interruption,
  partial failure/retry, Markdown/TeX/code escaping, late math replacement guards,
  shared settings/focus, mobile overflow, exact margin geometry and annotations.
- Reader lint and changed-file Prettier checks pass.
- Desktop 1440px and mobile 390px production-source previews were captured and
  visually inspected with a fictional variational-calculus document/history at
  reading size 17px. They are source-rendered fixtures, not a live installed UI.
  Inspection caught and fixed a MathJax dynamic fraction/bracket CSS update.
- The Homepage browser's touch target assertion at home-browser.mjs:292 fails in
  this Chrome environment both in the integrated branch and unchanged 498b1491
  Homepage worktree. Its other source is unmodified here. This is not claimed as
  a passing aggregate Homepage browser run; route/account boundaries are covered
  by the passing service and paragraph-chat fixtures.

The document toolbar retains the canonical inline SVG L logo. All answer markup
uses a DOM allowlist and locally served versioned assets. Unsupported TeX remains
literal; no HTML/require/autoload extension is enabled for answer mathematics.
