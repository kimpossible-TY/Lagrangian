# Design

## Context

The saved-file Reader uses semantic HTML, browser DOM selections, HTTP APIs and origin-local storage. It has no compiler source map or Neovim control channel. Source highlighting already verifies an isolated HTML and PDF compilation before replacing a file. The user uses iTerm2 and PowerShell.

## Goals / Non-Goals

**Goals:** reuse the existing Reader and annotation implementation, deliver an interactive Reader beside source in the same Neovim terminal connection or an explicit native pane, preserve marks across launches, and protect unsaved editor changes.

**Non-Goals:** adding image decoding to Neovim's terminal emulator, claiming arbitrary terminal compatibility, importing upstream plugin code, or inventing source positions for generated mathematical content. No installed app release is part of this change.

## Decisions

### Keep a real persistent browser document

Use an optional Playwright Chromium runtime and a dedicated browser profile. Screenshot the viewport, display PNG frames using terminal graphics and translate terminal input into browser mouse and keyboard events. Existing JS performs layout, selection, highlights and strikes. A text-only conversion or periodic static screenshot without input would discard those behaviors.

Use Kitty graphics by default on compatible terminals, including the verified iTerm2 3.7.4. Legacy iTerm2 inline images remain an explicit backend; their file-display confirmations are not appropriate for automatic live frames. Query iTerm2 logical cell points through ReportCellSize rather than its whole-window pixel response, or accept cell-size overrides. Keep browser and image geometry equal, discard obsolete frames on resize, and restore terminal modes on exit. A native iTerm2 split avoids tmux passthrough and Neovim terminal-emulator limitations. Process arguments are arrays; PowerShell is a shell, and the containing terminal must support the chosen image protocol.

### Preserve storage identity and lifecycle

Connect to a configured stable Reader URL or start an owned Reader process at an explicit stable port. Never migrate to an arbitrary available port silently, because localStorage belongs to an origin. Use a dedicated persistent browser profile, never the user's normal Chrome profile. Editor shutdown and explicit stop terminate owned processes; connecting to an existing Reader does not stop it.

### Add an opt-in browser bridge

Expose selection and follow operations only for terminal-mode pages. Return the existing canonical selected fragments and use normal section loading/reading anchors for navigation. Keep active selections and open dialogs intact during automatic follow.

### Navigate conservatively

HTTP source/cursor endpoints validate the accepted revision and saved source snapshot. Uniquely matched literal prose and headings can navigate in either direction. Ambiguous, generated, mathematical and unsupported source regions report unavailable instead of guessing. Coordinates are one-based lines and zero-based UTF-8 byte columns, matching Neovim. A future compiler map can broaden coverage without changing terminal presentation.

### Let the editor own final source mutation

An optional CLI-configured Neovim server receives a verified edit only after existing compiler checks. Its Lua handler compares the current disk contents and loaded buffer with the original, rejects modified buffers, and performs the save. Terminal highlight requests assert the expected configured editor at request time and final save, so restarting a service at the same origin cannot turn them into standalone writes. The HTTP request cannot choose an executable or editor server. Standalone Reader writes retain their existing implementation.

## Risks / Trade-offs

- Frame encoding and transport can be expensive → cap redraw rate, avoid overlapping captures, and skip unchanged frames.
- Mouse cell coordinates limit selection precision → use measured geometry and forward real selection gestures; retain browser toolbar and keyboard controls.
- No compiler source map → report navigation coverage explicitly and test ambiguity, Unicode and stale snapshots.
- Reader processes can race external edits → retain source freshness checks and use editor-owned final mutation.
- Terminal protocol behavior differs → test encoded frames and actual browser functions separately, record any unverified native terminal path.

### Windows Terminal and remote PowerShell sessions

Windows Terminal displays SIXEL images; PowerShell remains the shell. Add an explicit `sixel` backend and detect local Windows Terminal environment markers. A remote connection may omit those markers, so `--protocol sixel` remains available. Decode only Chromium's noninterlaced 8-bit RGB/RGBA screenshot PNGs with Node's existing zlib runtime, then encode bounded six-row color planes and runs. Derive up to 216 colors from a bounded 5-bit screenshot histogram using weighted median cuts, retaining 40 grayscale levels for text. The previous fixed six-level RGB cube mapped gold highlights to pink/red; palette selection must preserve screenshot colors without importing or duplicating HTML theme policy. Unsupported PNG formats fail explicitly. Keep the same browser viewport, input translation, storage and source actions, and use a lower default capture rate for SIXEL.

An SSH session on the Mac cannot directly invoke the Windows client's pane launcher. Keep explicit `open = "manual"` for users who prefer another terminal connection; the default same-connection view is described below. In manual mode, `:FlowReader start` or `:FlowReader prepare` creates a private, versioned argument manifest and prints a shell-appropriate command to run in a second connection to the same Mac. The manifest is also the existing lifecycle control file: both connections use the editor's RPC address, process identity, stable profile and service options. The CLI accepts `--session` with presentation-only overrides, never executes a command from that file, and removes the manifest on renderer exit. `:FlowReader stop` and editor exit remove it, stopping any attached host through the existing ownership checks. Repeating start while prepared shows the command again. Only this explicit alternative requires the user to open the Windows pane and reconnect; no remote-to-local command execution channel is introduced.

Protocol/PTY tests validate pixel output, input ordering and owned cleanup independently of a physical Windows terminal. Real Chromium tests validate the screenshot codec and existing Reader behavior; Windows Terminal over the user's particular Devtunnel transport remains a separate manual check.

## Migration Plan

### Same-connection Neovim view

Default `:FlowReader start` opens a right-hand Neovim split. Neovim 0.12's `nvim_ui_send` writes positioned native frames to its attached TUI; the internal terminal buffer supplies raw Unicode, paste and mouse input only. No image bytes enter Neovim's terminal emulator. Buffer-local window-navigation maps return to source. Explicit `open = "native"`, native opener arrays and `open = "manual"` retain their existing delivery paths; SSH no longer selects manual attachment implicitly.

Separate the browser interaction/session controller from its native and editor transports. Both adapters reuse the same viewport, input, screenshot, source bridge and ownership logic. The editor transport uses versioned newline JSON over owned job pipes, acknowledges each presented frame for bounded backpressure, and tags layout generations so obsolete frames cannot paint a resized or hidden view. Lua owns window position, visibility, clearing, focus and repaint; source RPC continues using the source window while the Reader is focused. Closing the window, stopping or exiting disposes the owned job and restores editor display.

Let Neovim own divider resizing and source-window mouse gestures. Forward a left-button drag/release to the browser only when its press began inside the visible Reader document, retaining that ownership when the pointer crosses the divider. A press on the divider or source must not become a browser gesture when it later enters the Reader. Reuse the existing layout generation and repaint path after native window resizing. Add buffer-local terminal-mode `Ctrl-W <`, `Ctrl-W >` and `Ctrl-W =` mappings for native width/equalize controls without changing global mouse options or user mappings outside the Reader.

The view owns startup feedback in its existing window statusline. Reuse its update timer for an ASCII spinner and elapsed loading time, without estimated percentages or new transport messages. Keep loading visible through the host handshake and status-only or obsolete frames; switch to the existing Reader controls only when a current visible image is accepted. Closing the view disposes the same timer, and completed views retain idle frame suppression.

Update the Reader statusline only when its generated message changes, rather than comparing it with the option currently owned by a statusline plugin. A plugin can replace unchanged Reader feedback without the next periodic frame replacing it again. Loading ticks and new feedback still update normally. Observe redraws of the Reader buffer ranges to invalidate its image; a statusline-only or unrelated source redraw must not retransmit that image. Keep full Reader redraw, layout invalidation and cleanup behavior intact without requiring a statusline plugin.

For an already loaded lualine, hand statusline ownership over with its public `hide`/`unhide` API, limited to the statusline place. Pause it while the current window still contains the owned Reader buffer, restoring the cached Reader feedback after lualine restores its saved window options. Preserve the current `laststatus` layout across hiding. On source/other-window or tab focus, buffer replacement, close and launch failure, unhide and refresh lualine once against the new current window. Keep this lifecycle in the existing view owner, leave tabline/winbar and lualine configuration unchanged, and do not load or require lualine for users without it. Other statusline plugins retain the unchanged-message behavior above.

Keep terminal input and shell foreground ownership entirely with Neovim. Suspending its TUI client makes an interactive shell reclaim the foreground terminal even if another process sends SIGCONT later; direct-launch PTY fixtures missed this failure. Remove the independent TTY probe. `reader_terminal.lua` queries DA1, Kitty graphics and OSC cell reports using `nvim_ui_send` and bounded `TermResponse` callbacks, disposing the callback on every exit. No input-client signals, raw TTY reads or termios changes are needed.

Windows Terminal's recognized DA1 feature set identifies its default SIXEL virtual grid of 10x20 pixels per cell, independent of physical font pixels and placeholder SSH ioctl sizes. Compare required features rather than exact strings, permitting additional/reordered capabilities. Reject other SIXEL profiles with unknown geometry. Retry a lost or delayed query once after 1.5 seconds, with a further 2.5-second reply budget; cancellation never retries. Positive Kitty replies and explicitly requested iTerm cell reports do not depend on DA1. Failures report received capability information instead of conflating missing replies and unrecognized responses.

Retain a confirmed Windows grid only for the current attached UI channel, reusing it on restart/resize and invalidating it for another UI. Kitty logical dimensions still refresh after resizing. Select cursor-relative SIXEL placement and preserve the editor cursor; do not claim to restore an unobservable custom DECSDM mode. Kitty uses OSC logical cell dimensions where available, otherwise a 9x18 logical viewport scaled by its explicit row/column placement. Browser mouse coordinates use the same viewport. Reject missing required capabilities before painting. Real PTY tests must run under an interactive shell and verify foreground ownership for command startup, input, errors, timeout and restart. Physical Windows/Devtunnel remains separate coverage.

Install optional runtime prerequisites, load the Neovim module explicitly, and use a disposable document first. Stopping the module removes only its owned processes. Removing the module restores the previous workflow; existing source highlights and browser profiles remain available.

### Share explicit Codex context with the web Reader

The terminal action bridge's `save` invokes the same Save for Codex button and
HTTP action as the browser. Its owned service defaults to `OUTPUT/focus.json`;
connecting to an existing Reader uses that service's record. Read with the explicit
loopback URL through `focus.py`, or the managed profile's `--focus ID`. Browser
storage retains review strikes, appearance and reading position; legacy quotation
data is left untouched and has no library, repaint, relocation or migration path.

## Integration after the reader refactor

Continue this change on the existing refactor/reader-architecture branch. Source/cursor mapping extends the existing flow_reader.services.source_mapping owner used by Codex. Neovim RPC writes belong in services.editor_sync; saved snapshot navigation belongs in services.navigation. Source mutation remains in source_highlight and selection. Terminal execution is split into options, service lifecycle, browser session, editor bridge, native input/image host and CLI under tools/flow-reader/terminal/, with terminal.mjs retained as its executable launcher. The browser bridge belongs in web/features/editor-sync/ and delegates existing HTML selection actions and section navigation. Common policy stays renderer-independent; terminal clients do not gain a separate annotation implementation.

Archive the 21 original functional files before porting. After verified main integration, remove only hash-matching superseded originals and fast-forward the original checkout's local main; leave local-only agent configuration and untracked engine icons intact. Record current validation separately from the earlier uncommitted implementation's historical checks.

## Shared source edit restoration

The common Rust `tinymist-project::source_history` service owns saved-edit policy and persistence in the compatible schema-2 change record. It observes saved changes independently of palette layout and reader type. Project-scoped advisory locking serializes every reload, source observation, variant update and atomic replacement across processes; paged readers must not retain authoritative copies of the record in memory. Do not infer chronology from Git, browser scroll positions or ShaDa. Python `services/edit_location.py` resolves an explicit change-file or one exact root/entry match in Flow profiles, validates bounded record/source bytes and UTF-8 ranges, and exposes a small local CLI result for Neovim. The stored source text must equal current disk bytes; source hashes returned to editor RPC use its existing SHA-256 contract. Profile ambiguity, wrong project, corrupt records and stale sources never select another project.

HTML publication maps the same source range through accepted source carriers, falling back to the existing conservative cursor mapper only when no carrier covers it. Keep renderer targets and section mounting with the HTML adapter. Remove the independent HTML visual-history chronology. A stale or unmapped common edit never selects a different local edit. Refresh common navigation metadata when the shared record arrives after an HTML compile, without recompilation or changing the accepted content revision. Browsers observe a separate change token while retaining explicit-link, gesture and selection guards.

Compiler-only invocation carriers also bind complete matching callout/figure containers into private navigation ranges. They preserve title, unwrapped body and native figure argument navigation after removing visual chronology. These ranges do not authorize selection, source highlighting or editor cursor mapping; repeated or independent competing output is rejected. Only accepted anchor IDs and revision-bound navigation metadata reach the browser, never source paths or compiler carriers.

Neovim exposes `:FlowReader resume` without requiring a Reader window. Optional `restore_last_edit` restores once when the configured entry opens, including opening its last edited included source file. Resolve asynchronously and preserve buffers, explicit startup destinations, cursor movement and edits made while lookup is in flight. Reuse the existing guarded source jump. Local marks remain the fallback when no verified shared position is available. The terminal bridge treats its first cursor sample as a baseline so it cannot override the shared restored destination; actual cursor movement and explicit sync retain normal behavior.

Managed Flow discovery honors `FLOW_DATA_DIR`; explicit `change_file`/`--change-file` supports existing records. Managed HTML services receive the parent's exact change-file path from its launch plan, preserving nondefault data directories across launch environments. Standalone native previews and HTML services use the same Rust-derived deterministic project record when no managed record is selected. A thin Python client invokes the engine's bounded `source-history` command from the existing HTML file watcher before compilation, then registers exact source snapshots only after stable successful compilation. The command reuses the project service and preserves paged variant payloads. It does not lay out a document, start a background daemon or duplicate source policy in Python. Engine discovery is separate from Typst compiler selection, with explicit engine configuration and a capability check; unavailable or incompatible engines report an actionable error instead of silently using divergent history. Observations occur while either reader service is running, including with no browser viewers. When all services stop, the next observation can compare saved contents but cannot recover exact chronology of multiple unobserved saves. Tests use disposable profiles, records, documents and editor processes; no live service installation or restart is part of development verification.
