## ADDED Requirements

### Requirement: Lagrangian web viewer identity
Lagrangian SHALL be the canonical native macOS product and feature contract. Lagrangian Web Viewer SHALL be its web-optimized projection in `tools/flow-reader/web/`, using the shared `flow_reader` backend and `tools/reader-common` policy. User-facing viewer titles and HTML variant labels SHALL use Lagrangian Web Viewer, the manifest short name SHALL be Lagrangian, and the ready label SHALL be `웹 뷰어 준비됨`.

#### Scenario: Preserve native owners
- **WHEN** WV02C is delivered
- **THEN** `apps/macos/` is unchanged, retaining its existing Swift catalog, session adoption and editor consent owners

#### Scenario: Open the viewer or homepage
- **WHEN** a user opens the viewer or views an HTML document variant on the homepage
- **THEN** the visible viewer identity is Lagrangian Web Viewer and the homepage retains Lagrangian branding
- **AND** a titled document uses its title followed by ` · Lagrangian Web Viewer`

### Requirement: Read-only cross-project preview service
`cross_project_refs.py` SHALL load bounded schema-1 catalogs within the configured package root, preserve Swift resolution semantics, and extract plain-text snippets from mounted accepted documents through canonical `import_accepted_document`. It SHALL NOT guess ambiguous matches or read arbitrary target filesystems.

#### Scenario: Load and match bounded inputs
- **WHEN** a catalog and mounted profile registry are consulted
- **THEN** the catalog is at most 16 MiB with strict schema parsing, real-path containment and no path leaks
- **AND** the read-only registry matches explicit projectRefKey, profile ID, normalized root basename or project title, rejecting duplicate matches
- **AND** snippets are bounded to 600 characters and four blocks

#### Scenario: Preview an accepted mounted target
- **WHEN** a reference resolves uniquely and its mounted target has a matching accepted document
- **THEN** GET `/api/cross-project/preview` or `/d/<id>/api/cross-project/preview` returns HTTP 200 with status, projectKey, projectTitle, label, refText, title, snippet, truncated, targetUrl, anchor and pdfUrl
- **AND** the operation neither compiles nor starts services nor reads arbitrary unmounted filesystems nor mutates state

#### Scenario: Resolve without a usable snippet
- **WHEN** a unique target is unmounted, uncompiled, compiling or cannot be imported or matched
- **THEN** HTTP 200 retains unique catalog metadata and snippet is null
- **AND** targetUrl is a validated mounted route if mounted and otherwise null

#### Scenario: Ambiguous or unresolved identity
- **WHEN** resolution is ambiguous or unresolved, including an unavailable catalog
- **THEN** HTTP 200 contains the explicit status and no guessed snippet or target
- **AND** ambiguous responses contain at most 32 bounded candidate descriptors

#### Scenario: Validate requests and target routes
- **WHEN** preview input is not exactly project plus label or href plus optional text, contains malformed/duplicate/unknown parameters or exceeds 1024 characters per value
- **THEN** the server returns HTTP 400 with a non-sensitive JSON error
- **AND** generated target URLs permit only same-origin `/d/<id>/#<anchor>` or the explicitly configured reader_url-validated origin, rejecting unsafe schemes, traversal and arbitrary hosts

### Requirement: Viewer discovery and static-only delivery
`/api/state` SHALL include additive `viewer: {"name": "Lagrangian Web Viewer", "crossProject": <bool>}` metadata, true when the bounded catalog can be loaded. `handler_for(None)` SHALL construct no native services and SHALL retain allowlisted static serving.

#### Scenario: Discover standalone capability
- **WHEN** a standalone document has a valid catalog and no mounted peers
- **THEN** viewer.crossProject is true and metadata-only previews remain available

#### Scenario: Request APIs without a document
- **WHEN** a static-only handler receives `/api/native-*` or `/api/cross-project/preview`
- **THEN** HTTP 503 is returned without dereferencing absent state
- **AND** allowlisted assets remain available and arbitrary paths remain unavailable

### Requirement: Web cross-project preview and return
WV03C SHALL show a preview before explicit full-page `/d/<id>/#<anchor>` navigation. Shared `CrossProjectReturnStack` SHALL retain at most 32 serializable origins in tab sessionStorage with one-shot restoration. It SHALL preserve in-document fragment ReferenceReturn ownership and SHALL NOT use SPA pushState swapping or a competing popstate handler.

#### Scenario: Persist and deliver web return policy
- **WHEN** WV03C is implemented
- **THEN** the stack uses sessionStorage key `lagrangian:cross-project-return:v1` and one-shot pending restore uses `lagrangian:cross-project-pending:v1`
- **AND** both `reader-common/navigation/cross-project-return.js` and `features/navigation/cross-project-preview.js` are explicitly registered in `web/assets.json`

#### Scenario: Preview, jump and return
- **WHEN** a user first activates a uniquely resolved reference
- **THEN** a preview appears and the original document and location remain current
- **WHEN** the user explicitly jumps and later chooses cross-project Back
- **THEN** full-page navigation opens each destination and readiness-bound one-shot restoration recovers the saved origin location
- **AND** failed or stale restoration preserves recoverable return history without consuming newer entries

#### Scenario: Reload or explicitly open from Homepage
- **WHEN** the same tab reloads a document
- **THEN** bounded return history survives through sessionStorage
- **WHEN** the user explicitly opens a document from Homepage
- **THEN** cross-project history and pending restore reset
- **AND** ordinary in-document fragment navigation remains owned by ReferenceReturn
