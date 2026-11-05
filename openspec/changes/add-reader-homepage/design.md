# Design

## Context

See `proposal.md` for motivation and the mandatory dependency gate. PR #11 merged as `fb1baf78e26d7f0594243202d23ad0a34234d1f5`; `git merge-base --is-ancestor` passed after merge `7535d948` in the feature worktree. The 2026-11-02 user instruction authorizes implementation from the supplied visual reference and reuse of the actual HTML Reader logo. Main checkout and live services remain untouched.

### Historical inspected baseline (before PR #11)

The current worktree separates HTTP/static delivery from document publication and managed service lifecycle, as mapped by `docs/tinymist/dev/reader-architecture.typ`.

| Owner or route | Current behavior relevant to the Homepage |
| --- | --- |
| `tools/flow-reader/flow_reader/server/http.py` | Per-document request routing and response transport; not a host document registry or authentication policy owner. |
| `server/assets.py`, `web/assets.json` | Explicit reviewed static routes; `/` aliases `/index.html`, the full document Reader shell. |
| `GET /document.html` | Accepted document content with revision validation; not an alternative full Reader entry. |
| `GET /api/state`, `/health` | Document state; health returns 503 without an accepted revision. This is not host-wide health. |
| `GET /api/manifest`, `/api/sections/*`, `/api/assets/*` | Accepted, revision-bound document delivery. |
| Compiler GET/POST routes; source, highlight, focus, cursor and rendering POSTs | Existing concrete reader operations and source/snapshot guards. |
| `GET /service-worker.js`, `/api/offline`; `server/offline.py` | Document shell and accepted-snapshot offline inventory. |
| `services/manager.py` | `ReaderManager.profiles()` resolves configured HTML readers and parent app profiles, public URLs, and exact managed identities. |

Current POST routing compares a supplied Origin's netloc with the supplied Host and permits absent Origin on older operations. There is no independent configured Host allow-list or management browser session there. That check is insufficient for host account management; its presence must not be described as the proposed security boundary.

Prerequisite evidence was read with `git show origin/feat/reader-paragraph-chat:<path>` at `b0b5ffed346d38a5060b5714166477d9042f35b5`: its proposal, design, spec, `server/http.py`, and `services/chat_auth.py`. Its `POST /api/chat/auth` first checks the chat document snapshot, then supports `status`, `models`, `login`, `cancel`, and `logout`. Remote clients receive sanitized sign-in/plan status and catalog; management requires a loopback socket peer and loopback Origin hostname. A separate ephemeral `127.0.0.1` listener receives OAuth callbacks; the Mac browser opens the authorization URL, with a link fallback. `ChatAuth` owns SIWC PKCE, state/nonce and identity validation, 0600 credential persistence, serialized refresh, and best-effort remote revocation.

### Merged contract reconciliation and local activation

The merged auth API also required a per-start capability delivered through a 0600
host-local file and explicitly entered in the browser. The Homepage retains this
proof on POST session creation, then binds management authority to an opaque
in-memory session and synchronizer CSRF. No proof is returned by HTTP. The merged
ChatAuth, protected credential directory, callback listener, PKCE/state/nonce,
signature helper, cross-process refresh and revocation are reused unchanged.
Document account endpoints now reject all credential mutations and retain their
snapshot guard for observational status/catalog. Its active paragraph-chat spec
is amended in place; it is not yet an accepted capability in openspec/specs.

Local defaults are a dedicated `127.0.0.1:8769` admin origin. `home.py` composes
the host without creating a document Project or compiling. Optional `--proxy-port`
and an exact `--public-origin` create a separate read-only ingress; no public or
wildcard listener is created. The fixture uses `https://home.example:8443` only as
a simulated authority, not an activated address. Existing manager configuration
owns `homepageURL`, propagated to document `--homepage-url`; an unset value gives
configuration guidance. Host assets have their own explicit manifest.

Initial policy is one host-global account and uniform sanitized inventory/status
for all allowed viewers. Actual exposure requires the owner's homogeneous viewer
grants; deployments needing per-document roles must not activate this mode. The
real HTTPS identity, TLS/proxy provisioner and grants remain deployment decisions,
not blockers for independent local implementation. Remote management is deferred.

## Goals / Non-Goals

**Goals:** Introduce a host entry independent of any accepted document, compose existing inventory/status/authentication owners, and define a conservative account boundary for Tailscale access. Preserve existing document URLs, offline behavior, source guards, and conversation state.

**Non-Goals:** A provider framework, replacement OAuth flow, public hosting, per-user ChatGPT accounts, filesystem browsing, document creation, source editing, launch/restart controls, credential import, automatic inference, or changing paged engine protocols. Remote credential mutations are excluded from the initial contract.

## Decisions

### 1. Separate the host origin from document-service origins

The proposed host origin serves Homepage HTML at `/`. Each existing document service retains its own `/` and `/index.html` Reader shell and existing APIs. A document card links directly to its configured HTML URL or parent paged preview URL; it does not link to raw `/document.html`. Document settings replace account-management controls with a link to the configured Homepage origin; document chat remains in place.

The implementation uses dedicated host composition and a host route table, not a global change to the document handler's root alias. Implemented host-only routes are `GET /api/home/documents`, `GET /api/home/status`, `GET /api/home/account`, `GET /api/home/models`, `POST /api/home/session`, and `POST /api/home/account` for explicit `login`/`cancel`/`logout`. Session creation has strict Origin/Host checks and requires the per-start capability to grant management; account mutations additionally require the session and CSRF token. They are implemented in server/home.py. No account API requires a document ID or accepted revision. Homepage static files are registered explicitly rather than discovered from disk.

Host HTTP handlers delegate to narrow inventory/status and account operations. They do not call `paragraph_chat.snapshot()` for host account access, remove that guard from document chat, or acquire credentials themselves. `ChatAuth` remains the single credential/refresh owner; host and document services share its existing protected registration storage and serialization. Host-specific composition stays in the HTML Reader server/services boundary; no speculative cross-reader framework is needed.

Alternative: replace `/` on every reader service and relocate readers to a new path. Rejected because bookmarks, terminal clients, relative APIs, and root-scoped offline workers already rely on those origins. Host composition is implemented with loopback defaults; live reverse-proxy provisioning remains an activation decision below.

### 2. Read configured inventory and bounded status

An overview adapter consumes `ReaderManager.profiles()` and existing parent app profile information, projecting only stable document identity, display name, configured reader variants, and validated navigation URLs. It never exposes filesystem roots, source entry paths, launch arguments, or private registration data. Group HTML/paged variants by the existing parent/document identity; do not merge documents by display name.

Status probes target only configured services with bounded timeouts/concurrency. Report host reachability separately from document accepted-content readiness, compilation, stopped/unavailable service, and unknown/stale observation with its time. One failing service cannot block the inventory. Empty configuration is a normal state; invalid configuration and failed probes have distinct feedback. Reading this view never starts a process, compiles, or invokes a model. No arbitrary URL parameter becomes a probe target or redirect destination.

Alternative: scan workspace files or implement a parallel service manager. Rejected because existing configuration owns discoverability and lifecycle.

### 3. Move presentation, retain Mac-only management

The Homepage owns account controls and sanitized plan/model presentation. At the genuine Mac loopback ingress, an explicit user gesture may start/cancel SIWC login or sign out. Opening the page never starts OAuth, opens a browser, or tests a model. Remote HTTPS visitors receive sign-in state, plan-grant state, catalog availability, and a “Manage on this Mac” notice; mutation requests are rejected server-side even if a client fabricates controls.

This deliberately moves the UI without turning every Tailnet reader into a credential administrator. Network ACLs/grants still restrict who may see documents and sanitized status. A shared Tailnet is not proof of account-management authority. The provider account is host-global across documents and devices; a browser session does not identify an independent ChatGPT account. A remote read-only session cannot become an admin session by presenting a cookie on another ingress.

Keep the prerequisite's separate Mac callback listener and validation. Never accept OAuth callback codes at the host page, relay them through a remote browser, expose tokens, or redirect a remote browser to its own `127.0.0.1` as though that were the Mac. The link fallback remains Mac-only. Optional remote management requires an amended security decision and corresponding spec/tests, not just removal of a loopback check.

### 4. Validate authority, origin, ingress, and intent independently

Configure exact canonical public HTTPS origin(s) and separate permitted loopback authorities/ports from trusted startup configuration. Check Host against that configuration before serving host APIs. Account POST Origin must match the configured ingress scheme, host, and effective port exactly; reject missing, `null`, malformed, user-info, or foreign origins and malformed/duplicate Host values. Do not construct an allow-list, URLs, or OAuth redirects from the request Host. No wildcard origins or permissive CORS are added.

Account administration has a dedicated loopback ingress not targeted by the Tailnet reverse proxy. Eligibility requires a genuine loopback peer, configured loopback Host/Origin, and that local ingress. A proxy connection to localhost is remote for policy purposes. Where ingress provenance cannot be established, fail closed for mutations. Ignore untrusted `Forwarded`, `X-Forwarded-*`, and identity headers. If a proxy is configured, trust only its explicit socket/ingress contract for external scheme/authority; forwarded values alone cannot grant local privilege. No public/wildcard fallback listener is allowed.

Every credential change uses POST with a server-issued synchronizer CSRF token bound to the browser management session, in addition to these checks. GET account/model/status calls are observational and cannot start/cancel login or sign out. Provider refresh remains internal serialized credential maintenance. Session creation itself requires exact same-origin POST validation; a third-party page cannot mint a usable session. SameSite cookies supplement CSRF checks rather than replace them.

### 5. Keep browser sessions separate from provider credentials

After explicit host proof, generate random opaque 256-bit session handles and CSRF secrets; store session authority, ingress, expiry, and CSRF binding only in host memory. The browser receives only opaque UI handles and sanitized data, never access/refresh/ID tokens, PKCE verifiers, registration IDs, or account emails remotely. Keep CSRF tokens in page memory and a request header, not URLs or local/session storage. Account errors/logs redact secrets; request bodies and OAuth query parameters are not access-logged.

For HTTPS, use host-only cookies with `Secure`, `HttpOnly`, `SameSite=Strict`, no `Domain`, and the narrow host API path. Separate the loopback admin session namespace from the remote read-only namespace. Deliberate local HTTP exception: the exact configured loopback admin ingress may issue a host-only `HttpOnly; SameSite=Strict` cookie without `Secure`, scoped to `/api/home/`, after verified local same-origin session creation. This exception is unavailable through the remote proxy or remote HTTP. Cookies are not port-isolated, so local sessions remain bound to configured ingress/port and Origin, with CSRF protection; other localhost services receive no authority from the cookie. Do not claim that a Secure cookie works over plain IP HTTP.

Proposed limits are 15 minutes idle and 8 hours absolute, with shorter pending-login expiry retained from `ChatAuth`. Rotate session and CSRF secrets on successful sign-in/account change. Sign-out invalidates all management sessions and pending login attempts and stops local token use; remote revocation is best-effort with an honest result. Host restart discards all UI sessions, while protected provider credentials retain their existing persistence semantics. Other tabs get an expired-session response and rebootstrap only on an eligible ingress; requests never replay a mutation automatically.

Bound polling to visible page lifetime and dispose requests/listeners on navigation. Reject late responses from an old session/account generation so an old status response cannot repaint signed-in after logout. Interrupted/expired OAuth attempts require explicit retry; page disposal stops observation without silently starting or canceling a provider flow.

Alternative: expose provider credentials or reuse a document service ID as browser authentication. Rejected because neither provides safe host authority or session revocation.

### 6. Report account status without inferring entitlement

Keep account, catalog, and document status separate. `signedIn` means host credentials exist under the auth owner's definition; `planEnabled` reports a granted scope, not paid plan tier, quota, or successful model use. Catalog membership is not entitlement proof. Present unknown/unavailable/reauthentication-required states and bounded retry feedback; retain old observations only with an explicit stale label. Homepage requests never run inference to discover access. Only a separate explicit chat turn can establish live access. Authentication failures and sign-out do not delete conversation history or drafts.

All account, session, CSRF, and OAuth responses use `Cache-Control: no-store`. Exclude those endpoints from Service Worker handlers, cache inventories, and offline fallbacks; do not persist account payloads in browser storage. The host origin initially has no Service Worker. Static Homepage assets can be packaged normally, but a cached shell cannot present account data as current when disconnected. Separate host/document origins preserve current document offline caches and prevent a root document worker from intercepting administration.

### 7. Reuse Reader appearance and activity ownership

`web/reader.css` provides `--paper: #faf9f6`, `--ink: #292824`, `--accent: #35675d`, and `--surface: #fffefa`, with existing dark variants. Reuse these tokens and the approved L branding/favicon, readable status text, focus styles, and safe-area conventions. Extract shared appearance only where the Homepage actually needs it; do not load document rendering merely to obtain colors. Apply the existing theme preference mechanism within each origin; cross-origin preference synchronization is not assumed.

The existing `features/session/status-logo.js` presents activity supplied by the shared activity owner. Reuse appropriate presentation/labels without duplicating its state machine or claiming aggregate document readiness from host reachability. `add-reader-status-logo` has historical B-mark wording; `add-reader-favicon` specifies the approved L mark. Preserve existing assets and reconcile that naming during implementation rather than inventing a new logo. Document cards and account controls must work at mobile widths, with keyboard/touch, visible focus, explicit error text, and reduced motion.

## Risks / Trade-offs

- Shared host account → one Mac sign-out affects all document clients; explain this beside management controls and preserve their drafts/history.
- Reverse proxy appears loopback → separate admin ingress, exact Origin/Host checks, and fail closed when provenance is uncertain.
- Cross-origin document links → no session/provider secrets in navigation; validate configured destinations and keep document transport unchanged.
- Global inventory exposes more document names → sanitize metadata and limit access using the host's Tailnet grants; deployments with differently trusted viewers need an explicit access policy.
- Local HTTP cookie exception → loopback-only ingress and session binding; a hostile local process is outside browser-origin isolation and is not solved by CSRF.
- Dependency evolves before merge → re-read the merged auth/storage/spec contracts; avoid freezing branch internals into a second implementation.

## Migration Plan

The prerequisite merge is verified and its current active spec is reconciled. Implement local routes and packaging independently; resolve actual HTTPS ingress ownership and viewer grants before activation. Introduce host composition and explicit assets, then migrate document account controls to Homepage links while retaining chat/source guards and configured document entry URLs. Do not move credential files or rewrite registrations as part of UI relocation.

Validate new asset allow-lists, packaged/installed layout, and offline exclusions in isolated fixtures. Follow the normal CI bundle delivery process when implementation is separately authorized; this implementation authorizes no install, restart, push, or deployment. Future rollback disables the host entry and restores prior document account presentation without deleting credentials, documents, or chat history. Never rewrite immutable reader releases.

## Open Questions

1. Should a later change allow remote sign-in/cancel/sign-out? If so, which authenticated host-admin identity authorizes it, and how does OAuth complete on the Mac without remote loopback confusion? Initial delivery remains Mac-only; a yes requires revised specs and security review.
2. Which dedicated HTTPS host name/port and local admin port are available, and which existing app/proxy component owns their provisioning and trusted ingress configuration? This gates live activation; configurable local implementation and fake fixtures are complete without altering live services.
3. Are all Homepage viewers allowed to see the same document inventory and sanitized global account status? If not, define viewer roles and per-document visibility before exposing the host; Tailnet membership alone supplies no such application roles.
4. Is one host-global ChatGPT registration sufficient long-term, or are multiple administrators/devices expected? Initial UI preserves the prerequisite's host-owned registration model and reveals saved registration identities only locally.

## Review corrections

Inventory presentation retains document cards and Reader links by stable identity;
status polling updates existing nodes. A removed focused destination moves focus
to the document section. Keyboard navigation does not restart on every poll.

The shared chat_storage boundary canonicalizes the chosen private directory and
rejects Git directory/file ancestors before creation or chmod. Existing explicit
project-root exclusions also compare ancestor file identities so case/Unicode
spellings cannot bypass protection on macOS. Homepage supplies its source/bundle
root independently of inventory availability. External parent aliases remain
supported; leaf symlinks remain rejected. Ignore rules are defense in depth.
