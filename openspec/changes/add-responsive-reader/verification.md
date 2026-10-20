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

# Appearance control refresh — local source, 2026-10-18

The toolbar select is progressively enhanced into an icon/label button and native
auto popover with three labeled radio previews. A persistent selection surface
moves behind stationary labels; the current choice also has a checkmark. This is
a locally tuned frosted web material, not native optical rendering. The original
preference key, before-paint application, device synchronization and storage-error
behavior are retained. Unsupported browsers retain the native select.

- `node --test tools/flow-reader/tests/test_*.mjs`: all 63 tests pass, including
  six appearance tests covering the enhanced/fallback controls, persistence,
  unavailable storage, automatic device changes and cross-tab synchronization.
- Prettier checks pass for `index.html`, `theme.js`, `reader.css` and
  `test_theme.mjs`; `git diff --check` and strict OpenSpec validation pass.
- In-app browser checks use working-tree frontend assets through a separate
  loopback development proxy and the actual managed PDE document. At widths
  320, 390, 430, 580, 640, 641 and 768px, toolbar scroll width equals client width,
  toolbar height remains 56.1875px, and the panel stays inside the viewport.
- Native radio arrow keys change appearance immediately while keeping the panel
  open, keyboard focus is visible, Escape returns focus to the trigger, Enter
  reopens it on the selected radio, outside clicks dismiss it, and seven rapid
  trigger activations leave open/expanded state consistent. Light and dark
  previews and their surrounding actual document were inspected.
- Isolated fixtures exercise the stylesheet's accessibility branches explicitly;
  these are not OS preference emulation. Reduced motion computes zero transition
  duration, solid/transparency fallbacks remove backdrop filtering, and the
  forced-colors branch retains a 2px selected boundary. A 200% root-text fixture
  fits at 320px and 390px, including complete labels and decorative samples.

Evidence: `dist/reader-appearance-checks/viewports.json`,
`accessibility-fixtures.json`, `light-390.png`, `dark-390.png` and `zoom-320.png`.
These are local-source checks, not installed-release or physical-device
acceptance. Screen-reader speech remains deferred as above.

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

## Equation number alignment, 2026-10-18

The HTML exporter wrapped the inline equation number in a paragraph after the
expression. Export a block number directly beside the math instead. A grid now
centers the number vertically at the inline end, reserving its own column and
measuring only the remaining mathematical cell for responsive composition.
Unnumbered equations keep their full width; composition notices occupy another
row.

The `equation-numbers.typ` fixture and `?check=equation-numbers` browser module
pass 627 checks across 320px, 390px and 768px viewports. Each viewport covers
native MathML, 13px/18px/30px CHTML, narrower/wider containers, short expressions,
a tall matrix, a multiline derivation, a long sum with a three-digit number,
unnumbered math, reference retention, and notice placement. No checked expression
or equation block requires horizontal scrolling after composition. Screenshots
were inspected at 390px. Reports and images are in
`dist/reader-equation-number-checks`.

The existing runtime fixture retains all 25 checks at both 320px and 390px,
including selection, canonical copy, decoration fragments, references and stale
composition rejection. All 11 build/adapter tests pass using the installed Typst
package directory, including byte-identical paged output. Prettier and
`git diff --check` pass. These are local Chromium checks; the managed Reader and
physical iPhone were not updated or exercised in this change.

## Combined appearance and equation-number installation — 2026-10-18

Installed clean Reader runtime `c70654cf8982b225a295cd199f57a59d1fbf0972`,
including the appearance preview panel and equation-number alignment. The main
branch retains both source changes in one commit. Installation used a clean,
detached managed worktree, preserving unrelated local skills and engine icon
files. The temporary worktree was archived after the immutable release was saved.

All 63 Reader JavaScript tests and 20 build/installer/manager tests pass, as do
Prettier, strict OpenSpec validation and patch whitespace checks. The managed
Reader restarted as PID 40506 and accepted its full native-figure document with
exit code 0, no compiler-loss warnings and no unsupported constructs. Its 1,413
equation numbers export directly beside their expressions. All 23 public shell
assets match the installed commit over both loopback and certificate-validated
HTTPS. Both origins deliver identical 8,743,779-byte document HTML across 58
transport sections. The last visual-edit target remains null.

Actual HTTPS mobile WebKit checks at 320px, 390px and 768px verify eight equation
layouts per width (four original equations at 13px and 30px), with at most
0.0078125px vertical center difference and no expression/number overlap or
horizontal scrolling in those components. The appearance panel stays inside each
viewport, light/dark choices apply, and Escape closes it. No application errors
occurred. The actual 390px/30px screenshot was inspected. Physical iPhone and
screen-reader speech validation were not repeated for this update.

Configuration bytes and all Flow profiles are unchanged. The original PDF
service retains PID 65035 and its prior HTTPS response hash. The previous Reader
release and rollback launcher/configuration backups are retained. Receipts,
asset hashes, browser measurements and screenshots are under
`dist/reader-session-install-20261018/`.


## Installed appearance controls with saved highlights — 2026-10-18

The final installed Reader runtime is `0b6549dce4cc52bde49e8503b66e3db5a4c49489`.
It retains the combined appearance/equation changes above and reduces only the
compact appearance button's minimum width from 4.8rem to 4.4rem. Actual saved
highlights add a count to the toolbar: the earlier width could put the original
page link on a second row at a 320px desktop viewport with a scrollbar.

Installation used the existing installer from a clean, isolated sparse checkout
of the committed revision, preserving unrelated working-tree files. Its 385
immutable release files pass manifest integrity checks. All 23 public assets
match the installed bytes over both loopback and registered HTTPS (46 checks).
The accepted full document passes its content gate, and both origins deliver
identical HTML. Strict publication and native figures remain enabled.

Actual HTTPS browser checks retain the user's one saved highlight. Automatic,
Light and Dark each keep toolbar height at 56.1875px and scroll width at the
305px client width in a 320px viewport; the panel stays inside that viewport.
Dark survives reload, arrow keys change the native radio choice, and Escape
closes the panel with focus returned to the trigger. The original Automatic
preference was restored after testing. The 390px installed-control screenshot
was inspected; this does not constitute physical iPhone or speech acceptance.

The appearance tests and real clean-commit installer test pass. The managed
Reader runs as PID 43119. Configuration bytes are unchanged, and the original
PDF service retains PID 65035 and HTTP 200. The previous immutable release and
launcher/configuration backups remain available. Receipts and the actual HTTPS
screenshot are under `dist/reader-appearance-install-20261018-134857/`.


## Icon-only appearance controls — 2026-10-18

Installed clean runtime `9ef8a1e0eaf7b95cddce039d0947b86023f7c96a`. The trigger
is a 44px icon-only button; mode names and the live description are visually
hidden while native radio and button accessible names remain intact. Previews
and the selected checkmark remain visible. All 63 JavaScript tests pass.

Actual HTTPS checks cover all three choices at 320px with one saved highlight: no
visible trigger text, 1px clipped choice names/status, a 56.1875px toolbar and no
width overflow. Keyboard selection and Escape/focus return work; the original
automatic choice was restored. The inspected 390px screenshot and receipts are
in `dist/reader-icon-only-install-20261018/`. All 385 release files pass integrity
checks and all 23 public assets match over loopback and HTTPS. Accepted document
HTML and configuration bytes are unchanged; the original PDF retains PID 65035
and HTTP 200. Physical device and speech acceptance were not repeated.


## Remove the toolbar page-view link — 2026-10-18

Installed clean runtime `e9e7c9ad82afc42da7a11c15e7239000720350ef`. The page-view
anchor, poll-time link update and obsolete positioning rule are removed. Text
size and appearance controls align at the toolbar's inline end. Existing paged
addresses and Dashboard choices remain available.

All 63 JavaScript tests, syntax/formatting checks and strict OpenSpec validation
pass. The 385-file release manifest is intact, and all 23 public assets match
over loopback and HTTPS. Actual HTTPS checks at 320px, 390px and 768px find zero
toolbar links, no original-link element, no width overflow and a 56.1875px toolbar.
Reading controls end 8px inside the client edge at each width. Appearance radio
keys and Escape/focus return work; Automatic and the saved highlight are retained.
The 390px installed screenshot was inspected. Receipts and the image are in
`dist/reader-remove-page-link-install-20261018/`. Accepted document HTML and
configuration bytes remain unchanged; the original PDF retains PID 65035 and
HTTP 200. Physical device and speech validation were not repeated.


## Minimal navigation and reading gestures — 2026-10-18

Installed clean runtime `cef42231292938223a58b6e405508daba43c23c6`. The toolbar
contains two 44px icon buttons and centered Flow branding. Reading settings
contain text-size controls, the existing unlabeled appearance previews and saved
highlights. The outline is an independently scrolling native modal drawer.
Article pinch gestures preview a 13–30px text size and commit reflow once on
release; inner-left rightward swipes open the outline, and reverse swipes close it.

All 68 JavaScript tests, seven compiler-enabled serving tests, the clean-install
test, source formatting/syntax checks and strict OpenSpec validation pass. The
real Reader fixture passes 26 synthetic-touch/interaction checks at each of
320px, 390px and 768px. Coverage includes pinch preview/commit/reverse, cancellation,
third-finger exclusion, selection and vertical-scroll guards, browser-edge and
link exclusion, drawer modality and cancellation, rapid reopening, settings/font
and saved-highlight alternatives, focus return, unsupported-popover fallback and
live reduced-motion cancellation. Canonical text/math order is retained.

Actual registered HTTPS checks in Chrome verify two 44px toolbar actions, a
56.1875px toolbar, no horizontal overflow and contained settings panels at all
three widths. Font buttons reflow 13px to 14px and back; outline navigation closes
the drawer and focuses the article. Escape returns focus to each trigger. The
original Automatic/13px preferences are restored and no browser errors occur.
The inspected installed/settings/outline screenshots and measurements are in
`dist/reader-navigation-install-20261018-retry/`; synthetic reports are under
`dist/reader-navigation-checks/`. Synthetic events and desktop viewport checks do
not establish physical iPhone touch arbitration or perceived gesture quality.
Physical-device gesture and screen-reader speech validation were not performed.

All 388 immutable release files pass integrity verification. All 24 public assets
match the release over loopback and HTTPS (48 checks). Accepted document HTML
retains SHA-256 `876b8a52a28cac7d3f5123be7b17eaf94f6eecb638f767909d5e56a623eb74a3`,
configuration bytes are unchanged, and strict/native delivery remains enabled.
The managed Reader runs as PID 65514; the original PDF retains PID 65035, HTTP 200
and its prior response hash. Rollback launcher/configuration backups are retained.


## Remove the normal document caption — 2026-10-18

Installed clean runtime `74d52424c96d30b8447039267d10cb2aacf1e0e5`. The normal
accepted-document status has empty text and `display: none`, removing its margin
and height. Loading, compilation, development and error messages retain their
existing states and remain visible when applicable.

All 68 JavaScript tests, formatting and strict OpenSpec validation pass. Actual
HTTPS inspection verifies a ready document, empty status text, zero status
height and no horizontal overflow at 390px. All 388 immutable release files and
48 loopback/HTTPS asset checks pass. Document/configuration bytes and the original
PDF service remain unchanged. The managed Reader runs as PID 69222. Receipts and
the inspected screenshot are in `dist/reader-remove-ready-status-install-20261018/`.


## Plain toolbar icons — 2026-10-18

Installed clean runtime `5d24941230eeb464b2162f2a1e3e853ca632b9b8`. Reading settings
now match the outline's plain icon treatment. Actual HTTPS inspection at 390px
confirms transparent backgrounds, zero borders and no shadows on both controls,
21px icons and retained 44px targets. Settings still open, focus the font action
and close normally; the page has no horizontal overflow. Formatting and strict
OpenSpec validation pass. All 388 release files and 48 asset delivery checks pass,
with unchanged document/configuration bytes and original PDF delivery. Receipts
and the inspected screenshot are in `dist/reader-plain-toolbar-icons-install-20261018/`.


## Floating outline capsule — 2026-10-18

Installed clean runtime `0c3d09807b858e2e2c1ae0dfc695acca65f6a231`. The outline
floats below the toolbar with 16px side gaps, a 32px radius, a restrained frosted
surface and a softer scrim. It fits short outlines and limits long ones to 60%
of viewport height or 34rem. All heading levels retain wrapping, indentation and
44px targets. Opening marks the current heading with an accessible location pill
and reveals it inside the independently scrolling list. A close icon, outside
dismissal, Escape, swipe cancellation and interruptible spring motion remain.
Travel includes the floating inset and shadow; the controller also preserves
scroll coordinates through native dialog focus before resolving the current row.

All 68 JavaScript tests, syntax/formatting checks and strict OpenSpec validation
pass. The browser fixture passes 31 interaction checks at 320×844, 390×844,
768×1024 and 768×360, including nonzero reading-position preservation after both
opening and settling, current-row semantics, floating bounds, reversal,
cancellation, reduced-motion changes, fallbacks and canonical text/math order.
The reports are in `dist/reader-floating-outline-checks/`.

Actual registered HTTPS checks in Chrome cover the long PDE outline at those
widths and a short landscape viewport. The 390px capsule measures 343×506.39px
at (16, 68), and the 768×360 capsule remains within (16, 68)–(368, 284), including
its 44px close control. Light and dark surfaces were inspected. Native pointer
activation keeps the reading offset at 343px and marks Notation; outside dismissal
also retains 343px. Escape returns focus to the outline icon, navigation focuses
the article, and wheel input scrolls the outline. The current row is revealed
again on reopen. Automatic appearance is restored and no browser errors occur.
Screen pointer input was used for the sticky toolbar: locator-based automation
scrolls that trigger's original layout position before dispatch, which initially
looked like an application scroll regression.

All 388 release files pass integrity checks; all 24 public assets match over
loopback and HTTPS (48 checks). Accepted document/configuration bytes and the
original PDF service remain unchanged. The Reader runs as PID 90581. Installed
light/dark screenshots, measurements and delivery receipts are in
`dist/reader-floating-outline-install-20261018-final/`. These checks do not
establish physical iPhone gesture feel, frame timing or screen-reader speech;
those were not repeated for this update. Solid contrast/transparency fallbacks
are implemented; operating-system preference emulation was unavailable.


## Remove reading-panel instructions — 2026-10-18

Installed clean runtime `cbf6032c575f42b539e75cfbea0852f2e2076e94`. The outline's
swipe footer and settings' pinch/swipe paragraph are removed with their unused
styles. The saved-highlight storage explainer and how-to empty-state instruction
are removed; a concise empty-state message remains. Outline bottom padding and
settings action spacing keep the compact panels balanced.

All 68 JavaScript tests, formatting and strict OpenSpec validation pass. Actual
HTTPS inspection at 390px confirms zero gesture/helper blocks, zero outline
paragraphs and a single neutral empty-state paragraph in saved highlights.
Outline/settings/highlights open and close correctly; saved-highlight dismissal
returns focus to settings. No horizontal overflow is present. All 388 release
files and 48 asset checks pass. Document/configuration bytes and original PDF
delivery remain unchanged; the Reader runs as PID 95037. Delivery receipts,
browser measurements and the inspected screenshot are under
`dist/reader-remove-instructions-install-20261018/`.


## Playful outline dismissal — 2026-10-18

Installed `d2e25325180756f5fb2354afa9aa9410810acdd0` after an initial compile timeout and automatic rollback. The old runtime subsequently completed its document compile; the successful retry verified all 388 release files and 48 local/HTTPS asset deliveries, unchanged configuration and original PDF delivery. Receipt: `dist/reader-playful-dismiss-install-20261018-verified/`.

All 69 JavaScript tests and strict OpenSpec validation passed. Actual HTTPS browser checks confirmed outside dismissal, focus return, reopen with 109 outline links and Escape/Return keyboard operation. Motion continuity is covered by the pure trajectory test; physical iPhone motion and OS reduced-motion switching were not repeated in this pass.


## Outline exit and swipe repair — 2026-10-18

The supplied iPhone recording shows animated entry but abrupt dismissal. Closed-dialog visibility was coupled to CSS display/overlay transitions; opening swipes also required the narrow 24–96px start band. The panel now uses an inert, assistive-hidden fixed visual layer for drag previews and exits, moves into the native modal only on committed opening, and returns to the closed dialog after exit. The article accepts starts outside the outer 24px edges and ignores height-only viewport changes for cancellation.

All 69 JavaScript tests, formatting and strict OpenSpec validation passed. The synthetic touch browser suite passed 37 checks in Chrome at 390×844, 320×740 and 768×360; desktop Safari also passed all 37 using Event-based synthetic contacts because desktop WebKit does not expose Touch construction. The suite explicitly observes visible anticipation with the native dialog already closed, rapid reopening, and swipe-to-open under injected reduced motion. Safari's subpixel button width and transient mathematical status text were corrected in the harness measurements rather than production settings or text rendering.

Installed `0ea814c84cf0417da411de1892bb6abc9e9f02e7`; all 388 immutable files and 48 local/HTTPS asset deliveries match. Accepted document SHA256 `da746265b8f0f084c51ab9a89afc182a8be8f89361f0eed95da07b136bb87951`, configuration and original PDF delivery match the pre-install state. Actual HTTPS native click confirmed 109 outline links, immediate semantic dismissal/focus return with the exit layer still visible, its eventual cleanup, and Return reopening. Receipts: `dist/reader-gesture-repair-install-20261018/`; browser reports: `dist/reader-gesture-repair-20261018/`. The user's iPhone setting and physical touch arbitration cannot be read from this Mac; physical iPhone retesting remains with the device.

## Authored paragraph tabs — 2026-10-18

The shared HTML `show h` rule reduced the paragraph helper's `h(1.5em)` to
ordinary whitespace. The `text-utils` adapter now exports an empty,
assistive-hidden inline spacer for that helper alone; CSS preserves 1.5em at
the inherited font. Both aliases, existing text handling and the paged spacing
remain intact, and no private marker or spacer characters enter quotations.

All 15 build/content/Typst checks pass, including byte-identical paragraph-tab
PDFs against the installed helper. The browser fixture passes 45 checks at both
320px and 768px with 13px/30px fonts: exact spacer widths, first-line indentation,
unindented continuation lines, inline/math/highlight placement, canonical
quotations/native text copy, ordinary paragraphs and horizontal bounds. Native
plain-text copy retains the browser path, so its existing whitespace is
normalized when comparing it with canonical quotation text. The actual PDE
compile passes with 589 tab spacers, 7,515 math roots, 101 helper highlight
wrappers, zero private markers and no compiler-loss warnings. Strict OpenSpec,
formatting and guide compilation checks pass.
Evidence: `dist/reader-paragraph-tab-checks/`. Physical iPhone behavior was not
retested in this pass.

Installed clean runtime `1c60c9a3f8e165ccc3a776f5e4c99bef3a51fee9`. All 395
immutable files and HTTPS CSS bytes match; configuration bytes are unchanged
and the original PDF endpoint remains HTTP 200. The accepted HTTPS document
retains all 589 spacers, 7,515 math roots and 101 helper highlight wrappers,
with zero private markers or compiler-loss warnings. At 390px, the actual
Notation paragraph has a 19.5px spacer at 13px font size, ready mathematics and
equal page/client widths. Delivery receipts, browser measurements and the
inspected screenshot are in `dist/reader-paragraph-tab-checks/deployment/`.

## Authored highlighted mathematics — 2026-10-18

The installed `text-utils:0.1.2` helper splits text into `highlight` elements and
mathematics into filled boxes. HTML exports the former but drops the latter's
background. A Reader-only fork now exports semantic inline marks and marked
display blocks, preserving paragraph boundaries, native MathML and the original
paged implementation. The complete composed math view receives the theme paint.
The PDE source retains its existing 93 `highlighted` and 40 `highlight` calls
in the committed sources; no authored calls were rewritten for this fix.

All 13 build/content/Typst integration checks pass, including byte-identical
PDFs against the installed helper. The actual PDE compile passes its content
gate with 7,515 math roots, 140 marks and no compiler-loss warnings. The isolated
browser fixture passes 137 checks at both 320px and 768px with 13px/30px fonts
and light/dark/light transitions, covering strings, single text children, nested
formatting/links, tall fractions, display equations, paragraph boundaries,
canonical copying, complete background geometry and horizontal bounds. Strict
OpenSpec validation and the development guide's Typst compilation pass.
Evidence: `dist/reader-highlight-checks/`. Physical iPhone rendering was not
retested in this pass.

Installed clean runtime `517ecba983cd8a18541cd54d955a21acc5a6dd2d` through the
managed installer. All 392 immutable files match their recorded hashes;
HTTPS CSS/theme/renderer bytes match the release. Configuration bytes are
unchanged and the original PDF endpoint remains HTTP 200. The accepted PDE
document passes its content gate with all 7,515 math roots and 101 helper-owned
highlight wrappers. At 390px, the actual Connections passage's two expressions
are ready, share their surrounding text's background and leave page width equal
to client width. Delivery receipts and the inspected screenshot are in
`dist/reader-highlight-checks/deployment/`.

## Current outline location across transport sections — 2026-10-18

The previous location resolver inspected only mounted headings. A heading-free
continuation whose title was outside the mounted window therefore had no current
entry, or incorrectly adopted the next mounted heading. Resolve the section at
the 120px reading line and use the complete ordered manifest for preceding
headings. Each opening centers the selected link in the outline and gives it
keyboard focus with `preventScroll`, including after manual outline scrolling.

The disposable API/browser regression fails on the previous implementation with
zero current links. The correction passes 132 checks across WebKit and Chrome at
390×844, 320×740 and 768×360, with both ordinary and reduced motion. Coverage
includes button/swipe opening, repeated manual list scrolling, unmounted earlier
headings, future headings, multiple headings in one section, deep ARIA headings,
Escape focus return, Enter navigation and unchanged article scroll coordinates.
All 69 JavaScript unit tests, JavaScript syntax, Prettier and strict OpenSpec
validation pass.

The actual PDE Reader at 390px has 109 outline links. Source-intercepted WebKit
checks cover sections 46 and 47, repeated opening and a genuinely unmounted
`loc-577` heading. Its current link is focused and centered within 0.12px;
opening itself preserves the article's exact scroll coordinate. Independent
asynchronous mathematical layout can still adjust the body after opening.
Reports and the inspected screenshot are under
`dist/reader-outline-location-checks/`. Physical iPhone interaction was not
repeated for this correction.

Installed clean runtime `6d8552c2e78e86ebda46e1acd02432b79faeafc3`.
All 393 immutable release files and 48 loopback/HTTPS asset deliveries match.
The accepted document, configuration and original PDF service match the
pre-install checks. The Reader passes its content gate with exit code zero.
Actual HTTPS WebKit checks repeat both continuation sections and manual-outline
reopening, confirming the current link's focus, visibility and centering without
moving the article on opening. Deployment receipts, browser results and the
installed screenshot are in `dist/reader-outline-location-checks/`.

## Source highlights and red review strikes — 2026-10-18

The HTML selection toolbar now retains saved quotations and adds persistent
source Highlight, temporary Red strike, Undo and Clear marks. Source highlighting
is revision-bound and compiler-verified: compile a marked candidate in a project
shadow, require the exact selected body intervals with one marker and unchanged
complete body text, compile the final unmarked helper call for HTML and with the
original PDF packages, then atomically save
only a still-current writable workspace file. Ordinary text supports standard
`highlight`; complete mathematics uses the document's `highlighted` helper.
Context and mathematical hints only rank candidates; compilation authorizes the
edit. Repeated macro output, code strings, partial formulas, stale revisions and
concurrent saves are rejected without changing source. A rejected native toolbar
tap retains its quotation, and older responses preserve newer selections.

Red strikes use canonical block text and disjoint logical ranges, survive font
and viewport reflow, section remounting and reload, and remain scoped to this
document. Changed block text invalidates a mark; unavailable storage retains
in-memory undo and clear. Their noninteractive lines never enter the compiler.
The wrapping selection toolbar and messages follow the visual viewport and
safe-area bounds.

All 96 Python tests pass, including 15 source-edit tests with real compilation,
HTTP origin/revision checks, Unicode smart quotes, imported files, repeated source
text and macro output, common-word context, complete/partial mathematics, source
permissions, concurrent saves and a failing PDF candidate. Complete numbered
equations do not require selecting their generated number. All 72 JavaScript
unit tests pass. WebKit and Chrome pass 86 browser checks at 320×740, 390×844 and 768×600, covering native
selection collapse, pending/newer selections, source persistence, saved quotations,
red strike reflow/reload and undo/clear without source changes. Prettier, syntax,
strict OpenSpec validation and the canonical Typst development guide compile pass.

An isolated copy of the actual PDE project successfully saves a real source
highlight and republishes all 7,515 math roots with no compiler-loss warning.
All 45 original project source files retain their pre-test hashes. Reports,
test logs, the compiled development guide and an inspected 390px screenshot are
in `dist/reader-selection-actions-checks/`. Physical iPhone native callout and
hardware-touch arbitration were not repeated in this pass.

Installed clean runtime `fe1d498fb4999155d8d3830eb3ba6756bac0a422`.
All 401 immutable files and 50 loopback/HTTPS asset deliveries match. Accepted
document/configuration bytes and the original PDF service match the pre-install
checks. Actual HTTPS WebKit checks confirm enabled source/review controls, stale
revision rejection, immediate red strikes, persistence after reload and clearing,
with no browser error. Source success is verified in the isolated full PDE copy;
no test highlight is inserted into the original document. The existing outline
suite also passes all 132 checks. Delivery receipts, the inspected installed PDE
screenshot and browser results are under `dist/reader-selection-actions-checks/`.

## Floating selection capsules — 2026-10-18

Replaced the rectangular selection card with a content-sized floating capsule.
Highlight, Save quotation and Red strike retain visible Korean labels, distinct
icons and 58px primary targets; the named close icon keeps its 44px target.
Undo and Clear all use a separate capsule while review marks exist. No action is
painted as selected. The accessible description remains available without a
visible heading; oversized selections retain visible guidance and a dismissed
pending request retains a disabled source action. Width is applied before
measuring wrapped height to keep the capsules above the visual viewport bottom.

All 72 JavaScript unit tests and 86 real-compiler selection browser checks pass.
Additional WebKit/Chrome checks cover 25 capsule states: light/dark at 320, 390 and
768px; selected, review-only and both capsules; 200% text; keyboard save/undo;
dismissed pending requests; increased contrast/reduced motion; Chrome reduced
transparency and forced colors; and a short viewport with a simulated 34px safe
bottom inset. Every visible action remains at least 44px and inside the viewport.
Inspected phone screenshots on light/dark and enlarged text. Prettier, JavaScript
syntax, strict OpenSpec validation, diff checks and the canonical Typst guide
compile pass. Evidence is in `dist/reader-selection-capsule-checks/`. Physical
iPhone callouts and hardware touch were not repeated in this pass.

Installed clean runtime `fc45c43632e05ca62d112bbdd168463dd81060d2`.
All 401 immutable files and 50 loopback/HTTPS asset checks match, with unchanged
accepted-document/configuration bytes and original PDF service. Actual HTTPS
WebKit confirms the 282×72px selection capsule at 390px, both review capsules,
enabled source controls, stale-revision rejection, strike persistence after reload
and revisiting its section, undo and clearing, with no browser errors. Reload
continues to follow the last accepted edit, so review checks explicitly revisit
the marked section. Inspected installed light/dark PDE screenshots and deployment
receipts are in `dist/reader-selection-capsule-checks/`.

## Adaptive authored annotations — 2026-10-19

Implemented the user's selected concepts 1, 3 and 12: short labels over shaded
terms, anchored popovers for longer/rich/colliding notes, and an adjacent note
column gated by viewport proportions and actual reading-font space. The original
target equation is no longer copied into a separate explanation. Native labeled
under/over braces and brackets use the same semantic association; unlabeled
grouping remains intact. This is a local implementation, not an installed release.

- `node --test` for annotations, continuous sections, language and decorations:
  16 passing tests, including protection of sections containing an open note.
- Real Typst adapter/build integration: 17 passing tests. All seven annotation
  bodies survive in the compiled fixture, the unlabeled brace remains, and paged
  brace/bracket SVG output matches the original renderer byte for byte.
- Real serving and compiler-update checks: seven passing tests, including local
  delivery of `annotations.js` and existing graphical-rendering cache behavior.
- Chromium browser integration: 35 passing checks at 320/390/768px with 18/30px
  reading fonts, 1280×800 landscape and 1024×1366 portrait. Checks cover canonical
  math, collision-free labels, unchanged note body nodes, nonoverlapping side
  notes, bounded popovers, keyboard/focus, native touch, dark appearance, native
  popover fallback, reload and an actual saved-source update while a note is open.
- A focused real CeTZ fixture retains both relationship drawings, a short label
  and a longer popover on a phone, and both notes in the wide side column, with
  no relationship diagnostics or browser exceptions. The full preexisting
  across-block fixture still reports its existing routing diagnostic identically
  with the HEAD Reader and this implementation; this change does not resolve it.
- Prettier, `git diff --check`, strict OpenSpec validation and compilation of
  `docs/tinymist/dev/responsive-reader.typ` to PDF pass. The global generated-doc
  check cannot run because `typlite` is not installed; the edited development
  document is not one of that generator's three mirrored sources.

Browser reports and actual light/dark, phone/landscape and graphical compatibility
screenshots are in `dist/reader-adaptive-annotations/`. No installed service,
package pin or release metadata was changed. Physical iPhone/VoiceOver validation
and release installation were not performed in this session.

### Installed adaptive annotations — 2026-10-19

Installed immutable Reader runtime
`5428891aeb87f48def7599753732a4a59321b9e4` after the user's explicit deployment
request. The release was prepared from a clean detached checkout of the current
branch's annotation-only commits; the unrelated terminal/editor work remains
uncommitted in the original checkout.

The real configured PDE preflight exposed an annotation containing mathematical
attachments and fences outside an equation context. Its HTML carrier now retains
an explicit inline equation, with an additional regression test. A multiline PDE
equation also required trying the target's left/center alignment before relegating
its short name to a popover. The actual `kernel` annotation now appears above its
shaded expression on a 390px phone. Browser assertions read canonical note text
instead of MathJax's duplicated visual/assistive DOM text.

The complete PDE compiles with 262 annotations, no missing annotation targets,
duplicate IDs or compiler-loss warnings. Paged SVG equivalence and all 18 real
build/adapter tests pass; the clean release also passes 16 JavaScript tests,
seven serving tests, the immutable installer test, and 33 synthetic browser
checks without the optional source-update phase.

The official immutable installer stopped the old Reader and started the new
app-managed Reader (verified PID 99224). All 405 release files match their
manifest. All 52 loopback/registered-HTTPS web asset checks pass, including the new
annotation module. Both origins deliver the preflight-verified document with
SHA-256 `1600aed6d29adda15410eed83d27fc89a343c7fd0bb2a8d3614938b651a6cd6b`.
The project configuration bytes and original PDF listener PID/content remain
unchanged. The installed service reports a successful, healthy, nondevelopment
native-canvas document with no compiler-loss warnings.

Chromium and WebKit each pass 12 checks against the actual registered HTTPS PDE
Reader: the photographed `kernel` short label, absence of cloned equations,
bounded phone width, a long source annotation opened by touch, bounded popover,
touch dismissal, canonical mathematical text, readable/nonoverlapping landscape
side notes, automatic portrait fallback, and no browser exceptions. Inspected
the actual WebKit phone and landscape screenshots. These are browser checks,
not a physical iPhone or VoiceOver session.

Deployment plans, prior-launcher/configuration rollback copies, content reports,
file-delivery receipts, and Chromium/WebKit screenshots are preserved in
`dist/reader-annotation-deploy/`. Only the Reader runtime was updated; the native
Flow application and its engine were not replaced.

### Short-name popover tap correction — 2026-10-19

The supplied phone recording shows the shaded `kernel` term receiving focus
without a visible annotation. Reproduced against the installed PDE document at
393px/18px, as well as at larger fonts, in Chromium and WebKit. A short name
that collided with mathematical ink correctly fell back to a popover, but the
next layout pass temporarily switched it to label mode to measure it, closing
the active popover immediately.

Compact layout now retains an open popover through short-label measurement.
Explicit dismissal, loss of its target and a transition to the visible side
column retain their existing behavior. Added a real compiled fraction fixture
whose denominator label collides with its numerator. The new browser regression
fails with the previous runtime at the open-state/focus assertion and passes
with the correction in both Chromium and WebKit (40 checks per engine). Checks
include keyboard focus return, repeated touch opening/dismissal and the fallback
without native popover support.

The actual PDE document additionally passes 38 checks per engine with the fixed
module served through an isolated browser route: 393px viewport, 13/18/20/24/30px
reading fonts, repeated taps, scroll/resize/selection-triggered layout, viewport
bounds, canonical equation text and no JavaScript exceptions. Reports and the
inspected WebKit 18px screenshot are in `dist/reader-annotation-video/`.
All 18 real build/adapter tests pass after updating the fixture's expected
annotation count, along with nine targeted JavaScript tests, Prettier,
`git diff --check` and strict OpenSpec validation.

Installed the correction as immutable Reader runtime
`3cd6344336b0d2bf6b576d73b8e5c27039e43ddb` from a clean detached checkout.
The official installer reports a running app-managed Reader (verified PID 6790).
All 405 immutable files and 52 local/registered-HTTPS asset checks pass; the
accepted document SHA-256 remains
`1600aed6d29adda15410eed83d27fc89a343c7fd0bb2a8d3614938b651a6cd6b`.
The configuration and original PDF listener/content are unchanged.

Against the actual registered HTTPS service, Chromium and WebKit each pass the
12 existing installation checks and 38 additional checks covering the reported
tap failure across the five reading fonts. The short-name popover remains open
through repeated touch, scroll and relayout, with no JavaScript exceptions.
Deployment receipts and inspected WebKit screenshots are in
`dist/reader-annotation-video/deploy/`. The two isolated validation servers were
stopped after verification. Physical iPhone/VoiceOver execution was not performed.

### Compact indexed names and close-control clipping — 2026-10-19

The next supplied phone screenshot shows an indexed delta in a full popover and
the close button's focus outline clipped at the rounded corner. The previous
classification treated every MathML identifier or script as rich content.
Compact scalar mathematical names with indices now qualify for labels, using
canonical text for the short-name check; fractions, roots, tables, large
under/over constructs and linked/image content retain the popover path. When the
preceding mathematical line occupies the local label position, a compact
mathematical label can use the reserved upper equation space, aligned with its
target. The mathematical body and its assistive MathML remain the original nodes.

The popover now reserves a 64px minimum height and trailing content area for its
44px close control, insets that control by 8px and draws keyboard focus inside
the button. Both short and explanatory popovers retain the complete close target
and focus ring within their clipped card at 320/390/768px and 18/30px fonts.

Chromium and WebKit each pass 51 compiled-fixture browser checks, including the
indexed delta, its native sub/superscript semantics, mathematical-ink clearance,
short/long close geometry, repeated touch and keyboard dismissal, side/compact
transitions and nonnative-popover fallback. All 18 real compiler/adapter tests,
nine targeted JavaScript tests, Prettier, strict OpenSpec validation and the
development Typst document's PDF compilation pass.

The photographed PDE paragraph in section 3 additionally passes 24 checks per
engine through isolated overrides of only the two changed web assets: visible,
fully indexed delta labels at 13/18/24px; close-control and focus geometry at
320/390/393px with 13/18/30px fonts, light/dark appearance, touch dismissal,
viewport bounds and no browser exceptions. Inspected the actual WebKit delta
and close-control screenshots in `dist/reader-compact-math/pde-fixed/`.

Installed immutable runtime `5c11c19998d779a4616ff524801759e084130876` from a
clean detached checkout. The complete PDE preflight retains all 262 annotations
and passes the strict content gate without compiler-loss warnings. The running
app-managed Reader is verified at PID 11055. All 405 immutable files and 52
local/registered-HTTPS asset checks pass; the document hash, configuration and
original PDF listener/content remain unchanged. Chromium and WebKit each pass
12 existing installation checks plus 24 delta/close-control checks against the
actual HTTPS service. Receipts and inspected screenshots are in
`dist/reader-compact-math/deploy/`. Both isolated validation servers were stopped.
Physical iPhone/VoiceOver execution was not performed.

## Connected local side notes and ordinary footnotes — 2026-10-19

Runtime c0e8d142 first delivered the wider tablet canvas and per-host annotation
reservations. Its 410 immutable files, 52 local/HTTPS asset deliveries and
63 tablet, 52 kernel, 24 delta/control and 12 baseline browser checks per engine
passed. The original PDF profile was stopped before this deployment and remained
stopped; its configuration and the accepted PDE HTML were unchanged.

Concept 12 now includes a local divider, thin accent connector and target dot,
with the actual equation reference and authored short title. Leaders reuse the
existing ink-aware router and cache local geometry. Ordinary footnotes load from
revision-bound endnote sections and share these local columns. A same-host
repeated reference shares one projection; section requests are coalesced.
Original numbered links/endnotes remain available in compact layouts and after
failed loads. Projection IDs are scoped; obsolete responses cannot populate
replacement records. Native math, language, emphasis and document links survive.

Before installation, Chrome and WebKit each passed 78 compiled annotation
checks, 18 distant-footnote checks (including repeated references, loading
failure, history remounts and original backlinks), 63 actual PDE tablet checks
and 13 actual PDE footnote checks. The glyph-collision check samples each
leader against visible glyphs and equation numbers. Twenty-two JavaScript and
18 compiler checks passed; the canonical Typst development guide compiled and
OpenSpec strict validation passed. Evidence is under
`dist/reader-side-footnotes/`. Final immutable installation verification follows.

The first two installation attempts reverted automatically after WebKit's native
ResizeObserver feedback warning. Separate pages removed canceled-polling noise,
then detailed error capture identified `ResizeObserver loop completed with
undelivered notifications`. Existing drawing/math scheduling methods can mutate
layout synchronously inside their observer callbacks. Queueing those four
callbacks to animation frames removes that feedback. A mutation guard around
each observer callback fails against a45cd866 and passes after the correction.
Chrome and WebKit each passed 79 annotation checks and 15 actual PDE footnote
checks with this guard; the 22 JavaScript checks and strict OpenSpec validation
also passed. Successful immutable deployment remains the final pending step.

Runtime 19a5eb0b was installed successfully from a clean detached checkout.
All 412 immutable release files and 52 local/registered-HTTPS asset deliveries
matched their manifest. Installed HTTPS checks per engine: 63 tablet layouts,
52 kernel labels, 15 footnotes/observer-mutation checks, 24 delta/close controls
and 12 baseline annotation checks; Chrome and WebKit reported no exceptions.
The actual PDE HTML SHA256 remains
`1600aed6d29adda15410eed83d27fc89a343c7fd0bb2a8d3614938b651a6cd6b`.
Service configuration is byte-identical. The original PDF profile remains in
its preexisting stopped state. The managed Reader is running; all owned
fixture/preflight services and their compiler workers were stopped. Delivery,
rollback-attempt and cleanup receipts remain under
`dist/reader-side-footnotes/`.

## Per-kind annotation priorities — 2026-10-19

The user clarified that “2” meant the existing concept 3 label. Short mannot
names now keep concept 3 at every width; longer explanations choose concepts
1/12 using the existing side-space checks. Ordinary footnotes continue to take
concept 12 whenever eligible. A short-only host reserves no side gutter. Mixed
hosts retain label padding, bound labels to the math/text cell and route side
leaders around those labels. Obsolete intrinsic short-side measurements were
removed.

Actual PDE WebKit validation exposed a pending-note measurement deadlock: hiding
an indexed delta as a closed popover prevented its mathematical width from
being measured. Once the host is ready, native note bounds can reserve one
bounded label row while its own composition finishes. The actual tablet test
now waits for the delta's composed mathematical view, as well as its label mode.
Chrome and WebKit each passed 82 compiled annotation/mixed-footnote checks and
63 actual PDE tablet checks. The 15 actual PDE footnote checks per engine and
22 JavaScript checks passed. OpenSpec strict validation and the canonical
Typst development guide compiled successfully. Evidence is under
`dist/reader-note-policy/`; immutable deployment verification remains pending.


The first policy installation reverted automatically to runtime 19a5eb0b after
WebKit's phone font-change check found an indexed delta hidden in popover mode.
A label's intrinsic output width had become its next composition budget, and
asynchronous horizontal movement could compare glyphs with a stale origin.
Short-note mathematics now uses the available host text width, excluding side
gutters and label padding, and checks overflow against the current origin.
A regression deliberately moves the delta while its asynchronous typesetting
finishes, then verifies inline canonical notation through 18/13/24px changes.
Chrome and WebKit each pass 86 compiled annotation checks, 63 actual PDE tablet
checks and 24 actual PDE phone delta/control checks. All 22 targeted JavaScript
checks and strict OpenSpec validation pass. The next immutable installation
uses this correction; deployment verification remains pending.


Runtime 08f82cb3 was installed from a clean detached checkout after both browsers
passed the clean PDE preflight (63 tablet and 24 phone checks each). All 412
immutable release files and 52 local/registered-HTTPS asset deliveries match.
Installed HTTPS checks pass in Chrome and WebKit: 63 tablet layouts, 52 kernel
labels, 15 footnotes/observer-mutation checks, 24 delta/close controls and
12 baseline annotations per engine, with no browser exceptions. The accepted
PDE HTML hash remains
`1600aed6d29adda15410eed83d27fc89a343c7fd0bb2a8d3614938b651a6cd6b`.
Configuration is byte-identical and the original PDF profile retains its
preexisting stopped state. The app-managed Reader is running at PID 78804.
All owned fixture/preflight services and their compiler workers were stopped.
Receipts, the earlier rollback and final screenshots remain under
`dist/reader-note-policy/`. Physical iPad/iPhone execution was not performed.


## Compact footnotes use concept 1 — 2026-10-19

Footnotes now use the existing anchored dialog whenever aspect ratio, host width
or reading size prevents concept 12. Number activation is consumed before endnote
anchor navigation, retaining the URL, history length and reading position.
Compact remote bodies load on demand; the dialog exposes loading, retryable
failure and busy state. Source hrefs and endnotes remain diagnostic fallbacks.
The body preserves authored formatting, mathematics, language, IDs and links.
Touch, Enter, Space, close, Escape and rotation transitions are covered.

Actual PDE validation found that asynchronous mathematical composition can
replace a reference after opening. Focus restoration now resolves the current
painted numbered link by its original reference identity, including repeated
references, rather than focusing a disconnected or non-focusable MathML node.
Chrome and WebKit each pass 31 distant-footnote fixture checks, 86 annotation
checks and 39 actual PDE footnote checks across landscape, portrait, 390px and
320px layouts with 18/30px reading fonts. The 22 targeted JavaScript checks pass.
Evidence is under `dist/reader-compact-footnotes/`; immutable installation is
pending.


The first installation of a0ac8899 reverted automatically when the strict
portrait reading-position assertion failed immediately after a font change.
A repeat WebKit run also caught the test's scroll operation targeting a
reference being replaced during mathematical composition. The actual PDE driver
now waits for visible mathematics and the current reference's geometry to settle
before measuring activation; its URL, history-length and scroll-position
constraints are unchanged. Five isolated Chromium portrait repetitions passed,
and the complete registered-HTTPS footnote checks passed 39 per engine using
the same application code. Reinstallation and final delivery checks follow.


Runtime a0ac8899 was successfully installed from a clean detached checkout.
Chrome and WebKit each pass all installed HTTPS checks: 63 tablet layouts,
52 kernel labels, 39 actual footnote/resize checks, 24 delta/close controls and
12 baseline annotations. All 412 immutable files and 52 local/registered-HTTPS
asset deliveries match. The accepted PDE HTML SHA256 remains
`1600aed6d29adda15410eed83d27fc89a343c7fd0bb2a8d3614938b651a6cd6b`.
Configuration is byte-identical; the original PDF profile retains its preexisting
stopped state. The app-managed Reader is running at PID 11388. All owned fixture,
preflight and compiler workers were stopped. Phone/portrait popover screenshots
were inspected, including 320px with 30px reading text. Final delivery, the earlier
rollback, screenshot and cleanup receipts are under
`dist/reader-compact-footnotes/`. Physical iOS execution was not performed.


## Side-note type at 80% — 2026-10-19

Concept 12 mannot and footnote columns now inherit 0.8em. This single scoped CSS
rule scales note prose and native mathematical composition while preserving the
existing popover/label rules, side eligibility and column width. Chrome and
WebKit each pass 86 annotation fixture checks. The mathematical/prose fixture
also passes 20 font and transition probes per engine at 13/18/24px body sizes
and 1024/1280px landscape widths. The development guide compiles and strict
OpenSpec validation passes. Deployment verification follows under
`dist/reader-side-font/`.


Earlier deployment attempts restored the prior release after browser-probe
failures. Diagnostics separated closed nested-note mathematics from each note's
own body, excluded inert mathematical staging IDs from published-ID checks,
waited for composed reference nodes and centered the actual visible trigger
before recording click movement. The popup font check now selects non-short
explanations, since scrolling to a short name can correctly turn it into a
concept 3 label. No production JavaScript change was needed.

Runtime 7439a4c8 is installed from a clean detached checkout. Chrome and WebKit
each pass 20 installed HTTPS font/presentation checks and 39 actual PDE footnote
checks. All 412 immutable files and 52 local/registered-HTTPS asset deliveries
match. PDE HTML SHA256 remains
`1600aed6d29adda15410eed83d27fc89a343c7fd0bb2a8d3614938b651a6cd6b`.
Configuration is byte-identical, the original PDF profile retains its preexisting
stopped state, and the managed Reader is running at PID 42055. All owned fixture,
preflight and compiler workers were stopped. Screenshots and delivery, earlier
rollback and cleanup receipts remain under `dist/reader-side-font/`.
Physical iOS execution was not performed.

## Explicit Save for Codex replaces the local quotation library (2026-10-19)

Removed the former localStorage quotation list, its reading-settings entry,
quotation paint and browser relocation flow. The selection capsule now provides
Highlight, Save for Codex and Red strike. Legacy quotation data is neither read,
deleted nor migrated; source highlighting and local review strikes retain their
separate behavior. The terminal action bridge uses the same HTML save action.

`POST /api/focus` verifies bounded accepted quotations, revision, process/start
identity and input freshness, then atomically replaces a private focus record.
Supported literal sources include their exact source hash and excerpt; generated,
mathematical, ambiguous or multi-block text remains usable context without an
invented source position. Logical endpoints use normalized Unicode offsets
(null when an occurrence is ambiguous), never PDF pages. Saving performs no
compilation, source write, message send or Codex turn. The browser waits for an
acknowledgment, retains failures for retry and preserves newer selections.

Each managed Reader exposes its own absolute focusFile and `--focus ID` reader.
The live read validates PID/project/document identity, accepted revision, source
inputs/hash/excerpt and selection age. Standalone and terminal-owned services
support `focus.py --url <explicit loopback origin>`. A companion Tail Hosting
patch lists and explicitly resolves both paged and HTML services, delegates HTML
reads to its manager and retains existing paged reading. Tests apply it only in
a disposable copy; no installed service, registry or global skill was changed.

Validation:
- Full Python Reader suite: 137 passed with the complete local Typst package catalogue; Node Reader suite: 91 passed.
- Real WebKit/Chromium selection checks: 152 passed across 320×740, 390×844 and 768×600. Coverage includes exact source-linked context, unmapped generated text, server record freshness, untouched legacy data, no automatic migration, native selection collapse, failed-save retry, duplicate suppression and newer-selection preservation.
- Chromium/terminal/headless Neovim: 20 integration checks passed, including shared Codex context, persistent review marks, cursor navigation, dirty-buffer refusal and verified source highlighting. Inspected `dist/terminal-reader-check.png` with the Codex action visible.
- Responsive and terminal Typst guides compiled to PDF and experimental HTML; required rendered text was inspected. Both OpenSpec changes, scoped Prettier, generated-doc checking and `git diff --check` passed. The experimental HTML compiler emits its standard development warning.
- Installation, deployment, actual production delivery and a new physical-terminal graphics check were outside this task.

## Codex context deployed from scoped commit 644cef9a (2026-10-19)

The managed PDE Reader now runs clean immutable runtime `644cef9a` at its
existing registered HTTPS origin. Codex source context uses the read-only
`source_mapping.py` module, so the deployment does not require the separate,
uncommitted Neovim/terminal integration. Those working-tree files were preserved
byte-for-byte and excluded from this session's commits. The final runtime has
416 verified immutable files and all 52 local/registered-HTTPS asset deliveries
match the installed release. Reader configuration, Tail Hosting registry and
paged focus record remain byte-identical; the original paged service retains
its existing stopped state. Authored PDE HTML SHA256 is unchanged at
`3f862504192dba2b2f342ec3f7ba9c2d8d286dc5389f3a270dea1e89ae38cd20`.

Applied the tested Tail Hosting focus adapter and updated the existing local
`read-preview-selection` skill for explicit HTML/terminal selection, distinct
Reader IDs, logical endpoints and fresh unmapped text. Tail Hosting's 14 tests,
registry validation and skill validation pass. The command
`tail-hosting focus --preview typst-pde-reader` resolves the live Reader's own
focusFile with a matching service identity. Production context remains `waiting`;
no synthetic selection was written into the user's shared record.

Chrome and WebKit both verified the actual HTTPS page at 320px, including the
visible/enabled Codex save action, viewport fit and absence of the old quotation
library. Each then exercised the installed release in a disposable service:
source-linked text save and validated CLI read, usable unmapped mathematics,
unchanged source and no extra compilation all passed. The scoped checkout's
Python suite has 114 passing tests, Node has 77, and browser selection checks
have 152. A preexisting dynamic-worker test cleanup race was fixed by closing
its worker before its temporary directory; the complete suite then passed.
OpenSpec, generated-doc checking, formatting and canonical documentation checks
are recorded alongside this rollout.

Recovery snapshots retain the previous launcher/configuration, Tail Hosting
adapter and selection skill. Receipts and screenshots are under
`dist/reader-codex-rollout/`, including `verified-rollout.json`; the initial
pre-deployment snapshot is `backup-20261019-165909` and the final rollout recovery
snapshot is `backup-scoped-20261019-171252`. No native app/engine release or
physical iOS verification was performed.

## HTML document activity notice (2026-10-19)

The paged reader's activity priority, localized notice controller, wait timer,
selection-release interaction, visual-viewport placement and styles were extracted
to `tools/reader-common/session/activity.js` and `activity.css`. Both reader adapters
now consume this implementation; the separate HTML notice UI was removed.
HTTP compiler state and sequenced section loading/publication stay with the HTML
adapter, while WebSocket/DOM events and native touch-selection checks stay with
the paged adapter. Theme colors and toolbar offsets remain local. The existing
shared change-navigation policy is also reused.
Healthy publication hides the notice without adding document spacing. Native
math/figure composition retains its existing local feedback. Obsolete loads,
connection errors and compiler/content-gate errors cannot report false success.

Validation:
- 119 shared/HTML Node tests passed, including six HTML signal-adapter tests and
  three shared activity priority, placement and notice-lifetime tests.
- The standard Python suite passed: 129 tests, with 41 compiler-dependent skips.
  This includes first-party asset delivery and the immutable installed-layout test.
- All seven serving tests then passed with the installed Flow project's package
  directory, `/Users/taeyoung/Library/Application Support/typst/packages`, and
  `/opt/homebrew/bin/typst`, including real compilation and failed-save retention.
  A first attempt with the generic package cache lacked
  `@local/project-references:0.1.0`; using the configured project packages resolved it.
- All 82 paged frontend Vitest tests passed. The preview TypeScript check and
  `node scripts/build.mjs build:preview` passed; the generated frontend embeds the
  shared CSS and controller, preserving initial feedback before WASM initialization.
  Yarn was unavailable, so the three
  `test:readers` commands were executed directly with the local Node/Python/Vitest.
- `activity-browser.mjs` passed in Chromium (installed Chrome) and WebKit with
  deterministic API responses and the actual Reader shell: initial compilation,
  loading, live updates, selections before/during fetch, touch and keyboard
  release, modal waits, compile/load/connection failure and recovery, 320/390/768px
  light/dark layouts and reduced motion. Screenshots were visually inspected.
- The existing real-engine `tests/preview/performance-smoke.mjs` passed with the
  rebuilt frontend and unchanged installed engine in both Chromium and WebKit:
  300-page initial rendering, live edits, held updates, native touch and keyboard
  selection release, distant pages, zoom, theme changes and reconnect. Receipts:
  `/tmp/flow-shared-activity-pdf-chromium.json` and
  `/tmp/flow-shared-activity-pdf-webkit.json`. These are isolated temporary services;
  no installed frontend or running project was replaced.
- Generated documentation, Prettier, strict OpenSpec validation and diff whitespace
  checks passed.

The implementation checks above preceded installation. Physical iPhone verification
remains separate; the authorized deployment is recorded below.

## Shared activity deployment (2026-10-19)

Installed the HTML Reader and tinymist-flow 0.1.26 from clean implementation commit
`8f8d2df333afa695a79b41bb9ce543c7222cff38`. Unrelated untracked checkout files were
excluded and preserved. The native ARM engine was built with the locked
`flow-release` ThinLTO profile, two workers and `RUSTFLAGS=-Dwarnings`; preview and
localization assets were regenerated in a detached clean checkout. The configured
signing certificate was retained and both candidate/installed bundle validation
passed. Native engine SHA256:
`16e370a9c982fa2234b841fb813072fc0d56b8a4b0aacf3acf78a5814a56a077`.

Validation and runtime state:
- Both new-engine 300-page Chromium/WebKit checks passed: updates, paused selection,
  native touch and keyboard release, distant pages, zoom, theme and reconnect.
- All 37 app tests passed with the new engine; one opt-in signing test was skipped.
- The immutable HTML archive has 486 verified files. All 44 first-party assets
  matched the installed source at both loopback and registered certificate-validated
  HTTPS. The authored 8,814,670-byte document retained SHA256
  `85541ed98d0cbd9a4088bc6a3a95ae26282d6d536e414a2c4f2a06e11d29c704`.
- Fresh Chromium and WebKit contexts rendered the production HTTPS Reader, observed
  connection loss/recovery and reported no browser errors.
- Installed-engine WebKit rendered the actual 322-page PDE document on an isolated
  loopback port with the app's partial-rendering setting. Activity transitioned
  through connecting, waiting, compiling, rendering and ready without browser errors.
  A first probe omitted the app's partial-rendering flag and timed out; the corrected
  probe used the actual app configuration. It did not modify project sources.
- The menu-bar app was relaunched into 0.1.26. Both paged profiles retain their
  stopped state; `typst-pde-reader` retains its running state. Project profiles,
  Reader configuration and saved focus files match their pre-deployment bytes.
  The prior HTML selection was already stale against changed sources before this
  deployment. Its original backup was restored exactly after service restart,
  preserving stale evidence rather than inventing a fresh source mapping.

Receipts and screenshots: `dist/shared-reader-activity-rollout/`. Reader recovery
configuration/launcher/focus snapshots are under `backup-20261019-212206` there.
The app installer retained the previous bundle under
`~/Library/Application Support/tinymist-flow/releases/20261019-213531-545166/`.
No remote release was published and no physical iPhone check was performed.

## Shared rendering, live pinch and local decoration deployment (2026-10-19)

Installed tinymist-flow 0.1.27 and its matching immutable HTML Reader from clean
commit `fe744971ff8da9b5682d6b3580de581b55662079`, confirmed by local tag
`flow-v0.1.27`. The source checkout retains its unrelated untracked files. Preview
and localization assets were regenerated in a separate clean checkout. The native
ARM engine used the locked `flow-release` ThinLTO profile, two workers and
`RUSTFLAGS=-Dwarnings`. Candidate and installed signatures/provenance passed with
the existing certificate. Installed engine SHA256:
`e31d723fa2c47dc2126de17f3fb79353277ec47cd9f79ce93d1224bb9b360db9`.

Validation and runtime evidence:
- All 37 app tests passed with the new engine, including persistent-certificate
  integration. The new paged frontend passed 300-page Chromium/WebKit checks for
  updates, selection holds/releases, distant pages, zoom, theme and reconnect
  against the previous installed engine before the app replacement.
- Installed-engine WebKit displayed all 322 actual PDE pages on an isolated
  loopback port using the app's partial-rendering configuration. The reader reached
  ready with 1,896 text lines and no browser errors. Managed PDF profiles were not
  started for this check.
- The immutable HTML archive has 498 verified files. All 46 first-party assets
  matched their installed source over loopback and certificate-validated HTTPS,
  including the shared scheduler and local decoration module.
- The actual accepted PDE document retains the previous canonical text and all
  172 logical decoration IDs. Of those, 154 carry local descriptors: 67 cancel,
  20 underline and 67 rect; 18 retain fallback. This current production snapshot
  differs from the earlier frozen 171-ID fixture. Descriptor coverage does not
  establish phone latency or total server-load savings.
- Fresh Chromium and WebKit contexts rendered the installed HTTPS document.
  Synthetic pinch changed body size to 25px and grew mathematical glyphs before
  touchend, with no preview preference writes and one final write. Reading-anchor
  drift was 0.46875px and 0.59375px respectively; viewport scale stayed 1. Each
  browser displayed nearby local decoration SVGs with zero decoration API batches
  and recovered after intentional connection loss, with no browser errors.
- The menu-bar app was relaunched into 0.1.27. Both paged profiles remain stopped;
  `typst-pde-reader` remains running. Project profiles, signing configuration,
  Reader configuration and all three focus files match their pre-install bytes.
  The Reader's startup waiting record was replaced with the exact saved context
  backup, preserving historical service/revision and stale evidence.

Receipts and screenshots: `dist/client-rendering-rollout/`, including
`verified-rollout.json`, `delivery.json`, `reader-browser.json`, `paged-browser.json`
and `local-coverage.json`. The latest recovery snapshot index is `preinstall.json`
and its files are under `preinstall-20261019-230800/`. The prior app is retained at
`~/Library/Application Support/tinymist-flow/releases/20261019-230801-029442/tinymist-flow.app`;
the prior immutable HTML release remains installed and its stable launcher/config
are backed up. No remote release or physical iPhone verification was performed.

## Authored flowbox deployment (2026-10-20)

Installed the immutable HTML Reader from clean implementation commit
`b7e971587902106abe6e452a15151cc0494c0a0a` on the existing `main` branch.
The independent archived checkout excluded and preserved unrelated untracked
files. This update uses the existing Reader installer and does not replace the
native app or engine.

- All 500 immutable release files match their manifest. All 46 first-party assets
  match the installed release over both loopback and certificate-validated public
  HTTPS. The published PDE passes its strict content gate with 101 flowboxes.
- The full delivered HTML is byte-identical to the pre-deployment document after
  replacing only the authored container class from `flow-derivation` to
  `flow-flowbox`; canonical text is also unchanged.
- Chrome and WebKit each pass three actual photographed-flowbox cases over the
  registered HTTPS origin: 390px/18px light, 320px/30px dark and 768px/30px light.
  Frames, bounded mathematical ink, centered equation numbers, cancellation paint
  and canonical text pass with no browser exceptions. The installed screenshots
  were inspected; there are no extra horizontal separators around the frame.
- PDE paged service PID 94765 remains running and Ewald remains stopped.
  Project profiles, signing configuration, Reader configuration and all three
  focus records match their backed-up bytes. The exact historical saved context
  was restored after startup without rewriting its service/revision evidence.
- The first rollout accepted the document but the temporary deployment helper
  mishandled a null startup selection; its recovery restored the previous
  launcher/configuration. After correcting that helper, the second rollout
  completed and all installed checks passed. The explicit `Use` context backup
  was retained across both attempts.

Receipts and inspected screenshots: `dist/reader-flowbox-rollout/`, including
`candidate.json`, `install.json`, `delivery.json` and `https-report.json`.
`preinstall.json` indexes the configuration, launcher, LaunchAgent and context
recovery files under `backup-20261020-191318-720344/`. The previous immutable
`fe744971ff8da9b5682d6b3580de581b55662079` release remains available for recovery.
No remote Git release or physical-device test was performed.
