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


## Desktop click-to-source follow-up

A per-panel iframe bridge reuses the clicked viewer's revision-checked focus
response. The response now includes the existing one-based source column. The
extension validates source window, origin, channel, canonical project containment
and positions; it converts Unicode scalar columns to UTF-16 and reveals the source
in the editor group. Mobile/external viewers remain standalone, selected-text
Codex actions do not navigate, and dirty target buffers require a save first.
No extra compiler, WebSocket, or focus-file polling was introduced.

Extension/config tests passed 27 cases and frontend bridge/frame tests passed 17.
A real VS Code integration test received the iframe event and verified the opened
source file plus the exact cursor position after Korean text and an emoji. It also
verified zero additional LSP preview tasks and service survival after disposal.
Type checking, ESLint, preview and desktop/web bundles, formatting and strict
OpenSpec validation passed. Engine integration and installed-version checks follow
the clean source build.


Flow 0.1.16 was built from clean source `ce9211ac` with warnings denied and ThinLTO
in 3m52s, signed with the existing identity, and installed with the previous bundle
retained for rollback. The installed engine SHA-256 is
`9ffb1debf4af07147de01d0bc6872ecdf8c5e5e2c9fe10bd9b0dd0bacded9926`.
The release manifest correctly records the new source revision and clean state;
the engine's cached `--version` Git text still reports `5218829a`. Use the manifest,
artifact hash and passing new-protocol test for this build's provenance, not that
stale embedded build metadata.

The optional real-engine source-navigation test passed: response coordinates
match the saved snapshot, another viewer receives no focus reply, and stale hits
return no source. Both engine bundle integration tests also passed (the separate
certificate-update test remained skipped). All 78 frontend tests passed. The app
suite passed 22 tests with four opt-in skips before the engine-specific runs.
Standalone Rust unit builds were interrupted during dependency rebuilding to avoid
competing with the optimized release build; they are not counted as passed. The
native release build and real-engine protocol tests provide the Rust-side checks
for the additional response field. The Typst guide compiled successfully.

Both installed extensions have JavaScript SHA-256
`96a8c4e2b93f8be6f7fccbbbb8f37a9340b6579dfe7291fa641798401e73a902`.
The managed PDE service restarted successfully and serves the new bridge-enabled
HTML (1,926,044 bytes). The menu-bar app was relaunched. Windows reload and
click-to-source confirmation was pending; the user then clarified that they use
Open in Browser. Version 0.1.16 connected only embedded readers, so it did not
cover their external-browser workflow. The follow-up adds an opt-in callback to
VS Code-opened browser URLs, while ordinary mobile URLs remain independent.


### External-browser follow-up

VS Code now creates an ephemeral loopback callback only when opening an external
reader. `asExternalUri` forwards it to the client. A per-reader random route and
exact reader Origin are required; payloads are bounded to 8 KiB, methods are limited
to POST/OPTIONS, and the extension disposes the listener on reload. Repeated opens
reuse that profile's endpoint. The normal phone URL carries no callback. No new
compiler, document-frame connection or focus-file polling is introduced.

The external callback integration test passed in real VS Code, verifying the
opened source and exact UTF-16 cursor position. Both embedded and external tests
passed in one run. Focused callback/extension/frontend tests passed 28 cases, and
the complete preview frontend suite passed 79. Type checking, ESLint, desktop/web
bundles and preview asset generation passed. Browser mode asks to reopen from
VS Code when its callback expires. The next signed release contains both modes.


Flow 0.1.17 was built from clean commit `650f97d8` with warnings denied and ThinLTO
in 3m46s. The build metadata generator was rerun before building; this release's
embedded Git SHA and manifest source revision both match `650f97d8`. The real-engine
source-navigation test passed again. The installed engine SHA-256 is
`22204b9c466647725d597047f66f51385e6f8cc2a43216d572b983a57ef1e429`.
Both installed extension bundles have SHA-256
`feaf31498c055fbbbbac7440609cc9e6c5e8eb196a46654bf1b854a1a709972d`.
The app installer retained the previous bundle and restarted the managed PDE
service, which serves the external-callback frontend (1,926,693 bytes). The menu-bar
app was relaunched. Windows external-browser confirmation remains pending.

## Upstream bidirectional synchronization

The earlier one-way focus/callback adapter is superseded by Tinymist's existing
`editorScrollTo`/`panelScrollTo` protocol. The component span-range resolver and
source-to-document mapper are extracted unchanged from RenderActor, and the
source reveal handler and selection admission policy are shared by ordinary
Tinymist and Flow preview. The existing frontend jump renderer is unchanged.
Each desktop reader adapts these events through its existing rendering socket
and a small extension-owned control socket; navigation carries no document
frames, source buffers or memory-file events. Phone URLs omit that connection.

Before the engine build, 28 focused extension/config tests and all 77 frontend
tests passed. The actual VS Code integration harness passed an external-control
source range reveal (including Korean/emoji column conversion), embedded reader
source reveal, the manual source-to-preview command, no programmatic feedback,
no additional LSP preview tasks and service survival after viewer disposal.
Type checking, changed preview-module ESLint, preview/l10n generation, desktop
and web bundles, Cargo formatting and strict OpenSpec validation passed.
The whole `lsp.ts` lint command reports pre-existing violations outside its
extracted source-reveal handler. Generated-doc checking requires `typlite`;
the changed shared-reader guide is standalone Typst and has no generated Markdown.
Real-engine checks and deployment evidence follow after the clean build.

## Flow 0.1.18: upstream bidirectional mapping and remote transport failure

Built and installed Flow 0.1.18 from clean commit
`3c0b3277e6efb3f070b9fafa3676516bd293804e`, with warnings denied, native ARM64
and ThinLTO. Installed engine SHA-256:
`541dd7c7dd618ae89fb124ae24e06632a5701a99c058a1b8a36098c21eb00f1d`.
Matching desktop and remote extension bundle SHA-256:
`a8cc048763fa5aec7b4380746095ef49ce7fe00aa8a08bc8710b9e384b47ce03`.
The app manifest recorded sourceDirty=false. The live PDE service delivered an
18,150,144-byte frame; document delivery alone does not confirm editor navigation.

- Frontend: 77 tests passed; extension/config: 28 tests passed. TypeScript, preview
  and both extension bundles, focused extension lint, formatting and OpenSpec passed.
- Actual VS Code shared-reader tests: 2 passed, including Unicode source ranges,
  manual panel sync, feedback suppression, no extra LSP preview tasks and service
  survival after viewer closure. Ordinary Tinymist preview tests: 3 passed.
- Real-engine navigation: 2 tests passed, covering both themes, component ranges,
  source-to-page mapping, revisions, phone isolation and zero additional compilation.
  Fixture synchronization was corrected to accept initial new frames as well as
  diffs; a cursor inside Text is required by the upstream leaf-at-cursor mapper.
- Installed app suite: 26 passed, 1 optional certificate test skipped.
- Chrome with the full renderer: preview click returned the first component range;
  panelScrollTo scrolled from 0 to 1608 and revealed page two; dark-theme preview
  click returned the second component range. This used a local control endpoint.

After Windows Reload Window and a fresh Open in Browser tab, the user reported
“Reopen this preview from VS Code” and neither direction worked. The remote host
listened on its editor control port but had no incoming connection. This narrows
the failure to the separate control transport; the precise browser/proxy error
was not observable from the Mac. Local checks did not cover this remote path.
The follow-up moves controls to the reader's already forwarded and authenticated
origin/port; only bounded navigation messages are relayed. The original renderer
connection continues to carry document frames directly.

## Flow 0.1.19: confirmed Windows Code Tunnel synchronization

Built the signed native ARM64 release from clean commit
`b679a577df92ec1fdef038055df4e5fb6640f0c9`, with warnings denied and ThinLTO,
in 4m17s. Both the embedded Git SHA and app manifest sourceRevision match that
commit; the manifest records sourceDirty=false. The installed engine SHA-256 is
`565f47311f7139c0adf007f7472caf1bfb06d3b09c2e745639c351e7e8b1f976`.
The matching desktop and remote extension JavaScript SHA-256 is
`7f0ae9e25099d2330ad7049f94ad1dc9e0c72ac39b8b7ab0c79ec56a67549547`,
and both bundled engines match the installed app engine. The installer retained
the previous app and restarted the managed PDE service; the new menu-bar app
was relaunched. Ewald remained stopped.

Editor controls now use the same forwarded origin and port as the reader.
The extension registers its random session directly over Mac loopback, and
embedded/external readers attach through that reader origin. Forwarded URL
prefixes and authentication query parameters are retained. Only bounded
editorScrollTo/panelScrollTo messages cross the relay; document frames retain
their existing direct connection. Tinymist's existing source mapping, reveal
handler, selection policy and preview jump renderer remain in use.

- Frontend: 78 tests passed; focused extension/config: 29 tests passed.
  Type checking, changed extension-module lint, formatting, preview/l10n
  generation, desktop/web bundles and strict OpenSpec validation passed.
- Actual VS Code shared-reader integration: 2 tests passed, including Unicode
  ranges, the manual panel-sync command, feedback suppression, no extra LSP
  preview tasks and service survival after reader disposal.
- Real-engine navigation: 2 tests passed, covering both themes, source ranges,
  source-to-page mapping, revision guards, phone isolation and zero additional
  compilation. The real-engine relay test also passed, covering private-host
  registration, Origin/Host checks, session isolation, message limits and
  renderer survival after editor disconnection.
- Installed app suite: 27 tests passed, 1 optional certificate test skipped.
  The relay fixture now compares the saved focus contents before/after
  navigation: document loading already initializes that file. This test-only
  correction was made after the clean release build and does not change the
  installed product code.
- Rust preview-feature check and Clippy passed with warnings denied; workspace
  Cargo formatting passed. The canonical Typst shared-preview guide compiled.
- Chrome with the full renderer: a preview click resolved the first component
  range; source navigation moved `#typst-container-main.scrollTop` from 0 to
  1608 and revealed page two. Clicking the second component returned its source
  range in both themes, including after a theme change. Reader and control
  connections used the same port. Local evidence is saved in ignored
  `dist/shared-flow-preview/bidirectional-0.1.19.json` and its PNG screenshot.

After Windows VS Code Reload Window and a fresh Open in Browser tab using
Flow 0.1.19, the user explicitly confirmed that both directions work:
browser component click moves the VS Code cursor, and source component click
moves the browser preview. This confirms the actual Windows Code Tunnel path,
in addition to local protocol/editor/browser checks. No further reload is
required. End-to-end latency was not re-benchmarked for this transport fix;
navigation tests confirm that synchronization adds no compilation.
