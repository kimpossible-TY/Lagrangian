## ADDED Requirements

### Requirement: Shared cross-project backend
The single `flow_reader` backend SHALL own the web cross-project preview adapter in `flow_reader/services/cross_project_refs.py`. Web adapters SHALL use it; native clients SHALL retain their Swift owner until an explicit later migration. Swift SHALL remain the matching/snippet semantic owner; Python SHALL conform through the shared JSON fixture.

#### Scenario: Request a preview
- **WHEN** a web adapter requests a uniquely resolved reference with an accepted target document
- **THEN** the backend returns a bounded preview derived from the canonical accepted document
- **AND** it loads bounded schema-1 `projects.json` catalogs and extracts snippets through canonical `import_accepted_document`
- **AND** previewing does not navigate or mutate source

#### Scenario: Verify cross-language conformance
- **WHEN** Python and Swift matching/snippet tests run
- **THEN** both read `tests/fixtures/cross-project-resolution.json` and assert the same expected targets and snippets
- **AND** native navigation and consent retain their existing Swift contracts

#### Scenario: Unavailable or ambiguous target
- **WHEN** catalog loading, resolution or accepted-document extraction fails or the target is ambiguous
- **THEN** the backend does not guess a target or grant source-write authority

### Requirement: Preview API capability
A bounded `GET /api/cross-project/preview` SHALL expose previews, and `/api/state` SHALL advertise the capability only when available.

#### Scenario: Discover preview support
- **WHEN** a client reads the state
- **THEN** preview capability is advertised only when available

### Requirement: Safe static delivery without document state
`handler_for(None)` SHALL safely serve allowlisted static assets.

#### Scenario: Serve assets without a document state
- **WHEN** `handler_for(None)` serves a static asset
- **THEN** allowlisted assets are delivered safely without accessing absent document state and arbitrary paths remain unavailable

### Requirement: Shared cross-project return policy
`tools/reader-common/navigation/cross-project-return.js` SHALL own bounded cross-project return history and commit/restore policy independent of concrete reader geometry and transport. Adapters SHALL inject their own operations; failed or cancelled navigation SHALL preserve the current location and retained history.

#### Scenario: Commit and restore
- **WHEN** a cross-project jump commits
- **THEN** the origin is retained in bounded history
- **WHEN** Back successfully restores it
- **THEN** that entry is consumed; a failed restoration leaves it retained

### Requirement: Preserve internal compatibility identifiers
User-facing naming SHALL NOT rename `tools/flow-reader`, `flow_reader`, `data-flow-*`, `flow-reader-bundle`, LaunchAgent IDs, CLI flags, API routes or terminal and Neovim Lua statuslines.

#### Scenario: Existing integration uses an internal identifier
- **WHEN** an existing client, package, launcher or terminal integration uses a supported identifier
- **THEN** it remains compatible after the branding change
