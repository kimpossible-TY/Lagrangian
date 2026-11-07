# Design

## Context

See proposal.md. The active `unify-homepage-reader` capability requires host proof for every account mutation. `server/home.py` owns request eligibility and proof validation; `HomeAccount` owns browser authority/CSRF; `ChatAuth` owns credentials and OAuth. These owners remain unchanged.

## Goals / Non-Goals

Provide exactly two local exceptions without granting management authority. No document API, proxy trust, credential format, OAuth callback or provider protocol changes.

## Decisions

- `POST /api/home/session` with `purpose: "oauth"` may create an OAuth-only session after the existing exact Host/Origin checks and admin socket-peer/forwarding validation. Ordinary session requests remain read-only unless host proof is valid. This avoids making all loopback sessions management sessions.
- HomeAccount stores OAuth permission separately from management. Login/logout accept either permission with valid session-bound CSRF; cancel still requires management. Rotation retains the initiating session's scope; logout removes all authority. HTTP independently requires local eligibility for login/logout and host proof for all other operations. Privileged status still requires proof plus management session.
- The Homepage shows login/logout using server eligibility, obtains OAuth CSRF on explicit action when needed, and navigates the current browser to a validated `https://auth.openai.com` authorization URL. Management unlock remains available for account selection/cancel. The fallback link stays available if navigation is interrupted.
- Keep ChatAuth unchanged. Exercise its actual PKCE/state/nonce generation through HTTP with injected discovery and no external network or browser launch.

## Risks / Trade-offs

- Local same-origin code can now start OAuth or sign out with its own scoped session: this is the approved exception. Cancel, account identities and other management operations retain proof checks.
- Credential changes can stale a tab's CSRF: existing failure handling avoids automatic mutation replay; a subsequent explicit action can obtain fresh OAuth CSRF.
- Navigation leaves Homepage: tests intercept the OpenAI destination and verify return/history without sending real credentials.

## Migration Plan

No persistent migration. Normal reader bundle delivery after review deploys the change; reverting sources restores the gate. This task does not install/restart live services, commit or push.
