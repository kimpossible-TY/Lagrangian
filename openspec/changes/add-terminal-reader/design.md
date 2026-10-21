# Design

## Context

The saved-file Reader uses semantic HTML, browser DOM selections, HTTP APIs and origin-local storage. It has no compiler source map or Neovim control channel. Source highlighting already verifies an isolated HTML and PDF compilation before replacing a file. The user uses iTerm2 and PowerShell.

## Goals / Non-Goals

**Goals:** reuse the existing Reader and annotation implementation, deliver an interactive native terminal pane, preserve marks across launches, and protect unsaved editor changes.

**Non-Goals:** rasterizing inside Neovim's terminal buffer, claiming arbitrary terminal compatibility, importing upstream plugin code, or inventing source positions for generated mathematical content. No installed app release is part of this change.

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

Windows Terminal displays SIXEL images; PowerShell remains the shell. Add an explicit `sixel` backend and detect local Windows Terminal environment markers. A remote connection may omit those markers, so `--protocol sixel` remains available. Decode only Chromium's noninterlaced 8-bit RGB/RGBA screenshot PNGs with Node's existing zlib runtime, then encode bounded six-row color planes and runs. Use a 256-entry palette with dedicated grayscale levels for text. Unsupported PNG formats fail explicitly. Keep the same browser viewport, input translation, storage and source actions, and use a lower default capture rate for SIXEL.

An SSH session on the Mac cannot directly invoke the Windows client's pane launcher. Add `open = "manual"` and use that mode automatically for SSH sessions without an explicit native opener. `:FlowReader start` prepares a private, versioned argument manifest and prints a shell-appropriate command to run in a second connection to the same Mac. The manifest is also the existing lifecycle control file: both connections use the editor's RPC address, process identity, stable profile and service options. The CLI accepts `--session` with presentation-only overrides, never executes a command from that file, and removes the manifest on renderer exit. `:FlowReader stop` and editor exit remove it, stopping any attached host through the existing ownership checks. Repeating start while prepared shows the command again. This deliberately requires the user to open the Windows pane and reconnect; no remote-to-local command execution channel is introduced.

Protocol/PTY tests validate pixel output, input ordering and owned cleanup independently of a physical Windows terminal. Real Chromium tests validate the screenshot codec and existing Reader behavior; Windows Terminal over the user's particular Devtunnel transport remains a separate manual check.

## Migration Plan

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
