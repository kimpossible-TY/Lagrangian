= Responsive reader development

The independent reader modules are in `tools/flow-reader`. They generate HTML
from the saved Typst entrypoint, using a temporary package overlay. The installed
packages, paged service, and source documents are not rewritten by a reader build.

== Current delivery

On 2026-10-18 the PDE Reader is installed from clean runtime `74d52424` with
strict publication and native figures enabled. The Tail Dashboard document entry
automatically opens this Reader on touch devices; explicit Reader/original-page
choices persist, and desktop automatic selection retains the paged view. The
original PDF service and its address remain available. All 24 public Reader assets
match the committed bytes, and HTTPS document delivery matches the managed HTML.
The normal accepted-document caption below the toolbar is hidden without spacing;
loading, compilation and error diagnostics retain their status region.
This release reduces the toolbar to outline/settings icons, moves text size,
appearance and saved highlights into settings, and adds article pinch-to-text
reflow and an outline swipe drawer. Actual HTTPS checks cover 320/390/768px
layouts, font buttons, outline navigation and keyboard/focus behavior. Synthetic
touch checks cover cancellation, scroll/selection guards and reduced motion.
Physical iPhone acceptance of the new gestures remains outstanding.

The default is 13 CSS pixels. Current acceptance covers every body passage at
320, 390, 430 and 768px, large body text at 320/430px, all 66 native figures and
six tables at both 13px/30px across those four widths, original decoration
callbacks, real graphical relationships, and physical iPhone reading/navigation.
The completed receipts and exact coverage boundaries are in
`openspec/changes/add-responsive-reader/verification.md`. VoiceOver speech is
explicitly deferred by the user. Offline reload is not implemented.

== Browser icons

The Reader serves Flow's blue document-ribbon branding as a multi-size ICO
(16–64px), a 64px PNG favicon, and an opaque 180px Apple touch icon. Its HTML
declares all three with a versioned URL to refresh existing browser icon caches.
Regenerate these assets from `assets/branding/tinymist-flow.png` using
`python3 tools/flow-reader/generate-icons.py` (requires Pillow).

== Reading appearance

The toolbar has two 44px icon buttons, with the Flow identity centered between
them: outline at the start and reading settings at the end. Font controls,
appearance previews and saved highlights live in the reading-settings panel.
The original paged view is available through the Dashboard and its
existing address; the Reader toolbar has no page-view link.

Reading settings offer 자동, 라이트 and 다크. 자동 follows the
device's current appearance and reacts when it changes. Explicit choices persist
in the current browser across reloads and documents on the same origin. The
choice applies before the stylesheet paints. With unavailable browser storage,
the control still works for the current visit.

The icon-only settings button opens an anchored panel with three reading
previews. The selected preview has a checkmark and a moving selection surface;
the panel stays open while comparing modes. Assistive names and the live
description are retained without visible mode labels in the enhanced controls.
Arrow keys change the radio choice, Escape returns focus to the button, and
outside interaction dismisses the panel.
Browsers without native popovers retain the standard select within a dismissible
settings panel, alongside font controls and saved highlights. Reduced motion
removes spatial transitions; reduced transparency and increased contrast use a
solid panel. This is a locally tuned web material, not native optical rendering.

Light appearance pairs warm paper with charcoal text and a muted amber highlight.
Dark appearance uses charcoal paper, soft light ink and a deep gold highlight.
Authored highlights and browser-saved quotations share the matching palette;
native text selection uses a separate sage tone. CeTZ and mannot SVGs and their
frames are transparent; native label backplates match the enclosing paper or
callout wash. Neutral ink follows the theme, while colored labels, marked terms
and vector paint retain their color family at readable contrast. Original paint
attributes, geometry, SVG masks/gradients and raster pixels remain intact.
The source surface plots already have transparent raster backgrounds.
Appearance changes recolor the current content without document
compilation or changing saved quotations and reading positions.

== Required reading behavior

All essential text, equations, figures, and annotations must be readable in the
continuous body at the chosen font size. Do not require zoom, horizontal panning,
slides, a next-section click, or a separate enlarged-equation view. Compose long
mathematics and figure layouts to the available width, preserving their meaning
and readable labels. Optional navigation and saved-highlight controls are allowed.

The default body size is 13 CSS pixels, shared by the initial HTML/CSS and the
Reader module. A versioned local preference starts legacy readers at 13px once;
subsequent explicit choices persist, with 1px controls up to 30px. Existing
quotations and saved reading positions are retained. Canvas and relationship
requests accept the new 13px lower boundary.

Two-finger pinches on the article choose a body size from 13–30px. A small
preview shows the candidate during movement; releasing a finger commits once
through the existing anchor-preserving reflow path. Cancellation, an extra
finger or a selected passage prevents an accidental change. Article gestures
own text sizing rather than browser magnification; normal vertical scrolling
remains available. Settings buttons provide the same adjustment without a gesture.

A rightward swipe starting 24–96px inside the article opens the outline drawer,
leaving the outer browser-back edge alone. Reverse swipes close it. The drawer
tracks horizontal intent, rejects vertical motion and interactive starts, and
returns to its initial state on cancellation. Its committed state uses a native
modal dialog with keyboard dismissal and focus restoration. The outline scrolls
independently. Reduced motion removes spatial travel and cancels active motion
when the preference changes.

The viewport uses device width with initial/minimum scale 1 and
`shrink-to-fit=no`; it has no maximum-scale cap. The article alone intercepts
pinch and horizontal drawer gestures for the explicit text-reflow interaction.
Safari text-size adjustment is 100% so rotation keeps the selected text size.
Reading anchors compare the root layout width (`clientWidth`) rather than
`innerWidth`, which WebKit can change during a pinch without a new text layout.
No page transform or CSS zoom is used to obtain a fit. A committed modal outline
temporarily locks background scrolling.
Before a debounce or compiler busy check, decoration and relationship schedulers
remove obsolete SVG paint, including while their mathematical terms are pending.
The previous wider drawing cannot enlarge the page while its replacement loads.
The `viewport` browser fixture checks fresh and legacy preferences, reloads,
actual width changes and a synthetic visual-only resize. That last check is not
a substitute for a physical iPhone pinch test.

On 2026-10-18 the user refreshed the installed 13px Reader on a physical iPhone,
pinched to reduce it and released: “여백 없이 정상입니다”. This confirms the
reported margin behavior for that device; its browser version was not supplied.

After runtime `a4dc981d` is installed, the user also confirms on the refreshed
iPhone Reader that text, mathematics and figures are readable without zoom or
horizontal movement, and that reference navigation and back both work:
“표시와 참조 이동 모두 정상”. This is a physical-device reading/navigation
check, without a supplied browser version. VoiceOver remains explicitly deferred.

The legacy drawing path still has unresolved widths and small labels. The native
label path below is the deployed mobile path. Notes and relationships appear
inline automatically. A document-wide overflow check is insufficient; future
changes still require checks of their affected components and reading actions.

== Legacy adaptive CeTZ canvas

The reader's common CeTZ adapter preserves drawing programs and logical
coordinates. For a requested reading width, it repeatedly measures the original
program at a different coordinate unit, keeping inherited text size independent
of geometry scale. The browser requests nearby canvases automatically through
`/api/canvases` when width or font size changes. Returned SVG dimensions use CSS
pixels rather than inherited em units. Results for obsolete widths are not applied.

The API validates canvas IDs, revision, width, and font size; cached drawings can
be reused across request batches. Uncached requests reject a changed source
snapshot. A failed width fit retains the original geometry and reports overflow.
The `width-fit` result does not establish readable labels or absence of collisions.
Explicitly small label text, long fixed legends, and opaque layout islands still
need work. Do not promote this development implementation as the mobile default.

The complete PDE compile exposes 57 direct CeTZ canvases. At 343px drawing width
and 18px inherited text, 49 fit; at 273px and 30px, 44 fit. These drawing widths
correspond to plain-body phone widths of 390px and 320px in the test browser,
but nested callouts can be narrower. The browser measures the actual container.
Evidence is under `dist/reader-canvas-checks`.

== Native figure labels

`--semantic-canvases` enables an independent figure path for builds
and services. It exports the original CeTZ label bodies as canonical HTML/MathML
before SVG flattening, together with their original anchor bounds and a
geometry-only SVG. Physical and numeric source coordinates are retained. The
browser scales the geometry uniformly while keeping physical strokes independent
of that scale. It never scales the completed label glyphs.

Label mathematics uses the common mathematical renderer. Short labels stay at
their original points when their measured boxes fit without other text or
sampled strokes. Other labels remain completely visible below the figure,
with matching readable diagram numbers and dotted leaders for displaced markers.
No label reveal or enlarged view is required. Source order and mathematical
identities remain intact; synthetic numbers and loading messages are excluded
from quotations. Layout publication waits for a selection or reader dialog.
Long legends use the full available width, with their number above the body;
short legends can share a row with their number. The number must not subtract
width already budgeted for mathematical composition.

Label text keeps the chosen reading size and deliberately larger source sizes.
The HTML adapter explicitly retains source size, weight and color, and converts
stack/fixed-box label containers to native flow. The browser adapts low-contrast
label ink to its actual light or dark background while retaining its color family;
original colors remain in the exported source and vector geometry is unchanged.
Native label backplates match the enclosing surface. The actual source contains
gray, mint and orange label colors with less than 3:1 contrast on that background,
so font size alone is not a sufficient readability check.
Text show rules are suppressed inside an exported mathematical equation. Its
outer typography applies once; its glyphs stay native MathML instead of becoming
embedded HTML with a second font multiplier.

All native labels belong to the initial canonical export, including nested
drawings, references and decoration IDs. Width/font changes need no canvas
compiler request. Large geometry remains inline through transport asset
separation so placement can inspect its paths. Offscreen figures reset obsolete
placements immediately; pending empty leader SVGs have explicit zero dimensions
so their default 300px box cannot widen a narrow reading page.
Each leaf label passage has a source-derived reading key independent of its
generated diagram number. Reading a diagram without a passage across the
reference line preserves its point in the original geometry. Font and width
changes restore those anchors. All mathematical labels compose when any part
of their canvas is nearby, including a later passage in a long legend.
Loading-notice removal also preserves the reading anchor. Passage offsets use
whole CSS pixels so repeated publications cannot accumulate scroll rounding.

The first CeTZ 0.4.2 checkpoint exposed 58 native figures and 658 label bodies. Browser
runs at 320px and 390px each pass 1,277 checks at 18px and 30px, covering canonical
text, complete label boxes, font floors, ink contrast, physical strokes, separate
markers, mathematical ink, full page width and absence of canvas compiler
requests. A controlled nested/fixed-size fixture passes 159 checks. Separate
six-check position runs cover native label passages, geometry points and viewport
changes, including the actual PDE document. Evidence is under
`dist/reader-label-checks`.

The paired full PDE PDFs remain byte-identical at a fixed creation timestamp:
10,758,514 bytes, SHA-256
`3fb2b8cb775215a9d7a3905048489299bad22331b3401c7223bbc48f86d1ef46`.
All 1,914 reference display strings outside canvases are unchanged. The extracted
outside-canvas prose differs only by one whitespace boundary; its non-whitespace
text is identical. These checks do not establish complete arrow/leader geometry
or physical-device accessibility. The remaining older diagrams and surface plots
are covered by the adapters described below. Current figure, visual-fidelity and
physical-device acceptance is recorded above and in the verification report.
On 2026-10-18 the user explicitly
deferred actual VoiceOver speech validation to follow-up work; it is not a gate
for this rollout and must not be reported as completed. Disabling the option keeps
the established coordinate-unit delivery path.

== Older CeTZ and Fletcher figures

The Reader also overlays CeTZ 0.3.4, as required by Fletcher 0.5.8. Its original
processing context, bounds and transformations remain in that version. Both
adapters share only the native HTML/MathML exporter in `@local/flow-canvas:0.1.0`.
Original package hashes and licenses remain in the overlay provenance.
Relative 0.3.4 coordinate units retain their original paint with an explicit
unsupported diagnostic; they are not silently accepted as native composition.

Native label mathematics receives its budget from the available canvas width,
not the intrinsic width of its previous glyph box. This prevents a short accent
from alternating between inline and block composition. A small optical inset,
included in both measurement and publication, retains italic/accent overhangs.

This covers five previously opaque PDE diagrams. The frozen source now exposes
63 native figures. At 320px, all 1,387 checks pass at 18px and 30px; the five older
figures also pass 111 checks at 390px. The controlled older-version/Fletcher
fixture passes 45 checks and the original native fixture retains 159 passes.
All 2,121 retained vector primitives have the original attributes and ancestor
transforms. Removed label paint is represented by the native mathematical bodies.
The complete fixed-timestamp PDE PDF remains byte-identical, with the same hash
recorded above.

== Surface plots and stable source figures

The Maquette 0.1.3 adapter keeps the original raster pixels and vector axes,
exporting the original SVG text as native label bodies. SVG text anchor and
baseline alignment retain their source x/y positions. The original 3D mesh,
camera and author coordinates are unchanged. Both the original raster payloads
and the complete PDE PDF remain byte-identical. Nested raster frame dimensions
are normalized to the original viewBox, avoiding a second scale when reading
fonts change.

The frozen PDE now has 67 native figures and 699 label bodies: 58 from CeTZ 0.4.2,
five from CeTZ 0.3.4/Fletcher and four from Maquette. No opaque SVG island remains
in this snapshot. Geometry fills its available width, including originally
small diagrams, while label fonts and physical strokes retain independent sizes.
The eight canvas compiler/API tests include exact source pixel, axis position and
PDF comparisons. `surface-source-audit.json` and `surface-pdf/verification.json`
under the label evidence record the full-source comparisons.

All 67 figures pass 1,475 browser checks at 320px with 18px and 30px fonts after
full-width geometry fitting. The report includes every native label, readable
ink/markers, complete mathematical paint, physical strokes, bounded component
width and absence of per-canvas compiler requests. Evidence is
`all-native-fullwidth-pde-320.json`.

Native geometry receives a source identity independent of generated canvas
counters and internal SVG IDs. Source label keys include that identity, so
repeated axis labels do not jump between different plots after an insertion.
The manifest indexes geometry identities as well as reading keys. Source-update
restoration checks the original geometry rather than trusting a reused counter.
Identical duplicate geometry remains subject to unique-context relocation;
ambiguous text alone is never sufficient.

An isolated copy of the actual PDE source passes eleven browser update checks.
It inserts two preceding surface panels while preserving a selected native axis,
its quotation, and a geometry reading point. The original panel counter changes
55 to 56 to 57 while its source identity remains stable. The selected label moves
from 88px to 87.55px at the reading line. The original PDE files are not edited.
Evidence is `pde-native-source-update.json`.

== Tables in continuous reading

HTML tables keep their original cells, math nodes and source order. The Reader
stacks each logical row vertically with column associations; it does not clone
or shrink mathematical content. Explicit headers remain authoritative. The
common bare-cell header pattern receives header roles, while unrecognized first
rows remain data. Repeated prose column hints use CSS generated content so they
cannot duplicate canonical quotations or mathematical identities. Header spans
map to their logical columns. Cells receive stable leaf reading keys, including
direct table navigation during asynchronous composition.

The six actual PDE tables contain 94 cells. At 320px and both 18px and 30px fonts,
629 browser checks pass for original node retention, source order, header
associations, complete mathematical ink, readable fonts and bounded component
width. Merged-header and unheaded-data fixtures are included. Evidence is
`tables-pde-320.json`. These DOM checks do not replace assistive-device testing.

== Build and inspect

```sh
python3 tools/flow-reader/build.py \
  --root /absolute/project \
  --entry main.typ \
  --package-path /absolute/typst/packages \
  --font-path fonts \
  --compiler /absolute/path/to/typst \
  --output dist/reader
```

The output directory contains `document.html`, `compile.log`, and `report.json`.
The command exits unsuccessfully when the content gate fails, even if Typst
successfully generates HTML. Review unsupported annotations, compiler warnings,
missing links, duplicate anchors, and unresolved annotation targets.

The package forks retain their original licenses. `packages/provenance.json`
records the original package versions and per-file hashes. Reader-specific
changes are target-aware and preserve paged output. The current CeTZ adapter
keeps its legacy coordinate-unit SVG path available alongside native composition.
Figure and device policies still need their explicit rollout validation.

== Local reader service

```sh
python3 tools/flow-reader/serve.py \
  --root /absolute/project \
  --package-path /absolute/typst/packages \
  --font-path fonts \
  --output dist/reader \
  --original-url https://original-paged-preview.example/ \
  --watch
```

The server binds loopback and reports its selected port. `--port` selects a
specific development port. `--allow-incomplete` permits a development preview
with visible fidelity diagnostics; do not use that flag for the mobile default.
`/api/state` exposes compile state and the accepted revision. `/health` indicates
whether a document is available, independently of whether the latest source
compiled successfully. A failed compile retains the previous document.
The HTTP shell is available while the first compile runs; readiness remains false
until a document is accepted. File watching uses the compiler's dependency JSON
and explicitly configured font directories. It does not recursively scan the
project's unrelated media, caches, or cloud placeholders. Known parent directories
use their entry names to detect new imports; metadata-only timestamp changes and
Finder's `.DS_Store` do not invalidate the accepted compiler inputs. A newly discovered
dependency graph is compiled again against a measured input snapshot before
publication. The served revision includes that snapshot, so changes to a dynamic
drawing invalidate the revision even when its placeholder HTML is unchanged.

The reader supports native text selection, a heading outline, font size changes,
width-aware equations, visible inline annotations, reading anchors, and saved
highlights. Select a passage and choose the save action; the toolbar's saved list
returns to the passage. Records belong to this document in the current browser's
local storage. They do not synchronize devices and are removed with site data.
Updates wait for an active selection or any reader dialog to close.

A highlight stores exact text and surrounding context for each selected block.
`/api/locate` resolves it against the accepted snapshot, including when edits move
it to another section or change an automatically generated label. Ambiguous or
removed text remains in the list with an explicit status. CSS Custom Highlight
ranges preserve MathML structure; unsupported browsers show a block marker and
the saved quotation. Source selection sharing, offline reload, and the remaining
mobile rollout work are tracked in the responsive-reader OpenSpec change.

== Last visual edit

The HTML Reader and paged preview share the same render-before-jump queue and
2500ms recent-gesture policy. Successful saved changes to body text, mathematical
markup and native figures produce a revision-bound HTML target. The Reader
service stores that target and its canonical body baseline atomically in
`last-change.json` inside its managed document output, with mode 0600. History
belongs to the project and entrypoint, survives service restarts, and is recorded
even when no browser is connected. It does not write the PDF service's history.

A fresh entry or reload restores the last visual edit ahead of an older saved
reading position. A newly opened named link and browser-history return retain
their explicit destination. Without valid edit history, the existing reading
position rules apply. The first accepted document establishes a baseline;
subsequent accepted edits create navigation history.

Recent scrolling defers an automatic jump and exposes the floating 변경 위치로
button. A gesture during destination loading also defers it. Selections and open
Reader dialogs still postpone document publication. Connection recovery, theme
and font changes do not replay an already observed edit. Failed compilations,
metadata changes and source comments cannot replace the last visual target.
Navigation copies are excluded; authored body changes take priority over updated
reference copies. A removed block uses a surviving adjacent target.

== Sections and graphical annotations

The service publishes a revision-specific `/api/manifest` and HTML sections at
`/api/sections/section-N?revision=...`. The browser automatically appends and
prepends neighboring sections as the reader approaches either edge. There are
no next/previous section buttons. It normally retains six mounted sections,
allowing more when content is nearby or contains a selection/focus. Distant
sections become measured-height placeholders and are restored on approach.
The manifest resolves references and footnotes across sections.
Reading keys are assigned before partitioning, using named labels or contextual
text, so a section boundary change does not itself invalidate a saved passage.
Insertions, restoration, source updates, reloads, and browser history use the
reading block and its viewport offset. A selected section is never parked;
source updates wait until the selection or reader dialog closes. Saved highlights
paint every mounted section. Boundary failures preserve the readable body and
retry automatically. Transport HTML is cached separately from the bounded DOM.
Large vector drawings and embedded images are delivered unchanged as separate,
lazy-loaded assets. SVG drawings with interactive links remain inline.

Text annotations are visible beside the reading flow, with a preview of their
marked expressions and an accessible association from the original terms. Authored
small prose sizes inherit the chosen reading size. There are no note disclosure
controls or relationship dialogs.

Graphical annotations retain their original CeTZ programs. The browser measures
marked terms in the original body nodes and sends those rectangles and the chosen
font size to `/api/graphics` automatically. Overlapping relationships share a scene;
relationships spanning blocks preserve the intervening prose and original order.
The common adapter preserves the first marked term as the coordinate origin for
both literal coordinates and named anchors. The service returns the complete SVG
bounds, including negative offsets. The body reserves vertical room for these
bounds; labels inherit the reading size through a fresh Typst measurement context.
No authored figure coordinates are rewritten, and no source code is accepted in
the request. Revision changes and changed term positions reject obsolete overlays.

Some authored arrows use only numeric offsets, with no named destination term.
When a pure vector annotation of this kind collides with reflowed text or exceeds
the width, the Reader preserves its complete original paths and arrowheads in a
visible band directly below its source scene. Only geometry is fitted, retaining
stroke thickness. No destination is invented from numeric coordinates. This
fallback excludes baked glyphs and measured label bodies. Named connections
continue to follow their measured terms and automatic routing.
If only one endpoint names a term, that endpoint remains exact; its unbound
literal endpoint may move into clear reading space without exempting unmarked
mathematical ink from the route obstacles. CeTZ renders the resulting path and
its original arrowheads. A route request cannot move a named term endpoint.

Each logical marked term can supply an ordered array of fragment rectangles.
Relationship records keep the original source node, and the mathematical identity
model resolves it to every presentation fragment after typesetting. The request
retains gaps between lines instead of treating them as marked content. Single
rectangles keep the previous CeTZ behavior. For multiple fragments, compass and
angle anchors choose an actual fragment edge in that direction; ties prefer the
edge nearest the area-weighted center. The default/center anchor is the nearest
fragment center. Path anchors traverse the fragment perimeters in logical order,
without adding paths through the gaps. Literal coordinates remain relative to
the first logical fragment. This anchor policy does not solve connector collisions.

The initial implementation recompiles the full source for an uncached graphical
request. On the PDE project this can take several seconds; nearby scenes start
loading automatically and failures retry without a reveal action. Cached results
are reused. Reusing a persistent compiler is a subsequent performance task.

Width diagnostics compare the full drawing with the actual body width. A
conservative collision diagnostic compares label rectangles with body text and
samples stroked connector paths against unmarked text. It is not a complete
collision solver: overlay-to-overlay intersections and opaque image content are
not covered. Explicit small label sizes still need a policy. Earlier native-MathML
Jacobi checks demonstrated width and connector collisions. Inline delivery alone
does not establish responsive readability or permit promotion.

== Automatic connector paths

The shared CeTZ adapter records planar open line and Bezier connections between named
marked terms. Metadata retains each connection's original endpoint identities,
anchor names, path, and whether a Reader route was applied. Ordinary canvases and
paged rendering have no routing context. Authored PDE drawing programs and
coordinate offsets remain intact.

The browser plans a path around measured text ranges, stretched operators, and
label bounds. Only the connection's own endpoint terms are exempt; other marked
terms remain obstacles. A bounded orthogonal search keeps horizontal coordinates
inside the body and permits vertical outsets. It preserves each anchor's outward
direction and can turn earlier when the next line leaves a narrow gap. Clear
connections retain their original curves. Closed loops and unsupported drawings
are not collapsed into another representation.

Numeric routes return through the revision-bound geometry request. CeTZ validates
that their endpoints match its original resolved anchors, then draws the new
path using the original stroke and mark definitions. Bezier default, control,
and path anchors remain available; labels attached to the path follow it. Unknown
route IDs, changed endpoints, and out-of-range coordinates are rejected. At most
two route adjustments are requested per measured geometry. Unresolved collisions
remain visible layout failures. Newly composed math is required before measuring
connections or paint after a width/font change.

Free literal endpoints reserve space for the original arrowhead as well as its
centerline. A colliding candidate remains invisible while its replacement is
pending, preventing temporary paint across readable mathematics. SVG sampling
ignores an isolated initial move that has no painted stroke; zero-length round
and square caps remain obstacles. Native figure label placement uses the same
painted-path sampling policy.

Mathematical obstacles use each CHTML glyph's own surface and complete stretched
operator surfaces. This preserves channels between derivation rows where a text
range's empty font ascent/descent would falsely cover a fixed endpoint. Assistive
and staging copies are excluded; prose retains its measured range bounds and
every mathematical surface retains its marked-term identity.

Relationship frames and SVG backgrounds remain transparent in both appearances.
Equation numbers and links inherit the reading palette. Original vector paint
and marked mathematical term colors adapt to that surface; filled decoration
underlays retain readable contrast against their own marked term's ink.

The server caches each relationship by its accepted revision and complete
geometry independently of request batching. A mixed batch compiles only missing
layouts and retains unchanged results. Accepted revision changes clear both
cache levels. After a failed save, cached accepted paint remains available while
new uncached geometry against changed source is rejected.

The frozen PDE compiler audit identifies 23 supported connections across 12 of
its 15 graphical annotation programs. This is protocol coverage, not a claim that
every relationship is now collision-free. The browser fixture uses the original
Jacobi connector program at normal and large reading sizes. Evidence is under
`dist/reader-routing-checks`, including the paired full-PDE PDF comparison with
an identical creation timestamp. Arbitrary drawing semantics, overlay-to-overlay
crossings, label reflow, and remaining mathematical overflow still need work.

== Semantic mathematical decorations

The mannot adapter preserves a marked term as native MathML and gives its paint
a separate decoration ID. The original underlay/overlay callback remains in
Typst. `/api/decorations` accepts measured visual fragments, the inherited ink,
and reading font size for an accepted revision; it returns only the original
decoration layers. Each fragment has its own size and SVG namespace. Underlines,
highlights, boxes, and stretched brackets therefore need not freeze the whole
mathematical expression into one unbreakable image.

The browser measures every client rectangle, paints layers around the original
nodes, and requests nearby terms automatically. It removes obsolete paint while
new geometry is pending, visibly reports pending/failed decoration rendering,
and retries automatically. Cache reuse includes revision, all fragment sizes,
ink, and font size. Position-only changes can reuse paint. The service rejects
unknown IDs, invalid geometry, changed revisions, and missing or duplicate layers.
An empty SVG is a valid present layer. Document equation numbering must not leak
into stretched bracket decorations. SVG normalization preserves XML tag casing.

Repeated explanatory targets compose independently. A nearby original term must
not wait for a far-offscreen copy's mathematical composition before receiving its
highlight or cancellation. Only nearby, composed fragments supply geometry;
publication keys include their occurrence identity even when their dimensions
match. The same callback paint can still be reused. A tall-equation fixture
verifies the original cancellation while its explanation remains uncomposed,
then verifies that copy through ordinary scrolling at 13px and 30px.

Line breaking can retain an empty mark carrier before its actual painted
fragments. Once its mathematical view is composed, a zero-area carrier does not
represent missing paint and cannot retain a loading notice. Native/pending views
and real unpainted rectangles still report their pending state. Paint audits
likewise inspect nonempty client rectangles, not empty line-break scaffolding.

The mathematical renderer distinguishes authored derivation alignment from
matrix/cases/vector structure. Its row composition moves original nodes into
separately breakable mathematical rows, preserving anchors and nested tables.
This adapter is integrated into the Reader. Wide fractions, brackets, matrices,
and other indivisible structures still need responsive composition.

The initial PDE compile retained 102 mannot decoration IDs; its compiler audit rendered
two fragments for each one. The dedicated fixture verifies six decoration kinds,
including a custom two-layer callback and the note's marked-term preview. The
full original-package and overlay PDF comparison is byte-identical. Evidence is
under `dist/reader-semantic-checks`; see the research guide for the paired equation
corpus measurements and their limits.

=== Native cancellation and overline

Native cancellation also retains semantic mathematical body text. The adapter
captures resolved set-rule properties and passes the original stroke, length,
angle function, inversion, and cross settings to Typst's cancellation renderer
on an empty box for each measured fragment. Mathematical body glyphs never enter
the paint SVG. The compiler tests check the returned angle, length, two-diagonal
cross, inherited ink, explicit colors, thickness, and dashes.

Typst's custom `mrow` boundary preserves nested mathematical show rules during
HTML export. The HTML normalizer promotes a tagged cancellation row to semantic
`menclose`; the visual renderer makes only these paint-backed enclosures breakable,
then restores their notation in assistive MathML. Ordinary enclosures remain
intact. An overline becomes an accented `mover` with a grouped body and explicitly
stretchy spacing macron. A combining accent alone can remain a short glyph,
so the browser checks that the visible bar spans its complete body.

The frozen PDE snapshot contains 6,759 outer mathematical roots, including
1,412 display equations. Its former 77 mathematical SVG islands are now semantic
mathematics: 67 cancellations and ten overlines. The full compile passes the
content gate without mathematical-loss warnings. All 169 decoration IDs produce
two requested fragments in a separate compiler audit. This audit validates
delivery, not real-page collision freedom. Sources and authored coordinates are
unchanged, and the paired full-PDE PDF output remains byte-identical.

Width validation measures complete stretched-operator surfaces, not the clipped
glyph pieces used to construct them. It still checks real glyph extents and
scroll width. A small display overhang can trigger at most two additional
line-breaking passes at the same font size, reserving at most one em. Larger
indivisible expressions remain explicit layout failures. The isolated corpus
probe does not run dynamic paint, connector composition, or this runtime width
correction, and cannot establish production acceptance. Evidence is under
`dist/reader-math-overflow-checks`.

== Inline expressions wider than the body

A wide inline expression can automatically compose as a block in the reading
body. Short expressions whose complete ink fits remain inline; a wider container can restore the original
presentation. Explicit `mstyle` preserves the original inline fraction, limit,
and script typography during block line breaking. The ordinary publication guards
still protect active selections, revision changes, and obsolete measurements.
Original paint follows the resulting marked fragments, and surrounding sentence
text retains its source order. This requires no expansion control or font reduction.

Publication also checks the actual paragraph line. An accent can fit in isolation
yet overhang when its short expression lands at the right edge. In that case the
Reader gives it an ordinary body line at the same size. A previous status notice
is removed before measuring, so its block cannot change line breaks and leave a
false warning. The actual PDE Fourier-hat paragraph reproduces this at 430px/30px.

The actual Reader fixture checks both 18px and 30px text at 320px and 390px,
including fraction-size comparison, canonical copying, accessible references,
all fragment paint, vertical visibility, and restoration in a wider container.

The runtime corpus probe snapshots the Reader modules and their local assets,
then calls `ResponsiveMath.candidate` for every source mathematical root and each
nested expression relocated from an annotation. The frozen corpus has 6,759 roots
and 6,873 resulting expressions. At a 273px reading body with 30px text, overflow
falls from 97 to 53; at 343px with 18px text, it falls from eight to five. All four
runs retain zero rendering, token-binding, logical-text, and SVG-count errors.
These figures use the actual candidate conversion path and common reading widths.
Contextual paragraph styles, dynamic paint, graphical relationships, publication,
and device accessibility still require separate checks. Evidence is under
`dist/reader-inline-checks`.

Run the reproducible candidate probe with the bundled renderer and fonts:

```sh
python3 tools/flow-reader/research/math_runtime_probe.py /absolute/path/document.html --output dist/reader-runtime-probe
python3 -m http.server 61508 --bind 127.0.0.1 --directory dist/reader-runtime-probe
```

Open `/math-runtime.html?font=30&width=273` at the intended viewport. The report
records the source hash, renderer file hashes, input roots, composed expressions,
promotions, overflow, and semantic errors. Completion is not mobile layout
acceptance; unresolved fractions, bracketed groups, figures, and device checks
remain open.

== Structured mathematical composition

The frame planner measures fractions, radicands, spanning braces and bars,
scripted bases, and table cells in the actual calibrated mathematical font.
An explicit inner MathML box permits line breaking inside a wide child while
retaining the original operators, grouping, script level, labels, and token IDs.
Zero-width discretionary spaces allow product breaks after preferred operator
breaks. Small norms and intervals stay intact, and a function name remains with
its argument. Scripted bases reserve the measured width of attached scripts.

The planner makes at most four frame passes plus two small overhang corrections,
then retains the candidate with the least measured overflow. Candidate and
published checks use the same fractional CSS width. A wide matrix retains all
rows and columns; inter-cell spacing becomes 0.1em and surrounding fences use a
narrower optical size while still stretching to the full table height. Matrix
entries and their scripts keep their original reading sizes.

MathJax masks overlapping extender glyphs when painting a stretched operator.
The Reader applies matching axis clipping to those stencil surfaces so invisible
pieces do not add scroll area. Complete operator surfaces and real glyphs still
participate in width checks. This mask does not clip the mathematical body.

The actual Reader fixture includes the PDE energy-flux identity, a nested
Poisson-kernel fraction, a Hamiltonian radical, an electromagnetic 4-by-4 matrix,
an originally painted marked brace, a volume-form product and a long overline.
It checks canonical copying, horizontal and vertical geometry, matrix structure
and font size, intact norms, full-height fences, complete overlines and every
marked fragment at 18px and 30px. All 69 checks pass at each of 320px and 390px.
The existing inline, selection/update, routing and native-decoration fixtures
also pass their 26, 25, 15 and 21 checks at 320px.

The paired frozen PDE runtime probe now has zero overflow among all 6,873
expressions at both 273px/30px and 343px/18px. The previous inline renderer had
53 and five overflows at those respective settings. Both new runs retain zero
rendering, binding, canonical-text and SVG-count errors. These are candidate
conversion checks at common reading widths; real paragraph contexts, dynamic
paint and figures, device behavior and assistive reading remain separate work.
Evidence is under `dist/reader-frame-checks`.

The clean structured-math commit is installed in the independent development
Reader. The actual PDE energy-flux identity fits its complete component at
390px/18px and 320px/30px. The original PDF service retains its process and
returns HTTP 200. That checkpoint also exposed page widening from distant
unadapted canvases and reading-position drift. The delivery stage below addresses
those issues independently of the mathematical candidate audit.

== Drawing delivery and reading position

An unadapted CeTZ canvas reserves a bounded aspect-ratio placeholder, using the
original SVG/image dimensions. Its automatic width/font request replaces that
placeholder. A previous fitted drawing remains visible during a font update if
it still fits. A narrower viewport can reserve the placeholder immediately,
including while a compiler request is in flight or the drawing is offscreen.
An impossible fit retains its complete drawing and explicit diagnostic.

Drawing replacement and placeholder changes preserve the logical reading anchor.
The Reader owns scroll anchoring, restores font changes synchronously, and keeps
a stable block/offset for width and font-loading events. Height-only changes
from mobile browser bars retain ordinary vertical scrolling. Named plain Typst
blocks can also be reading anchors. Containers with paragraph children defer to
those children. A selection or revision guard on mathematical publication still
applies independently.

The actual canvas-loading fixture checks initial delivery, pending page width,
full label size, rapid font changes, responsive publication, viewport changes,
stale requests, and explicit failed fits. It passes 12 checks when growing the
viewport and 13 when shrinking during a font request. A further 16-check width
round trip restores the accepted drawing immediately while an obsolete request
waits. A frozen actual-PDE fixture
checks the energy-flux identity at 18px/30px while changing between 320px and
390px in both directions. Its nine checks pass in each direction, including
direct target navigation, canonical text, equation width, whole-page width, and
reading position. Direct targets cross the same 90px reference line used for
reading restoration: root scroll padding is 88px. This prevents the preceding
paragraph from becoming the anchor during initial asynchronous composition. The
entry policy distinguishes a newly opened link from a reload/history entry.
A new named link wins even when its URL matches an older saved location; a
reload resumes the current reading block. A four-check browser fixture seeds
that conflict and verifies both actions, with 1px reload-position error.
Evidence is under `dist/reader-entry-checks`. The
mathematical and update regression fixtures retain their 69 and 25 passing
checks. Evidence is under `dist/reader-position-checks`.

The managed named-link fix is installed at commit `43c046d3`. A fresh tab at the
same previously saved energy-flux URL aligns its target at 87.625px, with no
whole-page overflow at 390px. Its accepted compile passes; the original PDF
service retains PID 39357 and returns HTTP 200. The delivery receipt is
`dist/reader-entry-checks/managed-update.json`.

These delivery checks do not validate every figure's label collisions or
readability. The mobile default still waits for the remaining figure and device
checks.

== Logical mathematical selections

`web/math-identity.js` assigns source token IDs before mathematical typesetting.
A logical token can bind to several visual occurrences, including operators
repeated at a continuation. The model retains the original Unicode characters
and text order, while each character points to its actual browser range.
Mathematical alphabet encoding, variation selectors, stretchy operator glyphs,
and spacing are handled explicitly. Missing tokens or unexpected text fail binding.

The Reader's quotation and highlight helpers now use this logical text index.
Selections produce separate source intervals when presentation order is different;
highlight ranges do not span intervening unselected scripts. Reading-position
text also uses the same index. Native paragraphs keep their text and selection
behavior. A renderer must bind the model successfully before publishing its view.

The isolated PDE probe at 320px/30px checks all 6,759 outer mathematical roots,
including 1,412 display equations, with no binding failures or logical quotation
changes. It retains 324 logical marked nodes across 395 presentation fragments.
A browser fixture checks superscript-only
selection and base-plus-subscript highlighting after real MathJax reordering.
Evidence is under `dist/reader-identity-checks`. This corpus result establishes
logical binding, not complete mathematical visual fidelity or accessibility.

== Mathematical renderer lifecycle

Display equation numbers occupy their own column at the inline end, vertically
centered beside the complete expression, including matrices and multiline
derivations. The renderer measures the remaining mathematical cell for line
breaking so long equations cannot extend underneath their numbers. Unnumbered
equations retain the full width. Loading/error notices occupy a separate row.
The exporter emits a block number directly beside the mathematical element;
an inline number would acquire an unwanted paragraph wrapper in Typst HTML.

The development Reader composes nearby expressions with a locally bundled
MathJax 4.1.3 MathML-to-CHTML renderer. The common derivation-row adapter permits
line breaking within each authored derivation step; matrices and cases retain
their structure. `web/vendor/mathjax-4.1.3/manifest.json` records package origins
and every retained asset hash. The server exposes those listed assets with
versioned caching. Renderer scripts, dynamic font data, and fonts need no CDN.

Transparent alignment columns are flattened within each derivation row, keeping
attributed cells and mathematical grouping intact. Alignment scaffolding must not
make an entire right-hand side indivisible at a particular font/width combination.
All 6,873 expressions in the saved corpus pass the actual candidate renderer at
273px at both 18px and 30px after this adjustment, with no overflow, lost token, source-text change
or SVG change. The real annotated PDE derivation also passes its eight component
checks. Evidence is `alignment-corpus-273-18.json`, `alignment-corpus-273-30.json` and
`graphics-12-fixed-320.json`.

`web/math-renderer.js` retains the original semantic template and builds each
candidate in a hidden, inert stage. It publishes only after fonts settle and all
source tokens and marks bind successfully. Publication refreshes fragment paint,
relationship geometry, and saved highlights while preserving the reading anchor.
The renderer checks revision generation, mounted records, current width/font,
and active selections after asynchronous work. Font changes wait for selection
to end; source updates continue to use the Reader's existing selection/dialog
guard. Failure retains the current expression, displays a diagnostic, and retries.

Canonical copying excludes duplicate assistive content and retains original
script order. Native assistive MathML accompanies the visual CHTML. Presentation
glyphs are hidden from the accessibility tree, while references remain ordinary
keyboard-accessible links. These DOM/tree checks are prerequisites, not a claim
that VoiceOver or mobile Safari has been verified.

The source document's HTML language is retained on the reading article and in
section metadata. English source content no longer inherits the Korean Reader
shell. Notes, copied mathematical targets and rendered/assistive mathematical
roots retain their source language when moved. Korean region names and temporary
status messages keep the UI language. Unknown source language remains explicitly
unknown. Existing local language attributes survive transport and rendering;
Typst 0.15.1 does not itself export all local `text(lang: ...)` changes. The
`language` browser fixture checks the exported attributes and mathematical DOM;
it does not validate spoken VoiceOver output.

The browser integration fixture combines a long highlighted sum, original CeTZ
relationship, scripts, derivation rows, matrix, SVG decorations, and references.
Run `tests/runtime_fixture.py` with normal server arguments against a disposable
project containing `tests/fixtures/responsive-math.typ` as `main.typ`. It exercises
the actual Reader and exposes its report after the body. The checks include
canonical copying, font reflow, active selections, obsolete candidate rejection,
and automatic error recovery. Evidence is under `dist/reader-runtime-checks`.
Unresolved mathematical overflow and drawing collisions still prevent promotion
to the mobile default.

Long browser sweeps can opt into `audit=NAME` on the disposable runtime fixture.
Their hidden JSON reports are checkpointed through its test-only, same-origin
endpoint under the fixture output. Revision checks, bounded payloads and an owned
`dist` source/output requirement keep that protocol separate from the production
server. Completed evidence survives a browser-control disconnection. Body sweeps
retain per-section counts, visit every actual mathematical occurrence, check
canonical text and ink, and require original decoration paint on marked passages.
An incomplete range is never counted as completed coverage.
The explicit `math-only=1` mode separates complete width/token coverage from
dynamic-paint coverage and records that choice in the report. Every completed
section also records and checks its requested viewport; an interrupted browser
session cannot silently substitute a different width.

== Managed installation

The Reader lifecycle module belongs to this repository and reads the installed
Flow app's `--profiles` output on each start. Its configuration stores a parent
profile ID and Reader runtime/port options; it does not copy the project root,
fonts, entrypoint, or package settings. It installs its own LaunchAgent and does
not replace or restart the existing paged app or engine.

After a Reader stop, wait until launchd removes the terminating job before
starting another release. A successful `bootout` can precede that removal; an
immediate start can otherwise mistake the old PID for a running Reader. A stop
that does not finish is reported without signalling unrelated processes.

Install only from a clean commit:

```sh
python3 tools/flow-reader/install.py \
  --profile existing-flow-profile \
  --port 23627 \
  --public-url https://your-host.ts.net:23627/ \
  --semantic-canvases \
  --start
```

During validation, add `--development` to retain the development notice and keep
the Reader out of the default mobile entry. The installer archives the committed
Reader sources into an immutable release under the Flow application support
directory. A stable launcher in `reader/bin/flow-reader` exposes `--profiles`,
`--launch-plan ID`, `--status ID`, and `--control start|stop|restart ID`. Reader IDs
append `-reader` to the parent ID. Port validation includes every saved Flow
profile, including projects that are currently stopped.

The installer accepts `--semantic-canvases` for native figure composition.
Omitting this option preserves its installed setting; `--no-semantic-canvases`
returns to coordinate-unit delivery. This setting belongs only to the Reader;
the parent Flow/PDF profile is unchanged.

Tail Hosting registers the derived profile using this launcher as `managerBinary`
and `kind: typst-reader`. The maintained adapter is
`apps/macos/tail-hosting-reader.patch`. It delegates lifecycle operations and reads
`/api/state` for compile status; an HTTP 200 from the shell does not imply a valid
compile. The new Tailscale Serve route must use a free port and preserve all
existing handlers. The installer itself does not modify ingress.

To stop or roll back, stop the Reader ID with its launcher, disable only its new
ingress port, and retain the original paged endpoint. Installed Reader releases
are kept for recovery. Changing a saved Flow project's paths takes effect when
its Reader is restarted. macOS may separately request Documents access for the
Reader's configured Python executable. A background compile waiting on this OS
request is not a successful readiness check. Resolve the normal permission prompt
before verifying managed delivery; do not treat a working foreground preview as
proof that the LaunchAgent can access the same inputs.

== Document entry through Tail Dashboard

The Hosting project card offers `문서 열기` directly, with `자동`, `읽기 화면`
and `원본 페이지` choices. A browser-local choice takes precedence over automatic
device selection and survives refreshes. An unavailable storage API still allows
the current explicit choice. Opening the original PDF address directly retains
that original view; no new redirect or service proxy is installed.

Automatic touch-device opening requires exactly one parent/derived-Reader pair
with the same project and nonempty entrypoint and both primary service URLs.
Registration, process, listener, HTTP and Reader observations must be fresh and
healthy. The running Reader must explicitly report `development: false`,
`semanticCanvases: true` and an accepted revision. Missing flags, stale state,
development builds and ambiguous pairs keep the original default. A strict
Reader's accepted output stays usable during a new or failed save, with compile
failure still reported independently. An explicit Reader choice permits preview
of the development build; this does not promote the mobile default.

`/api/state` reports the actual native-label option. Tail Hosting carries service
kind, entrypoint and `compile.observedAt`; `compile.checkedAt` continues to mean
the last compilation time. An old but unchanged accepted document must not be
mistaken for an unreachable service.

Apply `apps/macos/tail-hosting-reader-mobile.patch` in Tail Hosting after the
existing Reader adapter, and `apps/macos/tail-dashboard-reader-mobile.patch` in
Tail Dashboard. The patches include focused tests and a loopback browser fixture.
Update the Reader from a clean commit, then restart only the Tail Hosting status
monitor to load its new report fields. Dashboard static assets are served without
caching and do not require a server restart. Do not run a full Hosting install
or document lifecycle check just to update these read-only reports.

Keep `--development` while the remaining layout and device gates are open. To
roll back the entry, select the original page or restore the saved Dashboard
assets. The original service and its ingress do not depend on this integration.

== Verification

```sh
FLOW_READER_PACKAGES=/absolute/typst/packages \
  python3 -m unittest discover -s tools/flow-reader/tests -v
node --check tools/flow-reader/web/reader.js
node --test tools/flow-reader/tests/test_continuous.mjs
```

For a small browser fixture with frequent transport boundaries:

```sh
python3 tools/flow-reader/tests/continuous_fixture.py \
  --write-fixture dist/continuous-fixture
python3 tools/flow-reader/tests/continuous_fixture.py \
  --root dist/continuous-fixture --entry main.typ \
  --package-path /absolute/typst/packages \
  --output dist/continuous-fixture-build --watch --allow-incomplete
```

The fixture generator refuses to overwrite an existing source. Verify automatic
forward/backward loading, distant-section parking, native selection, saved quote
return, reload, browser history, and source changes that move a block across a
transport boundary. Interrupt only the test server to verify automatic recovery.
The current browser evidence is under `dist/reader-continuous-checks`.

The integration tests invoke the compiler and compare paged outputs. Browser
checks must additionally inspect MathML namespaces: HTML footnote markers inside
math need token integration points, otherwise browsers may render the remaining
equation as ordinary text despite a successful compilation.

Before mobile rollout, verify the complete actual document at 320, 390, 430, and
768 CSS pixels, large font sizes, reference navigation, annotations, saved edits,
and recovery after compilation errors. Preserve and separately verify the
original paged endpoint. Compilation success alone is not a release gate.
