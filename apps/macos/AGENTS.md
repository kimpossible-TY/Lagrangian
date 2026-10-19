# Native Flow app

Read the root AGENTS, `docs/dev-guide.md` and the app OpenSpec contracts.

- `sources.json` is the single explicit source list used by packaging and tests. Update it whenever a Swift source is added, moved or removed.
- Keep profile models/validation, environment paths, settings persistence, command execution, LaunchAgent control, engine launch, CLI and AppKit UI in their respective files.
- ProjectService owns profile-update lifecycle and recovery. Validate before stopping a service; preserve the prior settings and recover the previous service on failure. Inject storage/service operations for focused tests.
- AppKit callbacks gather inputs and delegate lifecycle operations; do not add filesystem or launchctl workflows to UI callbacks.
- Preserve CLI flags, environment variables, settings schema and engine arguments. Development tests/builds must not install or restart the user's app/services.
- Run `python3 -m unittest discover -s tests/flow-app -v`. Set FLOW_TEST_ENGINE for external-engine integration/packaging coverage when available.
