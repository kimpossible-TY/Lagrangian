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

- Share the paged engine's project-scoped saved source edit with HTML/terminal Readers and opt-in Neovim source restoration. Resolve one exact project/entry and validate saved source before navigation.
- Move source-edit observation and persistence into the common Rust project service. HTML-only sessions use the same bounded source policy and serialized record transactions as paged previews, including failed compilations and concurrent processes.

## Capabilities

### New Capabilities

- `terminal-reader`: interactive terminal delivery of the HTML Reader with editor navigation and safe source edits.

### Modified Capabilities

Project source-edit history becomes renderer-independent; existing paged coordinates and HTML navigation guards remain with their adapters.

## Impact

`tinymist-project`, paged preview history, the engine CLI, `tools/flow-reader/`, the optional Neovim module, and canonical Typst developer documentation. HTML service startup requires an engine supporting `source-history`; the HTML compiler remains independently configurable. Existing dependency pins and installed services are unchanged.
