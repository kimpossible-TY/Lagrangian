# Web computation and offline reading verification

## Implemented so far (2026-10-24)

Raw CompileRequest/CompileResult execution is injected through Project.execute.
Base HTML, private carrier HTML and marked/final highlight HTML plus PDF validation
use it. The default implementation uses the existing Typst executable. Python
normalization, loss warnings, source correspondence and final source writes remain
the acceptance owners. The foreground browser compiler is now connected through
HTTP leases and generated WASM assets; `--browser-compiler` enables it explicitly.

The HTML web app includes a manifest and generated 192/512 icons. Its Service
Worker installs the explicitly listed application and MathJax assets under a content
version, then saves all accepted sections/assets into a staging cache. A final
identity check precedes the atomic pointer change. Failed downloads, quota errors
and document races preserve the last complete snapshot. Requests retain the hosted
base path. Offline reload uses stored sections and mathematics; reconnect refreshes
through existing document/service identity checks. Settings report offline save status.
Unsupported dynamic geometry still needs its existing server rendering path.

## Evidence

- `python3 -m unittest discover -s tools/flow-reader/tests -p test_execution.py -v`:
  7 passed, including actual Typst HTML/PDF compilation and injected-executor
  acceptance, carrier failure and paged-candidate checks.
- `FLOW_READER_PACKAGES=... python3 scripts/test-reader-services.py`: 224 tests,
  passed with 7 skips. Six require FLOW_TEST_ENGINE for actual shared source-history
  integration; the companion patch fixture requires TAIL_HOSTING_SOURCE.
- `node --test tools/flow-reader/tests/test_*.mjs`: 171 passed, including interrupted
  snapshot downloads, quota failure at pointer commit, revision changes, bounded
  retention and hosted-path isolation.
- Reader architecture checks: 2 passed. Full reader ESLint command passed with
  zero warnings using node_modules/.bin/eslint (Yarn is not on this host's PATH).
- `tests/offline-browser.mjs`: actual Typst + isolated Python HTTP server + full
  Reader shell passed in Chrome and desktop WebKit at 390x844. Verified PWA worker
  activation, cached MathJax, offline reload, a never-mounted second section,
  reconnect to an edited document and another offline reload of the new revision.
  Chrome uses browser offline emulation; WebKit uses actual server connection drops
  because its emulation fails navigation before Service Worker dispatch.
- The installed-layout test passed in an isolated temporary release; no user service
  was installed or restarted. OpenSpec strict validation, generated-document check
  and compilation of reader-architecture.typ passed.

A separate minimal reproducer showed this installed Playwright/WebKit build resolves
`waitForFunction(async () => false)` immediately. The browser fixture therefore
awaits CacheStorage values in Node and compares them to the revision printed by the
server before disconnecting; it does not trust that asynchronous polling helper.

## Browser compiler evidence (2026-10-24)

`verification-web-computation.json` records the corpus/compiler identities,
per-run metrics and complete output comparisons. Canonical architecture and
reproduction notes are in `docs/tinymist/dev/web-computation.typ`.

- The snapshot and lease suites cover immutable bytes, temporary candidates,
  maintained adapters, discovered preview-cache dependencies, explicit fonts,
  capture races/limits, heartbeat loss/reassignment, stale/duplicate results,
  invalid outputs, closure and native fallback (7 snapshot + 9 pool tests).
- Actual `compiler-pool-browser.mjs` runs in Chrome and desktop WebKit passed
  base/source-carrier execution, shared accepted revisions, pagehide reassignment,
  external source edits during compilation, HTML/PDF highlight validation and
  final writes, and dynamic geometry with native incremental fallback.
- The generated compiler builds from locked workspace dependencies and exact
  wasm-bindgen CLI. Rust tests and warning-denying Clippy passed; workspace fmt
  passed. HTML/PDF, incremental changed imports and missing/restored files were
  exercised in actual WASM Workers. The latest-used evaluator cache policy fixes
  a measured sixth-run wasm32 memory exhaustion with the earlier retention policy.
- Real PDE: both desktop browsers completed 12 versions (first compile + 11 edits),
  with all 24 normalized HTML outputs exactly matching native compilation and
  passing the content gate. First compilation was 15.04/15.43 s; incremental
  medians were 1.69/1.86 s (Chrome/WebKit). WASM linear memory stabilized at
  3,470,458,880 bytes after the second compile. This is a substantial footprint,
  not evidence of iPhone viability or total browser-process memory.
- Final Python service run: 242 tests passed with the same 7 optional-environment
  skips. Reader Node suite: 172 passed; architecture: 2 passed; reader lint, strict
  OpenSpec validation, generated-doc check and both changed Typst documents passed.
- Isolated installer validation packages the generated asset pair and manifest,
  verifies their installed paths in launch arguments, preserves the setting on
  upgrades and rejects modified assets without overwriting configuration.
  No user service was installed or restarted.

## Remaining objective

Additional local decoration/figure computation, offline highlight intent
persistence/idempotency and combined final verification remain unchecked tasks.
Physical iPhone lifecycle/memory/thermal measurements remain unavailable. Desktop
WebKit is not an iPhone measurement, and open-page computation does not imply
background execution. The active goal remains incomplete.
