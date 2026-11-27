## Why

Lagrangian's web experience needs a clear relationship to the native product and a shared cross-project architecture, without breaking existing integrations.

## What Changes

- Name the web-optimized projection Lagrangian Web Viewer and align its visible branding and contributor documentation.
- Establish Lagrangian, the native macOS app, as the canonical product and feature contract; share the existing `flow_reader` backend and `tools/reader-common` policy.
- Implement WV02C read-only web catalog resolution and accepted-document previews, and WV03I shared return policy and web preview/jump/Back interactions. Swift remains the matching/snippet semantic owner; Python is a conforming web adapter verified by a shared fixture.
- Preserve internal, protocol and packaging identifiers and existing native behavior during the ownership transition.

## Capabilities

### New Capabilities
- `web-viewer`: product positioning, branding and cross-project web interactions.

### Modified Capabilities
- `reader-architecture`: backend-owned cross-project preview and shared return policy boundaries.

## Impact

WV01R changes web assets, focused tests and canonical developer documentation. WV02C and WV03I are implemented in this change across the web backend and reader adapters, preserving the existing `add-cross-project-references` Swift-owned matching/snippet contract with shared JSON conformance tests. Native consumers retain their Swift owner. Native delivery requires source-provenance registration for the changed delivered sources.

## Non-goals

Renaming internal paths, API routes, protocol attributes, packages, LaunchAgents, CLI flags or terminal/Neovim statuslines; changing the native user guide, app installation or Rust engine. Delivery manifest changes are limited to the source-provenance registration required by native delivery.
