# Tasks

## 1. Registered preview transport
- [x] 1.1 Implement validated profile mapping and HTTP proxy; test IDs, query/path, framing, errors, redirects and absolute assets.
- [x] 1.2 Relay bounded WS upgrades and bytes; test Origin, credentials, handshake, bidirectional frames, disconnect and stop/restart.
- [x] 1.3 Deliver a scoped current-client bridge; test root/theme/loopback URLs and prevent cross-preview/global route escapes.

## 2. Shared Reader integration
- [x] 2.1 Compose and dispose proxy ownership in ReaderRuntime without controlling engines; test runtime shutdown and retained direct ports.
- [x] 2.2 Link Homepage and HTML paged aliases to registered preview prefixes, including parent-only profiles; test inventory and existing account/routing regressions.
- [x] 2.3 Document routing ownership, migration and client limitations in canonical architecture guidance; validate the edited Typst source.

## 3. Verification and handoff
- [x] 3.1 Run focused Python, delivered JS and relevant browser checks; record results and unavailable engine/device coverage.
- [x] 3.2 Validate OpenSpec strictly, review diff and write /tmp/preview-unify-report.txt with exact optional frontend/engine handoff and verification plan.

## 4. PR review fixes
- [x] 4.1 Allow data URL fetches only in proxied HTML connect-src; assert the exact policy and add a browser WASM fetch/instantiation regression.
- [x] 4.2 Drain bounded relay buffers after per-direction EOF before propagating half-close; test a slow receiver and close frame.
- [x] 4.3 Document the fixed preview bridge exception to the static asset manifest and record verification.
- [x] 4.4 Bound teardown after the first EOF, drain pending bytes and verify an unresponsive client releases the connection and slot.
