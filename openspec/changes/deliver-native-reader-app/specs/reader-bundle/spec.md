## MODIFIED Requirements

### Requirement: Publish the reader bundle on hit and miss
`.github/workflows/flow-engine.yml` SHALL upload `reader-bundle-<headSha>` and `flow-reader-bundle` for the run commit on an engine cache hit and on an engine cache miss. `scripts/engine-input-hash.py` SHALL NOT gain reader inputs. The `flow-engine-darwin-arm64` artifact name and extracted engine/app layout SHALL stay unchanged; its current app/application release SHALL be rebuilt even when engine source provenance is older.

#### Scenario: Web-only push
- **WHEN** a push changes `tools/flow-reader/web` and no engine input
- **THEN** the job reuses the retained engine executable/checksum/build provenance without running Cargo, and rebuilds current runtime/backend/reader and Swift app in a current-H checksum/run-bound permission-preserving tar envelope with stable extracted layout
- **AND** uploads a new `reader-bundle-<headSha>` whose `headSha` is that push

#### Scenario: Engine cache miss
- **WHEN** no retained artifact matches the engine-input hash
- **THEN** the job builds the engine and uploads `flow-engine-darwin-arm64`
- **AND** uploads `reader-bundle-<headSha>` and `flow-reader-bundle` for the same commit


### Requirement: Take the engine and the reader from one run
`fetch-engine --run-id` and `scripts/fetch-reader-bundle.py --run-id` SHALL accept the same numeric run id. The development guide SHALL show that one id as the way to stage both artifacts from one flow-engine run.

#### Scenario: Shared run id
- **WHEN** a caller passes one run id to both commands
- **THEN** both commands select that run
- **AND** the reader manifest `headSha` is that run's head SHA

#### Scenario: Existing updater consumes current payload
- **WHEN** build --engine follows both fetches with the same run R
- **THEN** the consumer reauthenticates the exact R/H artifact and reader through the existing manifest/archive owner
- **AND** old engine source provenance does not permit an old app, reader or payload
- **AND** a mismatch fails before installation without selecting latest again

#### Scenario: Reader and native archive transport owners
- **WHEN** reader or native artifact archives are materialized
- **THEN** the shared bounded archive owner authenticates raw bytes and validates member/path/type/mode/link/size limits before publication
- **AND** native tar metadata does not replace the reader manifest's same-R head/checksum validation
