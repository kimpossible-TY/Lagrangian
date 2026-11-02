# Homepage implementation verification

## Source and authorization

- Implementation developed in an isolated feature worktree; no main-checkout edits.
- PR #11 prerequisite is incorporated through the publication merge of the existing remote proposal head and current main. Original local implementation branches remain intact; their commits are not publication ancestors.
- User authorized implementation on 2026-11-02 using the concept image and actual HTML Reader logo. The approved concept image was visually inspected. Its example titles/statuses are used only in fake fixtures.
- Header SVG path is copied from the current Reader shell; a Python fixture compares the complete base path. Existing palette tokens and theme preference are reused. The math motif is decorative rather than a compiled preview.

## Implemented behavior

Dedicated `home.py` composition serves host `/` without constructing a document Project, compiling, starting managed services, or making inference requests. It reads existing manager/parent inventory, validates destinations, sanitizes names/identity, and observes configured HTML services with bounded background work. Paged readiness remains unknown. Empty, invalid, unavailable, unknown and stale states have explicit feedback.

Homepage management retains merged ChatAuth, its protected registration directory and original OAuth callback. A per-start private host proof authorizes an isolated browser session; Host, Origin, ingress, peer, CSRF, cookie scope and expiry are enforced independently. One process lease owns pending OAuth per credential directory. Remote proxy ingress remains read-only. Logout invalidates sessions and preserves history/drafts; revocation uncertainty is reported. Document auth APIs retain revision validation and reject all credential mutations; account links use configured `homepageURL`/`--homepage-url` and open separately.

## Passed checks

| Check | Result |
| --- | --- |
| `yarn test:reader-services` | 295 tests, 237 passed, 58 explicitly skipped; run through the existing Yarn 1.22.22 CLI. |
| Focused `test_homepage.py` | 10 passed, including the final single-host lease, session restart/credential rotation, expiration, CSRF, proxy denial, inventory states and complete logo-path checks. |
| `node --test tools/flow-reader/tests/test_*.mjs tools/reader-common/tests/*.mjs` | 271 passed. |
| `yarn lint:readers` | Passed with zero lint warnings/errors. |
| `yarn test:architecture` | 2 passed; no dependency cycle or ownership violation. |
| `home-browser.mjs` | 34 passed in isolated Chromium; no page errors. Desktop, touch/mobile, dark, title search, empty/error/stale, interrupted login, explicit cancel, catalog failure, cross-tab logout, delayed old responses, hidden/disposed pages, offline account, direct Reader/history navigation and simulated HTTPS proxy read-only behavior. |
| `paragraph-chat-browser.mjs` | 30 passed using fake OAuth/model services; existing history/drafts and paragraph interactions retained. |
| Isolated installed-layout test | Passed; host entry, manifest assets and imports exist in the staged immutable layout. No installed user service touched. |
| `node scripts/link-docs.mjs --check` | Passed after regenerating the existing derived Markdown. Regeneration also reconciled pre-existing main-source/Markdown drift in README and development guide. |
| Strict OpenSpec validation | Both `add-reader-homepage` and reconciled active `add-reader-paragraph-chat` passed. Requirement paragraphs remain below 500 characters (home maximum 155; paragraph-chat maximum 496). |
| `git diff --check` | Passed. |

The service-suite skips are 50 fixtures requiring `FLOW_READER_PACKAGES` (optionally `FLOW_READER_TYPST`), 7 requiring a fresh compatible `FLOW_TEST_ENGINE`, and 1 requiring `TAIL_HOSTING_SOURCE`. A later focused lease test adds coverage after that suite's discovery. Tests used fake providers and temporary data, without live sign-in, credential changes, paid inference, Rust compilation, installation or restart.

## Existing browser fixture limitations

Two additional legacy fixtures fail identically on an untouched archive of merge `7535d948` and on the implementation tree:

- `reading-settings-browser.mjs:142`: waits for a hidden compiler-diagnostics summary while its fixture explicitly disables the browser compiler. Earlier theme/font/mobile checks execute, but this fixture cannot complete its full diagnostic/focus sequence.
- `offline-browser.mjs:111`: cached mathematics reloads, then its expected offline status transition times out. Replacing the retired status assertion with the current logo phase did not resolve the baseline failure; the repository fixture is retained unchanged. Complete offline/reconnect integration is therefore **not claimed**. Offline policy tests pass and host assets/account APIs are isolated from the unchanged document worker.

These were reproduced using the preinstalled Typst compiler and isolated fixture projects; no Rust engine was built. Physical iOS/macOS browser, live Tailnet/TLS provisioning, actual paged protocol and full source-history integration remain unverified.

## Deliverables and activation decisions

Fake-data screenshot artifacts: `homepage-desktop-fixture.png`, `homepage-mobile-fixture.png`, `homepage-dark-fixture.png`, and `homepage-remote-fixture.png`. They were visually inspected. The supported Library batch-upload helper returned `Library prepare_uploads is not available`; no Library screenshot IDs were created and no alternate upload route was attempted.

Implementation defaults to a separate `127.0.0.1:8769` admin origin. Actual HTTPS identity, reverse-proxy/TLS provisioner, isolated read-only ingress and homogeneous viewer grants must be selected before activation. All allowed viewers share sanitized inventory/status and one host-global account; per-viewer document permissions and remote management are deferred. Existing document roots are preserved. No deployment, publication, live service restart, PR readiness change or push was performed.

Concurrent paragraph-chat redesign should preserve this branch's narrow migration in `web/features/paragraph-chat/controller.js` and its auth-specific Node/Python/browser tests. The host implementation owns auth/session/routes and Homepage assets; this branch makes no chat-layout redesign. `web/reader.css` changes only extract shared theme tokens to `web/theme.css`.
