## WV01R — contract and naming

- [x] WV01R.1 Define product positioning and compatibility boundaries (under 2 hours).
- [x] WV01R.2 Align web titles, manifest and home labels; add focused branding coverage (under 2 hours).
- [x] WV01R.3 Document ownership and run focused headless verification (under 2 hours).

## WV02C — read-only web backend cross-project previews

- [x] WV02C.1 Implement bounded catalog loading and Swift-compatible unique/ambiguous/unresolved resolution in `cross_project_refs.py` (under 2 hours).
- [x] WV02C.2 Extract 600-character/four-block plain-text snippets from mounted accepted documents via `import_accepted_document`; preserve metadata-only fallback (under 2 hours).
- [x] WV02C.3 Wire strict 1024-character preview queries, peer registry, viewer capability and `handler_for(None)` static delivery in standalone and routed servers (under 2 hours).
- [x] WV02C.4 Align design/spec/source map and verify backend, HTTP, routing, homepage, sections, install and strict OpenSpec validation; leave `apps/macos/` unchanged (under 2 hours).

## WV03I — shared return policy and full-page web interaction (implemented)

- [x] WV03I.1 Implement/test `CrossProjectReturnStack` max 32 entries in `reader-common/navigation/cross-project-return.js`, versioned sessionStorage and one-shot pending restore (under 2 hours).
- [x] WV03I.2 Implement/test `features/navigation/cross-project-preview.js`: explicit first-click preview and implicit href preflight through ReaderTransport, native unresolved/failed href navigation, original PDF page/target fallback for ambiguous/unmounted previews, explicit second-click full-page `/d/<id>/` jump including same-document reload, Back restoration with section-boundary/layout retries, detached-link cleanup, failed/stale transitions and Homepage explicit-open reset without fragment/popstate collisions (under 2 hours).
- [x] WV03I.3 Register both modules explicitly in `web/assets.json` and verify source/installed delivery and final web interactions (under 2 hours).

- [x] WV03I.4 Finalize exact schemas, transition ordering/retries, peer configuration/fallback and catalog publisher responsibility, anchorless mounted jumps and oversized-label metadata-only exception, allowed-origin injection, Homepage alternative controls, existing in-document ReferenceReturn consumption and semantic holding, route identity map, file map and executable headless verification contracts (under 2 hours).

## LAG-7 PR2 review corrections

- [x] S1: conform to Swift-owned resolution/profile/snippet rules and verify both runtimes against the shared JSON fixture.
- [x] S2: align implemented WV02C/WV03I scope, web/native ownership and required delivery provenance; validate both active changes strictly.
- [x] S3: import captured accepted snapshots outside publication locks, coalesce/cache bounded imports per target and share parsed catalogs; verify concurrency, invalidation and native caps.
