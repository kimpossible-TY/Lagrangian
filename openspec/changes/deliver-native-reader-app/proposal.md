# Proposal

## Why
Engine cache hits currently republish an older native app. Native reading also depends on development paths rather than a verified portable computation and backend payload.

## What Changes
- Reuse only engine bytes and their provenance; build the current Swift, resources and backend on both cache paths.
- Stage signed portable Node, Python, compiler and the current reader trees with hash-bound manifests before sealing the app.
- Compose a verified bundle environment through the existing runtime and manager injection APIs.
- Reject incomplete, stale, escaping or modified payloads and preserve previously valid stages.

## Capabilities
### New Capabilities
- `native-reader-delivery`: fresh native packaging, portable dependency verification and bundle-relative default execution.
### Modified Capabilities
- `flow-macos-app`: retain artifact name/layout and engine checksum/build provenance, but rebuild current app/release on both cache paths; consume same-run current payload through existing fetch/build CLI.
- `reader-bundle`: preserve same-run reader checks and cache keys while distinguishing reused engine bytes from fresh app/artifact bytes. Profile schema and service lifecycle remain supported.

## Impact
Delivery scripts, the workflow app boundary, native composition, isolated regression tests and canonical delivery/runtime Typst documentation. Engine cache keys and Rust sources are unchanged. Core/page consumers retain their owners; final source rebinding, GUI/VoiceOver and macOS 13 runtime certification are separate gates.

NA14 bridges the installed old updater CLI across fetch/build processes without editing its live copy. Invalid or unavailable current portable payloads fail before installation. Offline consumer validation is separate from production propagation and final PM/GUI acceptance.
