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
