## ADDED Requirements

### Requirement: Product identity
The maintained native app SHALL use Lagrangian for its app name, bundle identifier, executable, and default install location.

#### Scenario: New app bundle uses the Lagrangian identity
- **WHEN** the app is packaged
- **THEN** its bundle name, identifier, and executable use the Lagrangian identity

### Requirement: Legacy data migration
On first launch without the corresponding `FLOW_DATA_DIR` or `FLOW_LOG_DIR` override, the app SHALL move the legacy directory to its Lagrangian path and leave a compatibility symlink at the legacy path. Migration SHALL be idempotent and refuse source/destination collisions without overwriting either directory.

#### Scenario: First launch migrates existing user data
- **WHEN** Lagrangian starts and only a legacy tinymist-flow support or log directory exists
- **THEN** its contents are preserved at the Lagrangian path
- **AND** the legacy path resolves to the migrated directory
- **AND** repeated launches do not move or duplicate data

#### Scenario: Explicit data directory remains authoritative
- **WHEN** the user supplies `FLOW_DATA_DIR` or `FLOW_LOG_DIR`
- **THEN** migration does not move the corresponding default directory
- **AND** the existing environment-variable contract is preserved

#### Scenario: Both legacy and new directories exist
- **WHEN** migration finds independent source and destination directories
- **THEN** startup reports both paths and fails safely
- **AND** neither directory is overwritten, merged, or deleted

### Requirement: Existing service and engine contracts
The rename SHALL preserve Tinymist crate/protocol identifiers, Flow CLI flags and environment variables, profile settings schema, existing project IDs/ports/URLs, LaunchAgent labels, and reader/browser storage identities. The migration SHALL NOT stop, launch, bootstrap or restart user services.

#### Scenario: Existing managed services remain available during migration
- **WHEN** legacy paths are migrated while services still refer to absolute legacy paths
- **THEN** those paths resolve through the compatibility symlinks
- **AND** `ReaderManager.owns_agent` accepts a LaunchAgent whose launcher path resolves through the compatibility symlink to the same `flow-reader` executable while rejecting unrelated reader binaries
- **AND** the migration itself does not change service state

### Requirement: Tail Hosting preview, reader, and background manager migration
The packaging CLI (`scripts/flow-app.py migrate-tail-hosting` and `restore-tail-hosting`) SHALL use separate per-kind handlers to migrate both `typst-always-preview` and `typst-reader` services as well as an existing background login LaunchAgent from `tinymist-flow.app` to `Lagrangian.app`. It SHALL require in preflight that `Lagrangian --migrate-data` has already migrated the data directory (rather than copying reader data in `flow-app.py`), validate port availability, reader engine/release SHA-256 hashes, and `Tail_hosting` patches before any mutation, and delegate reader installation to `tools/flow-reader/install.py --flow-manager` and login LaunchAgent installation to `Lagrangian --login on` (only when a login plist already existed). Because `install.py` refuses to replace a release while a reader job is running, and the legacy launcher rejects a compatibility-symlink plist, `migrate-tail-hosting` SHALL decide which jobs are running from the reader configuration the way `install.py` does, accept a plist whose `ProgramArguments` tail is `--serve <id>` and whose launcher path resolves to the installed `flow-reader`, stop each such job with `launchctl bootout` and a wait until it is unloaded (without `disable`), and record an undo that bootstraps that plist again. After the file migration succeeds it SHALL restart those readers with `flow-reader --control restart <id>`, and if that restart fails it SHALL print the command and the reader's current state. Dry-run SHALL apply `install.py`'s preconditions: a clean Reader checkout, each reader stopped or planned to be stopped, and each service id equal to `parentID + '-reader'`. Mid-flight file rollback SHALL run every completed undo, collect undo errors, and raise after the full undo list; rollback itself SHALL NOT stop services. `restore-tail-hosting` SHALL restart a reader whose desired state is running by `launchctl bootout`, waiting until the job is unloaded, then `enable` and `bootstrap` of the restored plist, because the restored release's `owns_agent` matches the launcher path by string equality. Both commands SHALL support `--dry-run` and a full round-trip restore.

#### Scenario: Unmigrated legacy data directory fails preflight with `--migrate-data` instruction
- **WHEN** `migrate-tail-hosting` runs while `~/Library/Application Support/tinymist-flow` is still an unmigrated directory or `~/Library/Application Support/Lagrangian` is missing
- **THEN** preflight fails before modifying any files or services and instructs the operator to run `Lagrangian --migrate-data` first

#### Scenario: Dry-run reports planned changes without mutating files
- **WHEN** the operator runs `migrate-tail-hosting --dry-run` or `restore-tail-hosting --dry-run`
- **THEN** the command validates `--migrate-data` state, reader artifacts, patches, port availability, a clean Reader checkout, that each reader is stopped or will be stopped, and that each reader id is `parentID + '-reader'`, and prints planned updates
- **AND** no configuration, LaunchAgent plist, or service state is modified

#### Scenario: Running reader is stopped, installed, and restarted
- **WHEN** `migrate-tail-hosting` runs while a reader launchd job is running
- **THEN** it stops that reader with `launchctl bootout` and a wait until the job is unloaded before `install.py` updates the release
- **AND** the plist launcher path may be the `tinymist-flow` compatibility symlink
- **AND** after the file migration succeeds it restarts that reader with `flow-reader --control restart <id>`
- **AND** if installation fails, the previous reader plist is bootstrapped again

#### Scenario: Reader and background manager migrate and restore cleanly
- **WHEN** `migrate-tail-hosting` runs against a Tail Hosting root containing `typst-always-preview` and `typst-reader` services after `Lagrangian --migrate-data`
- **THEN** reader engines and releases under `~/Library/Application Support/Lagrangian/reader` are verified by SHA-256 in place
- **AND** `tools/flow-reader/install.py --flow-manager` updates the reader release, `reader/config.json`, and `reader/bin/flow-reader`, and `Lagrangian --login on` updates the login LaunchAgent if one already existed
- **AND** `migrate-tail-hosting` prints `flow-reader --control restart <id>` for each migrated reader service
- **AND** `restore-tail-hosting` restores the original preview services, reader services, patched files, and `tinymist-flow.app` background manager, and restarts a reader whose desired state is running with `launchctl bootout`, a wait until the job is unloaded, then `enable` and `bootstrap` of the restored plist

#### Scenario: Port conflict, corrupted reader artifact, or mid-flight failure aborts safely
- **WHEN** a reader backend port is occupied by an unrelated listener, a reader engine/release file fails SHA-256 verification, or a patch fails preflight
- **THEN** `migrate-tail-hosting` fails in preflight before updating `services.json` or LaunchAgent plists
- **AND** if an error occurs mid-flight after file mutations have begun, `migrate-tail-hosting` runs every completed undo even when one undo fails, then raises, without stopping services, and leaves original files restored when the undos succeed
