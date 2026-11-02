# Verification

The UI change is local on feat/reader-paragraph-chat-redesign. Homepage prerequisite
498b1491 is integrated locally; its independent account authority and read-only
document status/catalog contract are retained. No application install/restart,
push, live sign-in or model inference was performed.

- Node HTML/shared policy and architecture tests: 276 passed, zero skipped.
- Reader services: 296 tests total; 238 passed and 58 optional integration tests
  skipped. Compiler,
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
- Homepage Chromium fixture: 34 checks passed with zero page errors after the
  touch-target test correction. Paragraph chat Chromium was rerun: 40 checks
  passed with zero page errors. Node policy/architecture tests were rerun:
  276 passed. Reader lint also passed. Diagnosis reproduced the exact failing measurement on a detached
  HTML Reader link: isConnected=false, width=0, height=0. Current rendered links
  measured 152x44px, 152x44px and 312x44px at a 390px touch viewport. Refresh
  replaces cards between locator resolution and evaluation. The test now waits
  for its document response/rendering frame and atomically queries current links,
  asserting the existing 44px tolerance on both axes for every link. Product CSS
  and original Homepage worktree are unchanged.


The document toolbar retains the canonical inline SVG L logo. All answer markup
uses a DOM allowlist and locally served versioned assets. Unsupported TeX remains
literal; no HTML/require/autoload extension is enabled for answer mathematics.
