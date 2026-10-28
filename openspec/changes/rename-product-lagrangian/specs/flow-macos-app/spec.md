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
- **AND** the migration itself does not change service state
