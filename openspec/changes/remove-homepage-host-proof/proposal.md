# Proposal

## Why

The Homepage currently requires a private host capability before a local browser can start ChatGPT OAuth or sign out. A browser on the Mac should be able to choose Continue with ChatGPT and proceed directly to OpenAI while remote visitors retain status-only access.

## What Changes

- Exempt only Homepage OAuth login start without registration selection and logout from host-proof on genuine admin loopback requests.
- Issue an explicitly requested OAuth-only browser session with CSRF; retain the management session and capability requirements for cancel and privileged account status.
- Show local login/logout controls before unlock and navigate directly to the validated OpenAI authorization URL after login start.
- Retain exact Host/Origin validation, real socket-peer checks, forwarding/proxy rejection, session expiry/rotation, PKCE, state, nonce and server-only credentials.

## Capabilities

### New Capabilities

- `homepage-account-auth`: define loopback-only login/logout without host proof, retained request and OAuth guards, host-proof-gated management and remote/tailnet status-only access as a standalone capability using only ADDED requirements.

### Modified Capabilities

None. No accepted spec currently covers Homepage/account authentication. The new `homepage-account-auth` capability owns account authorization policy and supersedes only the blanket host-proof requirement for Homepage login without registration selection and logout in active `unify-homepage-reader`'s `reader-host` requirement “Local capability authority on a shared origin” and its borrowed-session scenario. That active requirement and design explicitly defer these exceptions to this owner. Cancel, registration selection, identity disclosure, document isolation and remote denial retain their existing guards. Both changes remain independently archivable with ADDED requirements; neither requires an accepted `reader-host` spec or prior archival of the other.

## Impact

Homepage HTTP policy, HomeAccount session permissions, Homepage UI and isolated Python/Node/browser fixtures. ChatAuth remains the credential and OAuth protocol owner. No dependencies, live services, storage migration, commits or pushes.
