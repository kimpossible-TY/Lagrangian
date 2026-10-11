# Verification

## Scope

Initial implementation validation used macOS arm64 with VS Code 1.141, before
replacing the production app, engine or user settings. The authorized deployment
follow-up is recorded below. The VS Code integration test uses
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


## Authorized deployment — 2026-10-11

Built Flow 0.1.15 from clean commit `5218829a` with the native arm64 flow-release
profile, ThinLTO and warnings denied. Verified the persistent signing certificate
matches the installed 0.1.14 certificate. Installed with the app updater, which
saved the previous bundle and restarted the previously running PDE service. Ewald
remained stopped. Relaunched the menu-bar app.

The matching 0.15.8 VSIX was installed in both desktop and remote-server extension
directories. After the remote-reader correction below, the installed JavaScript hash is
`525274871dca866ae6107d8003f692905f707b9ebd77934cf7f28181e6e6ae61`.
The signed engine hash is
`2e28b6e610a22543fa9f77e7f1fe7a029b6db8da252f6adeb5e63cbd6b3b888c`.

Enabled sharedFlow and compileOnSave in the PDE and Ewald workspace settings,
preserving other options and automatic-save preferences. Backup copies, the old
extension directories and old engine are stored under the Flow support directory's
`shared-preview-backup-20261011-184947` folder. The user reloaded the Windows
window; the new remote LSP log explicitly contains `compileOnSave: true`,
`preview.sharedFlow: true` and the installed app engine path.

The app tests passed 22 ordinary checks (three optional checks skipped). With the
new engine supplied, both optional bundle/real-preview integration tests passed;
the separate certificate-update test remained skipped. The installed extension
opened the actual PDE shared reader twice in an isolated VS Code window without
adding an LSP preview task. This routing test used syntax-only mode only in its
temporary test user profile; production diagnostics remain enabled. Closing the
reader left the service responding with HTTP 200.

The actual managed HTTPS reader returned HTTP 200. Its dark-theme WebSocket
delivered an 18.2 MB document frame in 11.055 seconds on the first connection and
0.166 seconds on the next connection. These are host-side first-frame delivery
timings, not rendering or Windows network timings.

## Real PDE workload comparison

The fixture copies the real 316-page PDE project, fonts and local packages. Each
fresh LSP process compiles once, then receives 32 visible text changes 200 ms apart,
waits two seconds, writes the copied file and sends didSave. The original document
is never edited. Three before/after runs alternate old engine/default admission
and new engine/compileOnSave. The existing production processes remain present.

| Metric | Before | After |
| --- | --- | --- |
| Automatic starts before save, each run | 2, 2, 2 | 0, 0, 0 |
| Save to LSP completion, seconds | 9.687, 9.981, 10.019 | 8.630, 8.686, 8.636 |
| Median save to completion | 9.981 s | 8.636 s |
| Median sampled peak resident memory | 1407.8 MiB | 1627.0 MiB |

Median save-to-completion decreased by about 13.5% in this workload. Resident
memory did **not** improve; the after run ranged from 1611.6 to 2467.2 MiB and macOS
memory compression/swap makes RSS an incomplete pressure metric. Do not claim a
memory reduction from these measurements. Input-time automatic work disappeared,
but a save/filesystem-notification race still caused one discarded evaluation in
each optimized run. Save-time LSP diagnostics remain a separate compilation.

Raw numeric results are in `measurements.json`; the replay script and per-run logs
are preserved under `dist/shared-flow-preview/`. These measurements do not quantify
Windows Code Tunnel's save-to-visible-render latency or isolate a production
whole-system memory reduction from sharing the preview backend.


## Remote reader correction

The user reported a blank Windows webview and the missing browser-opening control
after the first installation. Host HTTP/WebSocket delivery and command routing do
not establish client rendering. The first implementation preferred the profile's
private HTTPS URL even in remote extension hosts, requiring independent client
access to that address; this is a plausible cause, not a confirmed client network
trace.

Remote readers now resolve the loopback service through `asExternalUri` regardless
of the profile's public URL. The visible header includes an Open in Browser button
that opens only the extension-resolved URL. Its nonce-protected message handler
does not accept an arbitrary destination from the webview. Local sessions retain
the public URL preference. The existing Flow compiler and engine are unchanged.

The focused suite passed 23 tests, including remote routing with a configured
public URL, forwarding query preservation, browser-button destination and error
handling. Type checking, focused ESLint, and desktop/web bundles passed. The
corrected VSIX was force-installed in both extension directories and its hashes
matched. The installed corrected extension also passed the actual PDE routing
test: two opens, no additional LSP preview task, and HTTP 200 after closing the
reader. The canonical Typst guide compiled and strict OpenSpec validation passed.
After reloading Windows VS Code, the user confirmed that both the browser button
and the document are visible. This completes client display verification; browser
button click-through and Windows save-to-visible latency were not separately
measured. The installed Flow 0.1.15 app is tagged `flow-v0.1.15` at its clean
source revision `5218829a`; the accompanying extension correction is `b0b15f9a`.
