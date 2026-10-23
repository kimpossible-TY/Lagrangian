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

## Authorized installation and reboot verification

2026-10-23: installed Flow 0.1.30 and the matching immutable HTML Reader release
from clean commit `43c8f9a359a0f860fb48d60de4240009777cc10f`. The native
warning-denying `flow-release` build includes the rebuilt paged frontend.
App and engine retain the previous signing certificate and designated
requirements. Signed engine SHA-256:
`9e35f0eb53de13091ddba10134f5918a881f46226596a7f182578274a7eac058`.

- The app installer retained the prior bundle for rollback. Recovery snapshots
  also contain Reader configuration, launcher, profiles and reading records.
  PDE paged and HTML services resumed; Ewald remained stopped. The running
  menu app was reloaded from the new bundle.
- All 533 immutable Reader files and 52 public assets match the candidate.
  Local and configured HTTPS delivery return the exact unchanged 8,956,107-byte
  PDE document. Profiles, Reader settings and both readers' last-change targets
  are preserved; HTML startup refreshed only its accepted-input fingerprint.
- App tests run 82 checks successfully, with the optional separate persistent
  signing-identity test skipped. Actual installed app/engine signatures,
  certificate continuity, version, hashes and clean source provenance pass.
- Chromium and WebKit using the installed Reader show immediate paint before
  an intercepted source request and remove it on rejection without modifying
  the production document. Both browsers using the installed native engine
  against canonicalized isolated sources pass immediate paint, native selection
  release, real verified source writes, unchanged surrounding text and removal
  of temporary paint when the compiled replacement renders. An initial probe
  used macOS's noncanonical temporary path and did not receive file-watcher
  updates; canonicalizing it, as existing engine fixtures do, resolves the
  harness issue without product changes.
- After the user's Mac reboot, installed signatures and all Reader release
  files still verify, PDE services restart automatically and Ewald stays stopped.
  HTML reports a successful accepted compilation. TLS-validated paged WebSockets
  deliver light and dark PDE frames of 18,338,264 and 18,394,224 bytes.
  Final screenshots were inspected. Receipts, snapshots and browser reports
  are indexed in `dist/optimistic-highlight-rollout/verified-rollout.json`.

This closes installed-service coverage from the implementation checkpoint.
Physical iPhone gestures and the optional companion integration remain untested.
