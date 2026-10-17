# Development checkpoint — 2026-10-17

This is an implementation checkpoint, not a completed mobile rollout.

## Actual PDE compilation

The full `Partial_Differential_Equations/main.typ` was compiled using Typst 0.15.1,
the project's font directory, and the isolated reader package overlay.

- HTML compilation succeeds. No unresolved internal link targets, duplicate IDs,
  or unresolved annotation targets were found.
- 6,864 MathML roots, 242 SVG islands, 309 figures, and 3,679 paragraphs are emitted.
- 217 annotation records have targets. Fifteen graphical annotations remain
  explicit unsupported diagnostics; the content gate intentionally fails.
- There are no unhandled compiler-loss warnings. Remaining warnings concern the
  experimental HTML target, page set rules, and PDF marker tags.
- Original installed packages and document sources were not edited.

Reproduction and detailed output are in `dist/reader-pde/report.json`,
`compile.log`, and `document.html` (ignored development artifacts).

## Paged compatibility

The full PDE document was compiled once with the original packages and once with
the reader overlay, using the same fixed creation timestamp and font settings.
Both compiles completed without warnings. The PDFs are byte-identical:

`df521a67309175168494639ae795be4fd156db96ee54ceb29afd7ad41e7e134b`

Detailed results and PDFs are in `dist/reader-pdf-comparison`. This comparison is
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

## Automated checks

`FLOW_READER_PACKAGES=... FLOW_READER_TYPST=/opt/homebrew/bin/typst python3 -m unittest discover -s tools/flow-reader/tests -v`

Tests cover nested references, annotation associations, math decorations, SVG ID
namespacing, MathML/HTML boundaries, unchanged paged output, package isolation,
and preservation of the previous served document after an actual compile error.
JavaScript syntax is checked with `node --check tools/flow-reader/web/reader.js`.

## Outstanding requirements

- Faithful responsive graphical annotation rendering (15 actual PDE cases).
- Width-aware figure composition and readable labels; the current canvas adapter
  preserves SVG content but still scales complete canvases.
- Long-document segmentation: loading the full document creates a large DOM and
  exceeded the inspection tool's full accessibility-tree limit.
- Persistent highlights, source selection sharing, and broader update/anchor tests.
- Offline reload and font delivery on a real mobile browser.
- Managed Flow lifecycle, new Tailnet endpoint, explicit view preference, and
  mobile entry routing while preserving the existing page view.
- End-to-end mobile delivery and regression verification before promotion.
