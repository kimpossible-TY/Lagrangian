# Project compiler internals

## Read

Read [the architecture source map](../../docs/tinymist/dev/reader-architecture.typ) and the compiler filesystem/lifecycle OpenSpec contracts.

## Ownership

- `src/compiler.rs` is the public facade. `compiler/artifact.rs` owns result/snapshot data; `report.rs` owns reporting; `coordinator.rs` owns interrupt/event coordination; `instance.rs` owns project-instance state; `execution.rs` owns compile preparation/execution.
- Scheduling tickets and cache eviction remain in their existing modules. Private compiler unit tests live under `compiler/tests/`; share only test support.

## Contracts

- Preserve crate API/reexports, revision synchronization, handler notification order, ticket identity/lifetime, stale completion rejection and cache ownership.
- Do not make production internals public just to move tests.

## Verification

From the repository root, run `RUSTFLAGS=-Dwarnings cargo test -p tinymist-project --locked`, `RUSTFLAGS=-Dwarnings cargo clippy -p tinymist-project --all-targets --locked` and `cargo fmt --check --all` after production changes. Compile the consuming tinymist crate when changing the facade.
