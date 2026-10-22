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

## 7. Windows Terminal and remote PowerShell

- [x] 7.1 Add native SIXEL screenshot encoding, protocol selection and meaningful pixel/terminal lifecycle tests.
- [x] 7.2 Add private editor-owned session manifests and manual/SSH start, preserving source RPC and stop/restart behavior; verify CLI and Neovim integration.
- [x] 7.3 Document Windows Terminal/PowerShell remote setup and ownership; run scoped Node, Python PTY, Neovim, real browser, lint and documentation checks, recording physical Windows coverage separately.

## 8. Same-connection Neovim Reader

- [x] 8.1 Separate browser session behavior from native/editor transports; add bounded versioned editor frame/input delivery and stale-layout guards.
- [x] 8.2 Add a right-hand Neovim view with measured geometry, browser input, source focus, repaint and owned cleanup; make it the default start while retaining explicit native/manual modes.
- [x] 8.3 Verify probe/TUI restoration, same-connection frames, input, resizing, source RPC and stop/restart with isolated PTY and real Chromium fixtures.
- [x] 8.4 Update canonical guides, ownership and OpenSpec contracts; run scoped checks and record unverified physical Windows coverage.

### Windows Terminal verification, 2026-10-21

- HTML/terminal Node suite: 141 passed. SIXEL tests independently reconstruct RGB/RGBA pixels for all five PNG filters, alpha/background, color planes, runs and partial bands; malformed/unsupported/oversized input is rejected.
- POSIX PTY lifecycle: 9 passed, including SIXEL quit and removing an attached session's manifest. Headless Neovim smoke passed for manual/SSH preparation, private arguments, source RPC identity, sync, shell quoting, repeat start and stop. CLI checks preserve a prepared session and reject duplicate/expired attachments.
- Real Chromium/Neovim integration: 22 checks passed, including encoding the real 760x700 screenshot, source navigation, persistent strikes, Save for Codex, modified-buffer refusal and verified source edits. Inspected the resulting Reader PNG. A sample frame encoded to 41,543 bytes in about 32 ms on this Mac; this is a local observation, not a transport benchmark.
- Isolated archived-layout installation test passed. Reader dependency/cycle tests: 2 passed. Scoped ESLint (zero warnings), Prettier, strict OpenSpec validation, generated-document checking and diff whitespace checks passed. Canonical terminal/architecture guides compiled to PDF; terminal HTML text/ordering was inspected (Typst emits its expected experimental HTML-export notice).
- No physical Windows Terminal, Windows pane launcher, or Devtunnel image/input path was exercised. This adds native SIXEL output and editor-owned attachment in a second remote terminal connection; opening the Windows pane and reconnecting remain manual. No live service or user editor configuration was changed.


### Same-connection Neovim verification, 2026-10-21

- Default start now opens an internal right-hand view over the existing connection. Browser input/capture policy is shared by native and editor transports; explicit native/manual launchers remain available. No user configuration or installed service was changed.
- HTML/terminal Node and architecture checks: 147 passed. Editor transport coverage includes bounded acknowledgments, resize generations, Unicode/paste/drag, malformed input and cancellation/EOF. Subsequent focused editor transport checks passed after tightening viewport bounds.
- Eight isolated Neovim TUI scenarios passed using a real POSIX PTY: measured placement despite false SSH ioctl pixels, default mouse/Unicode/paste, source focus/navigation, resize/quit/restart, modified source preservation, hidden tabs/full redraw/idle frame suppression, floating borders, split failure, helper crash/timeout recovery and replacement-buffer ownership. Terminal modes and SIXEL cursor-placement state remain preserved. The standalone Neovim source RPC/manual/native smoke also passed.
- Existing native terminal lifecycle/race tests: 9 passed. Isolated archived-layout installation: 1 passed, including the new transports and probe helper. No live installation or service restart occurred.
- Real Chromium/Neovim integration: 24 checks passed, including a full 500x580 SIXEL frame in an actual Neovim TUI, input/source cursor/quit, existing persistent review marks, Save for Codex, modified-buffer refusal and verified source highlights. Inspected the browser PNG. The TUI fixtures validate escape streams and behavior; they do not constitute a physical Windows rendering test.
- Scoped ESLint (zero warnings), Prettier, Python syntax, strict OpenSpec validation and diff whitespace checks passed. Canonical terminal and architecture guides compiled to PDF; terminal HTML text/command ordering and generated-document checks passed.
- Physical Windows Terminal/Devtunnel delivery and the internal Kitty/iTerm2 view were not exercised. The default view requires Neovim 0.12+ on a POSIX host and a terminal that answers capability/cell-geometry queries; it remains outside tmux/screen. Neovim may coalesce mouse coordinates in one input batch.

## 9. Preserve shell job control during internal startup

- [x] 9.1 Reproduce the reported suspended editor under an interactive login shell; remove TUI stop/resume signalling and use Neovim-owned terminal responses.
- [x] 9.2 Verify bounded capability failure, Windows virtual geometry, foreground ownership and browser input/restart; update canonical ownership/docs and remove obsolete probe delivery.

### Shell job-control fix verification, 2026-10-21

- The reported `suspended` state was reproduced under an interactive shell. The earlier direct-launch PTY fixtures omitted shell job control: stopping the TUI allowed the shell to reclaim the foreground despite a later SIGCONT. The independent Python TTY probe and all TUI stop/resume signalling have been removed.
- Fourteen isolated Neovim TUI scenarios now run under an interactive zsh. Typed `:FlowReader start`, foreground process-group ownership, Unicode/paste/mouse, resize, source navigation, stop/restart, dirty/replacement buffers, hidden views, Windows DA1 profiles, Kitty replies/logical geometry, query errors, cancellation, timeout and response-handler cleanup passed.
- Real Chromium/Neovim integration: 24 checks passed, including the same-connection 500x580 SIXEL viewport under an interactive shell, browser input/source cursor/quit, persistent review marks, Save for Codex and guarded source highlights. The browser snapshot was inspected.
- HTML/terminal Node and architecture checks: 147 passed. Native PTY lifecycle: 9 passed. Archived-layout installation: 1 passed. Headless Neovim source RPC/manual/native smoke passed. No live installation, editor configuration change or service restart occurred.
- Canonical terminal and architecture guides compiled to PDF, terminal HTML text was checked, generated docs and strict OpenSpec validation passed. Scoped ESLint, Python syntax and diff whitespace checks passed.
- Physical Windows Terminal/Devtunnel delivery remains unverified. Internal SIXEL uses the recognized Windows default virtual grid; unknown SIXEL geometry is refused. Kitty input/frame transport is covered by the emulator fixtures, with physical Kitty/iTerm2 rendering still separate coverage.

## 10. Show startup feedback in Neovim

- [x] 10.1 Show an animated loading status and elapsed time until the first current image arrives; verify delayed startup, normal controls, idle output and closing while loading, and update the canonical guide.

### Startup feedback verification, 2026-10-21

- A disposable interactive-shell PTY confirmed immediate `Loading... 0s`, changing spinner/elapsed time, continued loading through the handshake and status-only/obsolete frames, and normal controls after the first current image. Closing during delayed startup stopped updates and preserved source contents.
- Existing Neovim TUI scenarios: 14 passed, including idle frame suppression and stop/restart. Headless Neovim smoke passed. Real Chromium/Neovim integration: 24 checks passed.
- Canonical terminal guide compiled to PDF and experimental HTML; loading instructions were checked in the HTML. Generated docs, strict OpenSpec validation and diff whitespace checks passed. No user configuration, installation or live service was changed. Physical Windows display was not re-exercised.

## 11. Preserve screenshot colors in SIXEL

- [x] 11.1 Reproduce the light/dark highlight hue shift and replace fixed RGB-cube quantization with a bounded screenshot-derived palette, preserving grayscale and alpha behavior.
- [x] 11.2 Verify theme colors, palette pressure, real browser output and scoped lifecycle/packaging checks; update the terminal guide and contracts without changing shared HTML highlight policy.

### SIXEL highlight color verification, 2026-10-21

- The running HTML and terminal services served the same highlight CSS and equivalent highlight markup. The old fixed RGB cube reproduced the reported hue shift: light gold `(243,228,179)` became `(255,204,204)`, and dark gold `(81,69,43)` became `(102,51,51)`.
- Screenshot-derived color selection fixes the transport layer without importing theme tokens or changing HTML/Typst highlight policy. Six SIXEL tests passed, including reconstructed theme pixels, over 1,000 input colors, palette bounds/determinism, grayscale, alpha, all PNG row filters and malformed/oversized inputs.
- A real Chromium page using the shared CSS encoded light gold as `(242,227,179)` and dark gold as `(82,69,43)`. Both screenshot palettes remained below 256 entries; inspected light/dark screenshots.
- HTML/terminal Node and architecture checks: 150 passed. Neovim TUI: 14 passed. Native PTY lifecycle: 9 passed. Archived-layout installation: 1 passed. Real Chromium/Neovim integration: 24 checks passed.
- Scoped ESLint and Prettier, canonical guide PDF/HTML, generated docs, strict OpenSpec validation and diff whitespace checks passed. Existing services were inspected read-only; no live service was installed or restarted and no user source/configuration was changed. Physical Windows Terminal/Devtunnel rendering remains separate coverage.

## 12. Tolerate remote capability response variation

- [x] 12.1 Reproduce delayed/dropped capability replies and Windows DA1 feature variation; accept required feature sets, retry within a bounded budget and preserve positive Kitty/iTerm reports without requiring unrelated DA1 replies.
- [x] 12.2 Keep Windows geometry for the same attached TUI, report received capabilities on failure and verify cancellation, cleanup, foreground ownership and restart; align the guide and contracts.

### Remote capability detection verification, 2026-10-22

- The previous error was reproduced with a 1.6-second DA1 delay and with reordered/additional Windows features. Required-feature comparison and one bounded retry now handle both cases and a dropped first query, without assuming arbitrary SIXEL cell geometry.
- Twenty-two isolated Neovim TUI scenarios passed. New coverage includes same-TUI Windows restart/resize without replies, cache invalidation for a different UI, refusal without SIXEL, positive Kitty and explicit iTerm reports without DA1, capability details in failures and cancellation/handler cleanup. Foreground/input behavior remains covered under an interactive shell.
- Headless Neovim smoke passed. Real Chromium/Neovim integration: 24 checks passed. Canonical guide PDF/HTML, HTML wording, generated docs, strict OpenSpec validation, Python syntax and diff whitespace checks passed.
- The user confirmed the same Windows Terminal/Devtunnel connection, but its actual failed response was not captured during this change. Physical verification was requested with a module reload and the new diagnostic output; that result remains unverified. No user configuration, service installation or live-process restart occurred.

## 13. Resize the source and Reader divider

- [x] 13.1 Reproduce divider gestures entering the Reader, preserve native gesture ownership and add Reader-local keyboard width/equalize controls using Neovim's existing split layout.
- [x] 13.2 Verify divider movement from both window focuses, cross-boundary selections, keyboard and terminal resizing, current browser frame geometry and cleanup; update the canonical guide and record physical coverage separately.

### Divider resizing verification, 2026-10-22

- Reproduced the rightward divider drag being consumed as browser movement, leaving source and Reader widths unchanged. The existing view input owner now forwards drag/release only for a press started inside the Reader; native Neovim split sizing and layout generation remain the sizing owner.
- Twenty-five isolated Neovim TUI scenarios passed under an interactive shell, including divider dragging left/right from both focuses, current image placement, cross-divider browser/source selections, keyboard width/equalize controls, terminal resizing and cleanup. The focused keyboard test also passed with mouse support disabled and confirmed that setting remained unchanged.
- Headless Neovim smoke passed. Real Chromium/Neovim integration: 25 checks passed, including both window widths changing and a newly positioned 420x580 SIXEL browser frame after dragging the divider. Existing source navigation, review persistence, Save for Codex, verified highlights and quit remain covered. Inspected the browser snapshot.
- Canonical guide PDF/HTML and rendered control wording, generated docs, scoped ESLint/Prettier, Python syntax, strict OpenSpec validation and diff whitespace checks passed.
- The user confirmed Reader operation after upgrading Windows Terminal from 1.18. This divider enhancement has not yet been exercised on their physical Windows Terminal/Devtunnel path. No user editor configuration, installation or live service was changed.

## 14. Avoid statusline refresh flicker

- [x] 14.1 Reproduce competing Reader/lualine statusline writes in an isolated editor; update feedback only on content changes and scope image invalidation to Reader-buffer redraws.
- [x] 14.2 Verify external statusline refreshes, new feedback, delayed loading, full Reader redraws and existing TUI/browser interactions; align the guide and record physical coverage separately.

### Statusline flicker verification, 2026-10-22

- Reproduced the user's local lualine/global-statusline combination in a disposable Neovim TUI without loading or changing their full configuration. Before the fix, lualine and unchanged Flow Reader controls alternated six times over three seconds, with six redundant image transmissions. After the fix, the same idle interval had zero statusline changes, image transmissions or output bytes.
- Twenty-seven isolated Neovim TUI scenarios passed. New coverage exercises an external statusline refresh timer, unchanged/new feedback, statusline-only and source-only redraws, full Reader redraw recovery, delayed loading ticks/first image and preservation of source status, global status mode and unsaved source text. A focused delayed-frame check passed after fixture formatting.
- Headless Neovim smoke and 25 real Chromium/Neovim integration checks passed, including divider resizing, current frame placement, browser input, source navigation, review persistence, Save for Codex and verified source highlights.
- Canonical guide PDF/HTML, rendered wording, generated docs, strict OpenSpec validation, Python syntax and diff whitespace checks passed. This change adds no dependency on lualine and does not modify user configuration, install a release or restart a live service. Physical Windows Terminal/Devtunnel flicker remains separate coverage.
