# Integration into the maintained reader architecture

## Baseline and ownership

Ported the 21 original local functional items from the pre-refactor checkout into the existing `refactor/reader-architecture` branch at `e9c2b2b2`. Original source was archived with a SHA-256 manifest before editing. Agent configuration links/YAML and three untracked engine icons remain local-only.

| Original responsibility | Maintained owner |
| --- | --- |
| terminal.mjs options and stable identity | terminal/options.mjs |
| owned Reader process | terminal/service.mjs |
| persistent browser and readiness | terminal/browser-session.mjs |
| editor RPC/navigation client | terminal/editor-bridge.mjs |
| terminal input/image loop | terminal/host.mjs |
| input/graphics encoding | terminal/protocol.mjs |
| startup/shutdown composition | terminal/cli.mjs, supported terminal.mjs launcher |
| editor.py read-only mapping | existing flow_reader/services/source_mapping.py, shared with Codex |
| editor-owned verified writes | flow_reader/services/editor_sync.py and existing source_highlight/selection services |
| source/cursor freshness orchestration | flow_reader/services/navigation.py |
| server state/routes/arguments | existing flow_reader/server modules |
| browser selection/action/follow hooks | existing selection/source-highlight controllers and features/editor-sync/terminal-bridge.js |
| editor commands/pane lifecycle | editors/neovim/lua/tinymist/reader.lua |
| tests, canonical guide, OpenSpec | original feature files retained with package/module imports updated |

All 14 original terminal function/class bodies were compared by TypeScript tokens after splitting, with no body changes. The 13 editor tests and 18 source-highlight tests are preserved. Original Neovim Lua and canonical terminal guide bytes are unchanged. No obsolete flat Python implementation or separate terminal annotation store was restored.

## Validation

- Full real-Typst Reader Python suite: 136 tests; 135 passed, one optional external Tail Hosting-source test skipped.
- Final shared/HTML/terminal Node suite: 110 passed, including opt-in bridge, stale follow/disposal, editor capability and actual request payload tests.
- Final paged Vitest: 82 passed in 11 files. Paged implementation was unchanged.
- POSIX terminal lifecycle: 7 passed, including raw-mode restoration, resize/capture ordering, parent/control-file cleanup and owned compiler process groups.
- Standalone headless Neovim module smoke passed. The editor suite includes actual Neovim RPC, dirty-buffer refusal and verified saving.
- Real persistent Chromium + HTML service + disposable Neovim: 21 checks passed, including source/cursor navigation, active-selection/dialog/stale follow guards, review persistence, shared Saved for Codex, editor identity in the actual HTTP request, dirty-buffer refusal and source/buffer updates together. No page errors. The emitted Reader PNG was visually inspected.
- Installed-layout test passed after adding terminal CLI and archived service-path checks. It still serves and checks every first-party/shared asset and rejects undeclared paths.
- Actual supported `terminal.mjs --check --protocol kitty` with the optional Playwright module launched and closed Chromium successfully.
- Typst PDF/HTML checks passed for the terminal guide and integrated architecture guide. Generated-doc consistency, Python syntax, owned-file Prettier, OpenSpec strict validation and diff whitespace checks passed.

## Issues caught and resolved

The copied browser fixture had one obsolete dynamic math-module import; it now uses the relocated renderer. Installed CLI testing exposed symlink/canonical-path detection suppressing the launcher; terminal.mjs is now a dedicated entrypoint and the same installed-layout test passes. Final source review found that the terminal editor identity also needed forwarding through the extracted source-highlight controller; a controller regression test and an assertion on the real browser HTTP request now verify it reaches the server. Configured-editor checks remain enforced at request time and immediately before the final verified write.

## Limits

Current validation used headless Chromium, POSIX PTYs and disposable Neovim sessions. The earlier native iTerm2 checks above are historical; native iTerm2 UI, Windows image delivery, physical iOS and live installed service changes were not repeated. This integration does not install or restart the user's Reader/app services.
