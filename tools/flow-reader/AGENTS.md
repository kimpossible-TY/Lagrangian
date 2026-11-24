# HTML and terminal Reader

## Read

Use [the architecture source map](../../docs/tinymist/dev/reader-architecture.typ) for file ownership and [the terminal guide](../../docs/tinymist/dev/terminal-reader.typ) for native integration.

## Ownership

- `flow_reader/compiler/` owns inputs/signatures/fingerprints, overlays and isolated/incremental compilation; `audit.py` owns content acceptance policy. `source_map.py` emits `reference` carriers for `@label` references while opaquely skipping `canvas`, `<ident>.canvas`, `html.frame` calls and Typst code keywords (`let`, `set`, `show`, `if`, `for`, `while`, `import`, `include`, `context`).
- `document/` owns normalization and block/section identities; `passages.py` (`PassageIndex`) tracks `equation_number_ranges` / `in_equation_number` so `PassageIndex`, `CarrierPassages` and `MarkedPassages` share identical excluded-block, nested-tag and void-tag `.flow-equation-number` exclusion; `rendering/` owns validated geometry, workers and bounded caches.
- `services/` owns source validation/mapping, context records, navigation and service lifecycle. `accepted_snapshot.py` owns captured source-input freshness; callers retain lock ordering and action-specific responses. `server/` owns accepted publication, watcher, HTTP and static delivery.
- `services/source_history.py` transports observations to the Rust project owner and disposes only its own engine helpers. Keep edit chronology out of Python. Compiler-verified navigation-only container ranges remain separate from selection/highlight mappings and served metadata.
- `web/features/` owns semantic DOM adapters; `web/rendering/` owns HTML mathematics, figures and annotations. Keep executable Python launchers thin.
- `services/manager.py` owns exact managed HTML service resolution, launch settings and local editor registration. `services/editor_sync.py` owns private service-bound editor attachments and verified Neovim delivery. Terminal hosts never construct compiler launch plans or dispose shared services.
- `terminal/` owns presentation options, manager attachment, browser, editor bridge, shared input/capture controller, native/editor transports and protocol. Neovim owns internal-view capability queries and layout. Keep `terminal.mjs` supported and reuse HTML actions/storage. `web/features/editor-sync/terminal-bridge.js` exposes opt-in editor capabilities; source-write checks remain in Python services.

## Contracts and delivery

- Failed compilation preserves the accepted document. Keep snapshot/source guards and lock ordering around source operations and asynchronous publication.
- `web/assets.json` explicitly lists served first-party files. The exact `web/preview-proxy.js` bridge is an exception, served only at its fixed route under a registered preview prefix. Vendor assets use their separate manifest. Never serve arbitrary filesystem paths or auto-discover public assets.
- A verified reader bundle (`reader-bundle.json` beside `tools/flow-reader`) installs as release `headSha` with `--engine` and does not need a git checkout. `install.py` sets `sys.dont_write_bytecode` before importing `flow_reader`, then checks the copied trees against the manifest. `scripts/fetch-reader-bundle.py` verifies the bundle before that install and does not launch the reader. The Mac launchd updater (outside this repository) installs the reader from this verified bundle for each successful `main` run.
- `web/reader-common` links shared sources; `install.py` must package both trees with the same relative layout. Do not hand-edit vendor/generated bundles.
- Selection bounds: HTML (`web/features/selection/controller.js`, `services/source_highlight.py`) and Native Reader (`server/native_reader.py`) share `MAX_SELECTION_SEGMENTS=128` per fragment; browser formula excerpt prefetching in `web/features/selection/controller.js` is bounded by `MAX_PREFETCH_FORMULAS=128` and `MAX_PREFETCH_CONCURRENCY=4`.

## Verification

Commands run from the repository root:

- Browser policy/adapters: `node --test tools/flow-reader/tests/test_*.mjs`.
- Python services and installed layout: `yarn test:reader-services`. Installation tests require macOS.
- Required Python integration: set `FLOW_READER_PACKAGES`, `TAIL_HOSTING_SOURCE` (companion source checkout) and optionally `FLOW_READER_TYPST`, then run `yarn test:reader-integration`. This mode fails on missing prerequisites or skipped tests; it also needs macOS and Neovim for the full suite.
- Shared changes: `yarn test:readers`; frontend code: `yarn lint:readers`.
- Common source-history changes: set `FLOW_TEST_ENGINE` to a freshly built compatible engine and `FLOW_READER_PACKAGES` for real compiler/source-history tests. Run `tests/change-browser.mjs` for source-edit navigation and container targets.
- Terminal editor: `nvim --headless -u NONE -i NONE -n -l tools/flow-reader/tests/neovim-reader.lua`.
- Real Chromium/Neovim integration: `node tools/flow-reader/tests/terminal-browser.mjs` with `FLOW_READER_PLAYWRIGHT_MODULE` and `FLOW_READER_PACKAGES` set. Use the affected browser fixture in `tests/` for HTML interactions. Native terminal and physical-device checks are separate coverage.
