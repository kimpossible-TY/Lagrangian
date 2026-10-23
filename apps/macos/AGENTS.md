# Native Flow app

## Read

Read [the development guide](../../docs/dev-guide.md), [the architecture source map](../../docs/tinymist/dev/reader-architecture.typ) and the app OpenSpec contracts.

## Ownership

- `sources.json` is the single source list used by packaging and tests. Update it when a Swift source is added, moved or removed.
- Keep profile models/validation, environment paths, settings persistence, command execution, LaunchAgent control, engine launch, CLI and AppKit UI in their existing owners.
- `ProjectService` owns project creation defaults, profile selection/persistence and profile-update lifecycle/recovery. Inject storage/service operations for focused tests; UI callbacks gather inputs and adopt successfully saved settings.
- `ReadingSessionController` owns asynchronous lifecycle requests, serialized settings work, readiness, cancellation and polling policy. `PreviewReadiness` probes the existing document protocol; `NativeReadingEnvironment` supplies laptop lifecycle/power events. Keep AppKit event callbacks free of blocking service/storage operations.

## Contracts

- Validate before stopping a service; preserve prior settings and recover the previous service on failure.
- Preserve CLI flags, environment variables, settings schema and engine arguments.

## Verification

From the repository root, run `yarn flow:test`. Set `FLOW_TEST_ENGINE` for external-engine integration/packaging coverage when available. Follow the development guide for builds and releases.
