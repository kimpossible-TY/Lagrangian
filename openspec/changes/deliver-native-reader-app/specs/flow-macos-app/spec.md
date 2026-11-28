## MODIFIED Requirements

### Requirement: Fetch a verified engine without compiling Rust
`fetch-engine` SHALL select the latest successful `flow-engine.yml` run for a branch, including a push or manual dispatch, or the run named by `--run-id`. It SHALL NOT invoke Cargo or the Rust compiler. The downloader SHALL support bounded parallel Range downloads and the `gh run download` fallback, retaining tar/envelope repository, R/H and SHA verification.

#### Scenario: Fetch the latest run for a branch
- **WHEN** the latest successful run on a branch was a push or a dispatch of that ref
- **THEN** `fetch-engine --branch` for that branch downloads the run
- **AND** stdout is only the absolute `flow-engine` path

#### Scenario: Missing downloader
- **WHEN** `gh` is not available
- **THEN** the command fails and does not compile Rust

#### Scenario: Parallel artifact transport
- **WHEN** the artifact supports bounded Range requests
- **THEN** parallel download extracts the ZIP and unpack verifies the tar and envelope repository, R/H and SHA digests
- **AND** the token is sent only to api.github.com, never to blob HEAD or Range requests or logs

#### Scenario: Recoverable transport failure
- **WHEN** OSError, ValueError, URLError, BadZipFile, CalledProcessError, JSONDecodeError or KeyError occurs during parallel transport
- **THEN** the downloader cleans the destination, emits one stderr diagnostic redacting the token and URL queries and fragments, and uses `gh run download`

#### Scenario: Programming error
- **WHEN** an exception outside those listed occurs during parallel transport
- **THEN** it propagates without invoking the fallback

#### Scenario: Explicit gh transport
- **WHEN** `FLOW_DOWNLOAD_CONCURRENCY` is 1
- **THEN** the downloader uses `gh run download` directly

#### Scenario: Configure parallelism
- **WHEN** `FLOW_DOWNLOAD_CONCURRENCY` is absent, invalid or outside 1–16
- **THEN** the default or invalid value is 8 and numeric values are clamped to 1–16

### Requirement: Reuse an identical engine artifact
When the engine-input hash matches a retained successful artifact from `main`, or from the current ref when that ref is not `main`, the job SHALL reuse only the engine executable, checksum and build provenance and SHALL NOT run Cargo. Both cache paths SHALL prepare and verify current runtime/backend/reader and compile fresh current Swift/resources. The `flow-engine-darwin-arm64` name and layout SHALL remain stable, while its app and application release SHALL bind the current run head. The hash SHALL be recorded in a separate `flow-engine-input-<hash>` artifact. `fetch-engine` SHALL continue to download `flow-engine-darwin-arm64` and verify `flow-engine`, `flow-engine.sha256`, and `release.json`.

#### Scenario: Cache hit
- **WHEN** a retained successful run already published the current engine-input hash
- **THEN** the job reuses that engine's bytes and rebuilds the current app and application release
- **AND** the engine SHA-256 matches the earlier artifact
- **AND** the job does not run Cargo

#### Scenario: Cache miss
- **WHEN** no retained artifact carries the current engine-input hash
- **THEN** the job builds the engine and uploads a new `flow-engine-darwin-arm64` artifact
- **AND** the miss build caches Cargo with the flow-release Apple Silicon key

### Requirement: Package from a fetched engine
Packaging SHALL accept the path printed by `fetch-engine` through `--engine`, authenticate its exact run context and current portable payload/reader, and compile fresh current Swift/resources without compiling the engine. Current checkout, application/delivery/runtime source and reader head SHALL equal that run head H; retained engine build source E MAY be older. Missing, stale, mixed or tampered inputs and unavailable signing identity SHALL fail before install, preserving valid previous stages. Explicit delivery SHALL retain these checks. Standalone engines SHALL require explicit verified delivery; management-only fixtures SHALL opt in and fail require-delivery. Fetch stdout SHALL remain the engine path and successful build stdout SHALL end with the app path.

#### Scenario: Build the app from a downloaded engine
- **WHEN** `build --engine` receives the path printed by `fetch-engine`
- **THEN** packaging reauthenticates same-run artifacts and copies that executable and verified current portable payload into a fresh current app
- **AND** the command does not run a native engine build

#### Scenario: Old updater with incomplete producer artifact
- **WHEN** the existing fetch-engine, fetch-reader-bundle, build --engine sequence names a run without a current portable payload
- **THEN** build fails nonzero before installation without dependency fallback
- **AND** any valid previous app/cache stage is preserved

#### Scenario: Replayed run context or wrong current source
- **WHEN** the engine-local receipt or artifact differs from the reauthenticated exact run, current source or separate reader
- **THEN** build rejects the candidate before installation


#### Scenario: Source-bound archive survives permission-losing transport
- **WHEN** current app transport passes through upload-artifact v4 permission normalization
- **THEN** the source/R/H-bound tar preserves signed executable/resource modes and internal links
- **AND** build reauthenticates its raw archive binding separately from the fetched external-engine chmod
- **AND** missing or corrupted transport cannot downgrade to a flat app or installed dependency
