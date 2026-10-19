# Reader feature development

Read `../docs/tinymist/dev/reader-architecture.typ` and matching OpenSpec contracts before changing reader behavior. This file applies to tools; Rust/editor implementations follow the same protocol contracts under their own directories.

## Current ownership

- `reader-common/`: shared selection submission state, bounded review persistence and change-location queue. It imports no concrete reader and uses native ESM with declaration files for TypeScript consumers.
- `typst-preview-frontend/src/features/`: paged reader selection, review strikes, navigation, appearance, editor synchronization and connection/session behavior. Page geometry and engine transport remain local.
- `flow-reader/web/features/`: semantic DOM selection, review paint, navigation, appearance and section/session behavior. `web/rendering/` owns HTML-specific math, figures and annotations.
- `flow-reader/flow_reader/compiler/`: project inputs, package overlay, isolated/incremental compilation and one content audit/diagnostic policy.
- `flow-reader/flow_reader/document/`: exported HTML normalization, block/passages and section identities.
- `flow-reader/flow_reader/rendering/`: validated geometry, dynamic worker and bounded rendering caches.
- `flow-reader/flow_reader/services/`: source highlight, source mapping, Codex context, change history and managed service lifecycle.
- `flow-reader/flow_reader/server/`: accepted document publication, watcher, HTTP routes and static delivery.
- `flow-reader/terminal/`: terminal-specific options, service ownership, persistent browser, editor bridge, native input/image host and protocol. `terminal.mjs` remains the supported launcher; reuse HTML Reader actions and storage.
- `flow-reader/web/features/editor-sync/terminal-bridge.js`: opt-in selection/follow adapter and configured-editor capability; keep snapshot/source-write checks in Python services.
- `flow-reader/{build,serve,manage,focus}.py`: supported executable launchers; keep implementation in the package.

## Add or extend a feature

1. Classify it under selection, source-highlight, codex-context, review-strikes, editor-sync, navigation, appearance or session. Introduce another owner only when existing responsibilities do not fit.
2. Read implementations in each affected reader. Put matching policy/state in the shared layer and renderer differences in concrete adapters. Do not copy a controller into another reader.
3. Define input/output, unsupported capability, failure/stale handling and disposal. Use adapters for actual differences; do not accumulate reader-type conditionals in common code.
4. Preserve native positions: page coordinates and semantic DOM block offsets are different contracts. Never invent coordinates to satisfy an unrelated renderer's interface.
5. Keep document/revision/service validation on asynchronous results and source operations. An older response must not dismiss a newer selection or paint a newer document.
6. If shared contracts or ownership change, update the source map and applicable tests in the same change.

## Distinct action effects

- Source Highlight changes verified Typst source after candidate validation.
- Saved for Codex records only the explicitly selected context. It does not send messages or start an assistant turn.
- Review Strike is browser-local paint with undo/clear and existing storage keys. It does not edit source.
- Retired quotation storage stays untouched; do not reintroduce a parallel quote library or automatically migrate it into Codex context.

## Dependencies and delivery

- Shared modules must not import concrete readers; concrete readers must not import each other's internals. Do not add import cycles.
- Use actual existing consumers to justify abstractions. Keep geometry, DOM selection and protocol transport local where their semantics differ.
- `flow-reader/web/reader-common` links the shared source tree for native ESM resolution. `install.py` archives both directories so the same layout works after installation.
- Add every served frontend file to `flow-reader/web/assets.json`. Vendor files remain in their separate reviewed vendor manifest. Never serve arbitrary filesystem paths or auto-discover public files at runtime.
- Do not hand-edit vendor or generated bundles. Update source and run the existing build.

## Verification

- Full reader gate: `yarn test:readers` (shared/HTML Node, Python service/install and paged Vitest). Set the real-compiler environment below to include compiler fixtures.

- Shared policy: `node --test tools/reader-common/tests/*.mjs`.
- HTML browser modules: `node --test tools/flow-reader/tests/test_*.mjs`.
- Python service/install: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tools/flow-reader/tests`.
- Real compilation: set `FLOW_READER_PACKAGES` and optionally `FLOW_READER_TYPST` for the same suite.
- Paged frontend: `yarn workspace typst-preview-frontend test run` and `node scripts/build.mjs build:preview`.
- Run shared tests plus each affected reader's integration tests when changing shared behavior. Moving assets also requires the installed-layout test.
- Terminal integration: `nvim --headless -u NONE -i NONE -n -l tools/flow-reader/tests/neovim-reader.lua`; run `node tools/flow-reader/tests/terminal-browser.mjs` with `FLOW_READER_PLAYWRIGHT_MODULE` and `FLOW_READER_PACKAGES` for the real Chromium/Neovim check. Native iTerm2 and physical-device checks are distinct.
- Report feature owner, reused implementation, renderer differences and validation. Do not claim skipped device/browser checks passed.
