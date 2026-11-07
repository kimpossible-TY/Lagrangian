# Proposal

## Why
Homepage and HTML documents currently require separate Python processes and origins.
A single Reader host gives inventory, reading and account entry one stable address
while preserving Mac-only credential authority.

## What Changes
- Serve Homepage at `/` and configured HTML documents at `/d/<reader-id>/` in one Reader process.
- Compose existing Homepage and document handlers, compiler/watch state and ChatAuth.
- Keep old document origins through redirect-only listeners in the same process.
- Require the current private capability for management mutations and privileged identity reads, in addition to session/CSRF and loopback checks. `homepage-account-auth` in `remove-homepage-host-proof` now owns the narrowly superseding exceptions for Homepage login without registration selection and logout; see reader-host's local authority requirement.
- Offer one shared ReaderManager launch plan/job; document operator-controlled migration and rollback.

## Capabilities

### New Capabilities
- `reader-host`: shared Homepage/document routing, authority and lifecycle compatibility.

### Modified Capabilities
None. Existing active Homepage and paragraph-chat changes are prior art; this
change supersedes their separate-host topology without replacing their account,
conversation or presentation contracts.

## Impact
Python Reader HTTP composition, ReaderManager lifecycle and inventory, account
frontend and isolated routing/service tests. Existing per-document configuration
is retained until shared mode is selected. No dependencies or credential/history
schema migration. Canonical architecture and operator guidance are updated.
