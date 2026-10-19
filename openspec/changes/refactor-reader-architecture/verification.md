# Refactor verification

## Scope and ownership

Implementation starts at origin/main `262d7554`, on `refactor/reader-architecture` in an isolated managed worktree. The original checkout's uncommitted terminal/Neovim work is preserved separately. Existing Saved for Codex integration is the behavior baseline.

Shared reader policy is now in `tools/reader-common`. Concrete paged and HTML feature modules own native geometry, invalidation, transport and paint. Python service implementation lives in `flow_reader/{compiler,document,rendering,services,server}` with supported executable launchers retained. Project compiler and native app are split by responsibility with their public contracts preserved.

## Automated evidence

- `FLOW_READER_PACKAGES=".../typst/packages" PYTHONDONTWRITEBYTECODE=1 npm run test:readers`: integrated shared/HTML Node, Python and paged Vitest gate passed. Python: 113 tests, 112 passed and 1 optional external Tail Hosting-source check skipped. Paged Vitest: 82 passed. Final shared Node: 9 passed; HTML Node: 83 passed (92 total).
- Reader installation test archives both reader trees into a new clean Git fixture, runs the installed manager and supported CLI launchers outside the checkout, serves all manifest assets over HTTP and verifies relative module imports resolve in the archive. Static serving also rejects undeclared/traversal paths and checks vendor hashes/caching.
- `RUSTFLAGS=-Dwarnings cargo test -p tinymist-project --locked`: 21 tests and doc-tests passed.
- `RUSTFLAGS=-Dwarnings cargo clippy -p tinymist-project --all-targets --locked -- -D warnings`: passed.
- Warning-denying `cargo check -p tinymist --lib --no-default-features --features system,no-content-hint --locked` and `system,preview,no-content-hint`: passed after rebuilding preview assets.
- `cargo fmt --check --all`: passed.
- `python3 -m unittest discover -s tests/flow-app -v`: 37 tests, 31 passed and 6 optional external-engine checks skipped in the default run. Isolated service and source-manifest tests passed independently in review.
- With an explicit installed engine, `test_bundle.ExternalEngineBundle.test_preview_delivers_both_themes_through_configured_origin` passed: temporary app compilation, signing/manifest verification and actual light/dark document delivery through the configured origin.
- `tsc --noEmit` for the paged frontend and `node scripts/build.mjs build:preview`: passed.
- Both research probe CLIs generated a corpus from a disposable one-equation document and copied their relocated renderer dependencies successfully.
- `node scripts/link-docs.mjs --check`, architecture Typst PDF/HTML compilation and HTML heading inspection: passed. No generated Markdown was hand-edited.
- `openspec validate refactor-reader-architecture --strict` and `git diff --check`: passed.

## Browser evidence

The source-backed selection-action suite passed 152 checks in WebKit and Chrome at 320, 390 and 768 CSS pixel widths against the final HTML modules, without page errors. It verifies real source highlights, mathematical selection, Saved for Codex records, local strikes/undo/reflow/reload, stale selection acknowledgments and retry behavior. The reading-navigation fixture passed 35 checks per browser (70 total), including outline and touch navigation. WebKit used the fixture's Event/plain-contact fallback because its Touch constructor is unavailable; Chrome used the native constructor path. These are automated browser checks, not physical-device validation.

## Independent review

Two independent reviewers compared Python state/selection/dynamic-render bodies and Rust event/ticket/cache flow against the original, and reviewed Swift lifecycle/rollback, source-list packaging and both shared-policy consumers. Review found one management CLI exception-boundary regression; it was fixed and covered by subprocess tests for invalid arguments and missing configuration. Re-review found no remaining actionable regression.

## Limits

No user app installation, real LaunchAgent mutation, manual AppKit clicking or physical assistive-device testing was performed. The browser/engine checks use disposable projects and temporary bundles. Existing external Tail Hosting patches were not changed.

## Main integration

Verified implementation commit `d6df2694` was pushed on `refactor/reader-architecture` and fast-forward merged from origin/main `262d7554` into remote main. `git ls-remote --heads origin main refactor/reader-architecture` confirmed both remote refs at the implementation commit before this verification-only bookkeeping commit. The managed worktree is clean; hashes confirm all 28 original-checkout modified/untracked files remain unchanged. The original checkout's local main is deliberately left at its prior commit with its dirty work intact; remote main and the managed refactor branch contain the verified refactor.
