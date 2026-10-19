## ADDED Requirements

### Requirement: Explicit reader feature ownership
Shared user-action policy and state SHALL have one owner independent of renderer geometry and transport. Renderer adapters SHALL preserve their native location formats and validation. New shared modules SHALL NOT import concrete readers or introduce circular dependencies.

#### Scenario: Add a reading action
- **WHEN** an action is supported by paged and HTML readers
- **THEN** matching state and policy live in the shared feature layer and renderer-specific operations are injected
- **AND** source Highlight, Saved for Codex and browser review strikes retain their distinct effects and storage contracts

### Requirement: Responsibility-oriented implementation
The HTML Reader server, project compiler and native app SHALL expose responsibility-oriented internal modules without changing supported entrypoints, public crate APIs or user behavior.

#### Scenario: Compile and serve an existing project
- **WHEN** isolated or incremental compilation succeeds
- **THEN** both use the same content normalization and acceptance policy
- **AND** existing HTTP, source validation, lifecycle and CLI contracts continue working

#### Scenario: Deliver an installed Reader
- **WHEN** an immutable Reader release is packaged
- **THEN** it includes its Python package and all shared frontend assets
- **AND** its asset allow-list rejects arbitrary paths

### Requirement: Enforceable contributor guidance
Repository instructions SHALL describe actual ownership, dependency direction, reuse criteria and validation, including current renderer adapters and packaging boundaries.

#### Scenario: Extend a reader feature
- **WHEN** an agent adds a feature
- **THEN** it checks current specs and existing owners, extends common policy where applicable, implements renderer differences in adapters, and validates affected integrations
