# Design

## Context
See proposal.md. Existing `server/home.py` owns HTTP administration; `ChatAuth`
owns credentials and OAuth. `ReaderManager` resolves authoritative parent/service
profiles. Each existing HTML process has its own ReaderState and relative web
assets. Paged engine processes and protocols are separate existing renderers.

## Goals / Non-Goals
A shared Python Reader process owns Homepage, all configured HTML states and
redirect listeners. Keep compiler/watch and conversation state per document;
share one ChatAuth/ResponsesProvider and Homepage account lease.

Out of scope: live OAuth, TLS, Tailnet activation, live launchd changes, Rust
compilation, rewriting ChatAuth, moving the paged engine/WebSocket protocol into
Python, per-viewer permissions or credential/history schema migration.

## Decisions

### Routing and composition
Use `/d/<reader-id>/`, with the existing stable manager service ID (not title,
port or filesystem path). Exact configured IDs select existing `handler_for`
instances; only the routing adapter strips the prefix. Homepage handler is reused
at `/` and `/api/home/`. Document APIs/assets/worker remain beneath their prefix;
unknown IDs, encoded traversal and prefixed admin paths fail closed. Relative
frontend imports and worker scope already support this layout. Account links
resolve to the root of the current ingress. `/d/<id>/paged/` redirects to the
validated existing `originalURL`; paged content continues using its native
engine origin. Reverse proxying its live protocol would require a separate
engine/protocol change and is not needed to merge the Python Homepage process.

### Security boundary
Paths on one origin are not a security boundary. Keep exact admin Host/Origin,
genuine 127.0.0.1 peer, forwarding-header rejection, management session and CSRF,
and require the per-start capability for every credential mutation and privileged
account status read. Keep proof in Homepage module memory only; never cookies,
URLs, DOM after entry, HTTP responses or local/session storage. Document JS can
read sanitized status but cannot borrow an existing management cookie to gain
credentials or mutation authority. CSP on Homepage disallows embedding; document
assets are allowlisted. Remote proxy ingress always denies mutations, even with
copied capability/session/CSRF. No new TLS or proxy trust assumptions.

### Lifecycle and configuration
`serve.py --managed --data <directory>` composes all resolved profiles and one
shared account. `home.py` becomes a compatibility alias for this same composition.
`serve.py` direct document arguments retain legacy document-only serving until
manager configuration migrates. Config opt-in `shared: {port: 8769, publicURL: "https://..."}`
selects one manager label and launch plan; optional `proxyPort` is read-only and
requires publicURL. Existing configs remain readable for staged migration. The
manager retains per-document compiler/font/output/focus options through its
existing argument builder; presentation attachment uses the prefixed URL and
common PID. Shared shutdown closes document work before the single auth owner.

### Migration and redirects
Old per-document ports become loopback redirect-only listeners in the same
process. Their exact configured public HTTPS Hosts are accepted for existing
reverse proxies. Use 307, preserving path/query and browser fragment inheritance;
validate fixed redirect destinations from configuration, never request Host.
Redirects from legacy ingress lead to the canonical shared public origin when
configured, otherwise loopback. Legacy ingress never serves admin APIs. A shared
port that collides with an old document port is rejected before activation.
Existing root-worker caches may intercept bookmarks offline; on reconnect the
legacy worker endpoint serves a retirement worker that removes only its old
scope caches and unregisters. Offline readers retain data until reconnect.

### launchd / plist impact and rollback
Back up the plist-generating `services/manager.py` in the worktree before editing.
Do not change live jobs. At operator activation: stop existing per-document and
Homepage jobs, save their plists/config/launcher, select shared config, generate
one `io.github.kimpossible-ty.lagrangian.reader.shared` plist via manager, then
start it using the normal owner-checked lifecycle. Every document maps to that
job; no Homepage job is generated. Old ports must be free for redirect listeners.
Point the selected HTTPS proxy at the shared read-only ingress; old proxies may
continue to point at redirect ports. Preserve immutable releases and all data.
Rollback stops the shared job, restores saved config/launcher and old plists,
and starts previous jobs through existing tooling. No data migration is needed;
per-document worker/cache scopes differ but history and drafts keep document IDs.

## Risks / Trade-offs
- One process failure affects all HTML documents: launchd KeepAlive restarts it;
  accepted state and histories remain per document.
- Old ports still need listeners for compatibility: same PID, redirects only.
- Startup resolves a snapshot of manager inventory: config changes require the
  normal shared-job restart; Homepage observations must reflect loaded states.
- Same origin shares browser storage: existing document keys are identity-based;
  worker scopes/cache prefixes include `/d/<id>/`. Capability prevents borrowed
  cookie authority; a compromised Homepage script remains a trusted-code risk.
- Physical devices, real compiler, installed/live service and actual HTTPS/proxy
  provisioning require subsequent operator validation; isolated fake-provider
  tests cover routing and security here.
