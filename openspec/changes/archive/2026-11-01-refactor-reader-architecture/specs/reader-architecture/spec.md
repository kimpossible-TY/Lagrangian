## ADDED Requirements

### Requirement: Explicit reader feature ownership
Shared user-action policy and state SHALL have one owner independent of renderer geometry and transport. Renderer adapters SHALL preserve their native location formats and validation. New shared modules SHALL NOT import concrete readers or introduce circular dependencies.

#### Scenario: Add a reading action
- **WHEN** an action is supported by paged and HTML readers
- **THEN** matching state and policy live in the shared feature layer and renderer-specific operations are injected
- **AND** source Highlight, Saved for Codex and browser review strikes retain their distinct effects and storage contracts

#### Scenario: Schedule browser-local rendering
- **WHEN** paged WASM rendering or HTML mathematical composition receives repeated work requests
- **THEN** both use the shared frame scheduler to coalesce requests and serialize asynchronous rendering
- **AND** adapter-reported selections hold work without completion or repeated polling
- **AND** cancellation and disposal prevent obsolete completion callbacks while renderer-specific document, geometry and source validation remain local
- **AND** completion may enqueue new work without losing or concurrently executing it

#### Scenario: Activate a selection toolbar action
- **WHEN** either reader receives a press, deferred pointer release and click
- **THEN** one shared lifecycle retains the pressed selection for that click even if native selection collapses
- **AND** the reader retains its native selection format, capture/update guards and action effects
- **AND** disposal clears pending release work

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

#### Scenario: Validate an accepted source operation
- **WHEN** source highlighting, source navigation or saved context validates accepted compiler inputs
- **THEN** shared snapshot/fingerprint owners define freshness while callers preserve their existing lock order and stale/error responses
- **AND** changes to revisions, compilation or saved inputs invalidate the operation before publication or source mutation

#### Scenario: Create a native project profile
- **WHEN** the app receives a chosen Typst entry file
- **THEN** ProjectService selects existing-compatible project defaults and persists the new selected profile without starting or stopping services
- **AND** AppKit adopts the returned settings after persistence succeeds
- **AND** LaunchAgent generation and app-ownership detection use the same executable arguments

#### Scenario: Select a native project profile
- **WHEN** the app selects an existing profile
- **THEN** ProjectService validates and persists the selection without changing profiles or controlling services
- **AND** failed creation or selection persistence leaves the UI's prior settings intact

### Requirement: Enforceable contributor guidance
Repository instructions SHALL describe actual ownership, dependency direction, reuse criteria and validation, including current renderer adapters and packaging boundaries.

#### Scenario: Extend a reader feature
- **WHEN** an agent adds a feature
- **THEN** it checks current specs and existing owners, extends common policy where applicable, implements renderer differences in adapters, and validates affected integrations

#### Scenario: Find a design rule
- **WHEN** a contributor reads root or scoped agent instructions
- **THEN** the development guide is the canonical source of design principles
- **AND** scoped instructions identify local contracts and validation without duplicating the general policy

#### Scenario: Validate shared reader changes
- **WHEN** the reader CI gate runs
- **THEN** it executes the same lint and test commands available locally, including dependency boundaries, cycles, both readers and DOM rendering tests
- **AND** vendor/generated code is excluded from first-party lint
- **AND** optional compiler/browser coverage is distinguished from required integration runs, which reject skipped tests
