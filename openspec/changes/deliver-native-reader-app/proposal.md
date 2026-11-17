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
None. Existing engine artifact names, reader-bundle verification, profile schema and service lifecycle remain supported. The new delivery contract refines native app production without changing shared native document or security policy.

## Impact
Delivery scripts, the workflow app boundary, native composition, isolated regression tests and canonical delivery/runtime Typst documentation. Engine cache keys and Rust sources are unchanged. Core/page consumers retain their owners; final source rebinding, GUI/VoiceOver and macOS 13 runtime certification are separate gates.
