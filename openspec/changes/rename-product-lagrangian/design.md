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

## Verification

- Test successful migration, compatibility symlink and file preservation, idempotence, custom environment overrides, and collision refusal using temporary directories.
- Run native app unit tests and focused Reader service tests; regenerate canonical Markdown and verify generated-doc consistency.
- Do not build Rust or install/restart user services as part of this change.
