# Optional Neovim Reader integration

## Read

Read [the architecture source map](../../docs/tinymist/dev/reader-architecture.typ), [the terminal guide](../../docs/tinymist/dev/terminal-reader.typ) and `openspec/changes/add-terminal-reader/` from the repository root.

## Ownership

- `lua/tinymist/reader.lua` owns setup/commands, native pane lifecycle and bounded RPC operations.
- Source mapping, snapshot validation, verified source highlights and browser actions belong to the HTML Reader services/features. Reuse their policy.

## Contracts

- Do not change the user's editor configuration or replace typst-preview.nvim. Preserve unrelated buffers/services and clean up owned processes/control files.
- `apply_edit` rejects modified buffers and mismatching saved contents. Navigation uses saved one-based lines and zero-based UTF-8 byte columns; refuse uncertain positions.
- Launch argument arrays literally. Native image transport uses a supported terminal pane rather than Neovim's terminal buffer.

## Verification

From the repository root, run `nvim --headless -u NONE -i NONE -n -l tools/flow-reader/tests/neovim-reader.lua`, Python editor/terminal tests and the real terminal-browser fixture for affected boundaries. See [HTML Reader verification](../../tools/flow-reader/AGENTS.md) for prerequisites. Existing bootstrap/container tests cover other integrations separately.
