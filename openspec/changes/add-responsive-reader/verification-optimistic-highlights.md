# Immediate source-highlight verification

2026-10-23 local implementation on the current branch:

- Source-highlight submissions paint immediately in the paged and HTML readers.
  Terminal Reader uses the same HTML actions and paint. Existing status strings,
  source verification and review-strike storage remain unchanged.
- Shared lifecycle tests cover successful acknowledgment without early removal,
  same-snapshot reflow, accepted replacement, rejected/consecutive tickets,
  late responses and disposal. Concrete action tests cover native selection
  release, retained retry text, newer selections and service/revision changes.
- 193 shared/HTML Node tests, 98 paged Vitest tests and 37 DOM Vitest tests pass.
  Both reader TypeScript checks and the complete reader ESLint gate pass.
- With `FLOW_READER_PACKAGES` pointing at the configured Typst package cache,
  the Python service suite runs 195 tests successfully with one optional
  Tail Hosting companion bridge class skipped because `TAIL_HOSTING_SOURCE`
  was not configured. This includes real compiler source-highlight validation
  and isolated installed-layout asset delivery; no user service is installed
  or restarted.
- `tools/flow-reader/tests/optimistic-highlight-browser.mjs` passes Chromium and
  WebKit for paged and HTML/terminal actions in light and dark appearance at
  390 × 844. Delayed acknowledgments prove paint appears before responses and
  remains after successful source-write acknowledgment. Real DOM geometry
  checks cover HTML font/width reflow and paged scaling, native selection release,
  unchanged document text, pointer-transparent/inaccessible paint, accepted
  replacement, rejection, superseded success and disposal.
  These browser fixtures use controlled document/response publication; actual
  compiler correctness is covered separately by the Python service suite.
  Captured views under `dist/optimistic-highlight-checks` were visually inspected.
- The preview bundle rebuilds through `node scripts/build.mjs build:preview`.
  Generated documentation consistency, architecture source compilation,
  formatting, strict OpenSpec validation and whitespace checks pass.

Physical-device gestures, actual installed-service delivery and a complete
Tail Hosting integration run were not performed. Existing installed services
and unrelated working-tree files remain untouched.
