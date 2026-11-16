# Proposal

## Why

Document selection needs a compact, readable mobile layout with established accessible components.

## What Changes

- Present the document title as its preferred reader link and alternatives in a dropdown.
- Self-host pinned Basecoat and Web Awesome assets for the Homepage.
- Restore visual finish within the focused document library: separate paper background and solid document surfaces, restrained green identity, deliberate typography and spacing, truthful status, and consistent search/settings/menu feedback. The adopted measurements and acceptance matrix are in `design.md`.

## Capabilities

### New Capabilities

- `homepage-component-delivery`: Locally delivered components for the document library.

### Modified Capabilities

The active `homepage-library` change is refined: the title is the primary link, and a dropdown replaces native details while preserving its safe-destination and focus contracts.

## Impact

Homepage presentation, explicit asset manifest and tests change; account, reader and server authority remain unchanged.

## Visual restoration

Restore surface separation, depth, typography and interaction feedback while retaining the focused document-selection structure. Do not restore explanatory copy, slogans, Tail Dashboard, fabricated formula previews or a generic dashboard of cards.

Presentation changes are CSS-first in `tools/flow-reader/web/home/home.css`, with only necessary Home markup changes. Inventory, focus/lifecycle, appearance and account ownership stay with the existing implementations. Reuse shared theme tokens and pinned Basecoat 1.1.0 / Web Awesome 3.14.0; no new dependency, CDN or font is needed. Shared theme, Reader content, server/API and vendor source remain unchanged. Synthetic previews must serve the actual Home assets rather than a separate mock UI.

Acceptance requires meaningful source/contrast/delivery checks and rendered-browser evidence of responsive layout, accessibility and interaction states. Source checks alone cannot establish visual quality.
