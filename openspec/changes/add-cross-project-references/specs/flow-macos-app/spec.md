## ADDED Requirements

### Requirement: IDE directory registration
The IDE SHALL support adding a project directory with optional entry and projectRefKey. ProjectService SHALL discover regular .typ files from the root through two nested directory levels, excluding hidden directories. Results SHALL sort root main.typ first, then lexical relative paths. Registration SHALL prefer an explicit entry, otherwise root main.typ or the sole candidate. Ambiguous or missing entries SHALL raise FlowError before persistence or service control.

#### Scenario: Main or sole entry
- **WHEN** the IDE registers a directory with root main.typ or one discovered .typ file
- **THEN** that entry is selected and the new profile retains the chosen root and existing creation defaults
- **AND** settings are saved once without changing existing profiles

#### Scenario: Ambiguous or empty directory
- **WHEN** a directory has multiple candidates without root main.typ, or no .typ files
- **THEN** registration fails with FlowError before persistence
- **AND** an explicit valid entry resolves the multiple-candidate case

### Requirement: Stable cross-project identity
Profile SHALL encode an optional projectRefKey and decode legacy JSON without the field as nil. Non-empty keys SHALL match the entire pattern `^[a-z0-9][a-z0-9-]{0,63}$`. Existing Profile validation rules SHALL remain intact. Local matching SHALL prefer explicit keys over case-insensitive normalized folder/name fallback and SHALL NOT choose among duplicate matches.

#### Scenario: Legacy and explicit identity
- **WHEN** an existing profile is decoded without projectRefKey
- **THEN** it remains valid with a nil reference key
- **WHEN** a project is registered with a non-empty invalid key
- **THEN** validation fails before saving
