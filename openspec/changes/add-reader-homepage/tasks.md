# Tasks

Implementation authorized 2026-11-02 after PR #11 merged. Completed local work and fake-fixture coverage are recorded below. Live HTTPS/proxy activation and physical-device coverage remain separate; no push, deployment or service restart is authorized. See verification.md for exact evidence.

## 1. Prerequisite and decision gates

- [x] 1.1 Confirm `feat/reader-paragraph-chat` has merged into `main`; record the merged SHA and verify ancestry before touching implementation.
- [x] 1.2 Re-read merged paragraph-chat proposal/spec/auth/HTTP owners and reconcile its loopback-only account-management requirement with Homepage presentation; verify there is one credential owner and add an exact accepted-spec delta if required.
- [ ] 1.3 Activation pending: select actual HTTPS origin/proxy provisioner and viewer grants; configurable local/admin and separate read-only proxy fixtures are implemented. Record host HTTPS origin, loopback admin ingress, proxy/provisioning owner, and configured authority rules in the design; verify remote proxy traffic cannot reach the admin ingress as local authority.
- [x] 1.4 Resolve whether all allowed host visitors share inventory/status visibility and one host-global account; record the access policy or amend specs before implementation if roles are needed.
- [x] 1.5 Confirm initial credential management remains Mac-only and document remote management as deferred; verify no task or API silently permits remote login/cancel/sign-out.

## 2. Host inventory, status, and route ownership

- [x] 2.1 Add dedicated host composition and root/static route registration while preserving document-service roots; verify `/`, `/index.html`, raw `/document.html`, and existing document API compatibility with HTTP fixtures.
- [x] 2.2 Project configured manager/parent profiles into sanitized document cards and validated HTML/paged destinations; test empty/invalid configuration, duplicate names, unsafe URLs, and absence of private paths.
- [x] 2.3 Add bounded configured-service status observations independent of accepted documents; test ready/stopped/unavailable/unknown/stale states and one timed-out probe without blocking the list.
- [x] 2.4 Document host route and inventory ownership in `docs/tinymist/dev/reader-architecture.typ` and regenerate derived Markdown; verify the documented owners match composition and observation starts no services or compilation.

## 3. Account boundary and browser sessions

- [x] 3.1 Add document-independent host account/status/catalog adapters using merged `ChatAuth`; test availability without a document revision and confirm document chat snapshot validation still rejects stale requests.
- [x] 3.2 Enforce independent configured Host, exact Origin, and ingress/peer checks; test malformed/duplicate Host, forged matching pairs, absent/null/foreign Origin, wrong ports, proxy-loopback traffic, and untrusted forwarding headers.
- [x] 3.3 Implement isolated opaque browser sessions with session-bound CSRF and POST-only mutation handling; test missing/mismatched CSRF, state-changing GET rejection, and remote read-only handles denied management authority.
- [x] 3.4 Enforce HTTPS cookie attributes and the isolated genuine-loopback HTTP exception; test host/path scoping, ingress/port binding, and no management session on remote HTTP or a proxy ingress.
- [x] 3.5 Implement 15-minute idle/8-hour absolute expiry, sign-in rotation, logout/restart invalidation, and stale-tab response guards; verify expired/old sessions and late account responses cannot restore authority or signed-in state.
- [x] 3.6 Preserve the existing Mac callback and explicit OAuth gestures; fake-provider tests must reject host-origin callback codes, replayed state, remote login/cancel/sign-out, and verify pending-attempt cancellation on sign-out.
- [x] 3.7 Preserve single-owner credential refresh/revocation and honest sanitized status; fake-provider tests must cover refresh failure, unconfirmed revocation, plan/catalog uncertainty, no inference on page load, and retained drafts/history.
- [x] 3.8 Document the account/ingress/session security contract in canonical development documentation; regenerate derived Markdown and verify documentation matches the negative HTTP/session fixtures.

## 4. Homepage and Reader account entry

- [x] 4.1 Build document/status/account sections using Reader paper/green tokens and existing approved L assets; verify light/dark, empty/error, mobile, keyboard/touch, focus, reduced-motion, and text status with browser fixtures.
- [x] 4.2 Move management controls to the host page and replace document controls with configured Homepage links; browser tests must retain document location, chat history/drafts, reader variants, and normal source actions.
- [x] 4.3 Show sanitized remote status and “Manage on this Mac,” local explicit management feedback, and truthful plan/model uncertainty; test fake-provider login failure, reauthentication, unavailable catalog, and sign-out across tabs.
- [x] 4.4 Bound visible-page polling and dispose requests/listeners on navigation; test hidden/disposed pages and delayed old-session responses without duplicate OAuth or automatic mutation replay.
- [x] 4.5 Add Homepage/account navigation guidance to canonical Typst user documentation; regenerate Markdown and verify examples distinguish host origin, document origin, and Mac-only management.

## 5. Cache isolation and delivered layout

- [x] 5.1 Register Homepage assets explicitly and exclude account/session/CSRF/OAuth endpoints from all offline fallbacks; test no-store responses, no dynamic cache entries, disconnected-shell behavior, and unchanged document offline reading.
- [x] 5.2 Verify browser HTML/JSON/URLs/storage, logs, and conversation fixtures contain no provider secrets or remotely exposed registration identities; use fake credentials and include error/callback paths.
- [x] 5.3 Extend reader packaging/installed-layout fixtures for host assets and entry configuration; verify allow-lists/imports and staged bundle delivery without installing or restarting user services.
- [x] 5.4 Document host configuration, cache isolation, and rollback in canonical Typst sources; regenerate derived Markdown and verify rollback preserves credential registrations and conversation data.

## 6. Integration verification

- [x] 6.1 Run focused Python/Node/browser host-account fixtures plus `yarn test:reader-services`, `yarn lint:readers`, and `yarn test:architecture`; record actual results and unavailable prerequisites using isolated data.
- [ ] 6.2 Physical-device, actual HTTPS/Tailnet and paged protocol coverage remain pending; isolated loopback, proxy authority and direct reader navigation are tested. Verify local and simulated Tailnet HTTPS/proxy ingress end-to-end with fake OAuth/model services, existing HTML/paged navigation, and offline documents; report physical-device coverage separately without live auth, paid inference, Rust builds, or service installation.
- [x] 6.3 Run `openspec validate add-reader-homepage --strict` and `git diff --check`; verify each requirement remains below 500 characters and all artifacts agree with the resolved dependency/security decisions.
