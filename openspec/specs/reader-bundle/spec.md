# reader-bundle Specification

## Purpose
Package and deliver the tracked reader tree as a verified CI artifact paired with engine builds. Its manifest and checksums allow host tooling to fetch, stage, and install reader releases without requiring a local git checkout.

## Requirements

### Requirement: Publish the reader bundle on hit and miss
`.github/workflows/flow-engine.yml` SHALL upload `reader-bundle-<headSha>` and `flow-reader-bundle` for the run commit on an engine cache hit and on an engine cache miss. `scripts/engine-input-hash.py` SHALL NOT gain reader inputs. The `flow-engine-darwin-arm64` artifact name and layout SHALL stay unchanged.

#### Scenario: Web-only push
- **WHEN** a push changes `tools/flow-reader/web` and no engine input
- **THEN** the job republishes the retained `flow-engine-darwin-arm64` bytes without running Cargo
- **AND** uploads a new `reader-bundle-<headSha>` whose `headSha` is that push

#### Scenario: Engine cache miss
- **WHEN** no retained artifact matches the engine-input hash
- **THEN** the job builds the engine and uploads `flow-engine-darwin-arm64`
- **AND** uploads `reader-bundle-<headSha>` and `flow-reader-bundle` for the same commit

### Requirement: Reader bundle contents and manifest
The bundle SHALL contain the tracked `tools/flow-reader` and `tools/reader-common` trees, including `web/`, `install.py`, `manage.py`, and the `web/reader-common` symlink, plus `scripts/reader_bundle.py` and `reader-bundle.json`. The manifest SHALL record `headSha`, the SHA-256 and git mode of each file, and `bundleChecksum`.

#### Scenario: Tracked tree and manifest records
- **WHEN** the reader bundle is packaged for a commit
- **THEN** the bundle contains the tracked `tools/flow-reader` and `tools/reader-common` trees, including `web/`, `install.py`, `manage.py`, and the `web/reader-common` symlink
- **AND** `reader-bundle.json` records `headSha`, the SHA-256 and git mode of each file, and `bundleChecksum`

### Requirement: Fetch a verified staging directory
`scripts/fetch-reader-bundle.py` SHALL accept `--run-id`, `--head-sha`, or `--branch`, download the bundle with `gh`, and require the run head SHA, the manifest `headSha`, `bundleChecksum`, the archive checksum, and every file hash to match. It SHALL then unpack a staging directory and print that absolute path. On any failure it SHALL exit non-zero and SHALL NOT modify an installed reader.

#### Scenario: Checksums match
- **WHEN** the requested run published the reader bundle for its head SHA
- **THEN** stdout is only the absolute staging path
- **AND** that directory contains `tools/flow-reader/install.py` and `reader-bundle.json`

#### Scenario: Checksum or headSha mismatch
- **WHEN** the manifest `headSha`, `bundleChecksum`, archive checksum, or a file hash does not match
- **THEN** the command exits non-zero
- **AND** the installed reader and any previous staging directory are unchanged

### Requirement: Install the staged reader with an external engine
`tools/flow-reader/install.py`, run from a verified staging directory, SHALL install release `headSha` without a git checkout and SHALL accept an externally supplied `--engine`. A source tree without `reader-bundle.json` SHALL still require a clean git commit.

#### Scenario: Bundle install
- **WHEN** `install.py` is run from the staging directory with `--engine`
- **THEN** the installed release id is the manifest `headSha`
- **AND** the packaged trees match the tracked `tools/flow-reader` and `tools/reader-common` files

#### Scenario: Git install
- **WHEN** `install.py` is run from a checkout that has no `reader-bundle.json`
- **THEN** a dirty worktree is refused before the installed reader changes

#### Scenario: Staged install verifies before and after the copy
- **WHEN** `install.py` is executed from the staged bundle
- **THEN** importing the installer does not add `__pycache__` under that bundle
- **AND** the copied `tools/flow-reader` and `tools/reader-common` trees match the manifest hashes

### Requirement: Keep an unrelated staging directory
`scripts/fetch-reader-bundle.py` SHALL replace `--dest` only when that path is missing, empty, or already contains `reader-bundle.json`. Any other existing directory SHALL be left unchanged and the command SHALL exit non-zero.

#### Scenario: Unrelated destination
- **WHEN** `--dest` exists, is not empty, and has no `reader-bundle.json`
- **THEN** the command exits non-zero
- **AND** that directory is unchanged

### Requirement: Take the engine and the reader from one run
`fetch-engine --run-id` and `scripts/fetch-reader-bundle.py --run-id` SHALL accept the same numeric run id. The development guide SHALL show that one id as the way to stage both artifacts from one flow-engine run.

#### Scenario: Shared run id
- **WHEN** a caller passes one run id to both commands
- **THEN** both commands select that run
- **AND** the reader manifest `headSha` is that run's head SHA
