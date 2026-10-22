# Proposal

## Why

Neovim users need to read and annotate the existing HTML Reader alongside their source inside a terminal window. Keeping the browser document alive preserves mathematical layout, source highlights and local review marks.

## What Changes

- Add a terminal host that renders the existing Reader through Chromium and sends PNG frames to iTerm2 or a compatible graphics terminal, with real browser input and persistent document storage.
- Add an opt-in Neovim module that opens an owned native terminal pane and connects source navigation without changing the user's editor configuration.
- Add conservative, revision-checked source navigation and route verified highlight writes through the connected editor so modified buffers remain protected.
- Replace the mistaken local quotation action with the shared HTML Save for Codex contract, retaining legacy data without migration.
- Document setup, keyboard controls, supported terminal hosts and navigation limits.
- Add native SIXEL frames for Windows Terminal and an editor-owned session command for a second remote terminal connection, without requiring iTerm2 or replacing PowerShell.
- Make the default Neovim start open an internal right-hand Reader view in the same terminal connection, forwarding browser input and positioned image frames through the editor's TUI. Keep native panes and manual attachment as explicit alternatives.
- Show animated loading feedback and elapsed time in the Reader window's statusline until its first current image is ready.
- Preserve native Neovim divider dragging and expose window-width controls from Reader input mode, keeping browser selections separate from editor gestures.
- Pause an already loaded lualine statusline while the Reader is focused and restore it when focus returns to source or the Reader closes.

## Capabilities

### New Capabilities

- `terminal-reader`: interactive terminal delivery of the HTML Reader with editor navigation and safe source edits.

### Modified Capabilities

None. Existing paged preview and mobile Reader behavior remains the default.

## Impact

`tools/flow-reader/`, the optional Neovim module, and canonical Typst developer documentation. Playwright and Chromium are optional runtime prerequisites; existing dependency pins and installed services are unchanged.
