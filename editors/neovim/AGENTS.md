# Optional Neovim Reader integration

Read root AGENTS, `docs/tinymist/dev/reader-architecture.typ`, the terminal Reader guide and `openspec/changes/add-terminal-reader/` before editing.

- `lua/tinymist/reader.lua` is the optional editor adapter: setup/commands, owned native pane lifecycle and bounded RPC operations. Do not change the user's editor configuration or replace typst-preview.nvim.
- Reader source mapping, snapshot validation, verified source highlights and browser actions belong to the HTML Reader services/features. Do not duplicate that policy in Lua.
- `apply_edit` must reject modified buffers and mismatching saved contents. Navigation uses saved one-based lines and zero-based UTF-8 byte columns; refuse uncertain positions.
- Launch argument arrays literally, clean up owned processes/control files and preserve unrelated editor buffers/services. Native image transport runs in a supported terminal pane rather than Neovim's terminal buffer.
- Run `nvim --headless -u NONE -i NONE -n -l tools/flow-reader/tests/neovim-reader.lua`, Python editor/terminal tests and the real terminal-browser fixture for affected boundaries. Existing bootstrap/container tests cover other integrations separately.
