# Tasks

## 1. Browser and terminal host

- [x] 1.1 Implement persistent Chromium hosting and iTerm2/Kitty PNG output; verify protocol framing, size calculations and input decoding with Node tests.
- [x] 1.2 Forward real selection gestures and Reader actions, preserve origin/profile, and clean up modes/processes; verify browser action, persistence and lifecycle integration checks.
- [x] 1.3 Document prerequisites, controls, stable origin and terminal limits in canonical Typst documentation; execute the diagnostic and snapshot commands.

## 2. Editor navigation and safe source edits

- [x] 2.1 Add revision-checked conservative source/cursor endpoints; verify unique prose, ambiguous/generated text, stale sources and Unicode byte coordinates in Python tests.
- [x] 2.2 Route verified final writes through an optional editor callback; verify modified buffers and stale disk contents remain untouched and safe highlights still compile.
- [x] 2.3 Add the opt-in browser selection/follow bridge and conflict feedback; verify active selections/dialogs block follow and existing annotation behavior survives.
- [x] 2.4 Document navigation coverage and editor-owned saving alongside the setup instructions; verify documented APIs match implementation.

## 3. Neovim pane integration

- [x] 3.1 Implement optional setup and start/stop/sync commands with native iTerm2 launching; verify argument quoting and owned lifecycle in focused headless integration checks.
- [x] 3.2 Implement cursor/jump/edit RPC handlers and document configuration; verify dirty buffers, Unicode columns and safe file switching using disposable files.

## 4. Integrated validation

- [x] 4.1 Run Reader Python/Node suites and real Chromium selection/highlight/strike checks with terminal hosting; inspect a rendered snapshot and record native terminal verification limits.
- [x] 4.2 Validate OpenSpec, formatting and the complete scoped diff; preserve unrelated worktree changes and report unresolved checks accurately.

## Verification notes

- Node Reader suite: 86 passed. Editor mapping/RPC: 13 passed. Compiler-verified source edits: 18 passed. Reader serving: 7 passed. POSIX terminal lifecycle/race checks: 7 passed. Standalone Neovim smoke passed.
- Real Chromium terminal/browser/Neovim integration: 19 checks passed, including persistent marks, dirty-buffer refusal, absolute entrypoints, safe highlights and selection/dialog follow guards. Existing WebKit/Chromium selection actions: 86 checks passed. The generated Reader PNG was inspected.
- Native iTerm2 3.7.4: automatic split, measured geometry, mathematics, DOM drag selection, red strikes, persistent marks, bidirectional supported-source navigation, and source highlighting that updates both Neovim and disk were exercised with a disposable document. The final default launcher was verified without instrumentation; owned processes and the test window were closed.
- Regression coverage includes absolute entrypoints during isolated highlight compilation and both initial-resize and screenshot/resize ordering. Unrelated existing worktree files were preserved.
- Canonical guide compiled to PDF and experimental Typst HTML; scoped Prettier, Python syntax, OpenSpec strict validation and diff whitespace checks passed. After `typlite` was installed, `node scripts/link-docs.mjs --check` passed on 2026-10-19; no generated Markdown was edited.
- Windows native terminal delivery was not exercised. This renderer has no SIXEL backend; Windows Terminal is outside the current supported host setup. Navigation remains limited to uniquely matched saved literal prose/headings and supported transparent highlight wrappers.

## 5. Shared Save for Codex

- [x] Route the terminal save action to the shared HTML service context and remove the local quotation library without altering legacy storage.
- [x] Verify terminal acknowledgment/context reads, review persistence and existing Neovim highlight/navigation; document validation and local selection reading. No installation or deployment.

### Save for Codex verification, 2026-10-19

- Reader Python suite: 137 passed using the complete local Typst package catalogue and the isolated Tail Hosting adapter fixture. Node suite: 91 passed.
- WebKit and Chromium at 320×740, 390×844 and 768×600: 152 checks passed, including explicit server context, source freshness, unmapped macro text, failed-save retry, pending-save duplicate suppression, newer selection preservation, and untouched/untransmitted legacy local data.
- Real Chromium/terminal host/headless Neovim integration: 20 checks passed. The shared Codex record, persistent review strikes, editor cursor navigation, dirty-buffer refusal and verified source highlighting passed; the action-capsule PNG was inspected.
- Canonical responsive/terminal guides compiled to PDF and experimental HTML; required text was inspected. Both OpenSpec changes, scoped Prettier, generated-doc checking and diff whitespace checks passed.
- This work did not install a Reader release or Tail Hosting adapter, modify a registry/global Codex skill, or restart a live service. The portable adapter was applied only to a temporary test copy. Native terminal graphics were not re-exercised in this change; terminal integration used the real persistent Chromium document.

## 6. Integrate with the maintained reader architecture

- [x] Preserve the original local implementation and map every functional item into the refactored tree.
- [x] Reuse source mapping and selection/source-write services for editor navigation and verified saves.
- [x] Split terminal CLI, options, service lifecycle, browser session, input host and editor bridge; retain the supported terminal.mjs command.
- [x] Add the opt-in terminal browser adapter and editor capability checks to the existing feature controllers.
- [x] Update imports, static assets, installed-layout checks, architecture documentation and agent guidance.
- [x] Run reader/terminal/POSIX/Neovim and real browser integration checks; inspect the rendered snapshot.
- [x] Commit and integrate the verified result into remote/local main; preserve local-only agent settings/assets and archive superseded original source.
