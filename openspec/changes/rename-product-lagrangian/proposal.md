# Rename the product to Lagrangian

The private production repository is now `kimpossible-TY/Lagrangian`, but the installed app, data paths, packaging and current user-facing docs still identify the product as `tinymist-flow`. Align maintained product identity with Lagrangian without renaming Tinymist engine/protocol identifiers or rewriting historical verification records.

The first launch of the renamed app must migrate the existing Application Support and Logs directories without discarding the user's profiles, signing configuration, source history, reader state or recovery bundles. Keep the old paths as compatibility symlinks so existing LaunchAgents and integrations that still hold absolute legacy paths continue to work during the transition. Preserve `FLOW_*` environment variables and persisted profile schemas.

## Non-goals

- Do not install or launch the renamed app, restart services, or mutate the user's current 4.9 GB data during this source change.
- Do not rewrite dated verification evidence, release history, imported upstream identifiers or the Tinymist engine protocol.
- Do not alter existing profile IDs, ports, URLs, LaunchAgent labels or reader/browser storage keys.
