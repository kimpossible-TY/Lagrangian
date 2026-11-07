## Context

Phase 1 supplies shared appearance, material and motion tokens. The HTML Reader owns its chrome; document and overlay geometry have separate contracts.

## Decisions

Use system fonts in chrome and solid theme surfaces as the baseline. Enhance only the toolbar, outline drawer and reading settings panel with the shared frosted material when backdrop filtering is supported. Restore solid surfaces for reduced transparency or increased contrast. Opaque interaction fills provide predictable contrast over arbitrary document content. Keep existing control dimensions and positioning, with touch-sized settings summaries. Retain existing reduced-motion and forced-colors behavior.

## Risks / Trade-offs

CSS frosted glass approximates material rather than native optical effects. Static contrast tests cannot establish browser rendering, keyboard navigation, animation feel or device behavior; PM will capture and review screenshots.
