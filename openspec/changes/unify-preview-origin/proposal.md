# Proposal

## Why
Homepage and HTML Readers share an origin, but native Typst previews still send
readers to per-document ports. A registered-profile proxy gives previews the
same entry point without migrating engine processes or breaking old sockets.

## What Changes
- Serve registered preview data planes at `/p/<preview-id>/` alongside `/` and `/d/<id>/`.
- Proxy HTTP and WebSocket upgrades to fixed configured loopback ports, preserving local path/query.
- Adapt root-relative assets and existing root/theme WebSocket URLs in proxied responses.
- Link Homepage paged variants to the shared preview route, including preview-only profiles.
- Keep native preview lifecycle and original ports unchanged; add isolated transport/security/restart tests.

## Capabilities

### New Capabilities
- `preview-proxy`: registered preview routing, scoped delivery, transport and lifecycle isolation.

### Modified Capabilities
None. This extends the topology of the active `unify-homepage-reader` change;
its existing account authority and HTML document contracts remain in force.

## Impact
Reader Python HTTP composition, inventory and runtime, scoped compatibility
JavaScript and canonical architecture guidance. No Rust source changes, new
runtime dependencies, live installation, port migration or credential changes.
