# Web computation and offline reading verification

## Implemented so far (2026-10-24)

Raw CompileRequest/CompileResult execution is injected through Project.execute.
Base HTML, private carrier HTML and marked/final highlight HTML plus PDF validation
use it. The default implementation uses the existing Typst executable. Python
normalization, loss warnings, source correspondence and final source writes remain
the acceptance owners. This is not yet a browser compiler connection.

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

## Remaining objective

Immutable compiler input bundles, the matching WASM compiler/Worker, foreground job
leases and reassignment, additional local decoration/figure computation, offline
highlight intent persistence/idempotency and real PDE performance evidence remain
unchecked tasks. No physical iPhone measurements, memory results, background-worker
guarantees or full mobile compilation are claimed. The wasm32 Rust standard library
was installed as a build prerequisite; no browser compiler artifact has been built.
