# Verification

Worktree `/Users/taeyoung/Developer/lg-preview-unify`, branch
`feat/preview-unify`, HEAD `92408371` unchanged. No commit/push, Rust source edits
or local Rust builds, live launchd/service changes or Application Support edits.
All HTTP/WS backends, account state and browser profiles were isolated fixtures.

## Passed checks

- `openspec validate unify-preview-origin --strict` and `openspec validate unify-homepage-reader --strict`.
- `PYTHONDONTWRITEBYTECODE=1 PYTHONPATH=tools/flow-reader/tests python3 -m unittest test_preview_proxy test_reader_runtime test_routing test_homepage test_chat_storage test_paragraph_chat test_manager -q`: **108 passed**, no skips.
- After final transport hardening: `python3 -m unittest test_preview_proxy test_routing test_reader_runtime -q` with the same environment: **32 passed**; the final HTML/CSS/srcset/data-image changes then passed all **13 proxy tests** again.
- `node --test tools/flow-reader/tests/test_*.mjs tools/reader-common/tests/*.mjs`: **283 passed**, no skips, including two delivered bridge tests for HTTP and HTTPS URL rebasing.
- The repository's Reader ESLint command: passed with zero errors/warnings, using temporary dependencies in `/tmp/homepage-unify-browser` via a temporary resolution symlink (removed after checks).
- `preview-proxy-browser.mjs` with Playwright 1.56.1 and isolated installed Chrome: passed initially and after final HTML adaptation. Homepage preview-only link, root-relative assets, root/theme WS, binary frames, upstream stop/restart and retained direct port all passed without page errors.
- `typst compile --root . docs/tinymist/dev/reader-architecture.typ /tmp/preview-unify-architecture.pdf`: passed with the preinstalled compiler. `node scripts/link-docs.mjs --check`: passed.
- `git diff --check` and `git apply --check /tmp/preview-unify-frontend-handoff.patch`: passed. The handoff patch is optional and unapplied.

## Evidence and limits

Tests exercise registered-only routing, multiple preview separation, invalid IDs,
traversal, fixed loopback destinations, query preservation, scoped redirects,
HTML/CSS/inline/srcset assets, HEAD/Range, exact and duplicate Origin rejection,
credential filtering, editor-host denial, proxy ingress and account mutation 403.
The WS fixture writes its handshake and first frame together and accepts an early
client frame; text/binary/ping/close bytes round-trip. Invalid handshake/key,
connection limits, backend stop/restart and Reader proxy disposal are covered.
Runtime and Homepage fixtures cover preview-only parent profiles and `/d/` paged
aliases without adding native engine lifecycle operations.

No Rust source change is needed for the current source's embedded single-file
frontend: the Python response adapter delivers a scoped pre-client WS bridge.
Source findings and an exact optional frontend cleanup diff plus remote engine
verification plan are recorded in `/tmp/preview-unify-report.txt`. Shipping that
cleanup needs a rebuilt embedded frontend/engine artifact through remote CI; it
has not been applied or built in this session.

No actual engine rendering, installed bundle activation, native editor integration,
physical-device behavior or production TLS/Tailnet was verified. Current HTTP
proxying is GET/HEAD; preview interaction is WS. Opaque executable JavaScript and
future root ES-module imports are deliberately not rewritten. Original preview
ports/jobs and their direct Origin settings are unchanged; registration changes
require a normal Reader restart. Local processes reusing a registered port remain
within the existing loopback trust model.

## Re-verification on main 6b816f67 (2026-11-07 KST)

The uncommitted work from `feat/preview-unify` (base 92408371) was carried as a patch onto `feat/preview-unify-v2` at origin/main `6b816f67` (after PRs #18–#24). It applied without conflicts or code changes.
- Node reader suite: 307 pass / 0 fail / 0 skipped.
- `tools/flow-reader` Python tests: 365 ran, OK (61 skipped).
- `tests/flow-app`: 139 ran, 1 failure `test_reader_bundle...installed_destination_are_refused`, which is pre-existing on main.
- `preview-proxy-browser.mjs` with installed Chrome 156 (`CHROME_BIN`): passed.
- ui-baseline compare (report-only): ran, exit 0.
- ESLint on the proxy JS: clean. OpenSpec strict and `git diff --check`: pass.
