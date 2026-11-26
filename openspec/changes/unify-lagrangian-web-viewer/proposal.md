## Why

Lagrangian's web experience needs a clear relationship to the native product and a shared cross-project architecture, without breaking existing integrations.

## What Changes

- Name the web-optimized projection Lagrangian Web Viewer and align its visible branding and contributor documentation.
- Establish Lagrangian, the native macOS app, as the canonical product and feature contract; share the existing `flow_reader` backend and `tools/reader-common` policy.
- Define future WV02 backend ownership for catalog resolution and accepted-document previews, and WV03 shared return policy and web preview/jump/Back interactions.
- Preserve internal, protocol and packaging identifiers and existing native behavior during the ownership transition.

## Capabilities

### New Capabilities
- `web-viewer`: product positioning, branding and cross-project web interactions.

### Modified Capabilities
- `reader-architecture`: backend-owned cross-project preview and shared return policy boundaries.

## Impact

The initial WV01R work changes web assets, focused tests and canonical developer documentation. WV02 and WV03 are future implementation work across the backend and reader adapters; they must coordinate with the existing `add-cross-project-references` native contract and preserve its behavior.

## Non-goals

Renaming internal paths, API routes, protocol attributes, packages, LaunchAgents, CLI flags or terminal/Neovim statuslines; implementing WV02 or WV03 in WV01R; changing the native user guide, delivery manifest, app installation or Rust engine.
