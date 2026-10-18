# Current delivery — 2026-10-18

The PDE Reader is deployed in strict/native mode with a 13px default. The live
Tail Hosting status and deployed Dashboard model select Reader for mobile
automatic entry, while desktop automatic entry and an explicit original-page
choice retain the original PDF address. All original project inputs and authored
CeTZ coordinates are preserved. Physical iPhone fit, display and reference/back
navigation are confirmed; VoiceOver speech is explicitly deferred.

The completed coverage and delivery receipts appear at the end of this report.
The earlier checkpoints below describe their historical implementations and
failures; they are not unresolved failures of the current deployment.

# Historical development checkpoint — 2026-10-17

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

### Managed native label delivery

Clean commit `7dd8e8c7db02ddacea989e4ed4a2bfa40e98843c` is installed as the
independent development Reader, PID 46603. Its live saved-source compile exits
zero and passes the content gate. All six inspected modules/styles match the
commit. The real torsion diagram has width/scroll width 343/343 at 390px/18px;
all six labels are native, with four at their source points and two continuous
legends. Whole-page width/scroll width is 375/375. The original PDF remains
HTTP 200 in unchanged PID 39357. Receipts and screenshot are
`managed-update.json`, `managed-browser.json` and `managed-native-390.png` under
the label evidence. Mobile-default routing remains unchanged.

## CeTZ 0.3.4 and Fletcher coverage

The separate older-version fork preserves its original processing and geometry
while sharing native export with 0.4.2. All seven compiler/API tests pass,
including the older CeTZ/Fletcher PDF fixture's byte identity. Its browser
fixture passes 45 checks at 320px, with explicit hat/tilde regression cases.
The actual five newly covered diagrams pass 111 checks at 390px. The frozen
PDE now exposes 63 native figures; all 1,387 checks at 320px pass across 18px
and 30px. The existing native fixture retains 159 passing checks.

The older figures exposed an intrinsic-width feedback loop for short accents.
Their mathematical budget now comes from the available canvas width; optical
insets are included in candidate and published geometry, retaining the complete
italic/accent ink without changing font sizes. Relative 0.3.4 units remain an
explicit unsupported case, retaining their original paint.

All 67 original SVG roots retain their dimensions. Each of the 2,121 retained
vector primitives has identical attributes and ancestor transformations to the
source rendering. The 51 removed paint primitives belong to semantic label
content, including mathematical bars and transparent boxes. All 1,913 reference
display strings outside drawing wrappers and all 358,311 non-whitespace prose
characters remain identical. The complete PDE PDF remains byte-identical:
10,758,514 bytes and SHA-256
`3fb2b8cb775215a9d7a3905048489299bad22331b3401c7223bbc48f86d1ef46`.

Evidence under `dist/reader-label-checks` includes `legacy-cetz-fixture-320.json`,
`legacy-cetz-pde-390.json`, `shared-native-fixture-320.json`,
`shared-native-pde-320.json`, `legacy-cetz-vector-fidelity.json`,
`legacy-cetz-outside-text.json` and `legacy-cetz-pdf/verification.json`.
At this older-version checkpoint, four Maquette raster/vector surface plots
remained outside native composition; the following adapter covers them.

## Maquette axes, source update and table composition

The frozen PDE now has 67 native figures and 699 native labels: 58 CeTZ 0.4.2,
five CeTZ 0.3.4/Fletcher and four Maquette 0.1.3 figures. No opaque SVG root
remains in this snapshot. Original Maquette PNG data URIs are byte-identical.
Native axis x/y, text anchors and baselines retain their original data; font
changes no longer rescale the nested raster frame a second time. Geometry
fills its available width while label/stroke sizes remain independent.
The surface fixture and full PDE PDF remain byte-identical. Full PDF proof:
10,758,514 bytes, SHA-256
`3fb2b8cb775215a9d7a3905048489299bad22331b3401c7223bbc48f86d1ef46`.
Receipts are `surface-source-audit.json` and `surface-pdf/verification.json`.

After full-width fitting and the late-font scroll guard, all 67 native figures
pass 1,475 checks at 320px with both 18px and 30px fonts. No label, mathematical
ink, source text, contrast, marker, physical stroke, page-width or canvas-request
check fails. Evidence is `all-native-fullwidth-pde-320.json`.

Canonical geometry identities normalize internal SVG IDs. Source label keys
include their enclosing figure identity, and manifest lookups survive transport
repartitioning and numeric ID reuse. In an isolated copy of the actual PDE,
eleven browser checks pass after two preceding surface insertions. An active
native axis selection remains intact across the first accepted source update;
its logical quotation relocates to the same plot. The original panel IDs change
55→56→57, retaining source identity
`01578404a7bb7d55ea54468c69ba2a50e0f3d8c816d2c8b921cca2a11c413719`.
Its label top changes 88px→87.546875px; the second update preserves the geometry
reading fraction within the 1px tolerance. `pde-native-source-update.json`
records the result. The original PDE sources were not edited.

All six actual HTML tables now compose vertically without cloning source cells
or mathematical nodes. Their 94 cells retain canonical content and original
order. At 320px and 18px/30px fonts, 629 browser checks pass, including mathematical
ink, readable fonts, header associations and component/page bounds. A merged
header fixture and an unheaded-data fixture also pass in the same report:
`tables-pde-320.json`.

All 59 Python tests and 37 JavaScript tests pass with compiler integration
enabled. Mobile Safari, assistive devices and mobile-default acceptance remain
open; these software checks do not establish physical-device behavior.

At 390px, the six tables pass the same 629 checks at 18px/30px; every component
and the page remain bounded. Evidence is `tables-pde-390.json`.

The all-relationship audit exposed transparent alignment columns blocking one
derivation's RHS from wrapping at 273px/18px. Flattening only those columns fixes
the actual scene; all eight checks pass, including the original compiler path,
arrowhead and transform signature. All 6,873 saved corpus expressions pass at
273px at both 18px and 30px with zero overflow, errors, token binding failures, logical-text or
SVG changes. Evidence is `graphics-12-fixed-320.json` and
`alignment-corpus-273-18.json` and `alignment-corpus-273-30.json`; these include
the current renderer hashes alongside the original corpus provenance. The full
relationship audit continues separately.

The final overlay PDF, including one-ended connector support, is still
byte-identical: `complete-native-pdf/verification.json`.

### Managed complete native figures

Clean commit `c24d0f514d1d303d25a093591bb86130b7b2e5fd` is installed in the
independent Reader on port 23627, PID 66830. Its accepted live-source revision is
`56b26dce44537b7a4b731598fee2d7e6d836a1a7f3b5cd0dea369a1b14b2676b`.
Compilation exits zero and the content gate passes. All eight inspected assets
match that commit. The live saved source has 66 native figures and 685 labels,
with zero opaque SVG roots; these counts differ from the frozen 67/699 audit
snapshot. The formal-adjoint table measures 343/343px at a 390px viewport and
18px text, with all 17 mathematical views ready. The page measures 375/375px.
Screenshots and receipts are `managed-table-390.png`, `managed-surface-390.png`,
`managed-complete-native-install.json` and `managed-complete-native-delivery.json`.
The original PDF remains HTTP 200 in unchanged PID 39357. Mobile-default routing
remains unchanged.

### Relationship paint measurements

The free-end arrowhead case now passes 17 browser checks across 18px and 30px
at 320px. This includes hiding a colliding candidate while its replacement is
pending, preserving original compiler paths, transforms and arrowheads, native
targets, complete math and bounded width. Evidence is
`graphics-arrowhead-publication-320.json`.

Another apparent collision came from `getPointAtLength(0)` reporting an isolated
unpainted `M 0 0` before the actual subpath. Shared painted-path sampling removes
that phantom point for relationships and native label placement while retaining
round/square zero-length stroke caps. The actual relationship passes all 15
checks across both font sizes: `graphics-15-painted-origin-fixed-320.json`.
The sixth relationship also passes all 15 checks at both font sizes:
`graphics-6-painted-strokes-320.json`. A complete repeat of all 67 native figures
with the shared sampler passes all 1,475 checks at 320px and 18px/30px, without
compiler canvas requests: `all-native-painted-strokes-pde-320.json`.
All 42 JavaScript tests pass, including the SVG sampling and free endpoint
regressions. The unchanged Python/Typst modules retain their 59-test passing run.

An actual iPhone Mirroring connection was attempted but timed out before device
content became available. Mobile Safari and VoiceOver remain unverified; these
software checks do not claim physical-device acceptance.

### Managed painted-stroke update

Clean runtime commit `9680ef15a601a17295f3796f079195b682e0b904` is installed on
the independent Reader endpoint, PID 73655. Its live-source compile exits zero
and passes the content gate in 25.741 seconds; accepted revision:
`fdad60f7d56bf5c5c6343f94c312e9e29c7bbc761f2cd016bab61b43d06ca28f`.
All eight inspected assets match the commit. Delivery retains 66 native figures,
685 labels and zero opaque SVG roots. The actual formal-adjoint table measures
343/343px at 390px/18px; all 14 mathematical views inside the table are ready,
the target is at 88.125px, and the page measures 375/375px. The original PDF is
still HTTP 200 in unchanged PID 39357. Evidence is
`managed-painted-strokes-delivery.json`, `managed-painted-table-390.json` and
`managed-painted-table-390.png`. The temporary viewport override was reset.
The development notice and existing mobile-default routing remain unchanged.

### Mathematical ink surfaces and compiler reuse experiment

The complete relationship sweep exposed a failure at 30px in relationships 6
and 10 despite their isolated checks. A text `Range` includes the CHTML font's
empty ascent/descent area; in relationship 6 that box covers a fixed north
endpoint although the glyph's measured paint leaves a clear channel. The
collision inventory now uses CHTML glyph and complete stretched-operator
surfaces, preserves target identities, and excludes assistive/staging copies.
The horizontal math-bound check shares the same glyph-surface selection policy.
All 44 JavaScript tests pass, including a regression that reproduces the blocked
endpoint with the old font box and keeps its exact clear path with glyph bounds.
The original native canvas sampling and mathematical composition are unchanged.

An isolated full-PDE `typst watch` experiment uses an owned symlink source view
and a temporary package request file. It preserves the two actual relationship
SVGs exactly against fresh compiler requests, preserves a return to the initial
geometry, and leaves every source Typst file's size/mtime unchanged. All six
checks pass. Cold watch output takes 38.6191 seconds; the two geometry updates
take 17.8852 and 20.7666 seconds. Thus the earlier tiny-fixture watch result is
not evidence of a fast PDE renderer. No persistent compiler worker was installed.
All owned watch processes and their temporary source views were cleaned up.
Evidence is `watch-pde-probe.json` and `watch-pde-*-graphic-*.svg` under the label
evidence directory. Component evaluation/caching remains performance work.

Splitting the same experiment's inputs into one file per relationship reduces
the two warm updates to 5.909 and 6.3319 seconds, after a 41.5882-second cold
compile. All four checks pass, retaining the previously verified fresh SVG
identities and unchanged source files. `watch-pde-per-scene-probe.json` records
this result. This experimental worker is also terminated and remains outside
the installed service.

The installed-service path instead gains per-component relationship caching.
Its compiler integration test renders two relationships together, reuses either
without recompilation, compiles only one changed layout in a mixed batch, and
compares a cached component's geometry with a fresh standalone request. It also
checks cached accepted output after a failed save, rejects new geometry against
that changed source, and clears component entries on a newly accepted revision.
All 60 Python tests pass in 33.873 seconds with compiler integration enabled;
all 44 JavaScript tests pass. Logs are `python-tests-component-cache.log` and
`node-tests-painted-ink.log`. The complete current-client relationship sweep
continues separately.

The actual problematic relationships 6 and 10 now pass all 15 focused browser
checks together at 320px/30px: ready complete mathematics and relationships,
original marked targets, zero ink collisions/unrouted connections, unchanged
compiler path/arrowhead/transform signatures and bounded component/page width.
`graphics-glyph-surfaces-critical-320-30.json` records the result and measured
glyph obstacles. The temporary viewport was reset and the focused tab closed.

The full current-client sweep now passes all 211 checks for all 15 actual frozen
PDE relationships at 320px and both 18px/30px. Every source target, complete
formula, compiler path/arrowhead/transform signature and component/page bound
passes, with zero ink collisions or unrouted connections. Evidence is
`graphics-complete-glyph-surfaces-320.json`. The temporary viewport was reset;
the completed test tab and its owned server were closed.

Clean runtime commit `60275aeba39e3bf3e02101e09e8ca76ba65c0aad` is installed,
PID 78847. Its accepted compile exits zero and passes the content gate in 26.356
seconds, revision
`c2e6365469a6e9f5ed32c8c1cc00f335dc40f36b6f08f5ad58cc9a1b20af75f9`.
All eight inspected assets match; the live source retains 66 native figures,
685 labels and zero opaque SVG roots. The original PDF remains HTTP 200 in
unchanged PID 39357. `managed-glyph-ink-delivery.json` records the delivery.

An actual PDE relationship batch is then reused as individual requests with
identical results in 0.0383 and 0.0204 seconds. The uncached two-program batch
takes 52.4846 seconds under concurrent validation load. This proves cross-batch
cache reuse, not fast initial compilation. `managed-component-cache.json`
records the measurements. The actual deployed sixth relationship also reaches
ready at 320px/30px with complete 30px mathematics, zero collisions/unrouted
connections and 273/273px scene plus 305/305px page bounds.

Final dark-mode inspection finds the equation number on its light relationship
paper inherits the page's pale muted color, RGB 160/177/184. The frame now scopes
the matching light palette, including numbers and references. Mathematical
geometry and source coordinates are unchanged by this color correction.

The clean `b0838f54b4d2ba23b1430090bcea2bf530b6df5b` runtime is installed as
PID 82631. Its accepted compile passes the content gate in 10.027 seconds,
revision `962a18d6490b4f4effc258f61452465bfd3844ebc134d68337f130d9185fa49c`.
All eight inspected assets match; the original PDF remains HTTP 200 in unchanged
PID 39357. Actual equation-number contrast on light relationship paper improves
from 2.125866 to 4.742045. `managed-light-palette.json` and
`managed-light-palette-delivery.json` record the measured colors and delivery.
`managed-light-palette-table-390.jpg` shows the actual current table at 390px,
18px base mathematics, with 343/343px table and 375/375px page bounds.

The complete 67-figure native sweep also passes all 1,475 checks at each of
390px, 430px and 768px, with both 18px/30px fonts. Evidence is
`all-native-pde-390.json`, `all-native-pde-430.json` and
`all-native-pde-768.json`. Together with the current 320px repeat, these cover all
four required viewport widths for native figures; device accessibility and
other component gates remain separate.

The guarded Dashboard entry passes 15 Node tests and 14 independent browser
checks at 390px with simulated touch input. The browser fixture performs a real
reload and covers explicit preference, focus retention, status refresh, strict
versus development output, failed saves, missing revisions and unavailable
storage. Its direct open link reaches the exact owned Reader sentinel in a new
tab. Logs and `dashboard-entry-browser-390.json` are under
`dist/reader-entry-checks`. These are fixture results, not actual-device proof
or automatic-default promotion.

Tail Hosting's observation/mode/identity changes pass all 14 management tests.
Reader's public-state option test is part of the 61 passing Python tests in
`python-tests-mobile-state.log`. An additional body-math browser sweep now traverses the actual Reader sections and
their nested containers with normal viewport eligibility and publication;
it does not replace real container widths with the independent corpus budget.

Clean runtime `d6cd3f1d6d70d47f22bae895f77c041a475a92ef` is installed as PID
90739. The accepted live revision is
`e24d800b937d13bc184e2081848e300f382c159a7dbe4431f8199d2514052dd4`, with a
64.645-second compiler result during concurrent validation. Native figures stay
enabled and development remains explicit. Only the Reader and the Tail Hosting
status monitor were updated; PDF PID 39357 is unchanged and serves HTTP 200.

The Dashboard files are published atomically after comparison with saved file
hashes. Both served assets match their published files. Its actual HTTPS card
preserves an explicit Reader choice across reloads, and its direct document
link opens the actual managed Reader at port 23627 with the original-page link
intact. The choice is restored to automatic after checking. At 390px both
controls are 44px high and the page is bounded at 375/375px. Evidence is
`dashboard-mobile-publication.json`, `mobile-managed-delivery.json`,
`dashboard-live-navigation.json`, `dashboard-live-controls-390.json` and
`dashboard-live-reader-390.jpg` under `dist/reader-entry-checks`. The development
Reader is correctly excluded from automatic selection; no mobile-default
promotion is claimed. The original PDF and ingress are preserved.

Both companion patches apply to their recorded bases and reproduce all changed
files exactly. Existing external files are preserved under
`dist/reader-entry-checks/mobile-base-20261017-205126-138881`. The completed
loopback Dashboard fixture tab and port 61522 server are closed.

The actual Reader body sweep completes all 56 frozen PDE transport sections at
320px with the 30px font setting: 7,006 body-math occurrences and 21,075 completed
checks pass with no mathematical or horizontal-ink failures. These include the
Reader's visible explanatory-note occurrences and exclude native figure, data
table and relationship math covered separately. The real nested budgets reach
170px in the completed first range; they are not replaced with the independent
273px corpus width. `body-math-pde-320-30.json` records the combined evidence.

The first attempt completes sections 0–30, then stops while a short arrow is
outside the normal rendering margin. Centering that arrow left the Reader's
90px reading reference inside a preceding expanding formula. The harness now
aligns each audited passage to the ordinary reading reference. Sections 31–55
then pass all 10,697 checks, zero errors/failures, as recorded in
`body-math-tail-320-30-summary.json` and its full native accessibility record.
The prefix's bridge-truncated check-name list is explicitly disclosed in the
combined result; its completed section counts, ready counts and error summary
are retained. No production layout or source code changes are needed for this
test navigation correction.

The body harness also keeps its large report as non-executable JSON outside the
layout/accessibility tree and displays a compact progress summary. It records
numeric check counts and per-section counters so the bridge cannot truncate a
long list of successful check names. The initial browser-control session stops
responding while collecting a long report; resetting only that tool restores
native observation without restarting document services.

The 430px and 768px table sweeps each pass all 629 checks for the six actual
tables and 94 original cells at both font settings. Together with the existing
320px/390px runs, every required width passes. Evidence is `tables-pde-430.json`
and `tables-pde-768.json`. Their completed temporary tab is reused for the
390px/18px body sweep; the unused port 61520 fixture server and timed-out
background relationship tab are closed. The broader 390px relationship sweep
is incomplete: eight 18px relationships pass before its inactive-tab wait
expires at relationship 9. This is not counted as a completed wider sweep or a
layout pass.

The compact current body harness also completes all 56 sections at 390px/18px:
7,006 body-math occurrences, all 21,131 checks passing, zero errors/failures.
This run includes the additional per-section expression-coverage check and
retains all section counters without bridge truncation. Evidence is
`body-math-pde-390-18.json`, bound to frozen revision
`faeb2eb5506ff1379bb5f3d9bb780bd5aba643b18fffb15600df534d38bb19c8`.
The temporary viewport is reset and the completed test tab is closed. These
results do not claim wider relationship acceptance or Safari/VoiceOver testing.
The port 61523 fixture server is then stopped with no compiler children left;
`body-fixture-cleanup.json` records its cleanup. No temporary test servers remain.

### 13px default and viewport correction (2026-10-18)

The supplied iPhone image shows a narrow left column after a pinch. The Reader
has no whole-page transform or CSS zoom. A browser resize probe reproduces a
related real overflow: at 320px outer width the layout is 305px, while obsolete
decoration/relationship SVGs retain 359px scroll width during recomposition.
`dist/reader-viewport-checks/before-stale-paint-fix.json` records that failure.

The paint schedulers now retire obsolete SVGs synchronously before debounce or
compiler busy checks, including when their math is pending. The viewport also
requests device width, initial/minimum scale 1 and `shrink-to-fit=no`, without
disabling user enlargement. Anchor handling compares root `clientWidth` instead
of WebKit's pinch-sensitive `innerWidth`. The selected text size is held at 100%
text-size adjustment. HTML, CSS, JavaScript and drawing validation support the
13px default. Legacy font preferences transition once; subsequent choices persist
in 1px steps. Saved position and highlight keys are unchanged.

Fresh and legacy-20px browser cases each pass 26 checks across
390 → 320 → 430 → 390px, including reload persistence and a synthetic visual-only
resize. At the 320px step both layout and scroll width are now 305px. Final
original relationship paint and both decorations return automatically, with no
overflow. `fresh-font-viewport.json` and `legacy-font-viewport.json` record the
results. The normal runtime browser suite passes 25 checks, including selections,
canonical mathematical text, decorations, original relationship paint and failed
request recovery. The 320px and 390px native figure fixtures each pass 80 checks
at 13px, preserving original geometry, native labels and complete math.
The 61 Python tests and 46 Node tests pass; the additional actual legacy-canvas
compile at 13px passes all eight canvas tests. The Typst developer guide compiles.
The generated-document check cannot run because `typlite` is unavailable; the
changed guide is not one of that script's generated Markdown inputs.

This evidence is desktop Chromium with explicit viewport sizes. The synthetic
visual resize isolates anchor behavior; it is not a physical iPhone pinch test.
The supplied device's exact Safari/WKWebView behavior is not independently
reproduced, and mobile-default promotion remains gated. WebKit documents its
wide-content shrinking behavior at
https://webkit.org/blog/7367/new-interaction-behaviors-in-ios-10/ ; its current
`ViewportConfiguration.cpp` implements `shrink-to-fit` and minimum-scale handling.

Clean commit `c25d65efde2c57f48f9024fc70f967fcde2a9328` is installed in the
managed Reader only, with development/native-canvas settings retained. Public
HTML, CSS and all changed runtime modules match their committed bytes. Reader
PID 98459 accepts revision
`7706cb8b575d8f8e2c12e12e8e6e8835bbaace46c4b1589d1def49347158e110`
with exit 0 and content gate true. The actual Translation Invariance passage
uses 13px throughout visible math at 390 → 320 → 430 → 390px, with matching
layout/scroll widths 375, 305, 415 and 375px. The original PDF remains HTTP 200
in unchanged PID 39357. `managed-delivery.json`, `managed-pde-widths.json` and
`managed-13px-390.jpg` record delivery under `dist/reader-viewport-checks`.
The additional 320px/13px native fixture also passes all 80 checks. Both
temporary fixture ports 61524/61525 are closed, and the viewport override is
reset. No physical iPhone pinch result is claimed.

### Device confirmation and current-source acceptance (2026-10-18)

The user confirms the refreshed 13px Reader on a physical iPhone returns from
pinch reduction with no blank margin: “여백 없이 정상입니다”. This supersedes
the earlier pending physical-pinch result, without asserting a browser version,
VoiceOver speech or a complete mobile Safari fidelity audit.
`dist/reader-rollout-checks/iphone-pinch-confirmation.json` records the answer
against installed runtime `c25d65ef`.

A new frozen dependency snapshot copies 48 discovered project inputs and 16
fonts (6,113,884 bytes), records 136 external dependency hashes, and verifies
the originals stayed unchanged during capture. It does not copy the project's
unrelated gigabyte of files. At revision
`dabba9c4ad86787922eccf1862b2dadb467df7c0f168a5f078a30b0ac19538df`,
all 15 relationships at 390px and 13px/18px/30px pass all 316 checks, including
original vector content, mathematical ink and noncolliding routed geometry.
The harness uses ordinary Reader links for unloaded targets, records its active
phase and stores its full report outside layout and the accessibility tree.
This is a complete run; the earlier incomplete wider run is not counted.
Evidence is `graphics-pde-390-13-18-30.json` under the same audit directory.

Using this source snapshot, the original and Reader-overlay PDF compilations
produce identical 10,772,752-byte files, SHA-256
`bfe87286c97ec8b375426e3ddebffe6a4efaa0a416b493f7932a1c36ed7376b5`.
Both use creation timestamp 1735689600 and the same project/font inputs.
`pdf/verification.json` records the commands and digests. No original source,
CeTZ coordinate or installed package is rewritten.

Actual-book navigation passes seven checks covering distant native hash links,
back, forward and reload. A separate owned source copy passes ten selection
checks through an invalid save and a valid insertion of 200 preceding paragraphs.
The selected Translation Invariance equation moves from transport section 43 to
44; the exact quotation and reading top 87.59375px survive the failed save,
deferred accepted revision and selection release. All 64 copied inputs are then
restored; the watcher is stopped and its port closed. Evidence is
`native-history-pde-390.json`, `selection-source-update-pde-390.json` and
`source-update-cleanup.json`. Original source files are never edited.

The English export previously inherited the Korean Reader shell because its
HTML wrapper was discarded. The Reader now preserves the exported document
language on the article, outline titles, original notes, copied targets and
mathematical views; Korean interface/status names have their own language.
The browser fixture passes all 11 language checks, with HTML/MathML/SVG namespace
handling and explicit local language parts. Typst 0.15.1 does not export every
local `text(lang: ...)` rule; the fixture uses explicit HTML attributes to check
Reader preservation. Unknown source language is not inferred. This validates
markup and tree ancestry, not audible VoiceOver behavior. W3C's language-of-parts
guidance explains why this metadata matters:
https://www.w3.org/WAI/WCAG22/Understanding/language-of-parts.html .
Evidence is `a11y-language-before.json` and `language-browser.json`.

An isolated real launchd job switches immutable runtime c25 (13px) to d6 (18px)
and back to c25 (13px), accepting the complete document after each switch.
Release manifests verify all 357/355 runtime files. The original PDF PID 39357
and production Reader PID 98459 remain unchanged, and all 183 paired HTTP samples
are 200. Cleanup leaves no test job, listener or agent file.
`managed-lifecycle.json` records the completed rehearsal. Failed preliminary
receipts are retained separately: launchd could not execute a Documents-hosted
test launcher, and immediate stop/start could observe a terminating old job.
The fixture uses standard Application Support runtime storage; Reader management
now waits for launchd job removal after bootout. A bounded failure does not
signal another process. The corrected manager is exercised by the completed
rehearsal. Production configuration/launcher/jobs are untouched by that test.

All 64 Python tests and 48 Node tests pass, and the updated Typst developer guide
compiles. The normal actual-Reader runtime suite also passes all 25 checks after
the language change (`runtime-after-language.json`), including canonical copy,
selection-aware publication and automatic error recovery. Wider/default-font
sweeps and spoken screen-reader/device checks remain
separate acceptance work; this checkpoint does not promote automatic mobile entry.

Clean commit `f273e9832e789d14ed94892b4ac00dec8c3ba26e` is then installed
in the production Reader with development/native settings retained. Its seven
public HTML/runtime assets match committed bytes. The accepted revision is
`2b148de81bfe6aaf6d76ae586b3f751fd608ce38818e45a2ce8782163f87c86b`,
exit 0, content gate true, 15 relationships and 66 native figures. Manifest and
article language are English, while the Reader UI is Korean. At the actual
Translation Invariance passage, 390px viewport layout/scroll width is 375px and
all visible math is ready at 13px. The original PDF keeps PID 39357 and HTTP 200;
only the Reader changes from PID 98459 to 9310. Receipts are
`language-managed-delivery.json`, `managed-language-observation.json` and
`managed-13px-language-390.jpg` in the rollout audit directory. Native Safari
inspection times out before a tab is acquired; its running-app inventory alone
does not establish a WebKit or spoken accessibility pass (`safari-attempt.json`).

### Current source, original paint and actual inline lines (2026-10-18)

The user explicitly defers actual VoiceOver speech testing to follow-up work.
`voiceover-deferral.json` records that decision. It is neither a speech-test pass
nor a reason to block this rollout; the remaining device and layout checks are
tracked separately.

The frozen source's 8,756,496-byte HTML is byte-identical to the production
Reader document, SHA-256
`3577cab937601fc63eca8381a85196cc132d750343987784380f0eed9fc533e5`.
`html-source-equivalence.json` records both responses. This source has 66 native
figures, 171 decoration IDs and 7,049 body-math occurrences; older counts describe
their earlier frozen snapshots. All 66 figures pass 728 checks at each of 320,
390, 430 and 768px with 13px text. The 768px result combines complete disjoint
ranges after an observation timeout, retaining that timeout and its provenance.
The current 320px/30px figure run also passes all 728 checks.

All 56 current body sections at 320px/13px pass 21,260 mathematical checks. Its
receipt combines complete ranges with the same accepted revision, exact section
coverage, and matching expression totals. The 430px/13px sweep also passes all
21,260 checks. All six tables and 94 cells pass 317 checks at 320, 390 and 430px
with 13px text. These receipts precede the stronger dynamic-paint sweep and do
not by themselves claim visual decoration coverage.

Two additional runtime defects are reproduced and corrected. In a tall equation,
an original cancellation is visible at y=103px while its explanatory copy at
y=4424px remains native. Previously that copy blocked all paint for the callback.
`decorations-copy-baseline.json` retains the failed result. Nearby occurrences
now compose independently; publication keys distinguish equal-shaped members.
The corrected fixture passes ten checks at 13px and 30px, painting the original
before visiting its copy and retaining both canonical text and assistive
cancellation notation (`decorations-copy-fixed.json`).

The actual PDE Fourier-hat paragraph at 430px/30px previously reports 2.78125px
of italic/accent overhang at a line end. Adding the block warning itself moves
the expression to the next line, where the ink fits, but the old warning remains.
`body-math-fhat430trace.json` records those before/after measurements. Publication
now retires previous notices first, checks the real line and gives an overhanging
inline expression an ordinary line at the same font size. All 77 expressions in
that actual section pass 234 checks afterward (`body-math-fhat430fixed.json`).

The test fixture now persists bounded, same-origin, accepted-revision reports
inside owned `dist` source/output directories. Three real-HTTP tests cover its
origin, revision, path and sequence checks. This endpoint is absent from the
production handler. Reports keep completed ranges separate from interrupted
ones. An initial table audit failure comes from its diagnostic receipt's own
unbroken JSON line; wrapping that test-only receipt and rerunning yields the
completed results above. The failed artifact remains available. The isolated
320px relationship 6 passes all 15 checks at 13px/30px after an earlier full-run
timeout; that timeout is retained and does not count as complete coverage.

All 67 Python tests pass with the real Typst/package configuration, all 50 Node
tests pass, and the developer guide compiles. Full current-source body sweeps now
also require actual decoration paint after ordinary scrolling at four widths
and 13px/30px. Their pending results and mobile device verification still gate
automatic-entry promotion at this checkpoint. Evidence is under
`dist/reader-rollout-checks`, with raw durable reports in
`runtime-durable/browser-audits` and `runtime-decoration-copy/browser-audits`.

### Completed reading and component coverage

The physical iPhone response after installing `a4dc981d` is
“표시와 참조 이동 모두 정상”: ordinary text, mathematics and figures can be
read without zoom or horizontal movement, and reference navigation/back work.
`iphone-reading-confirmation.json` records that scope. Together with the earlier
pinch confirmation this completes the requested physical-device check; no browser
version or spoken VoiceOver result is inferred.

The accepted HTML remains 8,756,496 bytes with SHA-256
`3577cab937601fc63eca8381a85196cc132d750343987784380f0eed9fc533e5`.
During the audit an external edit changes the shared `text-utils/0.1.2/lib.typ`.
The production watcher accepts it automatically, while uncached requests against
the older non-watching fixture correctly return HTTP 409. The edited package is
preserved. Nine required external package versions (51 files) are copied into an
owned fixture, with before/after source hashes. Its newly accepted revision is
`e047bc8d468b51fe7a05e13e17a4d489eea8f9a8e11bd871e657b67b8c743405`.
Its normalized HTML is byte-identical, so the mathematical/figure HTML evidence
can be joined across the recorded dependency snapshots. Dynamic program delivery
is rerun on the new frozen inputs: all 171 IDs at 13px and 30px return both
requested fragments (342 callback cases, 684 fragments). This is compiler delivery
coverage, not a substitute for real-page paint or collision checks. The earlier
interrupted callback receipt remains explicitly incomplete. Production continues
to watch its configured shared packages; only the disposable audit is frozen.

| Component | Viewports | Font sizes | Complete scope |
| --- | --- | --- | --- |
| Body mathematics | 320, 390, 430, 768px | 13px | All 56 sections and 7,049 occurrences at each width |
| Body mathematics stress | 320, 430px | 30px | All 56 sections and 7,049 occurrences at each width |
| Native figures | 320, 390, 430, 768px | 13px, 30px | All 66 figures, 728 checks per width/font set |
| Native tables | 320, 390, 430, 768px | 13px, 30px | All six tables and 94 cells, 629 checks per width |

`body-validation-summary.json`, `native-validation-summary.json` and
`tables-validation-summary.json` enumerate the receipts. Complete current
390/768px body sweeps at 30px are not claimed. The 320px/13px body receipt is the
earlier successful identical-HTML baseline; current corrections retain its
already-fitting publication path. The stronger 430px run passes 42,631 checks
across both fonts; the completed 390px/13px, 768px/13px and 320px/30px runs each
pass 21,316 checks, including an explicit per-section viewport check.

A browser-control reset removes its viewport override during three figure cases.
Their recorded page widths expose the problem: canvas 6 at 390px/30px, canvas 46
at 768px/30px and canvas 66 at 768px/13px. These cases are excluded and rerun at
the requested dimensions. Combined receipts retain interrupted reports and every
replacement's provenance, and verify all 66 exact IDs and valid page widths.
They do not count the out-of-viewport results as passes. Figure/table harnesses
now reject a changed viewport during a case. Tables are repeated in one active
tab with that guard and per-case viewport metadata. All eight figure sets and
all four guarded table sets pass. Incomplete earlier paint sweeps remain partial;
they are not relabelled as complete runs.

### Strict mobile entry delivery

All 15 actual relationships at 320px/13px complete 121 checks with original
nearby paint required before geometry acceptance. Fourteen marked decoration
occurrences are painted alongside their complete mathematical bodies and original
vector paths. There are no collisions, unrouted connections, clipped scenes or
missing compiler paths. `graphics-pde-320-13-paint.json` records the complete
default-font range separately from the subsequent large-font run. The earlier
current-source 390px sweep covers all 15 relationships at 13px/18px/30px with
316 checks. `release-readiness.json` enumerates the acceptance receipts.

Clean runtime `75192e735942626b3ed2ab0bc80c29fcd70a1ae3` is installed with
development disabled and native figures enabled. Reader PID 32201 publishes
revision `fa118df47dce627e63b8768a24515a9e6fd936677211d43351e2e1b357113e1a`,
exit 0 and content gate true. All 17 public HTML/CSS/JavaScript assets match the
committed bytes, and the served document matches the audited HTML digest above.
The original PDF keeps PID 39357; all 46 samples through this real release switch
are HTTP 200. Three consecutive strict accepted-state samples confirm completed
startup. See `strict-install.json`, `strict-delivery.json` and
`strict-delivery-monitor.json`.

The Reader display name loses its development suffix without changing another
registry field or service. The live Hosting API and deployed Dashboard model
now report `acceptedReader: true`: mobile automatic entry opens port 23627,
desktop automatic entry opens port 23625, and explicit Reader/original choices
retain their respective addresses. Health and compilation observations are fresh.
The original PDF endpoint and lifecycle are not redirected or restarted.
`mobile-default-entry.json` records these real delivery decisions. The previous
registry bytes are retained in the local audit directory for review/rollback.
VoiceOver remains the user's explicit follow-up; no speech pass is asserted.

### Empty mark carrier regression

The extra 320px/30px paint lane finds zero-width, empty MathJax wrappers for
decorations 98 and 99 in relationship 9. Every real fragment and the relationship
are already ready, with zero collisions, but the wrappers retain a misleading
loading notice. `empty-mark-notice-before.json` records that actual state.
The status renderer now ignores only composed zero-area carriers; real unpainted
rectangles and native/pending views keep their notices. The paint audit uses the
same nonempty client-rectangle definition. All 51 Node tests pass, including
the regression that distinguishes these three states. The actual large-font
fixture advances past relationship 9 with all eight real decoration fragments
painted and its mathematical/vector checks passing. This correction does not
change source content, coordinates, font size, or drawing callbacks.

The completed 320px/13px+30px relationship result now contains all 30 exact
width/font cases, 241 checks and 36 painted decoration occurrences. The retained
prefix and corrected seven-case large-font range are disjoint and use identical
canonical HTML; interrupted case 9 is replaced, not counted as a pass.
`graphics-pde-320-13-30-paint.json` records the complete joined result. An isolated
repeat of relationship 9 is ready with the same two empty carriers present, all
eight real fragments painted, and no loading text (`empty-mark-notice-after.json`).

Clean runtime `92fa4a5b274a54e3ec8a2277c935d70bcb6ec2fc` is installed in
strict/native mode, Reader PID 35741. All 36 PDF samples in this additional
Reader-only switch are HTTP 200; original PID 39357 remains unchanged. The live
source watcher subsequently accepts further shared-package edits while preserving
the identical audited HTML. The final recorded accepted revision is
`11646cb232bb8c856eda9c211bb7616a5423f10c86d8c143190d6888b0daee4b`,
with exit 0 and content gate true. A later saved edit may normally advance it.
All 17 public assets match this runtime. `final-delivery.json` and
`final-mobile-entry.json` confirm both delivery and mobile automatic selection.

The actual public Reader at 390px shows 13px text and 17 visible ready mathematical
views at 13px; layout and scroll widths are both 375px. Article language is English,
UI language remains Korean, and the saved-document status is normal.
`managed-final-observation.json` and `managed-final-13px-390.png` record that view.
The temporary viewport override is reset. Disposable fixture servers are stopped;
some older detached test tabs cannot be closed through the browser APIs and their
cleanup is not asserted. The delivered Reader tab remains available.

### Published responsive Reader as Flow 0.1.25 — 2026-10-18

- Pushed the completed feature and packaging fixes to `main`; clean release source is commit `73152cf60dc77fd34385822c7bf6e2da2ccd8569`. Built and signed the Apple Silicon app from that revision with `sourceDirty=false`. The bundle and extracted ZIP pass `scripts/flow-app.py verify`; signing certificate SHA-256 remains `1de2d9bd2a9497ff7fd686977fd969ba5b245cef295555af147c4b6eec35ddf5`.
- The first install attempt rolled back after the PDE preview could not read its project fonts folder. After the user approved the macOS document-access permission, retry installed Flow 0.1.25 successfully and the menu app was reopened from Applications. The managed PDE profile is ready; original project files and authored CeTZ coordinates were not changed.
- Verified the original PDF preview and separately managed Reader through local/Tailnet HTTP: both return 200. The PDF route delivered its HTML document; the Reader endpoint remained available on port 23627. The user's iPhone checks confirm 13px mobile display, pinch behavior, reference navigation and back navigation. VoiceOver remains explicitly deferred.
- Pushed annotated tag `flow-v0.1.25`, resolving to the exact clean build commit above. Published [tinymist-flow 0.1.25](https://github.com/kimpossible-TY/tinymist-flow/releases/tag/flow-v0.1.25). GitHub reports `draft=false`, `prerelease=false`, and three uploaded assets whose SHA-256 digests match local files: app ZIP `2075ca760646a6aaaeb157469dd011a103d287f0b63e72a357ab31b90705497e`, release manifest `49e22937b1d45d278cf85e0cdfad3a3492298f0e1fe2b474eca571685dc2df74`, and checksum file `a2a6c63851f61065c6bd7eeffd7dfb96d46d4a5ff53d7fd2afc309404029425d`.
- Flow app CI passed at [run 39086388869](https://github.com/kimpossible-TY/tinymist-flow/actions/runs/39086388869). The general Rust/editor CI run 39086388924 was still in progress at publication; the prior Flow release process gates publication on the Flow app workflow.

The responsive Reader service is managed separately from the macOS app ZIP. Its implementation ships in the repository under `tools/flow-reader` and its deployed endpoint remains a distinct Tail Hosting service.

## Reader appearance refinement — 2026-10-18

The `fix/reader-colors` branch adds Automatic / Light / Dark, applies the saved
origin-local choice before CSS, follows live device changes in Automatic, and
keeps explicit choices usable without storage. Four Node tests cover initial
application, device overrides, reloads, invalid/blocked storage, cross-tab changes
and resets. They pass. The serving suite passes three checks, including delivery
of `theme.js`; four compiler integration tests skip without `FLOW_READER_PACKAGES`.
Prettier, strict OpenSpec validation and patch whitespace checks pass.

An isolated loopback preview uses the working frontend with the currently
accepted PDE output from the managed Reader. Its 281 unstyled HTML marks formerly
used browser-default yellow. Authored and saved marks now share muted amber on
warm paper and deep gold on charcoal. Browser measurements at 320, 390, 430 and
768 CSS pixels pass in both appearances: controls fit on one line in a 56.19px
toolbar, and the observed page has no horizontal overflow. Reload retains Dark.
Native canvases and relationship frames retain light paper, dark ink and local
light highlight tokens. No browser warnings/errors were observed.

Measured text/background contrast is 14.01:1 (light) and 13.42:1 (dark); highlight
contrast is 11.63:1 and 7.39:1. Secondary text and links also exceed 4.5:1 in both.
Measurements and 390px screenshots are under `dist/reader-color-checks/`.
These are desktop browser checks, not a new physical iPhone/VoiceOver acceptance.
The installed Reader has not been changed by this preview. Generated-doc checking
could not run because `typlite` is unavailable; the edited developer Typst source
is not one of the generator's three Markdown mappings.

## Transparent CeTZ and mannot appearance — 2026-10-18

The user's follow-up supersedes the fixed light drawing palette described in the
previous checkpoint. The white blocks came from CSS on SVG roots, native canvases,
label backplates and relationship frames. Those drawing surfaces now blend into
their actual enclosing paper or callout wash. Original neutral paint follows the
reading ink; solid colored vectors, native labels and marked MathML/CHTML terms
receive contrast adjustments from retained source colors. Decoration underlays
use their own marked term's ink when checking readability. No vector coordinates,
SVG coverage masks/gradient resources, reference targets or raster payloads change.

The shared color, native label, decoration and theme Node suites pass all 22 tests.
The serving suite passes three checks including both appearance modules; four
compiler-dependent checks remain skipped without `FLOW_READER_PACKAGES`.
`tests/drawing-theme.html`, served directly from `tools/flow-reader`, passes five
appearance/late-paint phases with 13–16 checks each and zero failures. Coverage
includes callout backplates, semantic colored mathematics, vector/text contrast,
colored symbol use, unchanged masks/gradients/geometry, repeated theme restoration
and an adapted SVG clone arriving on a different background. The observer adapts
new paint independently of compiler response order. Source-color metadata survives
clones without accumulating presentation changes.

The working Reader was checked against actual PDE CeTZ and Jacobi/mannot content
at 390px in both appearances. Canvas/relationship/SVG backgrounds are transparent,
native label paper matches the selected reading background, and observed layout
and scroll widths agree at 375px. The dark marked terms retain purple, red and
blue with readable lighter ink. No browser warnings/errors were observed.
Screenshots and reports are under `dist/reader-color-checks/`, including
`cetz-dark.jpg`, `mannot-dark.jpg`, `mannot-light.jpg`, `drawing-fixture.json` and
`live-drawings.json`. All four original surface-plot raster layers have transparent
background pixels; their sizes, alpha extrema and payload hashes are recorded in
`source-rasters.json`. Two separately authored opaque PNG illustrations retain
their original pixels and intrinsic backgrounds; they are not CeTZ/mannot exports.
Prettier, strict OpenSpec validation and patch whitespace checks pass. The existing
`typlite` limitation remains. This is a local preview, without a new installed
release or physical iPhone/VoiceOver acceptance.

## HTML last visual edit — 2026-10-18

The HTML Reader and paged preview now import the same `ChangeLocationQueue`.
HTML history uses project-scoped canonical body fingerprints and current section
targets, with atomic mode-0600 persistence independent of viewers. New entries
and reloads restore the last visual edit; direct named links and history retain
their destination. Recent gestures defer navigation, including during target
fetches. Selections/dialogs continue to postpone publication.

Validation:

- All 77 Reader Python tests passed with the local Typst package root, including
  nine history tests for restart, disconnected changes, deletions, mathematical
  paint, native geometry, generated IDs, invalid records and rejected saves.
- All 61 Reader JavaScript tests and 80 paged frontend tests passed. The preview
  TypeScript check and preview asset build passed after extracting the shared queue.
- A disposable real-Typst fixture passed 13 WebKit checks at 390px/320px: live
  edits, reload, explicit links, history, gesture deferral, button bounds/click,
  polling failure/recovery, theme/font changes, gestures during destination
  loading, selection release, nonvisual comments and failed compilation. No
  browser application errors occurred in the completed run.
- A read-only audit of an installed 8,756,496-byte HTML snapshot produced 4,862
  tracked blocks across 59 sections. An in-memory late edit resolved to section
  40. Its history record was 1,286,780 bytes, within the 4MiB bound; the two splits
  and observations took 8.36 seconds. The source and installed history were not edited.
- Scoped Prettier, Python compilation, strict OpenSpec validation, generated-doc
  consistency and compilation of the updated Typst development guide passed.

The installed Reader, native app and PDF service were not updated. Physical
iPhone acceptance of this new navigation behavior remains unverified.

## Last-edit Reader installation — 2026-10-18

Installed clean runtime `eede70488f90bb7413f3e036b0ed23e9d81208a5` using the
existing independent Reader installer. The clean detached checkout passed all
76 Python tests, 61 Reader JavaScript tests and 13 real-Typst WebKit scenarios.
The separate outline changes were excluded from this commit and
installation, and their working files were preserved.

The managed `typst-pde-reader` restarted successfully as PID 96124 and accepted
its full document with strict publication and native figures enabled. All 20
public assets match the installed commit. Registered certificate-validated HTTPS
delivery returns the exact managed 8,756,496-byte HTML, with 56 sections. Its new
history baseline contains 4,862 blocks in 1,286,398 bytes with mode 0600. No prior
HTML edit target existed, so the next accepted visual save creates the first one.

On the actual registered Reader origin, a fresh 390px touch WebKit context loaded
the new module without application errors. A browser-only controlled last-edit
hint navigated into actual section 41 and survived reload ahead of a different
saved reading position. The resulting screenshot was inspected. The server's
history stayed at its initial null target throughout this read-only check.
This verifies installed frontend delivery/restoration without editing the book.

Reader configuration bytes and all Flow profile settings are unchanged. The PDF
service remains at PID 65035 and serves the same HTTPS HTML hash; Ewald remains
stopped. Backups, installation/test logs, hashes, browser receipt and screenshot
are retained under ignored `dist/reader-last-edit-install-20261018-122131/`.
The prior immutable Reader release is retained for rollback. The macOS app bundle,
engine, public address and authored source are unchanged. Physical iPhone
acceptance of the new navigation remains outstanding.

## Hierarchical outline installation — 2026-10-18

Installed clean Reader runtime `3823005e0586d464263cc5f891215a1847ab4711` with
the existing managed installer. The previous installed runtime predated the
outline change. The actual PDE outline now contains 109 entries instead of 96,
including its 13 previously omitted h5 headings. Document HTML bytes, configuration
and last-edit history are unchanged; the original PDF service retains PID 65035.
All 23 shell assets match the installed commit on both loopback and HTTPS.

Actual HTTPS WebKit checks at 320px, 390px and 768px confirm 16px additional
indentation per level, no outline horizontal overflow, and navigation to a deep
heading. No application errors occurred, and the 390px screenshot was inspected.
Section and installer tests passed before installation. Receipts, test output and
screenshots are under `dist/reader-outline-install-20261018-130116/`.
