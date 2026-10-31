# Design

## Product identity

- Use `Lagrangian` for the macOS app/bundle/executable, default install path, Application Support and log directories, current documentation, root package name and branding asset path.
- Use `io.github.kimpossible-ty.lagrangian` as the bundle identifier.
- Keep the Rust executable and protocol names, Flow feature terminology, CLI flags, `FLOW_*` environment variables, saved profile schema, existing LaunchAgent labels, and reader/browser storage identifiers stable.
- Rename only canonical current product documentation and assets; regenerate generated Markdown from Typst. Leave dated verification/deployment evidence unchanged.

## First-launch migration

- Add a small native migration owner called before constructing the app environment for GUI and normal CLI launches; keep `--version` read-only and migration-free.
- When the corresponding `FLOW_DATA_DIR`/`FLOW_LOG_DIR` override is absent, move the legacy directory to its Lagrangian path on the same volume, then create the old path as an absolute symlink to the new location.
- Make migration idempotent when that compatibility symlink already points to the new directory. If both legacy and destination directories contain independent data, fail with both paths in the error and change neither; never merge or overwrite ambiguously.
- If symlink creation fails after moving, attempt to restore the old directory path before returning the error.
- Migration changes directories only. It does not launch, stop, bootstrap, or restart LaunchAgents; preserving legacy path aliases keeps existing processes and plists usable until normal user-initiated service updates.

## Tail Hosting preview, reader, and background manager migration

- Keep separate per-kind handlers in `scripts/flow-app.py` for `typst-always-preview` and `typst-reader`, reusing the `typst-always-preview` migration path unchanged.
- Run a strict preflight phase before mutating any file:
  - Require that `Lagrangian --migrate-data` has already migrated `~/Library/Application Support/tinymist-flow` to `~/Library/Application Support/Lagrangian` (with the compatibility symlink in place); fail with a clear `--migrate-data` error message if legacy data is still unmigrated or `~/Library/Application Support/Lagrangian` is missing, rather than copying reader data in `flow-app.py`.
  - Check for port conflicts (configured duplicate ports and conflicting live TCP listeners on reader backend ports) and verify SHA-256 hashes of existing reader engines (`engines/<sha256>/flow-engine`) and immutable reader releases (`release.json` and `browserCompiler/manifest.json`) in place under `~/Library/Application Support/Lagrangian/reader`.
  - Validate `Tail_hosting` patches (`tail-hosting.patch`, `tail-hosting-reader.patch`, `tail-hosting-reader-focus.patch`, `tail-hosting-reader-mobile.patch`) in a temporary staging directory, detecting already-applied sections idempotently via reverse-patch check or canonical markers and failing before any mutation if an unapplied patch cannot apply cleanly.
- Preserve single policy ownership:
  - Delegate reader release, `reader/config.json`, and `reader/bin/flow-reader` launcher installation to `tools/flow-reader/install.py --flow-manager` (no duplicated launcher generator or `owns_agent` monkey-patching in `flow-app.py`).
  - Delegate background login LaunchAgent installation to `Lagrangian --login on` only when a login LaunchAgent plist already existed.
  - Update `ReaderManager.owns_agent` in `tools/flow-reader/flow_reader/services/manager.py` to compare `Path(arguments[0]).resolve() == Path(expected[0]).resolve()` when string equality fails so LaunchAgents referencing `~/Library/Application Support/tinymist-flow/reader/bin/flow-reader` across the compatibility symlink remain owned by the migrated reader instance while unrelated reader binaries are rejected.
- Preserve pre-migration files (`services.json`, `tail-hosting`, patched files, `profiles.json`, `reader/config.json`, `reader/config.previous.json`, `reader/bin/flow-reader`, and LaunchAgent plists) in `migration-backup` (archiving any stale pre-reader backup into `migration-backup/pre-reader-backup`).
- Make mid-flight rollback a true reverse undo list (`undo_steps`) of completed file steps (`profiles.json`, reader environment, login LaunchAgent, patched files, `services.json`): execute every completed undo on failure, collect undo errors, and raise after the full list. Rollback does not stop or start services, swallow an undo and skip the rest, or rewrite plists as a temporary step.
- `install.py` refuses a release update while any reader job is running, and `reader_label` keeps the legacy label while its plist exists. The legacy `owns_agent` rejects a compatibility-symlink launcher, so `migrate-tail-hosting` reads running jobs from the reader configuration, checks `ProgramArguments[1:] == ['--serve', id]` and `resolve(arguments[0]) == resolve(flow-reader)`, stops an owned job with `launchctl bootout` plus a wait until unloaded, and pushes an undo that bootstraps that plist. After the file migration succeeds it restarts with `flow-reader --control restart <id>`; a restart failure prints that command and the current job state.
- `restore-tail-hosting` restarts a reader whose desired state is running by `launchctl bootout`, waiting until `launchctl print` is empty, then `enable` and `bootstrap` of the restored plist. The restored release's `owns_agent` compares `ProgramArguments` by string equality, so that command is the one that can load a compatibility-symlink launcher path.
- Support `--dry-run` on both commands. Dry-run checks the `install.py` preconditions (clean checkout, reader stopped or planned stop, `parentID + '-reader' == id`) and restores both preview and reader services as well as `tinymist-flow.app` as the background manager.

## Verification

- Test successful migration, compatibility symlink and file preservation, idempotence, custom environment overrides, and collision refusal using temporary directories.
- Test `ReaderManager.owns_agent` across compatibility symlinks and verify rejection of unrelated reader binaries in `tools/flow-reader/tests/test_manager.py`.
- Test `migrate-tail-hosting` and `restore-tail-hosting` round-trip in a temporary fake `HOME` and fake `Tail_hosting` root with a shared `launchctl`/`lsof` stub and subprocess guard (rejecting real `/bin/launchctl` or `lsof` invocations, production ports, and the real home `Library` directory). The stub can report a running reader pid. The legacy release fixture is the pre-PR reader tree (string-equality `owns_agent` and the `tinymist-flow` bundle id). Cover `--dry-run` install preconditions, a running reader stopped before install and restarted after, `--migrate-data` preflight, SHA-256 verification, patch preflight idempotency, port conflict rejection, undo continuation after a failing undo, and restore via `launchctl bootout` / wait / `enable` / `bootstrap`.
- Run native app unit tests and focused Reader service tests; regenerate canonical Markdown and verify generated-doc consistency.
- Do not build Rust or install/restart user services as part of this change.
