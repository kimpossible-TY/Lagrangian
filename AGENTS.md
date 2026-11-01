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

- Branching: use a branch + PR + review for Rust/engine code, changes to the Mac's live state (launchd, app, data migrations) and hard-to-revert work; small reversible changes (docs, config, tests, small scripts/workflows) may go directly to `main`. Otherwise continue on the current branch.
- Follow [remote Rust builds](docs/dev-guide.md#remote-rust-builds) for Rust compilation, checks, tests and Clippy. Use a Cloud environment verified against the private `kimpossible-TY/Lagrangian` checkout; local Rust compilation requires an explicit instruction to build locally for that run.
- Preserve unrelated user changes. Keep edits scoped and avoid dependency pins, version metadata and release files unless required.
- Edit canonical sources. Regenerate files marked as generated, including Markdown via `node scripts/link-docs.mjs` and `tinymist.lock` artifacts via their owning generator.
- Use OpenSpec for new features, observable behavior/contract changes and refactors that move responsibility across boundaries. Small local fixes and documentation-only edits may skip a new change when existing contracts suffice. Continue a matching active change and keep its proposal, design, tasks and deltas aligned; archives are prior art.
- When moving files, update consumers, build inputs, static allow-lists and packaging inputs; regenerate new release artifacts and verify installed-layout delivery. Existing immutable releases remain immutable.
- Run the smallest meaningful checks listed by the development guide and scoped instructions; widen for affected consumers. Keep changed code warning-free and review snapshot diffs before accepting them.
- Summarize behavior, verification and any unverified coverage. Development tests/builds use isolated data and must not install or restart the user's services.
- Use Conventional Commits per work item. PR content lists modified features and issue operations; omit execution logs. Record intentionally imported upstream commits.

## CI/CD (how changes reach the Mac)

Never compile the engine locally to "check" or "deploy" a change; the pipeline builds it.

1. A push or merge to `main` triggers `.github/workflows/flow-engine.yml` on a macOS runner (`docs/**`, `openspec/**` and `*.md` are ignored). Newer pushes cancel older in-progress runs.
2. The workflow hashes the engine inputs via `scripts/engine-input-hash.py`. That script does not hash the reader. On a hit it republishes the cached `flow-engine-darwin-arm64` artifact in about 20 s; on a miss it runs a full cached Rust build (about 13 min). Both paths also upload `reader-bundle-<headSha>` and the stable name `flow-reader-bundle`: the tracked `tools/flow-reader` tree (`web/`, `install.py`, `manage.py`), `tools/reader-common`, the verifier, and `reader-bundle.json` (`headSha`, per-file SHA-256, `bundleChecksum`). A web-only reader change stays an engine cache hit and still publishes a new reader bundle.
3. On the MacBook, launchd job `dev.lagrangian.engine-autoupdate` (every 15 min) picks the newest successful run on `main`, then fetches, packages and installs `Lagrangian.app`, restarts the background app and refreshes the reader engine. It writes per-stage status to `~/Library/Application Support/Lagrangian/pipeline-status.json` (shown in Tail_dashboard) and logs to `~/Library/Logs/lagrangian-engine-autoupdate.log`. Reader web updates come from the bundle, not from the unsynced checkout. `python3 scripts/fetch-reader-bundle.py --branch main` (or `--run-id` / `--head-sha`) verifies `headSha` and every checksum, unpacks a staging directory, and prints that path. It exits non-zero on mismatch and does not modify the installed reader. The updater then runs `tools/flow-reader/install.py` from that directory with the fetched `--engine`.
4. Agents must not install, restart or replace the user's app, reader or launchd jobs by hand; to verify a change, push it (or open a PR for a cloud build) and watch the run. Engine/Rust verification before merge follows [remote Rust builds](docs/dev-guide.md#remote-rust-builds).

## Maintaining instructions

The development guide's Typst source owns shared design and validation policy. Scoped `AGENTS.md` files contain local reading links, ownership, contracts and verification only. Add a scoped file when a real responsibility boundary needs distinct guidance; keep general rules in one place.
