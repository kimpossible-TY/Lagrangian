# Project compiler internals

Read the root AGENTS and compiler filesystem/lifecycle OpenSpec contracts.

- `src/compiler.rs` is the public facade. Keep crate API/reexports stable when reorganizing private implementation.
- `compiler/artifact.rs` owns result/snapshot data; `report.rs` owns reporting; `coordinator.rs` owns interrupt/event coordination; `instance.rs` owns project-instance state; `execution.rs` owns compile preparation/execution.
- Keep scheduling tickets and cache eviction in their existing modules. Preserve revision synchronization, handler notification order, ticket identity/lifetime, stale completion rejection and cache ownership.
- Private compiler unit tests live under `compiler/tests/`; share only test support. Do not make production internals public just to move tests.
- Run `RUSTFLAGS=-Dwarnings cargo test -p tinymist-project --locked`, crate clippy and `cargo fmt --check --all` after production changes. Compile the consuming tinymist crate when changing the facade.
