# Design

## Context
The active unify-homepage-reader composition serves `/`, `/d/<id>/` and old HTML
redirect ports. Native preview parent profiles come from ReaderManager's native
manager `--profiles`; they include stable IDs and data-plane ports. Native engine
HTTP and WebSocket share that port. Engine process lifecycle remains native.

## Goals / Non-Goals
Expose one browser entry origin without moving compilation or claiming one engine
process. Keep all old preview listeners. No local Rust builds, live jobs/data,
OAuth/TLS/Tailnet activation, arbitrary upstreams, control-plane proxy or remote
editor-host registration. HTTP supports GET/HEAD; preview interaction remains WS.

## Decisions

### Registered routing and composition
A PreviewProxy owner is created from the startup parent profile snapshot. Validate
IDs, unique ports, numeric loopback destinations, maximum inventory and shared-port
conflicts before account/state construction. Never use publicURL, request Host,
query or redirect targets to select an upstream. `/p/<id>` gets a canonical slash
redirect; suffix path and query go unchanged to the fixed engine. The Reader's
existing Host guard applies first. Unknown/encoded IDs and traversal fail closed.
Proxy objects are shared by admin and optional HTTPS ingress and closed by runtime
shutdown. No engine start/stop command is added to proxy request paths.

Homepage paged variants use the parent ID `/p/<id>/`, even without HTML children.
Inventory receives the shared ingress origins explicitly; existing standalone home
fixtures retain their legacy projection. `/d/<id>/paged/` aliases the corresponding
registered parent preview in managed mode; legacy standalone handler tests keep
their existing configured redirect. HTML readiness never proves preview readiness.

### Origin and credential boundary
Check exact Host and exact Origin (when present) against the current Reader ingress;
require exactly one Origin for WS. Translate a validated request's Origin to the
fixed loopback engine origin so the existing engine Origin check still executes.
Do not trust forwarded headers. Filter request headers through an explicit data-
plane allowlist; never forward cookies, Authorization, Reader proof/CSRF, forwarding
headers or arbitrary Host. Drop Set-Cookie and upstream CORS/hop-by-hop headers.
Reject `/_editor/` host registration, admin and account namespaces below `/p/`.
Viewer `/editor/<channel>` sockets retain mandatory Origin and existing engine
validation. Public/proxy ingress cannot gain the home admin capability.

### HTTP and WebSocket transport
Use the standard library only. Each request opens a fresh bounded-timeout loopback
connection. No redirects are followed. Scope root/local upstream Location values;
reject redirects to other origins. Stream ordinary assets/PDF bytes; bound and
rewrite uncompressed HTML/CSS and recalculate Content-Length, dropping stale
validators for transformed content. Preserve Range and conditional requests on
untransformed resources. Reject ambiguous request framing and unsupported methods.

WS uses a raw handshake connection without a second buffered reader, validates
101/Upgrade/Connection/Sec-WebSocket-Accept before publishing 101, and preserves
initial bytes arriving alongside headers. A nonblocking select relay transports
frames unchanged, with bounded buffers and a connection limit. Each EOF propagates
a write half-close only after that direction drains. Owner close shuts down both ends. Requests after engine restart resolve
the same port afresh. Report unavailable upstreams as sanitized 503/502 responses.

### Existing client and absolute paths
Source inspection: `crates/tinymist/src/tool/preview.rs` calls frontend_html with
`"/"`; `crates/typst-preview/src/lib.rs` replaces the WS placeholder with that
value. `tools/typst-preview-frontend/src/features/appearance/document-theme.ts`
resets pathname to `/_theme/<theme>`. Vite's viteSingleFile plugin embeds the
current JS/CSS/WASM client into engine HTML. Proxied HTML permits `data:` only
in `connect-src` for the embedded WASM fetch.

For existing embedded releases, inject a small external classic script before
client scripts, served only inside the registered preview prefix. It adapts the
WebSocket constructor's same-origin or exact registered-loopback URLs to this
prefix, preserving query, theme and viewer suffixes. Other socket origins fail
closed. Rebase root-relative HTML attributes and CSS url/import references; keep
relative resources under a scoped base. Do not rewrite arbitrary executable JS
or add global `/assets`/`/_theme` catch-all routes.

No Rust source edit is required for the current single-file frontend. A future
client with root ES-module imports, new resource schemes, CSP hashes, or another
hardcoded transport requires a prefix-aware frontend/engine release rather than
unbounded string rewriting. Verification and the final report include a concrete
frontend cleanup handoff diff and remote build/test plan; no Rust file is edited.

### Migration and rollback
This is additive routing. Do not redirect or close original data-plane ports;
WebSocket redirects cannot replace direct clients. Keep native engine launchd
jobs, public preview URLs and allowed origins for direct readers. Existing shared
Reader config (default admin 8769) supplies the host. Operator activation is the
normal successful-main pipeline; no activation occurs in development. Restart
Reader when registered profiles change. Rollback restores the prior Reader
release; preview engines/direct URLs need no migration. Remove new Homepage links
with that release; existing saved `/p/` URLs then become unavailable.

## Risks / Trade-offs
- Plain loopback upstream transport retains the existing same-user local trust
  model; it does not authenticate another process reusing a configured port.
- Same-origin paths are not isolation against hostile trusted frontend code;
  retain capability checks on every account mutation and private status read.
- Idle WS sockets occupy bounded per-connection threads; backpressure and explicit
  shutdown prevent unbounded buffering or shutdown hangs.
- Fake transport and browser fixtures do not prove real engine rendering, native
  editor integration, physical devices or production HTTPS deployment.
