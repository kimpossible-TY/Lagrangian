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
WV03I SHALL show a preview before explicit full-page same-origin `/d/<id>/#<anchor>` navigation. Cross-origin HTTP(S) targets SHALL open externally without session return history. Shared `CrossProjectReturnStack` SHALL retain at most 32 serializable origins in tab sessionStorage with one-shot restoration. It SHALL preserve in-document fragment ReferenceReturn ownership and SHALL NOT use SPA pushState swapping or a competing popstate handler.

#### Scenario: Persist and deliver web return policy
- **WHEN** WV03I is implemented
- **THEN** the stack uses sessionStorage key `lagrangian:cross-project-return:v1` and one-shot pending restore uses `lagrangian:cross-project-pending:v1`
- **AND** both `reader-common/navigation/cross-project-return.js` and `features/navigation/cross-project-preview.js` are explicitly registered in `web/assets.json`

#### Scenario: Preview, jump and return
- **WHEN** a user first activates a uniquely resolved reference
- **THEN** a preview appears and the original document and location remain current
- **WHEN** the user explicitly jumps and later chooses cross-project Back
- **THEN** full-page navigation opens each destination and readiness-bound one-shot restoration recovers the saved origin location
- **AND** Back writes its one-shot pending entry before popping the stack and navigating
- **AND** failed or stale restoration retains that pending entry without consuming newer transitions

#### Scenario: Reload or explicitly open from Homepage
- **WHEN** the same tab reloads a document
- **THEN** bounded return history survives through sessionStorage
- **WHEN** the user explicitly opens a document from Homepage
- **THEN** cross-project history and pending restore reset
- **AND** ordinary in-document fragment navigation remains owned by ReferenceReturn

#### Scenario: Persist exact validated origin and consume once
- **WHEN** a user jumps to a unique same-origin mounted viewer target
- **THEN** stack JSON is `{version:1,entries:[{path,documentTitle,sectionId,anchor,scrollOffset}]}` under the stack key, oldest first, with at most 32 entries
- **AND** path is a canonical origin-relative path beginning with exactly one slash, the adapter further requires a `/d/<id>/` pathname, sectionId is nonempty, anchor is string or null and scrollOffset is finite
- **WHEN** cross-project Back is activated
- **THEN** pending JSON is `{version:1,transitionId,entry}` with a fresh UUID, written before stack pop and full-page navigation to the exact saved path/query/hash
- **WHEN** the origin's matching document/revision/service manifest and saved ready section are mounted with article not busy
- **THEN** the saved section takes precedence over fragment and other position hints and finite section-relative scrollOffset geometry is restored within one CSS pixel, including after semantic holding and focus
- **AND** only successful restoration removes the matching exact-path/transition pending record, once; corrupt records recover empty and failed storage operations do not claim successful persistence or consumption

#### Scenario: Match links without changing ordinary navigation
- **WHEN** an unmodified primary click activates an explicit project/label link
- **THEN** project/label metadata takes precedence over href/text and opens a named nonmodal dialog with plain-text title, reference text and canonical snippet
- **WHEN** capability is enabled and an absolute safe HTTP(S) link has positive page fragment and is not a same-origin mounted viewer route
- **THEN** href/text catalog resolution may open the preview; unresolved results or request failures resume the original external action without recording return state
- **AND** ordinary fragments, relative and non-page links, downloads and modified clicks retain their existing behavior

#### Scenario: Ambiguous, unavailable or external target
- **WHEN** a preview has ambiguous/unresolved identity or no usable same-origin mounted target URL
- **THEN** the jump button is disabled with a clear explanation, and a safe PDF or unique cross-origin viewer target is offered externally when available
- **AND** no candidate is guessed and no external action records a session return entry

#### Scenario: Cancel or dispose preview work
- **WHEN** another request, Escape, outside click, close, document/service/revision change or disposal invalidates a preview
- **THEN** requests are aborted and generation/identity guards suppress stale success and failure effects
- **AND** disposal removes listeners, hides Back, and restores focus to a connected originating link; outside controls retain their focus

#### Scenario: Configure read-only peer matching
- **WHEN** the source previews a project key from its configured Project.packages catalog
- **THEN** only mounted ReaderState peers from the configured profiles and loaded inventory may supply target routes
- **AND** exact nonempty projectRefKey takes precedence over exact ID and normalized key/title fallback among unconfigured profiles, with duplicate matches rejected at each tier
- **AND** standalone or unmounted targets retain metadata-only preview without starting services; route IDs remain distinct from documentID, service and revision
