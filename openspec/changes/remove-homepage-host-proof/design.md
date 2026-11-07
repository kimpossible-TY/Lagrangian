# Design

## Context

See proposal.md. This change's `homepage-account-auth` capability owns account authorization policy. It supersedes the blanket host-proof rule in active `unify-homepage-reader`'s `reader-host` requirement “Local capability authority on a shared origin” and its borrowed-session scenario only for Homepage login without registration selection and logout. The linked reader-host requirement and Security boundary defer those exceptions here; all other management, identity, document and remote restrictions remain. No accepted reader-host spec or archive ordering is required. `server/home.py` owns request eligibility and proof validation; `HomeAccount` owns browser authority/CSRF; `ChatAuth` owns credentials and OAuth. These implementation owners remain unchanged.

## Goals / Non-Goals

Provide exactly two local exceptions without granting management authority. No document API, proxy trust, credential format, OAuth callback or provider protocol changes.

## Decisions

- `POST /api/home/session` with `purpose: "oauth"` may create an OAuth-only session after the existing exact Host/Origin checks and admin socket-peer/forwarding validation. Ordinary session requests remain read-only unless host proof is valid. This avoids making all loopback sessions management sessions.
- HomeAccount stores OAuth permission separately from management. An OAuth session request with a retained management cookie returns a separate OAuth-only CSRF token bound to that session, preserving its management handle and CSRF. This token cannot authorize cancel or registration selection, even with host proof. Login without selection/logout accept either permission; login with a nonempty registration requires current host proof at HTTP and management CSRF in HomeAccount before ChatAuth is called. Rotation retains the token's authorized scope; normal credential mutations invalidate old authority and logout removes all authority. Privileged status requires proof plus management session; unauthorized GET account returns 200 with sanitized public fallback. Invalid Host returns 421; other authorization failures return 403.
- The Homepage shows login/logout using server eligibility, obtains OAuth CSRF on explicit action when needed, and navigates the current browser to a validated `https://auth.openai.com` authorization URL. Management unlock remains available for account selection/cancel. The fallback link stays available if navigation is interrupted.
- ChatAuth.login accepts a per-call opener opt-out. HomeAccount passes `open_browser=False`, making Homepage's current-browser navigation the sole consent navigation owner. ChatAuth's default still invokes the configured system opener for terminal/other callers. Exercise real PKCE/state/nonce generation through HTTP with injected discovery and an opener spy, and verify the default opener contract separately without external network or browser launch.

## Risks / Trade-offs

- Local same-origin code can now start OAuth or sign out with its own scoped session: this is the approved exception. Cancel, account identities and other management operations retain proof checks.
- Credential changes can stale a tab's CSRF: existing failure handling avoids automatic mutation replay; a subsequent explicit action can obtain fresh OAuth CSRF.
- Navigation leaves Homepage: tests intercept the OpenAI destination and verify return/history without sending real credentials.

## Migration Plan

No persistent migration. Normal reader bundle delivery after review deploys the change; reverting sources restores the gate. This task does not install/restart live services, commit or push.
