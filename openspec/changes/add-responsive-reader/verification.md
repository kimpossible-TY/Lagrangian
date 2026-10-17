# Development checkpoint — 2026-10-17

This is an implementation checkpoint, not a completed mobile rollout.

The user clarified that reading must not require zoom, slides, horizontal panning,
or an extra click to expand equations/essential annotations. Earlier checks of
whole-document overflow do not satisfy that requirement. The current prototype
still fails it: at 390px, a real PDE equation needs 367px inside a 343px container;
section progression previously required a next button. Continuous loading now
removes that requirement; annotations and relationships now also appear inline
without reveal controls. Width and collision failures remain. Historical checks below remain
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

The subsequent adaptive-canvas implementation exposes 57 direct CeTZ canvases in
the complete PDE HTML. It does not claim coverage of every opaque SVG/layout
island. The recorded `pde-canvas-audit.json` checks all 57 at two requested sizes:
49 fit a 343px drawing width with 18px inherited text; 44 fit a 273px width with
30px inherited text. Unresolved canvases are listed explicitly. The first case
has a long fixed legend; source inspection also finds explicit 6pt/8pt labels.
Thus these width results do not establish readable labels or collision freedom.

The canvas fixture verifies that reducing geometry from 529.13px to 277.2px leaves
the glyph outlines and 1pt strokes identical at 18px text, while 30px text changes
the glyphs. A 500pt-wide fixed-coordinate drawing reports overflow with its original
geometry. Both the existing reader fixture and new CeTZ fixture retain byte-identical
paged output against the original packages. All 32 reader tests pass, including
per-canvas cache reuse across different batches and rejection of stale revisions
and uncached rendering after failed source edits. Browser evidence and full PDE
audit data are under `dist/reader-canvas-checks`.

The actual PDE browser check at a 320px viewport and 30px body text measures
210px of available width inside a nested callout. Canvas 2 and canvas 3 render
at 207.89px and 207.80px respectively, following automatic width/font requests.
The recorded values and screenshot are `browser-320-30.json` and
`pde-320-30.png` under that directory. This is evidence for those two drawings,
not a whole-document readability result.

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

After the adaptive canvas change, the full PDE comparison was repeated against
the then-current saved sources. The original packages and reader overlay again
produce byte-identical PDFs, both with SHA-256
`54a0deaf35d426b750aa45c0b8f655ecf0d2faf002b6adc4e1e35e62de9ac3ab`.
Evidence is `dist/reader-canvas-checks/paged/comparison.json` and the adjacent
PDFs. The earlier hash above belongs to the earlier source snapshot.

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
Thirty-two tests now cover geometry-dependent CeTZ output, geometry validation,
cached responses, rejection after failed source edits, section/annotation
boundaries, image-byte preservation, and stable reading keys after both a section
boundary and a generated Typst label change. They additionally cover immutable
installation, inherited Flow project settings, port and process ownership,
compiler dependency watching, and quotation relocation with ambiguous/missing
results and revision checks.
The canvas checks additionally cover coordinate-unit fitting without glyph or
physical stroke scaling, fixed-coordinate overflow, unchanged paged output, and
cache reuse across differently grouped requests.
JavaScript syntax is checked with `node --check` for `reader.js` and `canvases.js`.

## Continuous reading checkpoint

The reader now fetches adjacent transport sections automatically in both
directions. Distant sections retain measured height while their DOM content is
parked; nearby, selected, and focused content remains mounted. The nominal window
is six mounted sections, but protecting content takes priority over that count.
There are no next/previous section controls. Notes have section-scoped
identifiers, canvas observation is updated without resetting existing drawings,
and highlights paint all mounted sections.

The dedicated synthetic fixture initially has 12 transport sections. Browser
checks at 390px verify scrolling through successive sections, a six-section
mounted window, zero duplicate IDs, retained native selection after automatic
loading/parking, saved-quote return, and automatic loading in the reverse direction.
Reload preserves the same reading key and a 4.140625px block top. A second reload
after a linked jump and subsequent reading preserves a 30.171875px block top,
even when the URL's section hint refers to an earlier location.
Restoring a parked final section returns its five paragraphs and exactly the
previous 803.28125px height, with six sections mounted afterward. Browser Back and
Forward return to the same reading keys; the recorded Back check has 50px offset
drift and Forward has 0.25px. Broader pixel-level history/anchoring checks remain
open rather than treating those results as exact position preservation.

Adding 20 preface paragraphs moves a selected block from section 5 to section 7.
The new source revision is published, but the reader retains the selected word
and its existing DOM until selection is cleared. After update, that block moves
from 418.59375px to 418.078125px (less than 1px drift). Stopping only the fixture
server leaves its 36 mounted paragraphs readable; after restart the next section
loads automatically without a retry click.

The full PDE is separately compiled and served with the production partition
sizes. In a 390px browser, its first two sections join directly between the end
of the linear-endomorphism proof and Jacobi's Formula, with zero duplicate IDs
and zero orphan MathML `mrow` elements. At 320px/30px text they still form a
continuous body. This is not a mathematics-fit result: the existing long equation
in the screenshot still requires local horizontal scrolling and remains unfinished.

All 32 Python integration/unit tests pass. Four Node tests additionally verify
stale neighbor/restoration responses, automatic retry after a failed boundary
request, and retention of selected/focused sections during parking. Reproduce
with `node --test tools/flow-reader/tests/test_continuous.mjs`; the manual browser
fixture is `tools/flow-reader/tests/continuous_fixture.py`. Evidence is
`dist/reader-continuous-checks/browser-checks.json`, `fixture-saved.png`,
`pde-boundary-390.png`, and `pde-boundary-320-30.png`.

The continuous reader and preceding canvas adapter are installed as the separate
development Reader from clean commit `88973e75e4a88a94d882acc5bbd2cb675494ba5e`.
Only the Reader was stopped and started; the original paged engine retains PID
39357. Both HTTPS endpoints return 200. The new Reader reports a successful
accepted compile, and its served `sections.js` matches the committed module.
The HTTPS browser at 390px loads sections 0 and 1 automatically with zero
next/previous controls and retains its existing saved quotation. Evidence is
`managed-update.json` and `managed-pde-390.png` in the same directory. It remains
in development mode; mobile default routing has not changed.

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
- Width-aware equation and figure composition with readable labels and inline essential
  annotations. Current local scrolling,
  unresolved width fitting and graphical collisions fail the clarified contract.
- PDE and real-device highlight checks, source selection sharing, and broader update/anchor tests.
- Offline reload and font delivery on a real mobile browser.
- Explicit view preference and mobile entry routing after figure and fidelity
  validation, while preserving the existing page view.
- End-to-end mobile delivery and regression verification before promotion.


## Inline annotations checkpoint

The Reader now displays text notes and graphical relationships in the continuous
body. No note disclosure, relationship button, or annotation dialog is required.
Graphical scenes reuse the original equation nodes, preserve intervening prose,
and merge overlapping relationships. Original CeTZ programs and source coordinates
are preserved. A common translation restores the original first-marker coordinate
origin; complete drawing bounds reserve vertical room outside the equation.

The compiler tests cover literal coordinates after moving the first marker,
negative drawing bounds, physical SVG dimensions, and the requested font size in
both label measurement and rendering. Browser checks use the dedicated
`inline-annotations.typ` fixture: two graphs share one equation, another spans
separate blocks, and an authored 6pt prose note inherits the reading font size.
The intentional cross-block connector is reported as a collision with intervening
prose. This is conservative detection, not automatic collision resolution;
opaque image ink and intersections between independent overlays are not audited.

The actual PDE Jacobi formula at 320px/18px uses a 406.313px scene inside a 273px
body. Its original graphical program renders automatically and the diagnostic
reports both overflow and a sampled path/text collision. The equation still needs
width-aware mathematical layout. Essential annotations now being inline does not
make this a completed responsive reader. Explicit small labels, other figures,
selection/history behavior, offline delivery, and real iPhone Safari remain open.

A full PDE comparison with a fixed creation timestamp produced byte-identical
PDFs from the original packages and the reader overlay (SHA-256
`54a0deaf35d426b750aa45c0b8f655ecf0d2faf002b6adc4e1e35e62de9ac3ab`).
Evidence is under `dist/reader-inline-checks`: `paged/comparison.json`, browser
measurements and screenshots, and the reader test log.

At 390px/18px and 320px/30px, the fixture renders all three graphs automatically
in two scenes. Both relationships on the first equation fit without sampled
text collisions. The intentional cross-block collision is detected at both sizes.
Text notes use 18px and 30px respectively, including the authored 6pt span; no
disclosure controls, annotation dialogs, or duplicate IDs remain in the fixture.
All 34 Python tests and 8 Node tests pass. The Node tests include obsolete-document
responses, changed term geometry, replacement records after parking, and automatic
retry. JavaScript syntax, diff whitespace, and the canonical Typst guide compile
also pass.

The clean commit `0a6fa4ccd44dc488d1e97a5d673ce508879df6c4` is installed as the
separate development Reader on HTTPS port 23627. Its accepted PDE compile passes
the content gate, and the served shell, stylesheet, and JavaScript match that
release. The managed browser displays inline notes at 390px and retains the
existing saved quotation. The original paged endpoint remains HTTP 200 with its
same process. Mobile default routing is unchanged. `managed-update.json` and
`managed-pde-390.png` record this check. Temporary fixture/PDE services were stopped.

## Semantic decoration checkpoint

The mannot adapter now emits native marked mathematical content separately from
the original decoration callbacks. Revision-bound requests provide each fragment's
dimensions, reading font, and ink; results retain layer order and anchor outsets.
The browser paints every measured fragment separately, removes obsolete paint on
geometry changes, reports pending/errors, and retries automatically. SVG XML case
is preserved, and stretched bracket decorations no longer inherit equation numbers.

All 102 PDE decoration IDs render at two supplied fragment sizes (204 fragments
and 204 layers). The dedicated browser fixture at 390px/18px has seven semantic
term occurrences, including a note preview, and eight ready paint layers. It
retains mathematical body text independently of highlights, boxes, ordinary/wavy
underlines, brackets, and a custom two-layer callback. This is compiler and fixture
evidence, not a complete real-document layout acceptance result.

Both adapter versions compile the same frozen PDE dependency snapshot with no
missing link targets, duplicate IDs, unresolved annotation targets, or unhandled
compiler-loss warnings. Each contains 6,759 outer math roots and 1,412 display
roots. The new output exposes 102 decorations, 58 direct canvases, 25 cases, and
11 matrices. The independently edited live source must not be mistaken for a
stable before/after benchmark input.

The isolated MathJax candidate combines semantic decoration bodies with optional
composition of 398 derivation tables. Both comparison variants relocate note
prose visibly before typesetting. Overflow changes from 26 to 12 at 390px/18px
and 240 to 96 at 320px/30px. All four runs have zero input errors and zero SVG
count changes; row composition itself preserves text order. MathJax presentation
text and fragment occurrences still change. Dynamic decoration paint and graphical
relationships are not drawn by this probe, and the candidate is not connected to
the Reader. The research guide records exact hashes and limitations.

The full PDF comparison is byte-identical between original packages and the new
overlay (SHA-256 `8e86c79313fc61d207bc14c08bc10940e25dc820b23d3bc7917d00007dd4cd52`).
All 39 Python and 10 Node tests pass, including every decoration layer, empty SVGs,
cache reuse, failed saves, obsolete revisions, and separated fragment rectangles.
JavaScript syntax, formatting, diff whitespace, and canonical guide compilation
pass. Evidence is under `dist/reader-semantic-checks`, including the four frozen
corpus reports, `decoration-audit.json`, `decorations-390.png`, test logs, and
`paged/comparison.json`. The original PDF and installed development Reader both
remain HTTP 200. This checkpoint is not installed; mobile default routing remains
unchanged. Cancellation/overline islands, multi-fragment graphical anchors,
readable figure labels, collision resolution, and final mobile acceptance remain open.

## Logical mathematical identity checkpoint

The source token model binds every mathematical token to all of its visual
occurrences, independently of renderer DOM order. It retains canonical Unicode
and source order while mapping mathematical alphabet variants, variation selectors,
spacing, repeated continuation operators, and stretchy operator glyphs. Unexpected
text or missing tokens reject binding. Quotations split into separate logical
intervals when a visual selection skips source-order characters. Highlight ranges
do not include unselected superscripts between a base and its subscripts.

At 320px/30px, the frozen PDE corpus passes for all 6,759 outer math roots:
zero identity errors and zero logical text changes, with 324 logical marked nodes
bound to 395 visual fragments. The 1,412 display-only roots also pass (322 marks,
393 fragments). This is token association evidence, not a mathematical rendering
or accessibility acceptance result. Remaining mathematical overflow is unchanged.

The browser fixture passes nine checks, including source/presentation order,
superscript-only selection, disjoint logical intervals, base/subscript-only paint,
native prose exclusions, and a marked sum broken into four visual fragments.
The current Reader's native MathML fixture loads without script errors, retains
all eight decoration layers, and saves and relocates the selected heading word
`decorations`. Double-clicking a native MathML glyph selected a newline in this
browser; this does not establish general native mathematical selection ergonomics.

All 39 Python tests and 13 Node tests pass. Evidence is under
`dist/reader-identity-checks`: `all-math-320-30.json`, `corpus-320-30.json`,
`selection-320.json`, `selection-320.png`, and test logs. The candidate renderer
is not yet connected to the Reader. Multi-fragment relationship anchors, renderer
asset delivery/lifecycle, accessibility, and full mobile layout acceptance remain open.

The clean commit `c74039a85a47e3ae192e923a980604764002ea9c` was subsequently
installed as the separate development Reader on HTTPS port 23627. Accepted PDE
compilation passes the content gate with 102 decoration IDs. At 390px the actual
PDE page paints five nearby decoration layers and retains its saved quotation.
Both HTTPS endpoints return 200; the original paged process remains PID 39357.
Evidence is in `dist/reader-identity-checks/managed-update.json`,
`managed-browser.json`, and `managed-pde-390.png`. The screenshot also documents
remaining equation overflow; installation is not mobile layout acceptance.

## Fragment-aware relationship anchors

Relationship targets now resolve the retained source mark to all of its visual
fragments. The browser sends separate rectangles and includes each in the request
identity, so movement of a later line invalidates the overlay. The compiler
validates every rectangle and retains the legacy single-rectangle protocol.
Multi-fragment CeTZ nodes resolve compass and arbitrary-angle anchors on actual
fragment edges, center/default on an actual fragment center, and path anchors
along the separate perimeters in logical order. The first fragment remains the
literal coordinate origin. Authored PDE drawing programs are unchanged.

All 41 Python tests and 14 Node tests pass, including the existing byte-identical
paged fixture check. The new compiler fixture asserts cardinal, center, perimeter,
and 24 angular anchor locations. The browser fixture at 320px/30px passes ten
checks and carries all four rendered fragments from its detached original mark
into a relationship measurement. The frozen PDE's 15 original graphical programs
compile against 126 supplied fragments across 42 marked targets with the content
gate passing. That corpus audit uses synthetic geometry, so it does not establish
collision-free real-page rendering. Evidence is under `dist/reader-fragment-checks`.

The MathJax candidate still requires Reader lifecycle/asset integration and full
layout/accessibility validation. The mobile default remains unchanged.

The clean implementation commit `4cb61ce73e6eeeb676fc437b78de72256d8cbe55` is
installed as the development Reader on port 23627. Its served modules match the
release, its accepted PDE compile passes the content gate, and the actual Jacobi
relationship returns and paints through the new fragment request protocol at
390px. The scene correctly reports its remaining overflow (406.313px drawing
inside a 343px body); this is delivery evidence, not layout acceptance. Both
HTTPS endpoints return 200 and the original PDF process remains PID 39357.
`managed-update.json`, `managed-browser.json`, and `managed-pde-390.png` retain
the verification. Temporary fixture servers and the Chrome verification tab
were closed; the temporary viewport override was reset.

## Reader mathematical runtime

The Reader now uses locally bundled MathJax 4.1.3 conversion for nearby
expressions. Source token validation precedes publication, logical copying
excludes assistive duplicates, and the existing decoration/relationship modules
measure the resulting fragments. Initial temporary native geometry is withheld
from dynamic compiler requests. Versioned assets are restricted to the retained
manifest; the original distribution bytes and license metadata are preserved.

The existing 41 Python tests pass, and a separate new HTTP test verifies every
manifest asset hash, font content types, JavaScript compression, versioned caching,
and unknown-path rejection. All 17 Node tests pass, including loader network and
startup failure recovery. The actual Reader browser
fixture at 320px/30px and 390px/30px passes 25 checks: canonical copy and scripts,
selection-preserving font changes, fragment paint, intact matrices/derivation
rows, reference links, local assets, assistive MathML/ID handling, obsolete
revision/width rejection, and automatic recovery from an intentional composition
failure. The canonical Typst developer guide compiles, and formatting/diff checks
pass. Evidence is under `dist/reader-runtime-checks`.

The frozen full PDE document compiles with the content gate passing. At 390px/18px,
the actual Jacobi scene composes five mathematical rows, with 36 nearby expressions
successfully rendered and no mathematical error notice. Its original graphical
callback paints at the 343px body width. The relationship still reports a collision;
width fitting is not collision-free acceptance. Dynamic full-document compiler
requests remain slow. Actual screen-reader/mobile Safari checks, unresolved wide
mathematics, label collisions, and the mobile default rollout remain open.

## Connector paths and stable input snapshots

Reader-only CeTZ metadata identifies planar open lines and Bezier connections
between named marked terms. Browser routes retain their original endpoints,
stroke, and CeTZ mark definitions; path-attached labels and Bezier anchors are
preserved. Search work and compile retries are bounded, with unresolved layouts
reported explicitly. Other marked terms are obstacles, and short outward leads
can use the space before the next wrapped line. Original drawing programs and
coordinate offsets are unchanged.

All 45 Python tests and 25 Node tests pass. The compiler tests verify numeric
route validation, rejection of changed endpoints, original arrow marks, and named
path anchors/labels. A source-input regression verifies that directory timestamp
updates and Finder metadata do not reject rendering while newly created imports
remain detectable. The actual Reader fixture passes 15 checks at each of 320px
and 390px, covering 18px and 30px text, correct completed drawing font, endpoint
identity, collision-free width, original colored arrows, and stable bounded
requests. The existing 25-check mathematical selection/update fixture also passes
at 320px after the pending-composition change.

The frozen PDE compiler audit retains all 15 graphical programs and identifies
23 supported connections across 12 programs. At 390px/18px, the actual full PDE
Jacobi scene routes the colliding blue connection, retains the red curve, fits
the 343px body, and reports zero text/label collisions and no unresolved route.
This verifies one actual scene, not all graphical programs or all mobile layouts.
Evidence is under `dist/reader-routing-checks`.

A fresh paired full-PDE PDF compile uses the same frozen sources, fonts, and
creation timestamp for the original packages and Reader overlay. Both SHA-256
values are `3fb2b8cb775215a9d7a3905048489299bad22331b3401c7223bbc48f86d1ef46`.
The earlier attempted comparison with a historical PDF hash used different
creation-time/source conditions and was not a valid byte comparison; the paired
`pdf-paired.json` is the current evidence. Remaining wide mathematics, figure
labels, unsupported connectors, accessibility/device checks, and mobile rollout
remain open.

The clean implementation commit `c8c4cd9c7f333bf56cbd5debab00f2541f1638ca`
is installed as the independent development Reader on HTTPS port 23627. Its five
checked frontend modules match the release, accepted PDE compilation passes the
content gate, and the actual HTTPS Jacobi scene at 390px/18px reports zero
text/label collisions with the blue connection rerouted and the red curve kept.
The original PDF endpoint remains HTTP 200 in PID 39357. Installation and browser
receipts are `managed-update.json`, `managed-browser.json`, and
`managed-pde-390.png` under `dist/reader-routing-checks`. The temporary fixture
servers and verification tab were closed, and the viewport override was reset.
The mobile default remains pending full fidelity validation.

## Native mathematical decorations

Cancellation bodies remain semantic `menclose` content, with the original Typst
cancellation properties drawing only paint on each measured fragment. A tagged
`mrow` integration boundary preserves nested mathematical show rules during
export; normalization restores semantic enclosures afterward. The visual pass
makes only these paint-backed enclosures breakable and restores their notation
in assistive MathML. Overlines use a grouped body and explicitly stretchy spacing
macron; a browser regression verifies the bar spans the complete body.

The frozen source snapshot's 65 files are unchanged. All 6,759 outer mathematical
roots remain, including 1,412 display roots, while mathematical SVG islands fall
from 77 to zero (67 cancellations and ten overlines). The full PDE compile has no
mathematical-loss warnings and passes the content gate. All 169 decoration IDs
produce both requested fragments, totaling 338 layers. The final paired PDF
comparison uses identical frozen sources, fonts, and creation timestamp; both
SHA-256 values remain `3fb2b8cb775215a9d7a3905048489299bad22331b3401c7223bbc48f86d1ef46`.

All 48 Python and 27 Node tests pass. Geometry tests check cancellation length,
function and fixed angles, inversion, crossed diagonals, inherited and explicit
ink, thickness, and dashes. The actual Reader fixture passes 21 checks at each
of 320px and 390px, covering 18px and 30px text, canonical copying, fragment paint,
assistive cancellation, and full-width overlines. The existing 25-check math
selection/update fixture and 15-check CeTZ routing fixture pass at 320px. The
canonical guide compiles; formatting and diff checks pass.

The isolated paired corpus probe uses complete stretched-operator surfaces rather
than their clipped overlapping glyph pieces, and checks scroll width as well.
Both versions use the same measurement and frozen source. At 390px/18px, overflow
is 16 before and 14 after; at 320px/30px, it is 164 before and 157 after. These
counts are not directly comparable with the older 1,412-display-root reports;
these runs also include inline roots and complete stretched-operator surfaces.
Every run checks all 6,759 roots with zero rendering,
token-binding, logical-text, or SVG-count errors. New semantic bodies retain 394
logical marks across 482 presentation fragments at 320px/30px. The probe omits
dynamic paint, relationships, and the runtime's bounded small-overhang correction;
it does not establish production layout or screen-reader acceptance. Remaining
fractions, bracketed annotations, matrices, drawing labels, device checks, and
mobile rollout remain open. Evidence is under `dist/reader-math-overflow-checks`.

The clean implementation commit `d3fdd37e67f0d312674e00b4285fa01db250f6e6`
is installed as the independent development Reader on HTTPS port 23627. Its five
checked frontend modules match the release and accepted compilation passes the
content gate. The current live PDE has evolved beyond the frozen snapshot: it
contains 6,802 outer math roots, 67 cancellations, 12 overlines, and no mathematical
SVG islands. At 390px/18px, the actual Levi-Civita derivation retains two cancelled
fragments, all five paint layers, and assistive cancellation notation. Its 336px
math view has 336px scroll width and no math or decoration notice. The document
as a whole still overflows (541px scroll width versus 375px document width),
including pending distant drawings and unresolved expressions; this component
verification does not establish page-wide mobile acceptance.

The original PDF endpoint remains HTTP 200 in PID 39357; the updated Reader runs
in PID 2042. Installation, content/module hashes, actual browser measurements,
remaining overflow locations, and the screenshot are saved as `managed-update.json`,
`managed-browser.json`, `managed-overflow.json`, and `managed-pde-390.png` under
the same evidence directory. The mobile default remains unchanged.

## Automatic composition of wide inline expressions

Wide inline mathematics can automatically use block line breaking while an
explicit `mstyle` preserves its original inline fractions, limits, and scripts.
Short mathematics remains inline and widening a container restores the original
presentation. Publication still waits for token validation and respects active
selection, revision changes, and obsolete width/font measurements.

The actual Reader fixture at 320px and 390px passes 26 checks per viewport,
covering 18px and 30px fonts, exact fraction-size comparison, canonical copying,
surrounding sentence order, original paint for every wrapped mark, visible full
vertical content, keyboard-accessible math references, and automatic restoration
in a wider container.

The reproducible runtime corpus probe snapshots the actual candidate renderer and
its local dependencies. Its paired snapshots use the same frozen PDE HTML and
common reading widths: all 6,759 input roots yield 6,873 expressions after note
relocation. Overflow falls from 97 to 53 at 273px/30px and from eight to five at
343px/18px. Every run has zero rendering, token-binding, canonical-text, and
SVG-count errors. The larger-font run promotes 50 expressions. These figures
exercise the actual conversion API and calibration, with expression padding;
they are separate from the older stand-alone MathJax probe. Paragraph context,
dynamic paint, relationships, publication, selection, and device acceptance remain
separate checks. Source and renderer hashes are retained with the evidence under
`dist/reader-inline-checks`.

## Measured composition inside mathematical structures

The frame planner now passes width budgets into fraction children, radicands,
spanning brace/bar bodies and labels, scripted bases, and table cells. It keeps
short fenced groups intact, reserves attached-script widths, and introduces
zero-width discretionary product breaks. Wide PDE matrices retain four rows and
four columns, use compact inter-cell spacing and narrower full-height fences;
their entry and script fonts retain the selected reading size. No PDE source,
CeTZ drawing program, or PDF adapter changed in this step.

The final paired runtime snapshots use the same frozen HTML SHA-256
`f44aecb6c6aedead171a16798af603bd06235f718975148735535bde8cecd6b5`:

| Common body width / font | Previous inline renderer | Structured renderer |
| --- | ---: | ---: |
| 273px / 30px | 53 overflow | 0 overflow |
| 343px / 18px | 5 overflow | 0 overflow |

Each run checks all 6,759 source roots and 6,873 expressions, with zero rendering,
token-binding, canonical-text, and SVG-count errors. Source and renderer hashes
are recorded. Actual paragraph contexts, publication, paint, figures and device
acceptance are not claimed by this isolated candidate probe.

The actual Reader structure fixture passes all 69 checks at both 320px and 390px,
covering 18px and 30px text. It checks canonical copying, full horizontal/vertical
ink, page scroll width, matrix dimensions and entry fonts, full-height fences,
intact short norms, a full-width multi-line overline, and original paint on every
marked fragment. The existing inline, selection/update, connector-routing and
native-decoration fixtures pass 26, 25, 15 and 21 checks at 320px. The Python
suite passes 48 tests and the JavaScript suite passes 27 tests. The canonical
developer guide compiles successfully.

Two boundary fixes are covered by these checks: candidate and published width
use the same fractional CSS measurement; MathJax's already-masked extender
surfaces use a matching axis scroll mask, preserving complete visible operators
without phantom overflow from their stencil glyphs. The frame planner performs
at most four passes and two small global corrections, retaining its least-wide
candidate. Evidence is under `dist/reader-frame-checks`, including
`runtime-320-30-final.json`, `runtime-390-18-final.json`, viewport fixture reports,
regression reports, and screenshots. Figure fidelity and mobile-default rollout
remain unfinished.

### Managed structured-math delivery

Clean commit `c782df3ef7100241e542c9b1e786a66f1fc0a69e` is installed in the
independent development Reader on HTTPS port 23627, PID 16288. Its six served
renderer module/style hashes match that commit. The live saved PDE compilation
passes the content gate with exit code zero. The actual energy-flux identity
has component width/scroll width 343/343 at 390px/18px and 273/273 at 320px/30px;
both states are `ready`. Original PDF port 23625 remains HTTP 200 in PID 39357.

Whole-page widths still exceed the phone viewport because distant unadapted
canvases contribute their natural bounds. The font-change check also exposed a
reading-position drift before navigating back to the equation. Those failures
remain explicit; mobile default routing is unchanged. Delivery, browser geometry
and screenshots are under `dist/reader-frame-checks/managed-*`.

## Bounded drawing delivery and stable reading anchors

Unadapted CeTZ SVGs/images now reserve an aspect-ratio placeholder and cannot
widen the page before their automatic rendering completes. A previous fitted
drawing remains visible during a font update; a narrower viewport bounds it
immediately even while the renderer is busy. Obsolete width/font responses do
not publish. Failed width fits retain the full drawing and explicit diagnostic.
No source coordinates or drawing programs changed.

Drawing replacement uses the shared reading-anchor preservation callback.
The Reader owns scroll anchoring, restores a font mutation synchronously,
remembers the prior viewport's logical block/offset for resize and font-loading
events, and recognizes named plain Typst blocks without choosing a container
instead of its paragraphs.

The canvas-loading fixture passes 12 checks for 320→390px and 13 for 390→320px,
the latter while a larger-font rendering request is deliberately held. A
16-check width round trip also verifies immediate restoration of an accepted
drawing before an obsolete narrower request completes. Its
paragraph position remains within 2px through initial delivery, rapid 18→30px
font changes, publication, and viewport changes. A real compiler result with an
impossible fit remains completely visible with a diagnostic.

The frozen actual PDE fixture passes eight checks in each viewport direction.
At 30px text the energy-flux identity retains every canonical term and has
component width/scroll width 273/273 at 320px and 343/343 at 390px. Whole-page
width/scroll width is 305/305 and 375/375, respectively (the remaining 15px is
the browser scrollbar). The test anchors the equation itself across the 90px
reading reference line, after neighboring initial layout settles. It does not
assert that an equation below a preceding anchored paragraph keeps its own top
when that preceding paragraph becomes taller.

The structure and selection/update browser regressions pass 69 and 25 checks at
320px, and the Python/JavaScript suites retain 48 and 27 passing tests. Evidence
is under `dist/reader-position-checks`: canvas loading/shrink reports, PDE
position reports and screenshots, and regression/unit logs. Other chapters,
figure label collisions/readability, actual devices and source-update selections
remain separate acceptance work.

### Managed delivery and direct target alignment

Clean commit `131b7b54cb75ad7177c5330d42a0098335076985` is installed as the separate
development Reader, PID 23896. Its six served modules/styles match that commit;
the live PDE compile has exit code zero and passes the content gate. At 390px
and 18px text the equation component has width/scroll width 343/343, and the
whole page is 375/375. Original PDF port 23625 remains HTTP 200 in PID 39357.
The delivery receipt and screenshot are `managed-update.json`,
`managed-browser.json`, and `managed-pde-390.png` under the position evidence.

The managed check exposed a separate initial-navigation issue: 112px scroll
padding could leave the preceding paragraph across the 90px reading reference.
Its later growth could move the requested equation. Root scroll padding now
places the requested target at 88px. The actual-PDE position fixture additionally
checks this initial target before manually settling its font-change baseline.
All nine checks pass for 320→390px and 390→320px with 18→30px text. Evidence is
`pde-direct-320-390.json` and `pde-direct-390-320.json` and their screenshots.

### New entries versus reloads

A further browser check found that URL equality alone could treat a newly opened
named link as a reload, restoring an older position instead of the explicit
target. Initial loading now considers the history entry and navigation type.
The test bootstrap deliberately stores another reading block with exactly the
URL being opened. The new link still lands at its target; after scrolling to a
different paragraph, reloading that URL restores the paragraph instead of its
original fragment. All four checks pass with a 1px before/after reload offset
and no page overflow. Test-only bootstrap code runs before the Reader module;
normal serving does not expose it. Evidence is `entry-browser.json` and
`entry-reload-390.png` under `dist/reader-entry-checks`.

## Native canvas labels before SVG flattening

The independent `--semantic-canvases` option exports original CeTZ label bodies
as semantic HTML/MathML, source anchor bounds, and geometry without baked label
glyphs. Source coordinates are unchanged. Geometry scales uniformly, physical
strokes retain CSS thickness, labels retain their reading-size floor and larger
authored typography, and low-contrast label ink is adapted to its paper surface.
Colliding labels become continuous numbered legends with original-point leaders.
Long bodies keep the full measured width, placing their number above the body.

The compiler fixture covers tiny and larger text/math, fixed physical geometry,
explicit label scaling, stack/fixed-box content and nested canvases. Mathematical
leaves remain MathML without embedded HTML font wrappers. Native labels take part
in the initial counter/reference pass and use the common mathematical renderer;
width/font changes require no canvas compiler requests. Large native geometry
stays inline across transport sections. Offscreen obsolete placements reset
immediately and empty leader SVGs cannot add their default 300px width.

The frozen PDE exposes 58 native figures and 658 label bodies. Each full run at
390px and 320px passes 1,277 checks, covering both 18px and 30px reading sizes,
canonical text, complete label/marker boxes, text/ink sizes, contrast, physical
strokes, separate labels, legend associations and bounded full-page width. The
controlled fixture passes 159 checks at 320px. Evidence under
`dist/reader-label-checks` includes `native-pde-current-390.json`,
`native-pde-wide-legends-320.json` and `native-fixture-current-320.json`.

Source-derived leaf label keys are independent of generated diagram numbering.
Diagram geometry has a source-checked fractional reading anchor. Separate native
position runs pass six checks, including an actual PDE diagram, across font and
viewport changes. A long-legend deadlock is fixed by composing every mathematical
label when any part of its owning canvas is nearby. A real PDE body regression
also found that native loading-notice removal changed page height outside anchor
preservation. That change now uses the shared callback; whole-pixel passage
offsets prevent cumulative scroll rounding. All ten body position checks pass
for 390→320px, with the direct target at 88.125px before font normalization and
88.3125px afterward. Reports are `native-pde-position-390-320.json`,
`native-fixture-position.json` and `native-body-position-390-320.json`.

The paired complete frozen PDE PDFs are byte-identical with a fixed creation
timestamp: 10,758,514 bytes, SHA-256
`3fb2b8cb775215a9d7a3905048489299bad22331b3401c7223bbc48f86d1ef46`.
All 1,914 outside-canvas reference display strings are identical. The extracted
outside-canvas text differs only at one whitespace boundary and its 358,311
non-whitespace characters are identical. Evidence is under `paired-source`.
All 51 Python tests and 32 JavaScript tests pass; compiler integration tests are
enabled with the installed package/compiler paths. The canonical guide compiles.

This is a development option, not mobile-default acceptance. Nine opaque SVG
islands remain: five diagrams using the separate CeTZ 0.3.4 dependency and four
Maquette raster/vector surface plots. Full arrow/leader fidelity, source-update
and selection behavior for native labels, mobile Safari and assistive reading
remain open work. Existing PDF serving and mobile entry routing are unchanged.
