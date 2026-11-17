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

#### Scenario: Fixed owner correction supersedes historical bytes
- **WHEN** tracked source-provenance metadata registers an ancestor correction by full revision, exact changed paths and original/corrected digests
- **THEN** delivery verifies the immutable correction inventory and current bytes through the existing source-binding owner
- **AND** historical owner revisions/digests remain separate from effective corrected files
- **AND** dirty/missing sources, nonancestor revisions, mixed digests and unregistered changes fail closed

#### Scenario: Later source is not covered by an older correction
- **WHEN** a later source edit or new path is absent from the registered fixed correction and exact delivery-owned paths
- **THEN** source binding fails until the responsible owner supplies a new fixed revision and exact inventory
- **AND** an added file requires verified original absence rather than an invented original digest
- **AND** binding success alone establishes no app/runtime build, GUI, CI or PM acceptance

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

### Requirement: Existing updater CLI consumes same-run portable delivery
The old fetch/reader/build CLI SHALL consume same-run current portable delivery or fail before install. Build SHALL reauthenticate its bounded engine-local context through existing run/artifact, inventory, reader and signing owners. H SHALL bind checkout/app/delivery/runtime/reader; verified engine source E MAY be older. Invalid inputs SHALL preserve valid previous stages without dependency or implicit ad-hoc fallback.

#### Scenario: Current app on an engine cache hit
- **WHEN** R publishes current H app/payload/reader with a verified engine built at older E
- **THEN** the old sequence compiles current Swift/resources with that payload and passes require-delivery integrity
- **AND** stdout retains engine path, reader path and final app path compatibility

#### Scenario: Invalid delivery or interrupted build
- **WHEN** delivery is absent, modified, stale, mixed, replayed or signing/input verification fails or build is interrupted
- **THEN** the consumer exits nonzero before install and preserves valid previous stages
- **AND** no dependency acquisition or implicit ad-hoc fallback occurs

#### Scenario: Different explicit local signing identity
- **WHEN** a verified artifact is consumed with a different available certificate
- **THEN** only copied candidate images are signed and post-sign runtime/delivery hashes are rebound before the outer seal
- **AND** original artifact checksums and signing provenance remain distinct from local output identities

### Requirement: Permission-preserving current-run native artifact
The producer SHALL archive the exact current-H signed payload with ordinary modes, internal links and hidden files before upload. The consumer SHALL bind R/H, raw archive/inventory digests and the separate authenticated engine-mode normalization. Shared bounded archive, inventory, signing and atomic owners SHALL reject invalid inputs without flat/scratch/installed fallback or loss of a valid stage.

#### Scenario: Upload v4 normalizes envelope modes
- **WHEN** zip transport sets envelope regular files to 644
- **THEN** the inner signed file modes, internal relative links and hidden payload are restored exactly from the verified tar
- **AND** the old fetch/reader/build CLI produces current Swift/resources with require-delivery integrity

#### Scenario: Unsafe or changed archive
- **WHEN** a transport has missing files, wrong R/H, digest replay, duplicate/escaping paths, special types/modes, cyclic links, oversized entries/metadata or after-hash drift
- **THEN** it fails before executing untrusted inputs or publishing the candidate
- **AND** interruption or verification failure preserves the previous valid stage

#### Scenario: Previous engine cache input
- **WHEN** current run H reuses engine source E from an earlier artifact
- **THEN** only authenticated engine bytes/checksum/provenance are reused
- **AND** the current app and tar are produced anew with H, never copied from the retained app


#### Scenario: Sequential completed native source correction
- **WHEN** the fixed8744 source correction relative to fixed09e is registered after338
- **THEN** its exact15 original/corrected Git-object hashes and ancestry are validated without rewriting historical records
- **AND** actual8744 code is rejected with the old338-only inventory, while the clean current assembled source binds through the existing common owner
- **AND** no pending NA15/16 revision, engine provenance, runtime/reader/app or PM receipt is invented
