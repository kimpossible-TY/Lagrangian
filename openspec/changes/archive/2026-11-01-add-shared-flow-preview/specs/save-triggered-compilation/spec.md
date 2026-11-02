## ADDED Requirements

### Requirement: Save-triggered automatic compilation
Tinymist SHALL support an opt-in compileOnSave setting that defers automatic full compilation after text edits while retaining immediate source synchronization and stale-work invalidation.

#### Scenario: Repeated unsaved edits
- **WHEN** compileOnSave is enabled and a document receives multiple edits without a save
- **THEN** the current source snapshot reflects the latest edit without admitting automatic full compilation for those edits

#### Scenario: Discarded running evaluation
- **WHEN** an edit supersedes an already running compilation
- **THEN** the old evaluation cannot publish its result or release the edit deferral when it completes

#### Scenario: Save or external update
- **WHEN** the user saves, closes a buffer, explicitly compiles, changes entry, or a real filesystem update arrives
- **THEN** current pending work becomes eligible for compilation

#### Scenario: Default and configuration change
- **WHEN** compileOnSave is absent or disabled
- **THEN** existing automatic typing compilation remains enabled
- **AND** changing the setting reloads the project so pending state cannot remain stuck
