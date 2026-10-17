# Design

## Output and ownership

Use Typst's HTML target for semantic text and mathematical output. Add target-aware compatibility adapters for the PDE common packages. Preserve the source documents and existing package installation; build reader adapters into an isolated package overlay with recorded provenance. Any compiler modifications must be explicit, pinned, and tested independently.

The reader frontend and its asset/compile service live under `tools/flow-reader`. Existing engine compilation is the initial integration boundary. Flow supplies project root, entrypoint, fonts, and packages; Tail Hosting supplies HTTPS ingress. A separate reader process may be used during rollout so reader failures cannot interrupt the paged service.

## Fidelity

Page-relative annotation packages cannot run unchanged in HTML. Represent marked mathematical terms and annotation text as linked semantic content. Preserve custom graphical relationships through faithful rendering or explicit adapters. Never silently discard an annotation or mathematical decoration to obtain a successful compile.

Replace decorative blocks with semantic HTML containers so nested equation labels and references remain visible to the document introspector. Keep theorem kinds, counter resets, and target-location numbering. Use MathML where faithful and SVG for unsupported mathematical constructs. Figure panels stack at narrow widths; vector scaling alone is insufficient when it makes labels unreadable.

## Reader protocol

Every published document snapshot carries a revision and diagnostic status. Failed compilation leaves the last successful snapshot visible with a stale/error indication. Stable labeled block identities, with deterministic fallback matching, anchor the reading position and persisted highlights. Do not replace the active document while the user has a selection or open annotation.

Use content and asset requests on the reader's own origin. The original paged view remains reachable from the reader. Initial mobile routing must honor an explicit choice and offer both views.

## Validation and delivery

Compile the complete PDE project, checking unresolved references and unsupported output diagnostics. Compare paged output before/after adapter changes. Browser verification covers 320, 390, 430, and 768 CSS-pixel viewports, larger fonts, light/dark themes, navigation, selection, updates, and offline reload where supported. Verify the original live service and new Tailnet reader endpoint independently before changing mobile entry behavior.
