# HTML and terminal Reader

## Read

Use [the architecture source map](../../docs/tinymist/dev/reader-architecture.typ) for file ownership and [the terminal guide](../../docs/tinymist/dev/terminal-reader.typ) for native integration.

## Ownership

- `flow_reader/compiler/` owns inputs/signatures/fingerprints, overlays and isolated/incremental compilation; `audit.py` owns content acceptance policy.
- `document/` owns normalization and block/section identities; `rendering/` owns validated geometry, workers and bounded caches.
- `services/` owns source validation/mapping, context records, navigation and service lifecycle. `accepted_snapshot.py` owns captured source-input freshness; callers retain lock ordering and action-specific responses. `server/` owns accepted publication, watcher, HTTP and static delivery.
- `web/features/` owns semantic DOM adapters; `web/rendering/` owns HTML mathematics, figures and annotations. Keep executable Python launchers thin.
- `terminal/` owns options, started service, browser, editor bridge, native host and protocol. Keep `terminal.mjs` supported and reuse HTML actions/storage. `web/features/editor-sync/terminal-bridge.js` exposes opt-in editor capabilities; source-write checks remain in Python services.

## Contracts and delivery

- Failed compilation preserves the accepted document. Keep snapshot/source guards and lock ordering around source operations and asynchronous publication.
- `web/assets.json` explicitly lists served first-party files. Vendor assets use their separate manifest. Never serve arbitrary filesystem paths or auto-discover public assets.
- `web/reader-common` links shared sources; `install.py` must package both trees with the same relative layout. Do not hand-edit vendor/generated bundles.

## Verification

Commands run from the repository root:

- Browser policy/adapters: `node --test tools/flow-reader/tests/test_*.mjs`.
- Python services and installed layout: `yarn test:reader-services`. Installation tests require macOS.
- Required Python integration: set `FLOW_READER_PACKAGES`, `TAIL_HOSTING_SOURCE` (companion source checkout) and optionally `FLOW_READER_TYPST`, then run `yarn test:reader-integration`. This mode fails on missing prerequisites or skipped tests; it also needs macOS and Neovim for the full suite.
- Shared changes: `yarn test:readers`; frontend code: `yarn lint:readers`.
- Terminal editor: `nvim --headless -u NONE -i NONE -n -l tools/flow-reader/tests/neovim-reader.lua`.
- Real Chromium/Neovim integration: `node tools/flow-reader/tests/terminal-browser.mjs` with `FLOW_READER_PLAYWRIGHT_MODULE` and `FLOW_READER_PACKAGES` set. Use the affected browser fixture in `tests/` for HTML interactions. Native terminal and physical-device checks are separate coverage.
