# Verification

## Scope

Validated on macOS arm64 with VS Code 1.141. The production Flow app, engine,
profiles and user settings were not replaced. The VS Code integration test uses
an isolated user-data directory and a temporary HTTP reader fixture.

## Editor integration

- 22 Vitest tests passed across configuration and shared-reader tests.
- The desktop VS Code integration test invoked the actual preview command twice,
  loaded the reader iframe, observed no new LSP preview task, and verified that
  closing the reader left the HTTP service available.
- Eight concurrent shared-reader opens and a subsequent open reuse one health
  check and one webview in the unit test.
- TypeScript checking, targeted ESLint and Prettier checks passed.
- Native Rust Clippy passed for the library and tests with warnings denied.
- Desktop and web extension bundles built successfully.
- Localizations regenerated successfully from their TOML source.

## Compiler admission

The native arm64 test build used `RUSTFLAGS=-Dwarnings`, the `flow-release`
profile and `system,preview,export` features with default features disabled.
All five new configuration/admission tests passed. In the 32-edit fixture,
no new automatic compilation was admitted, every snapshot contained the latest
source, semantic tokens remained available, and saving produced a newer compiled
revision. A delivered stale worker result neither published nor restarted work.
Save, close and external updates released deferral; the default setting still
compiled an edit and published its error diagnostics.

The configuration suite passed 31 tests, the workspace-change suite passed 33
tests, and the scheduling suite passed four tests (68 distinct tests total).
The two host-watcher tests are ignored by the ordinary workspace suite and were
also exercised explicitly; see the host-watcher observations below.

## Documentation and specification

The canonical Typst guide compiled to PDF and HTML. OpenSpec strict validation,
Cargo formatting and git whitespace checks passed.

## Performance interpretation

These checks establish shared routing and reduced automatic work, not a measured
percentage improvement in a production book. The reader uses the managed HTTPS
URL directly when configured, otherwise VS Code's forwarded endpoint. Viewers of
the same Flow profile and theme use its existing compiler; separate themes can
require separate outputs.

Save-time LSP diagnostics still compile independently. Interactive language
queries can evaluate current unsaved text. An evaluation already running at an
edit cannot be forcibly cancelled, but its superseded result cannot publish or
restart deferred automatic work.

For a deployment comparison, use the same document, theme and 32-edit sequence
with and without the options. Record automatic compiler starts before saving,
save-to-visible-update latency and peak process memory, allowing the same warmup
for each run. Repeat on the actual Windows Code Tunnel connection. Do not infer
large-document latency or memory savings from the small regression fixtures.

## Host-watcher observations

The two explicitly ignored host-watcher tests initially timed out with the default
macOS temporary directory (`/var/folders/...`, a symlinked path). With
`TMPDIR=/private/tmp`, content-change notification passed consistently, while the
remove/recreate test intermittently timed out waiting for clean diagnostics after
recreation. One run passed both tests, but the final repeat still failed the
remove/recreate case. This is an unresolved validation limitation, not an all-green
host-watcher result. These existing tests leave compileOnSave disabled.

An attempted comparison from the original checkout reused the shared target's
118-test executable, so it was not an independent baseline build and does not
establish whether this behavior predates the change. No host-watcher code was
modified. The deterministic external-event admission regression passes.
