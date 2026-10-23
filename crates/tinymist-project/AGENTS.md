# Project model and compiler internals

## Read

Read [the architecture source map](../../docs/tinymist/dev/reader-architecture.typ) and the compiler filesystem/lifecycle OpenSpec contracts.

## Ownership

- `src/compiler.rs` is the public facade. `compiler/artifact.rs` owns result/snapshot data; `report.rs` owns reporting; `coordinator.rs` owns interrupt/event coordination; `instance.rs` owns project-instance state; `execution.rs` owns compile preparation/execution.
- Scheduling tickets and cache eviction remain in their existing modules. Private compiler unit tests live under `compiler/tests/`; share only test support.
- `src/source_history.rs` owns saved-source edit policy and UTF-8 ranges. `source_history/store.rs` owns exact project identity, record-path resolution and locked atomic persistence; renderer metadata remains opaque to this owner.

## Contracts

- Preserve crate API/reexports, revision synchronization, handler notification order, ticket identity/lifetime, stale completion rejection and cache ownership.
- Do not make production internals public just to move tests.
- Reload the shared source record inside its file lock before observing or publishing changes. Preserve other renderers' metadata, source sequence and exact source validation across processes; do not add an authoritative in-memory copy.

## Verification

From the repository root, run `RUSTFLAGS=-Dwarnings cargo test -p tinymist-project --locked`, `RUSTFLAGS=-Dwarnings cargo clippy -p tinymist-project --all-targets --locked` and `cargo fmt --check --all` after production changes. Compile the consuming tinymist crate when changing the facade.
