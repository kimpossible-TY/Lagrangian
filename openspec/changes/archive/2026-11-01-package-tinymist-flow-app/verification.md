# Verification and deployment — 2026-09-28

## Verified

- Swift 5 compilation with warnings treated as errors.
- Eight targeted configuration and update-recovery tests passed.
- Six Tail Hosting management/focus tests passed against a temporary patched copy.
- A real signed app bundle was installed, updated, and rolled back in an isolated temporary directory.
- Strict bundle signature, engine SHA-256, app version, and engine execution checks passed.
- Native UI opened with the branded icon and imported project controls; login startup was enabled.
- Installed version: 0.1.0, source revision `47149701d1ee9d79c5a0e189425f2faf8383e4b9`, clean build, ad-hoc signing.
- OpenSpec strict validation passed. Generated README consistency passed; the existing book template reports its unavailable `Source Han Serif SC` font on this host.

## macOS consent and live verification

The migration adapter was applied and the GUI Restart action launched the bundled engine under the existing preview job label. macOS TCC attributed the Documents request to `io.github.kimpossible-ty.tinymist-flow`, confirming the new identity. Computer Use refused access to the system UserNotificationCenter app for safety reasons, so the user completed Documents consent.

During the wait for consent, the previous Tail Hosting registry, launcher, and LaunchAgent were restored from the migration backup. The legacy preview resumed after consent. The migration was then reapplied and the imported profile restarted. The app and launchd both reported PID `63386` and `managedByApp: true`. The local HTTP endpoint returned 200. The unchanged Tailscale Serve route proxied the HTTPS URL to `127.0.0.1:23625`; the WebSocket returned 101 and delivered a complete 16,273,700-byte document frame.

System Settings showed `tinymist-flow` → `Documents Folder: on`. The app window showed `프리뷰 준비됨 · PID 63386` and login startup enabled. A Safari tap on the cover title recorded source `cover.typ` line 9 in the new focus file. Tail Hosting reported `service_matches: true`, `source_excerpt_matches_disk: true`, and `needs_reselection: false`; its focus PID was also `63386`. Six Tail Hosting management/focus tests passed after migration. No source document was moved and no Tailscale route was changed.

Unattended login after a real macOS login cycle and iPhone behavior after this packaging migration were not rechecked. The preview engine's existing iPhone implementation was not changed here. Ad-hoc signing caused a second Documents prompt when the final bundle replaced the earlier trial bundle. Future releases should use a stable code-signing identity and verify permission continuity.

## Repository naming — 2026-10-04

The development fork was renamed from `typst-relay` to `tinymist-flow`, preserving GitHub repository ID `1376877083` and its `Myriad-Dreamin/tinymist` parent. The earlier independent repository became `tinymist-flow-archive`, preserving ID `1376906710`. The repository description, local remote URLs, current documentation, and README source now use the product name. `git ls-remote` confirmed access to both repositories and their original branch heads.

The local typlite build, JavaScript syntax check, README regeneration, OpenSpec strict validation, and diff whitespace check passed. Both Typst sources compiled to PDF; the README also compiled to HTML, where the current repository, issues, and historical repository links were verified. The README template still reports the existing unavailable `Source Han Serif SC` and `BlexMono Nerd Font Mono` fonts; HTML export also reports its experimental-feature warning.

## Flow-only source ownership — 2026-10-04

Commit `9dfeb20f0193b0ace1e1be5ac082cc0f20dbfe9c` removes 3,033 unrelated tracked files and retains a 32-file app project. Swift app sources, branding, the Tail Hosting adapter, packaging, app tests, standalone documentation, Flow OpenSpec artifacts, workflow skills, and Apache License 2.0 remain. Rust engine crates, editor integrations, preview frontend sources, engine fixtures, dependency workspaces, and upstream release/CI files are no longer maintained in this tree. Prior sources remain in Git history. Previously generated local engine and editor outputs were preserved under `.local/retired-engine-artifacts/20261004-201615/`.

Packaging consumes an external executable via `--engine`, `FLOW_ENGINE_PATH`, or the current installed app. It probes required preview CLI support and completes and verifies a staged bundle before replacing its build output. The release manifest records the external engine version and input SHA-256 separately from the Flow source revision and bundled engine SHA-256. Native runtime preview arguments and focus/change/origin environment variables are preserved. The repository description now identifies Flow as a native macOS app.

Verification passed both in the development tree and a clean shallow checkout of the app-only commit:

- Fourteen tests passed, including fresh Swift compilation with warnings treated as errors, profile validation, missing/incompatible engine rejection, failed-build preservation, update recovery, real bundle signing, temporary installation, and HTTP/WebSocket preview delivery.
- Real preview checks confirmed system-theme support and distinct compiled light/dark documents through the configured HTTPS origin.
- The external engine was supplied from `~/Applications/tinymist-flow.app/Contents/MacOS/flow-engine`; its input hash remained unchanged. The fresh checkout contained no engine workspace, Cargo manifest, or target directory and stayed clean after the checks.
- The README and development guide were regenerated with an external typlite executable and passed `node scripts/link-docs.mjs --check`. JavaScript syntax and diff whitespace checks passed.
- All three standalone Typst documents compiled to PDF without warnings, and OpenSpec strict validation passed.
- The source commit was integrated into local main by fast-forward.

This extraction does not install or restart the live app. Existing mobile selection, assistant focus, device theme, and change restoration features continue to depend on the compatible external engine. A replacement engine requires compatibility verification; the CLI probe alone cannot establish support for every environment contract. CI compiles current Swift sources and the documentation; real-engine integration remains opt-in through `FLOW_TEST_ENGINE`.

## Preview branch integration — 2026-10-08

The preview activity status branch is integrated with the engine, preview frontend and supporting workspace sources restored at the user’s request. The merge retains the tinymist-flow repository identity, external engine provenance, staged packaging and freshly compiled Swift app tests. Native ThinLTO engine builds and deferred consent verification are also retained. Historical app-only extraction records above describe the earlier layout.

- App unit tests: 14 passed; 2 optional bundle tests skipped in the unit run.
- Optional external-engine bundle tests: both passed, including signature/provenance, isolated installation and both theme variants through the configured WebSocket origin. The installed engine input hash was preserved.
- Preview frontend: all 40 tests passed.
- Restored workspace: locked offline Cargo metadata and cargo fmt --check --all passed.
- User guide: compiled successfully with the compatible installed engine.
- The restored typlite binary built successfully offline; README and developer guide were regenerated and scripts/link-docs.mjs --check passed.
- OpenSpec CLI was unavailable locally; artifact presence and requirement/scenario structure were checked manually.
- Restored engine, vendor, frontend and preview/performance fixtures match the incoming branch exactly; the merge resolution diff against the incoming branch passed git diff --check. The complete staged restoration retains pre-existing whitespace findings in upstream files and fixtures; those sources were kept unchanged.

No live app installation, service migration or release tag was performed during integration.

## Persistent personal signing — 2026-10-10

Packaging can save an existing Keychain identity with `configure-signing --identity`, then reuse its certificate fingerprint for both app and engine builds. Explicit CLI and environment overrides retain precedence. Missing or malformed saved identities fail without replacing the previous output; configuration is saved only after a signing probe succeeds. Bundle validation checks the recorded public certificate SHA-256 against both signatures before executing either binary.

- Twenty app/configuration/recovery tests passed, including fresh Swift compilation with warnings treated as errors.
- Both external-engine integration tests passed: bundle provenance/signature and isolated installation, plus distinct light/dark document delivery through the configured WebSocket origin. The optional persistent-certificate integration test remains pending initial Keychain approval.
- The user guide compiled successfully, OpenSpec strict validation passed, and the patch passed whitespace checks.
- A personal code-signing identity named `tinymist-flow Local Signing` was created in the user's login Keychain. Its public certificate SHA-1 is `48CCFB52FB49CBE01B5FF5A0FD5859AFA8ADDBF1`. The private key remains in Keychain; temporary key/PKCS#12 files were removed. No general certificate trust or TCC database changes were applied.

The first signing probe opened native Keychain authorization. Computer Use refused access to `com.apple.SecurityAgent` for safety reasons; the user reported being unable to access the Mac. The pending probe was cancelled, and `signing.json` was not written. The installed app was not replaced during this signing work. Registration, certificate-signed build checks, initial Documents consent, live HTTPS delivery, and permission continuity after a subsequent installed build remain unverified. Resume by rerunning `python3 scripts/flow-app.py configure-signing --identity "tinymist-flow Local Signing"` and completing the native key-use authorization locally.

The user subsequently completed native Documents and Keychain Always Allow authorization. A first real signing check exposed an optional-argument parsing issue in certificate extraction; using `--extract-certificates=PREFIX` fixes it. Identity registration then succeeded, and all 23 tests passed with the real certificate, including distinct app builds satisfying the same designated requirements for both app and engine. Repeated signing completed without another Keychain prompt. Restarting the existing ad-hoc app restored live HTTPS document delivery for both light and dark themes. Certificate-signed installation and update continuity checks are the remaining deployment work.

### Certificate-signed installation and update continuity

Two production bundles were built from clean commit `67aa70bb0aca7d911bb1e58e5b7ca12b5f9f257a`, using the independent installed-engine input with SHA-256 `de7f898fad64268d7d686efeb36db4c2b3f860c20dcbe0f18f9a902e3ded5a44`. Both use certificate SHA-256 `1de2d9bd2a9497ff7fd686977fd969ba5b245cef295555af147c4b6eec35ddf5`. Their app executable hashes differ, while both app and engine designated requirements remain identical and verify against the earlier build's requirements.

The first bundle was installed as version 0.1.9 with deferred live health verification. The previous ad-hoc bundle is retained at `~/Library/Application Support/tinymist-flow/releases/20261010-140925-002430/tinymist-flow.app`. Its build timestamp is `2026-10-10T05:08:50.679982+00:00`; the second bundle's timestamp is `2026-10-10T05:10:03.569801+00:00`.

System Settings initially displayed Documents access as on, but TCC still compared the certificate-signed app against the previous ad-hoc requirement `cdhash H"50983a322e8eb62ae28cfe4bb820e75f14e8984c"` and reported a mismatch. The HTTP endpoint briefly started, but an HTTPS WebSocket check did not deliver a compiled document. Under the user's existing Documents-refresh authorization, the app's Documents approval was reset with the official `tccutil reset SystemPolicyDocumentsFolder io.github.kimpossible-ty.tinymist-flow` command, and only the PDE profile was restarted. No direct TCC database edits, general certificate trust changes, or broader access grants were made. The user then completed initial Documents Allow for the certificate-signed app. PID `41814` delivered complete light and dark documents through the existing HTTPS endpoint: 17,900,488 and 17,954,224 bytes, respectively.

The first normal update attempt exposed an asynchronous service-stop race: launchd bootout returned while the old PID was still visible, so the new app's Start command skipped launching a replacement. The installer reported the HTTP health failure and restored the first signed bundle. Installation and recovery now wait for stopped profile status with a bounded deadline before moving bundles or restarting profiles. Regression coverage verifies that the old executable remains in place while shutdown is pending and that a shutdown timeout is reported.

Using the corrected installer, the second signed bundle installed successfully with normal HTTP health verification. Its app executable SHA-256 is `df1b2cdeb7880db8adcfc2482efbe3b05b3fcca5a7628e5de6aa9bbcd99523db`, different from the first build's `5a50bdeb95d0a26744fa99a08c2511cf79bc8f6c4744bb018609c1fc2ea2107e`. New PID `46697` delivered complete light and dark documents through TLS-validated HTTPS WebSockets: 17,900,304 and 17,955,008 bytes. No further Documents reset, native consent action, or Keychain approval was requested or performed after the initial grant. The first signed bundle is retained for recovery at `~/Library/Application Support/tinymist-flow/releases/20261010-144155-550712/tinymist-flow.app`.

All 25 app tests passed with the real signing identity and independent engine input, including fresh Swift compilation with warnings treated as errors, both-theme document delivery, installation/recovery, and changed-build requirement compatibility. The updated guide compiled without diagnostics, strict OpenSpec validation passed, and the patch passed whitespace checks. Installed signature/certificate/hash verification passed. Profile configuration and both LaunchAgent files match their pre-install hashes; the Ewald profile remains stopped. Bundle comparison, installed-state and both live-delivery records are retained under `dist/signing-updates/`; the temporary clean build worktree was archived.

Permission continuity is confirmed for this installed update on this Mac with the retained local certificate. A fresh macOS login cycle and rendering on the user's iPhone were not rechecked. Certificate replacement or loss can require consent again. Earlier pending-approval paragraphs above record the initial provisioning stages and are superseded by these completed deployment results.

## User documentation discovery (2026-10-11)

- Reorganized the README around features, a real example screenshot, first-preview controls, mobile access, and separate first-install/update paths. Added a reusable theme-aware reading demo.
- Generated `docs/tinymist/flow-app.md` from the same source used for the bundled PDF. All generated documents and `--readme-only` pass consistency checks; a temporary canonical-guide change correctly rejects the outdated web guide.
- Checked 16 local documentation links and image references, including cross-document anchors. Rendered the README and web guide in a browser and inspected the seven-page PDF through SVG output.
- Compiled README, developer guide, user guide, and both reading-demo palettes. Markdown generation and paged compilation report no warnings; optional HTML inspection reports Typst's standard experimental-export notice.
- Captured the screenshot from the installed compatible engine with an isolated demo and focus file in a phone-sized touch browser viewport. Save for Codex persisted the selected demo sentence and source context. This is browser emulation, not a physical-device check.
- Built and verified an isolated app bundle with the updated PDF, using `yarn flow:build` and the installed external engine. `yarn flow:test` with `FLOW_TEST_ENGINE` passes 24 tests, including isolated packaging and dual-theme document delivery; the persistent-certificate test is skipped because no test signing identity was supplied.

## Seamless reading sessions (2026-10-23)

- Native Read saves and validates edited settings, starts or reuses the managed preview, waits for a binary full-document WebSocket frame from the current process, and opens the configured URL once. The AppKit window distinguishes requested startup, observed process and document readiness; failures remain inline. Service and settings work runs on a serial background worker, while wake, network and power events reconcile the current session without restarting an explicitly stopped project.
- The paged reader retains native selection and zoom during reconnect, guards document-specific viewport restoration, and defers replacement until selection release. The HTML reader bounds and cancels requests, pauses background retries, retains accepted content and selection, and rejects old document, revision, service or text anchors. A final review caught and fixed an HTML stable-key anchor that could otherwise restore changed text.
- `FLOW_TEST_ENGINE=… python3 -m unittest discover -s tests/flow-app -v`: 82 passed, one optional persistent-certificate test skipped because no test signing identity was supplied. The suite includes isolated app builds and temporary installation, real WebSocket delivery in both themes, AppKit action/lifecycle tests, and process/readiness failure cases. No installed app or user service was changed.
- `node --test tools/reader-common/tests/*.mjs tools/flow-reader/tests/test_*.mjs`: 187 passed. `python3 scripts/test-reader-services.py`: 175 passed; 42 optional integrations skipped without the external reader packages or Tail Hosting source. The HTML installation test passed.
- Paged preview frontend: 95 tests passed; typst-dom: 37 tests passed; both TypeScript projects passed `tsc --noEmit`. Scoped ESLint and Prettier checks and `node scripts/build.mjs build:preview` passed.
- Real WebKit 26.5 mobile-overlay and desktop-SVG browser checks passed with an isolated engine subprocess restart and native document probe. The HTML Reader passed 28 Chrome/WebKit browser recovery checks against an isolated HTTP fixture. These verify reconnect, offline/hidden retry suppression, retained native selection, content replacement after release, position recovery and stale-anchor rejection.
- The changed canonical Typst documents compiled; `node scripts/link-docs.mjs --check`, `openspec validate package-tinymist-flow-app --strict`, Swift strict lint and `git diff --check` passed.

Physical Mac sleep, battery drain and thermal performance, iPhone background suspension, and a combined installed production update were not measured in this development run. Those remain device and deployment checks; the lifecycle, power-cadence and recovery policies were exercised with isolated events and real desktop browser/engine interruption.

## Native engine application (2026-10-23)

- Built the current paged frontend, then a warning-denying native `flow-release` engine and signed Flow 0.1.29 bundle from commit `d36c4dd5ea5688024ed3d3ba723b3fd255e4dd53`. A targeted Cargo package clean and rebuild refreshed cached version metadata so the final engine's embedded commit and manifest source revision both name that commit. The final signed engine SHA-256 is `529db652b9608b138ccba16b71dcfed8ef0b7739c52a787c3e70808875500c02`; app and engine retain the installed certificate and designated requirements. Unrelated pre-existing untracked files were excluded from the clean-source provenance check without moving or changing them.
- Before installation, the final engine passed isolated bundle installation and distinct light/dark document delivery (two tests passed; the optional separate test-signing-identity test was skipped). Real WebKit 26.5 mobile-overlay and desktop-SVG restart/recovery checks passed with the newly built engine; the final metadata rebuild was also rechecked with the mobile-overlay test. Bundle signature, version, engine hash and executable checks passed.
- Installed the verified 0.1.29 bundle over 0.1.28 using the app installer, which retained the prior bundle for rollback. The managed `typst-pde` preview restarted from PID 215 to PID 26209; `typst-ewald` stayed stopped. The local and configured HTTPS endpoints returned 200. TLS-validated HTTPS WebSockets delivered complete `new,` frames for light and dark (18,338,064 and 18,393,864 bytes with distinct hashes). The menu bar app was relaunched from PID 33066 to PID 27162; the preview retained PID 26209. Installed bundle verification passed.
- This run closes the installed-update coverage pending in the preceding development record. Physical iPhone suspension and return were not exercised. The separately hosted semantic HTML Reader service was not updated by this native engine installation.

## Immediate-highlight application (2026-10-23)

Installed signed Flow 0.1.30 and the HTML Reader from clean commit
`43c8f9a359a0f860fb48d60de4240009777cc10f`, preserving certificate/designated
requirements, settings and running/stopped profile states. Installed Chromium
and WebKit checks confirm immediate paint, real isolated source writes and
compiled replacement; public PDE delivery passes in both themes. Following the
user's Mac reboot, signatures, immutable files and automatically restarted PDE
services verify successfully; Ewald remains stopped. Full receipts and limits
are recorded in the responsive-reader change's
`verification-optimistic-highlights.md` and
`dist/optimistic-highlight-rollout/verified-rollout.json`.

## Remote Apple Silicon engine artifact

- `.github/workflows/flow-engine.yml` is manual `workflow_dispatch` only. It cancels an older in-progress run for the same ref. `actions: write` stays because artifact upload and the Cargo cache save require it.
- Successful run https://github.com/kimpossible-TY/Lagrangian/actions/runs/40874149546 uploaded `flow-engine-darwin-arm64` (66,275,034 bytes) for head `d820314477186d58adccbbf35cc85fb648f7e597`. SHA-256 `51541f6744f0caaf5048ff6de76228c298fc2e49f765734c3049c9e8c5d41628`. `release.json` records that commit, target `aarch64-apple-darwin`, and profile `flow-release`.
- `python3 -m unittest discover -s tests/flow-app -v` on Linux covers fetch, checksum, manifest target, quarantine clearing, and `--engine` packaging with a mocked `gh`. macOS Swift and external-engine tests skip on Linux. Quarantine clearing and `fetch-engine` were not run on a Mac. This review follow-up did not start a macOS build.
- After `yarn install --frozen-lockfile`, the workflow runs `node scripts/stage-tinymist-assets.mjs` with no arguments. That script is on main from `76854b9c`. This follow-up did not run it on a Mac or start a macOS build.
- MSRV is checked by comparing `Cargo.toml` `rust-version` with `rust-toolchain.toml` `channel`. Both are `1.92`.
