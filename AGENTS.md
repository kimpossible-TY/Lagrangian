# Lagrangian contributor entrypoint

This repository maintains the native Flow app, tinymist engine, Typst readers and editor integrations. Preserve upstream crate/protocol identifiers and license notices.

## Before editing

1. Read [the development guide](docs/dev-guide.md), then the nearest scoped `AGENTS.md` and affected implementation/tests.
2. Identify the existing feature owner. For reader, compiler or app ownership, consult [the architecture source map](docs/tinymist/dev/reader-architecture.typ).
3. Check `openspec/config.yaml`, relevant accepted specs in `openspec/specs/` and matching active changes in `openspec/changes/` before changing behavior or responsibility boundaries.

## Design essentials

Follow the development guide's design principles: encapsulate responsibility and state, prefer composition, preserve substitutable contracts, keep interfaces focused, and inject concrete operations into policy. Use idiomatic traits, protocols, functions or classes for the language.

Keep identical policy and invariants with one owner. Reuse existing implementations; introduce abstractions for actual shared behavior or current extension needs. Minimize unnecessary state, branches and indirection while retaining clarity and testability.

## Working rules

- Continue on the current branch; create a branch only when explicitly requested.
- Follow [remote Rust builds](docs/dev-guide.md#remote-rust-builds) for Rust compilation, checks, tests and Clippy. Use a Cloud environment verified against the private `kimpossible-TY/Lagrangian` checkout; local Rust compilation requires an explicit instruction to build locally for that run.
- Preserve unrelated user changes. Keep edits scoped and avoid dependency pins, version metadata and release files unless required.
- Edit canonical sources. Regenerate files marked as generated, including Markdown via `node scripts/link-docs.mjs` and `tinymist.lock` artifacts via their owning generator.
- Use OpenSpec for new features, observable behavior/contract changes and refactors that move responsibility across boundaries. Small local fixes and documentation-only edits may skip a new change when existing contracts suffice. Continue a matching active change and keep its proposal, design, tasks and deltas aligned; archives are prior art.
- When moving files, update consumers, build inputs, static allow-lists and packaging inputs; regenerate new release artifacts and verify installed-layout delivery. Existing immutable releases remain immutable.
- Run the smallest meaningful checks listed by the development guide and scoped instructions; widen for affected consumers. Keep changed code warning-free and review snapshot diffs before accepting them.
- Summarize behavior, verification and any unverified coverage. Development tests/builds use isolated data and must not install or restart the user's services.
- Use Conventional Commits per work item. PR content lists modified features and issue operations; omit execution logs. Record intentionally imported upstream commits.

## Maintaining instructions

The development guide's Typst source owns shared design and validation policy. Scoped `AGENTS.md` files contain local reading links, ownership, contracts and verification only. Add a scoped file when a real responsibility boundary needs distinct guidance; keep general rules in one place.
