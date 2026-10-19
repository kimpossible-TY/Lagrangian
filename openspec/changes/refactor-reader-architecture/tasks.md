## 1. Establish change
- [x] Inspect current source/remote state and preserve unrelated local work.
- [x] Create isolated worktree and refactor/reader-architecture branch.
- [x] Record architecture and behavior-preservation requirements.

## 2. Shared reader features
- [x] Extract shared feature policy/state and remove cross-reader internal imports.
- [x] Organize paged and HTML adapters, feature code and rendering assets by responsibility.
- [x] Preserve feature contracts and validate shared assets in installed layout.

## 3. HTML Reader service
- [x] Move implementation into responsibility-oriented flow_reader packages, preserve CLI entrypoints.
- [x] Unify isolated/incremental content normalization, audit and diagnostic policy.
- [x] Separate HTTP delivery from mutable document/service state and update tests/imports.

## 4. Engine and native app
- [x] Split project compiler implementation and tests while preserving crate APIs and lifecycle semantics.
- [x] Split native app models, storage, lifecycle, launch, CLI and UI responsibilities; update packaging/tests.

## 5. Guidance and validation
- [x] Update root/scoped AGENTS and canonical architecture/development documentation.
- [x] Run reader, frontend, Rust, Swift and packaging checks appropriate to all affected areas.
- [x] Independently review final patch and resolve findings.
- [x] Commit/push branch, merge verified branch into main and verify remote state while preserving unrelated work.
