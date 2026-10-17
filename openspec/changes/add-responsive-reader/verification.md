# Development checkpoint — 2026-10-17

This is an implementation checkpoint, not a completed mobile rollout.

The user clarified that reading must not require zoom, slides, horizontal panning,
or an extra click to expand equations/essential annotations. Earlier checks of
whole-document overflow do not satisfy that requirement. The current prototype
still fails it: at 390px, a real PDE equation needs 367px inside a 343px container;
section progression still has a required next button, and other sections contain
collapsed annotations and graphical-view buttons. Historical checks below remain
useful evidence of rendering fidelity and lifecycle, but are not a responsive
reading acceptance result.

## Width-aware renderer experiment after the clarification

The isolated, self-hosted MathJax 4.1.3 probe checks all 1,411 outer display
equations from the accepted PDE HTML. At 390px with 18px text, 81 equations still
overflow; at 320px with 30px text, 294 overflow. There are no MathJax input errors
or SVG count changes in those runs. Presentation text order changes in 604/607
equations, and marker occurrence lists change in 31/61: these require logical
identity and selection handling independent of the rendered DOM. They are not
automatically evidence of mathematical corruption.

The experiment demonstrates useful line breaking for some equations but rejects
a direct MathJax swap as a complete solution. Long decorated terms already
flattened into SVG and multi-column derivation tables are concrete failure cases.
There were no changes to the installed Reader, original PDF service, or mobile
default from this experiment. Enhanced speech/exploration is disabled in this
isolated probe; production accessibility remains unverified. Surrounding content
and annotation programs are outside its acceptance scope.

Reproduction: `tools/flow-reader/research/README.md`. Local evidence:
`dist/reader-reflow-probe/corpus-390-18.json`, `corpus-320-30.json`, `390-18.png`,
and `320-30.png`. The corpus source SHA-256 is
`fb664809f1aff548bb2ea8c5379e9c8b3a87f5cd48167755685b072355040a96`.

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

The following earlier checks used the development reader on port 58538 with
`--allow-incomplete`. That temporary process has now been stopped after the
managed Reader on HTTPS port 23627 was verified. The managed endpoint also remains
in development mode and is not the mobile default.

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
Twenty-seven tests now cover geometry-dependent CeTZ output, geometry validation,
cached responses, rejection after failed source edits, section/annotation
boundaries, image-byte preservation, and stable reading keys after both a section
boundary and a generated Typst label change. They additionally cover immutable
installation, inherited Flow project settings, port and process ownership,
compiler dependency watching, and quotation relocation with ambiguous/missing
results and revision checks.
JavaScript syntax is checked with `node --check tools/flow-reader/web/reader.js`.

## Saved highlights and lifecycle checkpoint

Saved quotation checks use the synthetic fixture in
`dist/reader-highlight-checks`, independently of the managed PDE service.
The browser saved a Korean quotation, retained it across reload, and found it
again after its paragraph was edited and moved from section 0 to section 1.
An open saved-list dialog held the previous document while an update arrived.
At 320 CSS px with 30px text, the document scroll width remains 320px. A selected
MathML equation survives save and reload with all six original token children and
the MathML namespace intact. Evidence: `mobile-restored.png` and `mobile-math.png`.
These are desktop browser checks; iPhone Safari and broader PDE highlight cases
remain to be verified.

The managed Reader installer and lifecycle helper were implemented in commits
`2c68a2aa` and `6bfa698a`. A separate LaunchAgent and immutable release are installed
for `typst-pde-reader` on loopback port 23627. Port 23626 belongs to the user's
separate Ewald Flow profile and was preserved. Tail Hosting's adapter passes
12 management tests. The development Reader is now registered separately, with
HTTPS port 23627 forwarding to its loopback listener. The complete preexisting
Serve configuration was compared before and after allocation; every other route
remains identical. Both the new Reader and original PDF HTTPS URLs return 200.
The status reporter was restarted to load the new Reader monitoring adapter.

The first managed PDE compile waited on the macOS Documents permission prompt for
its Python 3.15 executable. TCC logs identified the prompt, and a process sample
showed Typst waiting to access its working directory. Subsequent readback confirms
that the wait resolved and the managed compile succeeded: `exitCode: 0`,
`contentGatePassed: true`, no compiler-loss warnings, and an accepted revision.
The assistant did not change macOS privacy settings. The existing paged endpoint
on 23625 still returns HTTP 200. The quotation implementation is installed from
clean commit `be7c8bfd`, and restarting only the Reader through Tail Hosting
succeeded. An actual PDE quotation was saved and found through the HTTPS reader.
The browser fixture also verifies an ambiguous result remains visible and a
user-deleted highlight stays deleted after reload.

A Reader-only SIGTERM test changed its PID from 86457 to 86684; launchd restored
the listener and accepted document within 14.65 seconds. All seven checks of the
original PDF during recovery returned HTTP 200, and its engine PID remained
39357. Evidence is in `dist/reader-highlight-checks/managed-recovery.json`.
Tail Hosting's refreshed status reports both services running with compile state
`ok`. The HTTPS Reader retained the saved PDE quotation after restart; at a
390px viewport its client and scroll widths both equal 375px (15px scrollbar).
The screenshot is `dist/reader-highlight-checks/pde-https-highlight.png`.

## Outstanding requirements

- Broader visual checks of the 15 graphical annotations and lower uncached latency.
- Width-aware equation and figure composition with readable labels, inline essential
  annotations, and automatic continuous section loading. Current local scrolling,
  complete-canvas scaling, and modal relationship views fail the clarified contract.
- PDE and real-device highlight checks, source selection sharing, and broader update/anchor tests.
- Offline reload and font delivery on a real mobile browser.
- Explicit view preference and mobile entry routing after figure and fidelity
  validation, while preserving the existing page view.
- End-to-end mobile delivery and regression verification before promotion.
