# Native reader delivery

## Purpose
Deliver the current native reader with verified portable computation and backend dependencies, independently of cached engine compilation.

## ADDED Requirements

### Requirement: Fresh application on engine reuse
The delivery pipeline SHALL package the current application sources, resources, backend and runtime on engine cache hits and misses. Engine reuse SHALL retain only engine bytes and provenance.

#### Scenario: App-only update with cached engine
- **WHEN** Swift, resources, backend or helper changes without an engine input change
- **THEN** the new app and delivery manifests bind the current source and payload
- **AND** engine bytes retain their verified input identity
- **AND** an older cached app is never published as the new app

### Requirement: Portable verified dependencies
Delivery SHALL bind exact supported official dependency distributions, checksums, licenses and signature evidence. All execution dependencies SHALL resolve inside the bundle or immutable verified sidecar, except operating-system libraries. macOS 13 target inspection SHALL be distinguished from execution on macOS 13.

#### Scenario: Relocated offline application
- **WHEN** a complete app is relocated and source, caches, global modules and network are denied
- **THEN** its default runtime and backend entrypoints resolve within the verified payload
- **AND** interpreter, compiler, shared reader and manager dependencies are present

#### Scenario: Unsupported or missing dependency
- **WHEN** a required executable, library, resource or configured managed service is absent or incompatible
- **THEN** verification or launch fails with a bounded diagnostic
- **AND** no external development or network fallback substitutes for it

### Requirement: Signed payload binding
Delivery SHALL sign internal executable and library bytes before computing runtime and delivery manifests and sealing the outer app. Verification SHALL reject payload drift, escaping paths, stale source or helper bindings and mismatched release pairs.

#### Scenario: Failed candidate
- **WHEN** a candidate has missing files, post-sign tamper or stale bindings
- **THEN** staging fails nonzero and retains any previous valid output

### Requirement: Evidence preserves acceptance boundaries
Verification SHALL record actual commands, inputs, exits and skips. Required installed-layout prerequisites or skips SHALL fail acceptance. Local cache fixtures, current-host builds, headless native paint, remote CI, GUI and macOS 13 execution SHALL have separate results.

#### Scenario: Initial production stage
- **WHEN** core or original-page integration has not been rebound to final owner commits
- **THEN** the initial app can pass delivery integrity checks
- **AND** final application acceptance remains explicitly blocked

### Requirement: Existing manager configuration remains usable
A verified app SHALL supply concrete executable operations through ReaderManager without rewriting existing schema-1 config. ReaderManager SHALL retain config, profile, source and lifecycle policy. Shared backend children SHALL authenticate and consume the same bundle bindings. HTTP fields and environment values SHALL NOT establish trusted executable identity.

#### Scenario: Relocated app with legacy external executable paths
- **WHEN** an existing valid config refers to external Python, compiler, Flow and engine paths
- **THEN** the relocated bundled manager uses verified bundled executables and retains identical config bytes
- **AND** profiles, launch plans, attachment validation and shared child compilation use the existing owners

#### Scenario: Invalid binding or configuration
- **WHEN** the app seal, manifest, release pair, required executable or schema is invalid
- **THEN** launch fails closed without external executable fallback or configuration mutation

### Requirement: Integrated sources and external PM acceptance receipt
Delivery SHALL bind integrated owner commits, canonical sources and packaged bytes. Acceptance SHALL require an explicit PM receipt binding the exact source revision, signed app checksum and named gate artifact digests/statuses with zero required skips. Normal launch SHALL require no receipt. Recording a PM decision SHALL NOT authenticate review quality, user permission or untested runtime coverage.

#### Scenario: Pre-GUI candidate without final gate evidence
- **WHEN** owner integration and current-host delivery pass but a complete external PM receipt is absent
- **THEN** integrity can pass and acceptance returns nonzero with the missing receipt diagnostic
- **AND** core/page integration is reported accurately without false pending-source claims

#### Scenario: Replayed or invalid PM evidence
- **WHEN** receipt/artifact bytes, app/source identities, statuses or required skip counts are missing, stale, tampered, failed or skipped
- **THEN** acceptance fails closed independently of normal app operation

#### Scenario: Explicit PM decision is recorded
- **WHEN** source/runtime/requiredtests/code-review/docs/nativeGUI/AX artifacts match the current app/source, digests, passed statuses and zero required skips
- **THEN** the verifier records the external PM decision
- **AND** synthetic test receipts remain mechanism-only evidence and are never actual acceptance

### Requirement: Final source identity and isolated inspection preparation
The final app, runtime, reader and delivery source binding SHALL equal the frozen HEAD. Source changes after a build SHALL require rebuilding. Fixed GUI fixture policies SHALL be reused with an explicitly owned storage root. Inspection setup SHALL remain stopped; smoke SHALL use a separate bounded foreground fixture and private clipboard. Historical isolation failures and readonly updater limitations SHALL remain explicit.

#### Scenario: Frozen final source
- **WHEN** final review preparation builds the app
- **THEN** runtime/source, reader/headSha and delivery/app sourceRevision agree with clean HEAD
- **AND** no test-only or documentation-only later HEAD is mislabeled as that app

#### Scenario: Prepared inspection without app activation
- **WHEN** a new inspection root is set up and a separate smoke is executed
- **THEN** inspection remains running=false and smoke processes/ports are cleaned
- **AND** only named private-board copy and explicit owned source/service fixtures are used
