# Preview proxy

## Purpose
Expose registered native Typst previews on the shared Reader origin while
preserving document routing, upstream security and independent preview lifecycle.

## ADDED Requirements

### Requirement: Registered preview routing
The shared Reader SHALL map `/p/<preview-id>/` only to registered parent preview profiles and their fixed 127.0.0.1 data-plane ports. Requests SHALL NOT select an arbitrary host, URL or port. Invalid or unknown IDs SHALL return 404 without an upstream connection.

#### Scenario: Registered preview and unknown identifier
- **WHEN** a visitor requests a configured preview or an unknown identifier
- **THEN** only the registered preview is proxied, with its local path and query preserved
- **AND** traversal and URL-shaped destinations are rejected

### Requirement: Preview transport and path scoping
The Reader SHALL relay HTTP GET/HEAD and WebSocket upgrades under the preview prefix. Root-relative HTML/CSS assets and the current client's root/theme WebSocket URLs SHALL resolve within that prefix. Upstream redirects SHALL stay scoped or be rejected.

#### Scenario: Preview shell and absolute assets
- **WHEN** the engine serves a shell with root-relative asset references and root WebSocket URLs
- **THEN** proxied asset and socket requests use `/p/<preview-id>/` on the shared origin
- **AND** Homepage and HTML routes are not used as asset or socket fallbacks

#### Scenario: Upgrade and exchange frames
- **WHEN** a valid same-origin client upgrades a registered preview socket
- **THEN** the Reader returns the upstream 101 handshake and relays binary/text/control frames bidirectionally without WebSocket redirects

### Requirement: Proxy security boundaries
Preview proxying SHALL require a recognized shared Host and exact Origin when supplied; WebSocket upgrades SHALL require Origin. Account cookies, credentials and capability headers SHALL NOT reach the engine. Editor-host registration SHALL remain unavailable through the proxy; account management SHALL retain its loopback and capability guards.

#### Scenario: Foreign or missing WebSocket Origin
- **WHEN** a caller supplies a foreign/duplicate Origin or upgrades without Origin
- **THEN** the Reader returns 403 before connecting upstream

#### Scenario: Remote read-only ingress
- **WHEN** a remote viewer reads a preview through configured HTTPS ingress
- **THEN** only validated preview transport reaches the fixed upstream with a validated loopback Origin
- **AND** copied account authority cannot invoke admin mutations or register an editor host

### Requirement: Homepage preview entries
Homepage SHALL link each registered preview to the shared `/p/<id>/` entry, including previews without an HTML Reader. Listing and proxy requests SHALL NOT start or restart a preview and SHALL NOT claim paged readiness from HTML state.

#### Scenario: Preview-only profile
- **WHEN** inventory contains a registered native preview without an HTML child
- **THEN** Homepage exposes its same-origin preview entry with honest unknown readiness

### Requirement: Independent preview lifecycle and compatibility
Original preview ports SHALL remain direct engine listeners. Reader shutdown SHALL close its proxy connections without stopping engines. A stopped preview SHALL produce a retryable unavailable response; reconnecting after its restart SHALL use the same registered route and a fresh upstream connection.

#### Scenario: Stop and restart an upstream
- **WHEN** an engine stops and restarts on its registered port
- **THEN** old proxied sockets close and new requests recover without restarting the Reader or selecting another preview

#### Scenario: Stop the Reader
- **WHEN** the shared Reader is stopped
- **THEN** proxy sockets close promptly and direct preview ports remain usable
