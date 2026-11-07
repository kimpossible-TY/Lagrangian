# Tasks

## 1. Contract

- [x] 1.1 Define the narrowly scoped exception in proposal and design, and record the complete contract as the new homepage-account-auth capability using only ADDED requirements; verify with strict OpenSpec validation.

## 2. Server authority

- [x] 2.1 Add OAuth-only session permission and retain management gates, expiry and rotation; verify login/logout success and cancel/status denial with isolated Python tests.
- [x] 2.2 Retain socket-peer, Host, Origin, forwarding/proxy and CSRF guards; verify both operations against negative request cases and exercise real ChatAuth PKCE/state/nonce through HTTP.

## 3. Homepage

- [x] 3.1 Enable local login/logout before management unlock and navigate directly to OpenAI; verify local/remote, session scope and proof retention with Node tests and update the browser fixture for direct navigation.
- [x] 3.2 Update the architecture authority description and existing fixtures; verify formatting/lint and Typst compilation, attempt the isolated browser check and record environment limitations.

## 4. Integration verification

- [x] 4.1 Run relevant Python services and Homepage Node/browser suites, strict OpenSpec validation and diff checks; report actual results and any skipped coverage without committing or pushing.

## Verification results

- `python3 tools/flow-reader/tests/test_homepage.py`: 20 tests passed. `PYTHONPATH=tools/flow-reader:tools/flow-reader/tests python3 -B -m unittest test_routing`: 9 tests passed.
- `node --test tools/flow-reader/tests/test_home_account.mjs`: 5 tests passed.
- `FLOW_READER_PLAYWRIGHT_MODULE` set to the existing Homepage Playwright install and `CHROME_BIN` set to Google Chrome: `node tools/flow-reader/tests/home-browser.mjs` completed 38 checks with no page errors. The OpenAI destination was fulfilled locally and was not contacted.
- `openspec validate remove-homepage-host-proof --strict` passed after converting the delta to the new `homepage-account-auth` capability with only ADDED requirements; no "Archive would refuse" message remains and no existing `reader-host` spec is required.
- This session did not re-run the full reader service suite, ESLint, or Typst compilation. ESLint is not installed in this worktree.
