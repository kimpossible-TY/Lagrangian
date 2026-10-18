# Design

## Last visual edit navigation

Reuse the paged preview's server-owned visual history and render-before-jump
policy. HTML coordinates reflow, so the independent Reader stores canonical
body-block fingerprints and a revision-bound target instead of PDF page points.
Exclude generated navigation and prefer original body content over changed
reference copies. Detect text, mathematical markup and native figure changes;
deletions use a surviving adjacent target. Persist the baseline and last target
atomically with mode 0600 in the managed document output, scoped by document ID.
Compare content fingerprints of compiler inputs, not timestamps, so metadata and
runtime-only recompilations do not invent edits. Invalid records establish a
baseline. Failed compilations never replace accepted navigation history.

The browser follows each new change token once, after its matching section is
mounted. Like the PDF queue, a gesture within 2500ms defers navigation and exposes
“변경 위치로”. Recheck gestures after section fetches; selections/dialogs continue
to postpone publication. Fresh entry and reload prioritize the last edit over
stored reading position, while an explicit named link or browser history return
retains its destination. Poll recovery and theme/font changes cannot replay an
already observed token. Without a valid edit, existing reading restoration applies.

## Reader appearance

### Minimal navigation and direct reading gestures

The toolbar has two 44px icon buttons: outline and reading settings, with Flow
centered between them. Both use plain 21px icons without a persistent background,
border or shadow; retain their 44px targets and keyboard focus indicators.
Font steppers, the existing appearance previews, and saved
highlights live in reading settings. Keep semantic button/radio alternatives to
all gestures, and keep names available to assistive input. The outline is a native
modal dialog with an independently scrolling nav, close control, outside dismissal,
Escape and native focus return; navigating a heading focuses the article.
Present the outline as a floating capsule below the toolbar, inset at least 16px
at the sides, with a 32px radius and a content-sized scrolling
list bounded to 60% of the viewport height and 34rem.
Its shared surface uses a restrained frosted fill, soft edge and shadow;
reduce the scrim so the reading context remains visible. Solid contrast and
transparency fallbacks retain legibility. Hierarchy uses indentation and type
weight, with 44px link targets and softly rounded interaction fills. Opening
marks the nearest reading heading with an accessible location pill, scrolling
only the outline to reveal it. Dismissal travel includes the leading gap and
shadow, preserving the existing spring,
swipe cancellation, Escape and focus behavior.
Preserve the article's scroll coordinates through native `show`/`showModal`
autofocus, which may otherwise scroll toward the offscreen close button. Restore
them before resolving the current heading; verify from a nonzero reading offset.
Hide the normal accepted-document status line and its spacing. Loading, compiling,
connection and publication diagnostics retain their existing status region.
Keep the reading panels free of instructional prose: no gesture hints, outline
footer instructions, highlight storage explainer or step-by-step empty-state
guidance. Retain control names, concise empty states and operational diagnostics.

The user's 2026-10-18 instruction replaces optional browser pinch magnification
inside the article with text reflow. Two article touches track a 13–30px candidate
using their distance ratio. Show a compact size preview and commit once when the
first finger lifts, through the existing anchor-preserving font path. Cancellation,
an extra finger, an active selection, or an open dialog does not commit. Remaining
fingers cannot begin another gesture until all lift. Keep normal one-finger
vertical scrolling; use article-scoped `touch-action: pan-y` and cancel only owned
touch sequences and WebKit's native gesture events. No viewport maximum-scale cap.

An opening swipe starts 24–96px from the left viewport edge, away from interactive
targets and existing selections. Resolve horizontal intent after 10px and reject
vertical/diagonal scrolls. Preview the drawer nonmodally under the finger, then
promote it to a modal dialog only if distance/recent release velocity commits.
The modal drawer supports the reverse swipe. Retarget native Web Animations from
current transform and analytic velocity using a locally tuned critically damped
spring; native semantics close immediately while a noninteractive exit finishes.
Cancellation restores the initial state, pauses retire old velocity, and reduced
motion settles directly with active animations canceled on preference changes.

The toolbar exposes Automatic / Light / Dark. A small classic script applies the
browser-local `flow-reader:theme:v1` choice before CSS paints, independently of
document compilation and the font/quotation/position keys. Automatic follows live
device appearance changes; explicit choices override the device and persist across
reloads and documents on the same origin. Storage failures retain a working choice
for the current visit. Other tabs follow preference changes and resets.

Enhance the native select into a 44px icon-only button opening a native
auto popover. Three equal radio choices show automatic split, light and dark
reading samples, with one persistent selection surface moving behind their
stationary samples. Keep choice names and the live appearance description
visually hidden for assistive access; show no Automatic/Light/Dark text in the
enhanced controls. Keep the panel open for immediate comparisons. Native radio
keyboard behavior, Escape, outside dismissal and focus return remain available;
unsupported popover browsers retain the select. Clamp the panel to the viewport
and keep the toolbar on one line at phone widths. Use a restrained frosted panel,
immediate press feedback and reversible CSS transitions, with solid contrast/
transparency fallbacks and no spatial motion under reduced-motion preferences.

Warm neutral paper and charcoal palettes define ink, secondary text, links,
controls, status colors and selection paint together. Authored HTML `mark` and
saved CSS Highlights share opaque, muted amber in light mode and deep gold in
dark mode. The saved-highlight fallback uses the matching edge color. Drawing
frames and SVGs are transparent; native label backplates match their enclosing
paper or callout wash. Theme changes only recolor existing content and do not
replace mathematical nodes or recompile the document. Compact controls must fit
a 320px viewport without wrapping their text or increasing toolbar height.

The shared drawing adapter retains original SVG paint attributes and remembers
original inline colors independently of its presentation overrides. It adapts
neutral ink to the surrounding palette and mixes colored ink toward a contrast
endpoint only when necessary: 4.5:1 for labels/marked mathematics and 3:1 for
vector strokes. Near-white vector backplates use the actual enclosing surface.
Filled decoration underlays retain at least 4.5:1 contrast against their own
marked term's ink. Coverage masks, clipping, gradient resources, path geometry,
references and embedded raster pixels are unchanged. The source surface rasters
already have transparent backgrounds. No whole-image inversion filter is used.

Live appearance changes and asynchronously mounted/cloned drawings use the same
adapter. Original paint metadata survives clones so repeated theme changes and
moving a drawing between differently colored containers cannot accumulate color
drift. Background composition includes transparent CSS color-mix layers. These
paint changes do not alter logical text, label measurements or reading anchors.

## Output and ownership

Use Typst's HTML target for semantic text and mathematical output. Add target-aware compatibility adapters for the PDE common packages. Preserve the source documents and existing package installation; build reader adapters into an isolated package overlay with recorded provenance. Any compiler modifications must be explicit, pinned, and tested independently.

The reader frontend and its asset/compile service live under `tools/flow-reader`. Existing engine compilation is the initial integration boundary. Flow supplies project root, entrypoint, fonts, and packages; Tail Hosting supplies HTTPS ingress. A separate reader process may be used during rollout so reader failures cannot interrupt the paged service.

The initial managed rollout uses a Reader lifecycle helper within this repository.
It reads the installed Flow app's profile export; only the parent ID, Reader port,
public URL, compiler and Python paths are stored separately. A clean-commit
installer archives immutable Reader releases under Flow's application support
directory. Its LaunchAgent has a distinct label and directly execs the Reader
process, so listener ownership can be checked without touching the paged job.
Tail Hosting consumes the helper's compatible profile/control interface and
reports the Reader's compile state separately from HTTP reachability. This does
not require replacing the installed native app or engine during rollout.

Reader stop waits for launchd to remove the terminating job before returning.
`bootout` may return earlier; an immediate start must not treat its old PID as an
already running Reader. A bounded wait reports failure without signalling other
processes or changing the original service.

Transport metadata carries the exported document language. The article, original
annotation bodies, copied target terms and mathematical views retain that language
independently of the Korean UI shell and status/region labels. Empty language
explicitly means unknown. Preserve local language attributes already present in
the export; do not infer missing language from text. DOM checks do not establish
spoken screen-reader behavior.

## Fidelity

Display equations use a grid with a flexible mathematical cell and an optional
intrinsic-width number cell at the inline end. Center both cells vertically so
fractions, matrices and multiline derivations retain a centered number. Measure
the mathematical cell for composition; the enclosing block also contains the
number and gap and must not supply the expression's line-breaking budget.
Unnumbered equations use one full-width cell. Loading/error notices span a
separate row and cannot move the number away from its expression's center.

Page-relative annotation packages cannot run unchanged in HTML. Represent marked mathematical terms and annotation text as linked semantic content. Preserve custom graphical relationships through faithful rendering or explicit adapters. Never silently discard an annotation or mathematical decoration to obtain a successful compile.

Replace decorative blocks with semantic HTML containers so nested equation labels and references remain visible to the document introspector. Keep theorem kinds, counter resets, and target-location numbering. Use MathML where faithful and SVG for unsupported mathematical constructs. Figure panels stack at narrow widths; vector scaling alone is insufficient when it makes labels unreadable.

## Required reading interaction

The outline includes HTML headings h1 through h6 and deeper `role="heading"`
exports with `aria-level` in source order. Its shallowest exported level starts
at the normal link inset; each additional heading level adds 1rem of inline-start
padding, including skipped levels. Long titles wrap
within the remaining panel width. All heading levels retain reading keys and
anchor destinations across transport-section boundaries.

The user's clarification on 2026-10-17 is the acceptance boundary: ordinary
vertical reading must expose all mathematical and explanatory content at readable
font sizes. Do not introduce slides/carousels, horizontal scrolling, zoom, or
click-to-expand equation views to compensate for a layout that does not fit.
TOC navigation and saved-highlight management remain optional controls; they are
not required to read any part of the text. Original-page access uses the Dashboard
and existing addresses. The Reader toolbar keeps outline and settings icons at
opposite ends, with the Flow identity centered.

Structured mathematical composition measures fraction children, radicands,
spanning brace/bar bodies and labels, scripted bases, and table cells in the
actual calibrated math font. Wide children receive an inner MathML line-breaking
box while their original operator tree, script level and logical identities stay
intact. Discretionary zero-width spaces permit product breaks after preferred
operator breaks; short fenced groups and a function name with its argument stay
together. Scripted bases reserve the measured width of their attached scripts.
The planner uses at most four frame passes and two small overhang corrections,
retaining the measured candidate with the least overflow. Both candidate and
published geometry use the same fractional CSS width.

A wide matrix keeps every row and column. Its inter-cell spacing can become
0.1em; its surrounding fences use a narrower optical size while stretching to
the complete table height. Entry and script fonts remain unchanged. MathJax's
overlapping extender pieces already have a paint mask; matching axis clipping
prevents those invisible stencil pieces from adding horizontal scroll area.
The complete stretched operator remains part of width and visibility checks.

Unadapted CeTZ canvases reserve an aspect-ratio placeholder within the body
until their automatic width/font rendering completes. Their original SVG/image
cannot widen the entire page while it waits outside the rendering margin. A
previous fitted drawing can remain visible during a font update; a result that
reports an impossible fit remains visible with its explicit failure diagnostic.
Placeholder height changes and drawing publication preserve the reading anchor.
The Reader owns scroll anchoring: browser anchoring is disabled, font mutations
restore synchronously, and viewport/font loading restores use the last stable
logical block and viewport offset.
Height-only browser-bar changes do not trigger manual anchor restoration.
The body starts at 13 CSS pixels. A versioned font preference resets the earlier
18px default and legacy saved sizes once; later explicit choices persist in
1px steps from 13px through 30px. Highlights and reading positions retain their
existing keys. HTML and CSS use the same default before JavaScript starts.

The viewport uses device width, initial/minimum scale 1 and `shrink-to-fit=no`.
The browser must not shrink the entire document to compensate for wide content;
component layout continues to use its actual available CSS width. The viewport
has no maximum-scale cap; article pinches use the explicit text-reflow gesture
described above. Safari
text inflation is held at 100% so rotation respects the selected text size.
Reading-anchor restoration compares the root's layout `clientWidth`, because
WebKit can change `innerWidth` during pinch without changing text layout. A
visual-only resize must not undo a newer scroll or recompose the reading column.
Decoration and relationship schedulers synchronously retire paint whose measured
key is obsolete or whose math is awaiting recomposition. This happens before
debouncing and the compiler's busy check. An old absolute SVG can otherwise
retain the wider page overflow during a narrow layout or a slow request, even
though the new paragraphs fit. Removing stale paint does not clip mathematical
content; the current revision's original drawing is published automatically.
Direct navigation uses 88px root scroll padding so its target crosses the 90px
reading reference line. Initial asynchronous composition then preserves that
target instead of the tail of the preceding paragraph.
An initial navigation also distinguishes a new named link from reload/history
restoration. It uses the current history entry and navigation type, rather than
URL equality alone: a new tab can open the exact URL stored by an older reading
session. Source updates preserve the visible reading anchor while a change jump
is deferred; otherwise the accepted visual-edit target takes priority.

Introduce a width-aware layout stage between semantic content and final DOM/SVG.
For mathematics, retain operators, grouping, numbering, labels and term identities
while choosing valid breaks and alignment for the available width. Native MathML
output alone does not establish automatic line breaking. Evaluate an established
math layout engine or extend the Typst math IR; verify fidelity before adopting a
renderer. Matrices and indivisible structures need explicit faithful alternate
compositions where generic line breaking is insufficient. Do not silently alter
the mathematical expression or shrink it below the selected readable size.

The initial isolated MathJax 4.1.3 corpus probe rejects a direct renderer swap as sufficient:
81 of 1,411 display equations overflow at 390px/18px, and 294 at 320px/30px.
The first implementation must preserve mathematical content separately from
decorations: the existing `core-mark` SVG fallback can freeze an entire long term
into one unbreakable image. Export the term's semantic children and its decoration
intent independently, then lay out decorations against the final fragments.
Likewise distinguish aligned derivation tables from mathematical matrices; page
alignment columns and trailing footnote cells cannot dictate narrow-screen width.

The semantic decoration adapter emits a marked MathML row and a separate decoration
ID instead of flattening that row into an SVG. The compiler retains the original
underlay/overlay functions. A revision-bound numeric request supplies each visual
fragment's measured dimensions, reading font size, and inherited ink. It renders
only the decoration at each fragment, returning layer order and anchor outsets.
No mathematical glyphs are copied into that decoration image. The browser paints
the layers around the original semantic nodes; cache keys include all fragments.
This protocol must reject stale revisions, missing fragments, and unknown IDs.

An explanatory copy outside the composition margin cannot block its visible
original. Measure only nearby composed occurrences, and include the member's
identity in the publication key. Geometry-only signatures retain callback-cache
reuse while equal-shaped copies still receive their own paint after scrolling.

A subsequent paired probe uses frozen project dependencies and moves annotation
prose into visible notes in both variants. Combining semantic mannot bodies with
optional derivation-row composition reduces overflow from 26 to 12 at 390px/18px
and from 240 to 96 at 320px/30px, across 1,412 display equations. These results are
not directly comparable with the initial probe's source/preparation. The candidate
does not draw its dynamic decorations in this experiment and is not installed as
the Reader's math renderer. Its unresolved overflow and logical fragment identity
still prevent promotion.

Keep logical term IDs and quotation text independent of presentation DOM order.
The probe found superscript/subscript DOM reordering and repeated marker attributes
after line breaking. A logical marked term may have multiple visual fragments;
graphical geometry must represent all of them rather than `querySelector`'s first
match or a single oversized union rectangle. Renderer adoption also requires
explicit accessibility, embedded-SVG, and reference verification. See the
reproducible evaluation in `tools/flow-reader/research/README.md`.

The logical math model stamps source tokens before typesetting and binds their
IDs to all output occurrences. It retains canonical source text independently of
presentation order, including mathematical alphabet variants and invisible source
selectors. Stretchy operators bind their complete glyph element when text nodes
are replaced by glyph pieces. Missing tokens and unexpected text reject the bind.
Quotation capture returns separate source intervals for visually contiguous but
logically disjoint selections; highlight ranges do not cover intervening scripts.
The Reader's text index uses this model when bound, and ordinary DOM text otherwise.
This prerequisite is verified in the corpus probe; it does not itself enable the
new math renderer or solve multi-fragment CeTZ anchor routing.

Preserve the author's CeTZ coordinates and drawing programs. The user's follow-up
clarification favors a shared adaptive canvas over manually repositioning every
figure. Numeric CeTZ coordinates use the canvas `length` unit; first evaluate a
reader-only adapter that maps the original coordinate system into the available
width while retaining readable text and appropriate stroke widths. Changing an
outer HTML box alone does not change absolute drawing positions. Scaling a
completed SVG scales its text as well, so it is not sufficient when labels become
unreadable. Re-evaluation with a changed coordinate unit must also account for
explicit physical lengths and user-defined text scaling.

Measure the resulting bounds and label collisions. Apply centralized panel/legend
layout rules only where unit scaling cannot satisfy readability; do not assume
that every authored canvas can be rearranged without semantic layout information.
Do not rewrite each source figure's coordinates as the default strategy. Keep
PDF layout and original source files intact. Essential annotations and graphical
relationships belong inline; their anchors must follow the reflowed mathematical
terms rather than retain page positions.

The first adapter assigns `data-flow-canvas` IDs to direct HTML CeTZ canvases.
`/api/canvases` accepts only known IDs, finite CSS widths, and supported reading
font sizes for the accepted revision. The compiler reevaluates the original
drawing at a requested inherited text size and iteratively adjusts its coordinate
unit. SVG dimensions are returned in physical CSS pixels so inherited HTML `em`
sizes do not scale the baked glyphs a second time. Unsuccessful fits retain the
original coordinate unit and report overflow; they do not compress the geometry
indefinitely or clip content. `width-fit` is only a width result, not a readability
or collision result. Explicit font sizes in authored labels still need a policy.

The browser requests nearby figures automatically and rerenders on reading-size
or width changes, rejecting results measured for an obsolete viewport. The service
caches individual canvases across different request batches and serializes dynamic
compiles with annotation compiles. It uses the accepted revision/input checks
already used for graphical annotations. Opaque layout/SVG islands without a canvas
ID remain outside this adapter; they must be covered before final acceptance.

The opt-in `--semantic-canvases` path separates labels before SVG flattening.
The initial canonical HTML exports each original label body as HTML/MathML,
alongside its original CeTZ bounds and a geometry-only SVG. Label math uses the
same renderer, identities, decorations and references as ordinary body math.
Stack and fixed-box label containers become native flow containers. Explicit
text size, weight and color are materialized where experimental Typst HTML
would otherwise discard them. The browser applies the reading-size floor,
retains larger typography, and adapts low-contrast ink to the current reading
surface while preserving its color family. Exported source colors and geometry
remain available and unchanged. Label backplates match the enclosing surface.

The geometry keeps the original coordinate system and uniform aspect ratio.
Physical strokes keep their CSS thickness independently of its scale. Short
native labels occupy their original anchors when their measured boxes fit and
do not intersect other labels or sampled strokes. Other labels remain fully
visible below the drawing with matching readable numbers at their original
points. Displaced numbers have dotted leaders. DOM/source order is preserved;
generated numbers and loading UI are excluded from logical quotations. This is
continuous composition, with no reveal action or separate enlarged view.
Long legend bodies retain the full measured width with their number above them.
Mathematical leaves remain MathML: the label text show rule is guarded inside
equations so the outer typography is applied only once.

Leaf label passages receive source-derived reading keys independent of diagram
numbering. A reading line over geometry preserves its fractional point in the
original coordinate plane; ambiguous source matches do not restore to another
drawing. Font and width publication use those shared anchors. All labels of a
nearby canvas compose together even when a long legend puts its geometry far
above the current viewport.
Loading-notice changes use the same preservation callback as geometry changes.
Passage offsets use whole CSS pixels to avoid accumulating scroll rounding over
many mathematical label publications.

CeTZ 0.3.4 uses a separate Reader fork because Fletcher 0.5.8 depends on that
version. Its processing context, transformations and geometry renderer remain
version-specific. Only canonical native export is shared through a small local
package. Unsupported relative units retain the original paint and a diagnostic.
Intrinsic label width is an output of mathematical composition, not its next
line-breaking budget. Native math uses the canvas width, minus enclosing insets,
with a matching optical inset in the candidate and published view for accent
and italic overhangs.

Offscreen native drawings also reset obsolete placements immediately on font or
width changes. Empty leader SVGs have explicit zero dimensions until publication.
Large native geometry stays inline across transport-section asset separation,
since label placement needs its paths. Resizing this path requires no canvas
compiler requests. Layout publication defers during a selection or reader dialog.
The legacy coordinate-unit path remains unchanged when the option is disabled.
Full arrow/leader geometry, device accessibility, source-update and rollout
acceptance remain separate gates; successful native-label checks alone do not
promote the Reader to the mobile default.

## Reader protocol

Every published document snapshot carries a revision and diagnostic status. Failed compilation leaves the last successful snapshot visible with a stale/error indication. Stable labeled block identities, with deterministic fallback matching, anchor the reading position and persisted highlights. Do not replace the active document while the user has a selection or open reader dialog.

Known input parent directories use entry-name fingerprints to detect import
creation. Their timestamps and Finder metadata are not compiler inputs; changing
those alone must not reject dynamic rendering or force a source recompilation.

Use content and asset requests on the reader's own origin. The original paged view remains reachable through the Dashboard and existing addresses. Initial mobile routing must honor an explicit choice and offer both views.

The configured document entry belongs to the existing Tail Dashboard Hosting
card. A direct document link and an automatic/Reader/original-page preference
sit outside its address-details button. Browser-local preferences are scoped to
the project; unavailable storage still permits the current explicit choice.
This entry does not redirect existing paged URLs or add another proxy/lifecycle.
Tail Dashboard only reads Tail Hosting's report and opens the selected address.

Automatic touch-device selection requires exactly one original/Reader pair in
the same project, the exact derived Reader service ID, the same nonempty
entrypoint and their primary service URLs. Fresh registration, process, listener
and HTTP checks must succeed. The Reader state observation must be at most 60
seconds old, with explicit `development: false`, `semanticCanvases: true` and a
nonempty accepted revision. Missing or incorrectly typed flags cannot promote a
legacy service. The observation time is distinct from the last compilation:
accepted strict output stays usable during a new or failed save. Explicit view
choices take precedence, including evaluation of the development Reader.
Unvalidated, unavailable, stale or ambiguous pairs retain the original entry.

Reader `/api/state` reports its actual native-figure setting. Tail Hosting
publishes service kind, entrypoint and the observation timestamp alongside the
compile timestamp. Its status monitor can be updated independently of both
document services. Portable companion patches are maintained under `apps/macos`;
they preserve each project's ownership and existing ingress.

Store highlights in browser-local storage scoped to a document identity derived
from the project root and entrypoint. A record contains one or more quotations,
their reading keys, and surrounding text. A revision-specific `/api/locate`
request resolves those quotations against the accepted snapshot across every
section. Use an existing key first, then exact quotation and matching context;
ties remain explicitly ambiguous. Removed quotations stay in the saved list.
The passage index stays on the service rather than enlarging the manifest.
Use CSS Custom Highlight ranges to paint text without inserting HTML into
MathML. Browsers without that API retain the saved list and mark the associated
block. This storage does not yet synchronize devices or survive clearing site
data. Updates wait while any reader dialog or text selection is active.

Partition the accepted HTML at top-level block boundaries for transport and cache
management, then load sections automatically into a continuous vertical reading
flow. Transport boundaries must not require next/previous clicks. Keep every annotation
in the same section as its preceding marked terms. Assign reading keys globally
before partitioning; the manifest maps native anchors and reading keys to their
sections. Fetch the visible and adjacent sections, then append/prepend automatically
as the reader approaches their boundaries. Preserve reading anchors and selections
when managing a bounded DOM/cache; the continuous reading experience must not
depend on the transport partition.
The browser keeps a contiguous range of visited sections, loading either neighbor
before its boundary reaches the viewport. It parks distant sections in measured
height placeholders and restores them automatically on approach. Keep at least
the nearby content and any selected/focused section mounted. Preserve a logical
reading block and its viewport offset during insertions and restoration; an
explicit jump may start a new window at its destination. Stale fetches from a
previous revision or navigation must never append to the new window. Failed
boundary requests retry automatically without discarding the readable content.
Highlights resolve against the whole revision and paint all mounted sections.
Keep large SVG and raster images as separate unchanged assets, with SVG hyperlinks
remaining inline. Revision-specific requests reject stale revisions.

For graphical annotations, the browser must measure marked terms in the actual
reflowed body layout and allocate space for their inline relationships. The
service passes only validated numeric geometry to the original CeTZ program and
returns its drawing. Inline scenes replace the former modal/cloned-scene
implementation. A source fingerprint belongs
to the accepted snapshot, not the latest failed compile. Cache by revision and
geometry, namespace SVG identifiers, and reject uncached requests after source
changes. The first implementation uses an isolated full compile; a persistent
compiler can later reduce its latency without changing this protocol.

Inline annotations use ordinary visible body content, with explicit associations
to their marked terms rather than dialog buttons. Graphical annotations group
overlapping target spans into a shared scene containing the original DOM nodes
in their original order. Never clone equations into a separate reading view.
Render nearby scenes automatically; resize/font changes invalidate their measured
geometry. Preserve the original annotation coordinate origin at the first marked
term. The compiler returns the complete drawing bounds and its offset from the
body scene so the browser can reserve vertical space without scaling glyphs.
Report horizontal overflow rather than hiding it. Width fit, label size, and
collision freedom remain separate acceptance requirements.

Marked mathematical terms retain their source identity when a renderer replaces
their DOM nodes. Resolve each relationship target to all of its bound fragments;
send their individual client rectangles in logical order. Keep the previous
single-rectangle protocol accepted. Multi-fragment markers expose anchors on
actual rectangles: directional edges maximize projection in the requested
direction, ties prefer the area-weighted center, and center/default chooses the
nearest actual fragment center. Perimeter anchors traverse the separate rectangle
perimeters in order. Literal coordinates retain the first fragment's origin.
The empty inter-line union is not a valid marked surface. This defines anchoring,
not collision-free connector routing or semantic simplification of the drawing.

For supported planar open line/Bezier connections between named marked terms, retain
their endpoint identities and original path in Reader-only CeTZ metadata. The
browser may propose a route around measured text and labels at the current
geometry. Numeric route requests must preserve the original endpoints; the
original CeTZ callback reevaluates the path and its marks/styles. Unsupported
drawings retain their authored rendering and explicit unresolved-collision state.
Never infer arbitrary drawing semantics or replace an arrowhead with an unrelated
browser glyph. Route decisions belong to the measured revision/geometry and are
bounded to prevent repeated compile loops. A route must fit horizontally without
shrinking the selected text; vertical outsets reserve body space automatically.

## Validation and delivery

The development Reader now owns the mathematical rendering lifecycle. It stamps
source tokens before mounting a section, then composes nearby expressions using
the pinned local MathJax 4.1.3 MathML-to-CHTML conversion API. Display derivation
rows use the evaluated row adapter; matrices remain intact. A hidden, inert stage
holds a candidate until fonts are available and every source token/mark binds.
Publication preserves reading anchors and updates decoration, relationship, and
saved-highlight geometry. A rejected candidate leaves the current expression
readable. Revision, mounted-record, width/font, and active-selection checks run
again after asynchronous composition. Distant parked sections release records;
restoration prepares new records. Failed loads/compositions retry automatically.

The renderer and retained font distributions are served from a versioned local
manifest with immutable caching; their upstream bytes and license metadata are
retained. No CDN is needed. Conversion results are not registered MathJax page
items, so Reader lifecycle owns recomposition and disposal. Copy uses canonical
source text, excluding the native assistive MathML duplicate. That assistive
MathML supplies the semantic accessibility representation; presentation glyphs
are hidden while visible reference links remain keyboard-accessible. DOM and
browser accessibility-tree checks do not replace actual screen-reader validation.
The user explicitly defers actual VoiceOver speech validation to follow-up on
2026-10-18. Retain it as unverified, without blocking this mobile-entry rollout
on that deferred check. Visual/device and mathematical-fidelity checks remain.
Overflow remains a visible failed layout condition. This integration does not
resolve the remaining indivisible structures, drawing collisions, or mobile
rollout requirements.

Native cancellation must retain a semantic `menclose` body instead of freezing
the cancelled text into SVG. The Reader-only adapter captures the resolved
cancellation properties and uses the existing fragment-decoration protocol to
draw the original Typst cancellation on an empty measured box. For visual line
breaking, replace only these paint-backed enclosures with transparent rows;
restore their enclosure notation in assistive MathML. Arbitrary enclosures remain
intact. The compiler's `mrow` boundary keeps nested show-rule bodies in math mode;
the HTML normalizer promotes the tagged row afterward. Overlines use native
accented MathML with an explicitly stretchy spacing macron spanning their whole
body. A combining accent can remain a short glyph and is insufficient. Neither
adapter changes the paged target or authored source coordinates.
Check measured glyph and stretched-operator extents as well as scroll width.
Use a stretched operator's complete visible surface rather than its clipped,
overlapping glyph pieces; those pieces do not represent independent visible ink.
A small measured display overhang can trigger up to two additional line-breaking
passes at the same font size, reserving at most one em of the available width.
Large indivisible structures remain explicit layout failures.

An inline expression that remains wider than its reading container may be
recomposed as a block in the continuous body. Retain its original `displaystyle`
(false by default for inline math), so fractions, limits, and script sizes do
not change merely to obtain block line breaking. Only publish this alternate
composition after the usual token, revision, geometry, and selection checks;
short inline expressions whose complete ink fits stay inline and widening the viewport can restore the
original presentation. No expansion action or font reduction is involved.

Retire any previous status notice before measuring publication in the actual
paragraph. A short accent at a line end can overhang even though the isolated
candidate fits; move that occurrence to an ordinary body line at the same size
and remeasure. A block warning must not itself change line breaks and become a
false permanent overflow state.

Compile the complete PDE project, checking unresolved references and unsupported output diagnostics. Compare paged output before/after adapter changes. Browser verification covers 320, 390, 430, and 768 CSS-pixel viewports, larger fonts, light/dark themes, navigation, selection, updates, and offline reload where supported. Verify the original live service and new Tailnet reader endpoint independently before changing mobile entry behavior.

A layout pass is not successful merely because the document root has no horizontal
overflow: inspect each equation, table, drawing, annotation and required content
control. Include 30px text, narrow widths, and rotated layouts. No clipped terms,
unreadably scaled labels, or required reveal actions may be hidden by the audit.

## Native surface figures and source identity

The separate Maquette 0.1.3 overlay exports flat SVG axis text through the same
native figure protocol. Original raw raster pixels and non-text SVG geometry
remain intact; x/y, text anchors and measured baselines locate readable labels.
The generic native exporter is shared with both version-specific CeTZ adapters.
Geometry uses the available width even when the authored drawing was smaller,
without scaling label glyphs or physical stroke thickness. Nested raster frames
fill the original viewBox independently of the selected reading font.

Canonical geometry hashes normalize internal SVG references and attribute order.
Native label keys include this source figure identity, and the manifest maps
unique figure identities to transport sections. A source update cannot restore
to a different plot merely because an earlier insertion reused its numeric ID
or axis quotation. Ambiguous text fallbacks are rejected. This identifies the
source geometry, not a semantic equivalence between arbitrary drawing programs.

## Responsive tables and free drawing placement

Keep original table, row, cell and mathematical nodes. Stack logical rows in the
continuous reading body and expose column/header associations with native table
elements and explicit roles. Honor explicit headers; infer only a recognized
bare-cell header pattern. Unknown first rows remain data. Repeated prose hints
are CSS generated content, excluded from canonical text and mathematical IDs.
Reading keys belong to leaf cells or nested source passages.

A literal-coordinate annotation may have no named destination endpoint. When
such a pure vector drawing collides with reflowed text or exceeds the width,
preserve its complete original paths, transforms and arrowheads in an automatic
band immediately below its original source scene. Fit only its geometry and
retain stroke thickness. Do not invent a connection to another term. This
fallback excludes embedded glyphs and measured label bodies. Named connections
continue to use measured endpoints and routing, with explicit failure if they
cannot be composed. All essential material stays visible through vertical reading.

A late font-loading event must not restore a stale passage over a newer scroll
whose scroll event has not yet been delivered. Track the scroll position of the
saved anchor before applying that delayed restoration.

Open line/Bezier annotations with one named endpoint expose that fixed endpoint
and an explicitly free literal endpoint. The browser may move the latter into
clear reading space, preserving the named endpoint exactly. Unmarked text remains
an obstacle even though the free endpoint has no tag. The compiler validates
named endpoint equality and renders the original styles/arrowheads on the new
route. Pure numeric drawings without any named endpoint retain the separate
continuous-band policy.

Within derivation rows, discard only transparent alignment-column scaffolding;
retain attributed cells and semantic mathematical groups. A right-hand alignment
column must not become an indivisible mathematical object at some font/width
combinations. Audit the actual annotated Reader scene as well as the independent
candidate corpus.

Reserve the original arrowhead's paint when choosing a free endpoint, rather
than checking only its centerline. Keep a colliding candidate invisible while
its automatic replacement is pending; publish the complete original or routed
paint only with its terminal layout state.

Collision sampling must follow painted SVG geometry. A zero-distance path sample
can identify an isolated, unpainted initial move before the real subpath. Begin
nonempty path sampling at a subpixel positive distance; retain painted
zero-length round/square caps and ignore unpainted butt-cap moves. Share this
policy between relationship routing and native figure label placement so neither
can introduce phantom obstacles from the same SVG.

CHTML text ranges include the font's full ascent/descent, leaving false obstacles
between mathematical rows and sometimes covering a fixed endpoint. Measure each
mathematical glyph's own surface, stretched operators once at their complete
surface, and carried SVG math. Exclude assistive and staging copies. Keep prose
range bounds and each mathematical surface's original marked-term identity.
Share the glyph/stretched-surface policy with horizontal mathematical bounds.

Relationship frames inherit the selected reading palette and remain transparent.
Their vector paint and marked term colors adapt to that actual surface, including
equation numbers, references, nested content and decoration underlays.

Dynamic response reuse is per component as well as per request batch. Key each
graphic, canvas and decoration by kind, accepted revision, ID and complete
validated geometry. A differently grouped request reuses unchanged components
and compiles only the missing layouts. A failed source save retains already
rendered accepted output; uncached geometry against changed sources is rejected.
Clear both cache levels when a new revision is accepted.


Outside-tap dismissal from rest adds an 80ms, 8px anticipation before the 320ms spring exit. Interruptions carry current position and velocity; moving entries and swipes keep the direct spring. Native dismissal and focus return remain immediate; reduced motion skips the effect.
