# Proposal

## Why

The Homepage currently requires a private host capability before a local browser can start ChatGPT OAuth or sign out. A browser on the Mac should be able to choose Continue with ChatGPT and proceed directly to OpenAI while remote visitors retain status-only access.

## What Changes

- Exempt only Homepage OAuth login start and logout from host-proof on genuine admin loopback requests.
- Issue an explicitly requested OAuth-only browser session with CSRF; retain the management session and capability requirements for cancel and privileged account status.
- Show local login/logout controls before unlock and navigate directly to the validated OpenAI authorization URL after login start.
- Retain exact Host/Origin validation, real socket-peer checks, forwarding/proxy rejection, session expiry/rotation, PKCE, state, nonce and server-only credentials.

## Capabilities

### New Capabilities

- `homepage-account-auth`: define loopback-only login/logout without host proof, retained request and OAuth guards, host-proof-gated management and remote/tailnet status-only access as a standalone capability using only ADDED requirements.

### Modified Capabilities

None. No accepted spec currently covers Homepage/account authentication; this delta does not depend on archiving `unify-homepage-reader` or creating an accepted `reader-host` spec first.

## Impact

Homepage HTTP policy, HomeAccount session permissions, Homepage UI and isolated Python/Node/browser fixtures. ChatAuth remains the credential and OAuth protocol owner. No dependencies, live services, storage migration, commits or pushes.
