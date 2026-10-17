# Development checkpoint — 2026-10-17

This is an implementation checkpoint, not a completed mobile rollout.

## Actual PDE compilation

The full `Partial_Differential_Equations/main.typ` was compiled using Typst 0.15.1,
the project's font directory, and the isolated reader package overlay.

- HTML compilation succeeds. No unresolved internal link targets, duplicate IDs,
  or unresolved annotation targets were found.
- 6,864 MathML roots, 242 SVG islands, 309 figures, and 3,679 paragraphs are emitted.
- 217 annotation records have targets, including 15 graphical annotations.
  All 15 original CeTZ programs successfully render against supplied term
  rectangles. The content gate passes, with no unsupported diagnostics.
- There are no unhandled compiler-loss warnings. Remaining warnings concern the
  experimental HTML target, page set rules, and PDF marker tags.
- Original installed packages and document sources were not edited.

Reproduction and detailed output are in `dist/reader-pde/report.json`,
`compile.log`, and `document.html` (ignored development artifacts).

## Paged compatibility

The full PDE document was compiled once with the original packages and once with
the reader overlay, using the same fixed creation timestamp and font settings.
Both compiles completed without warnings. The PDFs are byte-identical:

`a4a7a08ff8fe5e51e3b406d52069a42021c423faea24971dfd7adae8dcb7decb`

Detailed results and PDFs after the graphical adapter changes are in
`dist/reader-pdf-graphics-comparison`. This comparison is
distinct from the smaller automated fixture comparison.

The existing loopback service on port 23625 continues to return HTTP 200; its
installed engine, LaunchAgent, and Tailnet ingress were not changed.

## Browser checks on the actual PDE document

The local development reader runs at `http://127.0.0.1:58538/` with the explicit
`--allow-incomplete` flag. It is not the mobile default or a managed service.

| Viewport width | Client width | Document scroll width |
| --- | --- | --- |
| 320 | 305 | 305 |
| 390 | 375 | 375 |
| 430 | 415 | 415 |
| 768 | 753 | 753 |

The browser reserves 15 pixels for its scrollbar. At 390 pixels and a 30-pixel
body font, client and scroll widths also both equal 375 pixels. Oversize equations
scroll within their own containers.

The browser revealed a native export issue: footnote `sup` elements directly in
MathML caused HTML parsing to leave the math namespace. A token-boundary
normalizer fixes that before parsing; the rendered PDE has zero orphan `mrow`
elements after the fix. A real covariant-derivative term opens its matching
annotation dialog. Inline math no longer shows spurious vertical scrollbars.

Evidence: `dist/reader-pde/browser-checks.json` and `mobile-annotation.jpg`.
These desktop-browser checks do not establish iPhone Safari performance or
complete visual fidelity of every equation and diagram.

## Graphical annotations and section delivery

`dist/reader-all-graphics` records a complete PDE compile with geometry for all
15 graphical annotations. Every requested SVG was extracted, with no compiler
loss warnings. The browser renders the Jacobi-formula relationship at 18px and
30px body font sizes; the SVG viewBox changes from `460.39425 × 346.0785` to
`687.1995 × 496.863` in response to the measured layout. Curve directions and
labels come from the original CeTZ program. Initial uncached rendering still
requires a full source compile.

The current delivery manifest has 57 sections. The initial section is 45,547
bytes of uncompressed HTML; the largest is 239,009 bytes. The compressed global
manifest is 157,646 bytes and includes 5,184 reading keys. Large SVG and raster
images are fetched separately. The first section's DOM before the additional
reading identifiers contained 1,165 elements rather than the entire book.

Browser checks verify section navigation, a footnote jump from Jacobi's formula
to the endnotes, and its return link. Reloading preserves the same reading key
and the same measured block top (9.46875 CSS px). A lazily loaded real SVG returns
393px intrinsic width and renders at 343px inside a 390px viewport. Width checks
and 30px text retain no whole-document horizontal overflow.

Evidence: `section-delivery-checks.json`, `section-browser-checks.json`,
`mobile-graphic-annotation.jpg`, and `mobile-graphic-large-font.jpg` in
`dist/reader-pde`. These checks do not establish that every figure's labels are
readable at phone width; that remains a separate requirement.

## Automated checks

`FLOW_READER_PACKAGES=... FLOW_READER_TYPST=/opt/homebrew/bin/typst python3 -m unittest discover -s tools/flow-reader/tests -v`

Tests cover nested references, annotation associations, math decorations, SVG ID
namespacing, MathML/HTML boundaries, unchanged paged output, package isolation,
and preservation of the previous served document after an actual compile error.
Sixteen tests also cover geometry-dependent CeTZ output, geometry validation,
cached responses, rejection after failed source edits, section/annotation
boundaries, image-byte preservation, and stable reading keys after both a section
boundary and a generated Typst label change.
JavaScript syntax is checked with `node --check tools/flow-reader/web/reader.js`.

## Outstanding requirements

- Broader visual checks of the 15 graphical annotations and lower uncached latency.
- Width-aware figure composition and readable labels; the current canvas adapter
  preserves SVG content but still scales complete canvases.
- Persistent highlights, source selection sharing, and broader update/anchor tests.
- Offline reload and font delivery on a real mobile browser.
- Managed Flow lifecycle, new Tailnet endpoint, explicit view preference, and
  mobile entry routing while preserving the existing page view.
- End-to-end mobile delivery and regression verification before promotion.
