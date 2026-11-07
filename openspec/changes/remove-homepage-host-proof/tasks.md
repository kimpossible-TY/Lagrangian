# Tasks

## 1. Contract

- [x] 1.1 Define the narrowly scoped exception in proposal and design, and record the complete contract as the new homepage-account-auth capability using only ADDED requirements; verify with strict OpenSpec validation.

## 2. Server authority

- [x] 2.1 Add OAuth-only session permission and retain management gates, expiry and rotation; verify login/logout success and cancel/status denial with isolated Python tests.
- [x] 2.2 Retain socket-peer, Host, Origin, forwarding/proxy and CSRF guards; verify both operations against negative request cases and exercise real ChatAuth PKCE/state/nonce through HTTP.

## 3. Homepage

- [x] 3.1 Enable local login/logout before management unlock and navigate directly to OpenAI; verify local/remote, session scope and proof retention with Node tests and update the browser fixture for direct navigation.
- [ ] 3.2 Update the architecture authority description and existing fixtures; verify formatting/lint and Typst compilation, attempt the isolated browser check and record environment limitations. Code/fixtures, formatting/lint and browser attempt are complete; Typst compilation has not been verified in this revision.

## 4. Integration verification

- [x] 4.1 Run relevant Python services and Homepage Node suites, attempt the browser suite, run strict OpenSpec validation and diff checks; report actual results and any skipped coverage without committing or pushing.

## 5. PR #18 review corrections

- [x] 5.1 S1: Provide scoped OAuth CSRF for retained management cookies without changing management authority; cover first login/logout, scope denial and session capacity protection in HTTP/Node tests and the browser fixture.
- [x] 5.2 S2: Require current host capability plus management CSRF for nonempty login registration before ChatAuth.login; cover OAuth-only and management sessions with absent, invalid and current capability and empty/nonempty registration.
- [x] 5.3 S3: Let Homepage own consent navigation via a per-call ChatAuth opener opt-out; cover real production runtime composition with an opener spy and preserve default terminal opening.
- [x] 5.4 S4: Reconcile both active changes with explicit homepage-account-auth ownership and narrow supersession, 421 invalid Host and 200 sanitized account fallback; retain independently archivable ADDED-only deltas.

## Verification results

This revision uses HEAD `d794a3e092978b1271f68b6690966c7e4041f533` plus uncommitted review fixes on `feat/homepage-no-hostproof`, macOS arm64, Python 3.15.2 and Node v26.13.0. Results below were obtained on 2026-11-07 UTC. No commit, push or live-service changes were made.

- Final requested focused run from `tools/flow-reader/tests`: `PYTHONPATH=..:. python3 -m unittest test_homepage test_routing` passed 32 tests (23 Homepage, 9 routing), including the final management-capacity regression. The earlier combined run with `test_reader_runtime` passed 42 tests, including all 11 runtime tests and the production ChatAuth opener spy.
- Final full run: `PYTHONPATH=..:. python3 -m unittest discover -s . -p 'test_*.py'` ran 352 tests in 147.628s: 288 passed, 61 skipped, 3 errors. Errors are in unchanged fixtures: `test_editor.NeovimWriterTests.test_real_neovim_rpc_rejects_dirty_buffer_then_saves_verified_edit` (Neovim remote `edit!` exits 2), and `test_neovim_view.NeovimViewTests.test_interactive_shell_keeps_editor_in_foreground_during_start` / `test_unknown_sixel_geometry_preserves_editor_and_job_control` (`ps` denied by sandbox). The first full run before adding the capacity regression had the same three errors. No Homepage, routing, runtime or OAuth tests failed. Log: `/tmp/pr18-revision-python-full-final.log`.
- `node --test tools/flow-reader/tests/test_home_account.mjs tools/flow-reader/tests/test_reader_links.mjs`: 7 passed (6 Homepage account tests). `node --test tools/flow-reader/tests/test_*.mjs`: 250 passed, none skipped.
- `home-browser.mjs`: **NOT RUN (browser assertions)**. Attempt at 2026-11-07T00:40:31Z, on the HEAD plus worktree fixes identified above, with `FLOW_READER_PLAYWRIGHT_MODULE=/tmp/homepage-unify-browser/node_modules/playwright/index.mjs` and `CHROME_BIN=/Applications/Google Chrome.app/Contents/MacOS/Google Chrome`. Chrome aborted during launch (`SIGABRT`, `Target page, context or browser has been closed`) before any assertions; the new retained-cookie browser cases remain unverified. Log: `/tmp/pr18-revision-browser.log`. The previous “38 checks” claim lacked traceable SHA/environment/time evidence and is withdrawn.
- Both `openspec validate remove-homepage-host-proof --strict` and `openspec validate unify-homepage-reader --strict` passed with ADDED-only deltas and no archive-refusal warning.
- Reader ESLint scope from `package.json` passed with zero warnings/errors, using existing dependencies under `/tmp/homepage-unify-browser` and a verbatim temporary copy of the repository config for dependency resolution. Prettier passed for both changed `.mjs` files. No dependency installation or repository dependency files changed.
- `node --check tools/flow-reader/tests/home-browser.mjs` and `git diff --check` passed. Browser syntax validation does not substitute for the browser assertions that could not run.
- Typst compilation was not run in this revision; task 3.2 remains unchecked. Rust builds, live OAuth and physical-device checks were not run.
