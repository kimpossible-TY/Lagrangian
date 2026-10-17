# Design

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

## Fidelity

Page-relative annotation packages cannot run unchanged in HTML. Represent marked mathematical terms and annotation text as linked semantic content. Preserve custom graphical relationships through faithful rendering or explicit adapters. Never silently discard an annotation or mathematical decoration to obtain a successful compile.

Replace decorative blocks with semantic HTML containers so nested equation labels and references remain visible to the document introspector. Keep theorem kinds, counter resets, and target-location numbering. Use MathML where faithful and SVG for unsupported mathematical constructs. Figure panels stack at narrow widths; vector scaling alone is insufficient when it makes labels unreadable.

## Required reading interaction

The user's clarification on 2026-10-17 is the acceptance boundary: ordinary
vertical reading must expose all mathematical and explanatory content at readable
font sizes. Do not introduce slides/carousels, horizontal scrolling, zoom, or
click-to-expand equation views to compensate for a layout that does not fit.
TOC navigation, saved-highlight management, and an explicit original-page link
remain optional controls; they are not required to read any part of the text.

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

## Reader protocol

Every published document snapshot carries a revision and diagnostic status. Failed compilation leaves the last successful snapshot visible with a stale/error indication. Stable labeled block identities, with deterministic fallback matching, anchor the reading position and persisted highlights. Do not replace the active document while the user has a selection or open reader dialog.

Known input parent directories use entry-name fingerprints to detect import
creation. Their timestamps and Finder metadata are not compiler inputs; changing
those alone must not reject dynamic rendering or force a source recompilation.

Use content and asset requests on the reader's own origin. The original paged view remains reachable from the reader. Initial mobile routing must honor an explicit choice and offer both views.

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
Overflow remains a visible failed layout condition. This integration does not
resolve the remaining indivisible structures, drawing collisions, or mobile
rollout requirements.

Compile the complete PDE project, checking unresolved references and unsupported output diagnostics. Compare paged output before/after adapter changes. Browser verification covers 320, 390, 430, and 768 CSS-pixel viewports, larger fonts, light/dark themes, navigation, selection, updates, and offline reload where supported. Verify the original live service and new Tailnet reader endpoint independently before changing mobile entry behavior.

A layout pass is not successful merely because the document root has no horizontal
overflow: inspect each equation, table, drawing, annotation and required content
control. Include 30px text, narrow widths, and rotated layouts. No clipped terms,
unreadably scaled labels, or required reveal actions may be hidden by the audit.
