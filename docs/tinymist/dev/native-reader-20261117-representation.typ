#set document(title: "Native Reader: representation and proof gates")
#set text(size: 10pt)
#set page(margin: 20mm)
#set heading(numbering: "1.1")

= Decision and evidence boundary

Task: `lagrangian-native-reader-20261117-plan-v1:NR02:32d74e095a64`.
Project: `kimpossible-TY/Lagrangian`.
Every existing-source citation below refers to baseline
`5d71618e7ee320edbe759511fe634024fc8104a6`, using repository-relative paths and
one-based lines from `git show <baseline>:<path>`. Line intervals describe that
blob, not a future implementation. Planner `MIGRATION.md` F03–F06/F15/F16 and
`source-evidence.json` were discovery aids; the cited source was read directly.

*Recommendation, conditional on proofs:* retain Typst compilation and accepted
Python normalization/source validation. Give the native reader an immutable
semantic document with separate layout results. Try AppKit text presentation
with TextKit for prose and CoreText/CoreGraphics for measured text and drawing;
reuse engine layout for mathematical and graphical objects when adequate output
can be exposed. Keep paged and reflow layouts distinct. This is alternative A
below, with an engine-output proof before committing to its difficult objects.
It does not adopt a new production API or module list.

The first executable candidate is the headless prose/Unicode representation proof
P0 below. It needs no engine rewrite, live service, GUI or new dependency.
It can falsify text/index/selection assumptions quickly. Passing it would not
prove mathematics, page fidelity, native interaction or VoiceOver. A full
engine-owned layout alternative B remains available if local object composition
or semantic conversion fails. PDFKit is a paged comparison/export candidate C;
a PDF-only reader cannot satisfy the reflow and semantic-interaction goal.
WKWebView wrapping is outside the final design.

This deliverable is static design research only. No target Reader fixture or
engine protocol output was generated, native implementation built, GUI opened, performance measured,
service changed, or CI/Cloud job dispatched. Existing code and tests establish
output shape and intended invariants, not runtime success. Apple frameworks and
API names are candidates: external API freshness, local SDK headers, deployment
availability and minimum macOS version were not verified. Those are follow-up
prerequisites before using an API or choosing a supported OS.

= What the baseline actually produces

== Semantic HTML and private correspondence

`tools/flow-reader/flow_reader/compiler/execution.py:15–46,66–91` defines raw
requests for `html` or `pdf`, returns bytes, dependencies, exit code and elapsed
time, and explicitly leaves acceptance to callers. HTML invokes the compiler
with its HTML feature. A zero compiler exit code is not document acceptance.
`compiler/build.py:19–45,89–105` applies the existing reader wrapper/package
overlay, audits and normalizes output, conditionally computes correspondence,
and derives revision from normalized HTML bytes. These references share the
`tools/flow-reader/flow_reader/` prefix.

`document/sections.py:125–213` adds keys for headings, leaf table cells,
paragraphs, formula containers and native figure-label bodies, with separate
navigation anchors for callouts/figures. Keys derive from explicit labels or
context/text hashes plus occurrence counts. They are useful matching evidence,
not permanent node UUIDs: edits, duplicates and heading changes can change them.
`sections.py:216–342` retains language, outline, anchors, block-to-section and
canvas-identity indexes. It partitions HTML at transport limits (defaults
180000 characters / 140 blocks), protecting marked-term/annotation relationships
from section cuts. A section is neither a page nor a native paragraph.

The actual `SectionBundle` has `manifest`, HTML document bytes, asset bytes,
`passages`, and separate `navigation_ranges` (`sections.py:284–342`). The manifest
contains `revision`, `language`, `sections`, `anchors`, `blocks`,
`canvasIdentities`, `outline`. It does not contain glyph positions, native
layout constraints, all inline styles or a complete accessibility tree.
`sections.py:43–65` also separates large SVG assets while retaining inspectable
native-label geometry and linked drawings inline. Native consumption must
resolve the asset table; extracting only text loses visible content and links.

`document/passages.py:6–25,27–66` collapses whitespace and indexes canonical
passage text, excluding SVG/script/style/nav and annotation target bodies.
Those passages are an action index, not a complete visual or semantic tree:
unwrapped callout text can remain visible without being a selectable passage
(`tools/flow-reader/tests/test_sections.py:70–87`). A native importer must retain
visible content independently and report where existing verified actions are
unavailable, rather than build the article only from passages.

`compiler/source_map.py:25–40,256–285,293–319,479–527` adds compile-only carriers
in isolated sources, verifies accepted block text/identity and translates ranges
into normalized passage offsets. Source-map failure can yield partial/unmapped
or unavailable status while the accepted document remains usable. Original HTML
is delivered; private ranges are attached to passages only when text matches
(`sections.py:333–342`). Navigation-only invocation ranges are not selection
authority. `tools/flow-reader/tests/test_source_mapping.py:360–390` explicitly checks Unicode,
CRLF, byte-column versus saved-focus positions, unchanged HTML, and absence of
private ranges in the public manifest. This is a test definition, not a test run.

Reuse these owners. Any native semantic-tree serialization is *additional
output*, produced after existing acceptance, not permission to export private
source paths/maps wholesale or weaken source validation. An initial importer
may parse allowlisted normalized HTML offline; unsupported tags, styles or
MathML must produce a diagnostic and capability result. Foundation attributed
HTML import is not assumed to preserve these reader-specific semantics.

== Paged vector stream

`crates/typst-preview/src/protocol.rs:3–37` defines `diff-v1,` and `new,`.
`new,` wraps the same payload format emitted by a fresh incremental renderer,
and requires reset before merge. It is not a stream of SVG XML documents.
`crates/typst-preview/src/actor/render.rs:41–52,157–210,320–335` owns
`IncrSvgDocServer`, full/delta packing, optional focus identity/revision hints,
and render-before-change/resume ordering. The full request creates a fresh
renderer and replaces its server state. Do not assign independent semantics to
payload bytes merely because the prefix is understood.

The actual consumer imports a typst.ts `RenderSession`, keeps DOM measurements,
and delegates `merge` to `kModule` after reset for `new`
(`tools/typst-dom/src/typst-doc.mts:1–35,229–242,428–443`). It serializes queued
changes, holds them for selection and discards superseded queued work on `new`
(`:165–183,462–481,504–529`). These are existing WASM/DOM adapter operations,
not an available Swift renderer API or proof of native payload decodability.
Missing/out-of-order deltas must trigger full resynchronization in a future
native transport contract; the existing prefix helper itself does not establish
an explicit base-revision handshake.

There is reusable engine information before packing: page frames include groups
with transforms/clips, text with font/size/fill/stroke/text/glyph advances and
offsets, shapes and images (`crates/typst-preview/src/actor/render.rs:226–285`). That code hashes visible
items and deliberately ignores links/tags; its page hash is neither a semantic
identity nor a source-freshness proof. Source/frame resolution is separately
owned (`:342–370,374–440,443–461`); the last resolver converts positions to pt.
This is evidence for an engine display-list/export spike, not evidence that all
cluster/source/AX information survives `pack_delta` or is currently exported.

== Reflow composition is real work

`tools/flow-reader/web/rendering/math/renderer.js:90–105,213–227,251–330`
retains a MathML identity/template, measures width/font, invokes MathJax CHTML and
recomposes line budgets. `:354–449` gates publication by generation, selection
hold and current geometry; `:453–468` delegates mathematical copy to the
selection owner. The code's state named `native` refers to browser mathematical
presentation, not macOS native rendering. CoreText alone is not a MathML layout
engine, line-breaking mathematical compositor or mathematical speech provider.

`tools/flow-reader/web/rendering/graphics/canvases.js:1–6,33–55,67–85,191–286`
uses native-in-DOM label composition for semantic canvases and server-returned
SVG for other canvases, keyed by revision, object, width and font size. It checks
selection and stale response identity, limits visible work, batches and caches.
A width fit is explicitly not proof of no label collisions. Native redraw must
replace DOM label measurement/placement, validate fragment geometry and support
engine-generated hard geometry. Copying the SVG path alone loses label meaning.

Existing behavioral constraints remain relevant: accepted reader architecture
requires renderer-native positions and snapshot guards
(`openspec/specs/reader-architecture/spec.md:8–26,42–45`). The active responsive
design requires verified full-formula copy and excludes equation numbers from
selection (`openspec/changes/add-responsive-reader/design.md:61–97`). Its spec
requires parallel paged/PDF outputs and mathematical fidelity, semantic terms,
annotations and per-fragment decorations
(`openspec/changes/add-responsive-reader/specs/responsive-reader/spec.md:110–111,146–195`).
These requirements are inputs to the native proposal, not already implemented
native behavior; NR06 must state any deliberate contract replacement.

= Three implementation alternatives

== A — Semantic native flow with engine-supported objects (recommended proof)

Use normalized HTML/MathML and existing indexes to form typed native blocks and
inline spans. AppKit owns the actual view and input. TextKit (version to prove)
is a candidate for native text selection, focus and accessible text; CoreText
provides shaping/line measurement for custom fragments; CoreGraphics paints
paths and engine-produced object display lists. Prefer one layout result shared
by paint, hit-testing and AX. Do not let TextKit and a separate CoreText pass
shape the same line independently and then combine mismatched positions.

Native flow owns paragraph wrapping, spacing, table sizing, object baseline
placement and viewport anchoring. Typst retains source evaluation and object
fidelity. A math object initially needs an engine-produced baseline/ink box,
glyph/shape content and semantic identity. A rigid object with horizontal overflow
is only an explicitly limited proof step: final reflow must demonstrate narrow
width mathematical line breaks without scaling text down. Requesting
width-specific engine object layout needs a new contract; the present HTML
geometry APIs and SVG bytes are not already a native display list.

Benefits: earliest reuse of accepted prose/anchors/source actions; native text
interaction can be evaluated without a vector decoder. Costs: HTML style
translation, attachment-crossing selection, table structure, mathematical line
breaking/AX and graphics labels need explicit implementations. An attachment
view per formula must not split the article into disconnected selections.
If paragraphs work but complex objects fail, require an engine object-output
spike; if cross-object native selection/AX or reliable style translation fails,
compare B before creating production renderer modules. Do not hide failure
behind a WKWebView or remove the failing content.

== B — Engine-owned page and width-constrained flow layout

Expose a versioned native-friendly scene plus semantic sidecar from existing
Typst/Reflexo data, keeping font, glyph positioning, transforms, clips, paths,
images and links. AppKit/CoreGraphics draw and hit-test it; the native selection
controller and AX adapter use semantic ranges/reading order. Request layout with
page mode or reflow width/font policy; do not reflow already-positioned glyphs.
Candidate extraction points are pre-pack frames and existing accepted HTML,
not a promise of a particular Rust export module or FFI/IPC technology.

Benefits: one layout authority for hard mathematics/vector work; strongest
paged-fidelity starting point. Costs: new serialization/resource lifetime,
incremental dependency tracking, semantic joins and width-dependent layout;
the existing paged compiler output is not proof of a continuous reflow layout.
Native keyboard selection and VoiceOver remain custom work even if paint is exact.
First prove full-scene extraction and equality of full versus delta replay;
only then optimize deltas. If the packed format cannot be consumed natively,
prefer a small engine export over reimplementing its opaque decoder in Swift.
If flow semantics cannot be recovered, combine B for paged/hard objects with A
for semantic flow, or stop for an explicit output-extension decision. Rust
changes/builds require a separate authorized task and verified remote environment.

== C — PDFKit paged rendering plus a separately owned semantic model

Reuse existing PDF bytes for page-fidelity comparison or export; PDFKit is only
a candidate paged renderer. Add a revision-matched semantic tree, source/anchor
evidence and native interaction geometry if testing this path. PDF text
extraction, tags, reading order, formula copy and AX are not assumed correct.
A page selection rectangle is not a verified source range. Continuous scrolling
of fixed PDF pages is not semantic reflow; PDF cannot be assumed to preserve
the original HTML tables, links, math identities or width-dependent composition.

This can supply a quick visual baseline for B, but needs A/B for reflow and
cannot be the sole product architecture. If semantic/geometry joins fail,
retain PDF for export/comparison only. Do not spend the primary proof budget on
an apparently complete PDF viewer whose hardest selection/AX work is deferred.

= Candidate document and layout contracts

The following are proposed cross-language invariants, not existing API fields.
The accepted document is immutable; layout is replaceable and refers back to it.
The service owns acceptance/source freshness; a renderer owns geometry and view
lifetime. Reuse the existing snapshot contract rather than making native paint
authoritative: `tools/flow-reader/flow_reader/services/accepted_snapshot.py:9–31`
captures under the publication lock and checks revision, source signature and
input fingerprint before actions.

- `DocumentIdentity`: project/entry, service instance, accepted revision, schema
  version, input identity and explicit capabilities. Keep engine provenance and
  layout generation distinct. Acceptance is not inferred from a compiler process
  starting or a paint callback completing.
- `SemanticNode`: revision-scoped ID, role, language/direction, parent/ordered
  children, canonical displayed text/spans, named anchors, link targets, inline
  styles, table row/cell/header spans, math/figure identities and annotation
  target relationships. Retain visible-but-unmapped content. Keys and quotations
  can support relocation; ambiguous duplicates cannot silently inherit an anchor.
- `TextPosition`: node ID plus explicit offset unit and boundary affinity;
  `TextRange`: ordered half-open intervals plus original anchor/focus direction.
  Keep a reading-order range across paragraphs, tables and formulas, not a list
  of arbitrary selected glyph IDs. Separate current selection, submitted ticket
  and AX selection representation.
- `SourceEvidence`: opaque service-side correspondence/capability, with mapped,
  partial, generated, ambiguous or unsupported states. Rendered text, semantic
  offsets and glyph locations never grant source writes. A navigation-only
  container does not become highlight/copy authority.
- `LayoutResult`: document identity plus mode/width/font/theme/scale and layout
  generation; page/flow fragments with baselines, ink and advance boxes,
  bidirectional caret stops, text-to-glyph cluster relations, transforms/clips,
  resource references, anchor and semantic-range-to-fragment mappings. Font
  resource identity includes face/variation/fallback and resolved size. A font
  name alone cannot guarantee paged glyph IDs or metrics.
- `Capability/diagnostic`: advertise prose selection, full math copy, structured
  math AX, table navigation, graphic label selection and reflow independently.
  Unsupported constructs remain visible with an actionable diagnostic or a
  faithful limited rendering; never report parity by silently dropping nodes.
- `Publication`: adopt a complete matching accepted snapshot atomically; preserve
  the last accepted view on compile/import/layout failure. Hold replacement
  during active selection, bound queued work, and explicitly release/reselect
  if it cannot be retained. A stale ack cannot clear a newer selection. Reset
  invalidates geometry/AX markers and old resource handles. Disposal cancels
  only view-owned work, not shared engine/service lifetimes.

== Unicode, coordinates and font units

Python string enumeration/slicing in `document/passages.py:10–25` and
`compiler/source_map.py:256–285,503–527` uses Unicode code-point indexes.
Source hashes are over UTF-8 bytes. Swift `String.Index`/grapheme positions,
NSString/CoreText UTF-16 offsets, source UTF-8 bytes and LSP line/character are
different units. Carry a tagged unit at every adapter; never send a Swift
character count as a Python offset or assume all LSP characters mean bytes.
Preserve original CRLF and source bytes for validation.

Build per-span maps between original text, canonical whitespace-normalized text,
code points, UTF-8 and UTF-16. Do not introduce NFC/NFD normalization without a
correspondence map: precomposed Hangul and decomposed Jamo must round-trip to
their own original bytes. One ligature glyph can represent several characters;
a grapheme can contain several code points/glyphs. Store many-to-many cluster
relations. Visual bidi order does not replace logical copy/AX order. Hit-test
to a legal caret boundary with leading/trailing affinity; for overlapping boxes
use reading/paint order and clip membership. Test whitespace clicks, empty
lines, zero-width marks, surrogate pairs and positions outside text.

Paged positions use page identity plus points; flow positions use semantic
anchors and current layout fragments. Define origin, axis direction and page
numbering on the output boundary, then explicit transforms to AppKit view and
screen coordinates. Inverse-transform a pointer before hit-testing rotated or
scaled content. Do not reuse browser `pixelPerPt` (`tools/typst-dom/src/typst-doc.mts:100–101`) as a
native conversion. AppKit logical points, backing pixels, Typst pt, CSS px and
font-relative em must remain tagged. A baseline font pt size and object em
measurement require an explicit scale; device backing scale affects raster
paint only. Test 1x/2x and zoom without changing copied ranges.

= Fidelity mapping and unresolved work

- *Text/glyph/cluster:* paged B should preserve engine advances and font bytes or
  outlines; reshaping with CoreText is not pixel parity. Reflow A reshapes prose
  at current width/font and stores its own cluster/caret map. C supplies only a
  comparison until extraction/semantic joins are proved. All paths need an
  independent logical string and legal grapheme boundaries.
- *Mathematics:* paged layout can reuse fixed engine glyphs/paths. Reflow needs
  line breaking, baseline/number columns, fractions, scripts, cancellation,
  overline and fragment identities. Candidate engine object layout must return
  semantic-to-fragment mappings and annotation targets; otherwise additional
  output or a native math compositor is needed. Selecting a mathematical
  fragment can be inspected internally, but Copy follows full-formula policy:
  expand endpoints to the formula body, exclude number/attached label, fetch
  the existing verified source excerpt, and preserve surrounding prose. An
  unavailable excerpt falls back to displayed text with a notice; never reverse
  engineer Typst source from glyphs/MathML or compile on copy. Desktop live
  selection need not snap until copy/action activation (active design :71–97).
- *Tables:* A needs header relationships, row/column spans and measured native
  cell layout, with a documented row-major reading/copy order and delimiters.
  B needs semantic cells attached to fixed page fragments; a table crossing
  pages must not duplicate repeated headers in logical selection. Do not flatten
  the table to one text blob or claim that TextKit supplies table AX by default.
- *Vectors/figures:* reuse paths/images/fonts where decoding is proved; preserve
  transforms, clips, arrowheads, gradients, label baselines and link hit regions.
  Semantic labels must remain selectable/accessible at the reading font without
  scaling down to fit. Dynamic CeTZ callbacks may require existing validated
  server rendering; native geometry requests need tagged units and current
  revision/font/width/fragment IDs. Unsupported SVG paint is diagnosed, not
  silently approximated. A general SVG decoder is not assumed to exist in
  CoreGraphics or PDFKit.
- *Anchors/selection:* keep page anchors and flow anchors as a tagged union,
  validate target identity in the adopted snapshot, and remap semantic ranges
  after layout. A connected drag/keyboard selection crossing prose, inline math,
  figure label and section boundary must retain direction and logical order.
  Unloaded sections require bounded asynchronous range materialization; do not
  drop the middle of a selection or make copied content depend on visibility.
- *AX:* derive headings, paragraphs, lists, links, tables, equations, figures and
  annotations from semantics, not paint order. TextKit native accessible text
  and custom AppKit accessibility elements/text markers are candidates to test.
  CoreGraphics paint has no implied text AX. Keep one accessible occurrence of
  a formula, stable revision-scoped markers, range-to-screen bounds and selected
  text synchronized with the same layout. Equation number remains readable and
  linked while excluded from copied formula body. VoiceOver must navigate into
  meaningful math structure or report a documented limited representation;
  a generic “image” label or a successful AX tree dump does not prove math
  accessibility. Language-sensitive speech, focus, rotor/keyboard traversal,
  virtualized text and layout-change notification behavior require real native
  GUI/VoiceOver testing. Do not claim current browser math speech as a native
  baseline.

= Proof fixtures and stop/go decisions

No fixture or candidate file below has been created or executed by NR02. These
are exact proposed paths for a separately assigned proof task. They are not a
production module manifest and must not be added to `apps/macos/sources.json`
until a later integration decision. PM supplies a new task ID and write scope.

== P0 — Fastest headless text and representation proof

Proposed new files, one isolated proof owner:

- `tests/flow-app/native-reader-proof/fixtures/representation-minimal.typ`:
  two headings, two paragraphs spanning a forced transport-section boundary,
  explicit named anchor/link, emphasis, authored whitespace, repeated paragraph,
  a two-by-two header table and a simple inline formula. Include exact strings
  `한글`, decomposed `한글`, `é`, `😀`, `👩‍👩‍👧‍👦`, `office ffi`,
  `abc אבג 123`, a tab and CRLF. Record scalar sequences explicitly in the oracle;
  visual equality of composed/decomposed text is insufficient.
- `tests/flow-app/native-reader-proof/fixtures/representation-minimal.expect.json`:
  hand-reviewed logical order, legal endpoint/byte/code-point/UTF-16 mappings,
  cross-block copy results, anchor and unsupported-object expectations. Do not
  derive the oracle solely by calling the implementation under test.
- `tests/flow-app/native-reader-proof/export_fixture.py`: use existing
  `compiler.build.compile_project` and `document.sections.split_document`, in a
  caller-selected temporary root/output, to capture real normalized accepted HTML,
  manifest, assets and passages. Emit a small versioned proof JSON translation
  of allowlisted prose/roles with offset maps; validate against the oracle.
  Retain math/table objects and diagnostics even before their layout is supported.
  Source correspondence remains a private test-side fact, not a public endpoint.
- `tests/flow-app/native-reader-proof/RepresentationProof.swift`: a standalone
  executable consuming that JSON, using CoreText for headless line/cluster/caret
  geometry, CoreGraphics bitmap paint if needed, and assertions over index
  conversion, hit-test/range bounds, reading order and anchor remap. Do not
  pretend this is a TextKit/AppKit interactive reader. Emit bounded result JSON
  and a nonzero exit for failed assertions or missing required prerequisites.

Minimal contracts to freeze *before dispatch*: (1) accepted snapshot identity and
proof schema version; (2) canonical/display/source offset units, explicit maps
and grapheme endpoint policy; (3) ordered block/inline IDs and a full-formula
placeholder capability; (4) layout coordinate origin/unit, width/font inputs and
range-to-fragment mapping; (5) diagnostic/failure rules and atomic accepted
replacement. These are enough for P0; transport/FFI and a full native scene
protocol are not prerequisites.

Environment prerequisite: preinstalled compatible HTML compiler, a complete local
package/font set, Python and macOS Swift/CoreText SDK; exact compiler version and
hash recorded. `typst` existing on PATH does not prove compatibility with the
reader's custom flags or packages. Do not install/fetch dependencies or use live
profiles to make the proof pass. If capture is unavailable, a hand-authored HTML
fixture may run a clearly labelled importer smoke test, but real compiler-output
coverage stays blocked. Existing fixture examples at
`tools/flow-reader/tests/test_sections.py:59–123` and source-map tests at
`tools/flow-reader/tests/test_source_mapping.py:360–390` are reusable expectations to consult,
not native verification evidence.

Suggested future sequence: export once in a disposable directory, run the Swift
executable at widths 320/640/960 pt and font sizes 14/20/28 pt, then replay a
text edit at fixed identity transitions. Those values are experimental inputs,
not minimum supported window/font sizes. For each legal interior caret stop,
round-trip offset → caret region → hit-test → same endpoint/affinity, including
bidi secondary carets; at exact ambiguous boundaries accept only the documented
equivalent set. Assert zero mid-grapheme/surrogate endpoints and exact expected
copy across blocks. Sweep points outside/inside glyph ink separately from
advance boxes. Fail on lost text, silent unsupported nodes, wrong index units,
or stale geometry adoption. Report which portions were placeholders.

If P0 fails canonical correspondence, fix the importer/units before GUI work.
If it passes CoreText only, the next proof must compare TextKit geometry and
cross-attachment selection; neither headless geometry nor a bitmap proves
interactive text selection/AX. No production framework decision follows from
P0 alone.

== P1 — Hard objects and paged display list

Next fixture candidates:
`tests/flow-app/native-reader-proof/fixtures/math-graphics.typ` and
`tests/flow-app/native-reader-proof/fixtures/paged-delta.typ`.
The first contains a long aligned derivation, fraction/root/script, mathematical
alphanumeric astral symbols, equation number/reference, a footnote, mannot term
split across lines, cancellation/overline, and CeTZ with selectable labels,
rotated/clipped geometry and an unsupported callback. The second spans three
pages, repeated headers, images and links; edits insert/delete a page and change
one font/shape. The repository's
`tools/flow-reader/tests/fixtures/math-identity.html:65–74` illustrates a logical
subscript-versus-superscript probe; it remains a browser fixture, not a native
success criterion.

P1 prerequisites: engine export/decoder owner, local font/resource identity,
output-version/capability/geometry contracts, baseline/cluster sidecar and an
authorized way to obtain real full/delta captures. No guessed packed payloads.
Compare full snapshot B with replay of full A plus ordered deltas through B;
assert identical semantic/resource/scene fingerprints and rendered output under
the same rasterizer. Test `new` during pending deltas, missed delta, bad resource,
stale geometry and compile failure. Full resync must recover without presenting
a mixed document. A reused font handle must not outlive its snapshot resources.

At narrow and wide widths, measure line overflow, clipping, label overlap area,
baseline/number placement and anchor error in points; count missing symbols,
misbound fragments and unsupported cases. Compare paged paint to existing engine
PDF/vector output using the same fonts and output scale, reporting pixel-diff
area and maximum geometry displacement; antialiasing is not semantic failure and
must have a documented comparison tolerance. PM sets tolerances after baselines.
Math copy must match verified whole-formula source exactly and preserve prose
order; stale/unmapped/partial ranges must exercise the documented fallback.

If native decoding fails, try a versioned pre-pack scene export. If fixed objects
paint correctly but cannot reflow, keep the result paged-only and evaluate
width-specific engine layout. If per-term meaning/VoiceOver structure cannot be
exported, stop for an explicit semantic-output extension; visual fidelity alone
does not clear this gate. Do not rewrite the full engine or replace semantics
with OCR/PDF text inference.

== P2 — Actual native selection and accessibility

After P0/P1 and SDK availability review, propose
`tests/flow-app/native-reader-proof/NativeInteractionProof.swift` as a disposable
AppKit test window, explicitly authorized for a later GUI task. It must implement
the candidate native body (no WebView), keyboard and mouse range extension,
formula boundaries, cross-section selection, links and a visible unsupported
state. Inspect the AX tree and text-range/bounds queries, then have an actual
native user/VoiceOver pass over headings, mixed-direction text, tables,
mathematics, figures and annotation relationships. Check reading/copy order,
selected-text speech, zoom/theme, font changes, offscreen materialization and
focus restoration. Record exact macOS/SDK, app/engine revision and human steps.

Inject an accepted update while selecting and while waiting for a source-action
ack: old layout stays selected until release, and an old ack never dismisses the
new selection. Test disposal and compile failure without closing shared services.
AX marker resolution for an obsolete snapshot must fail safely, not point into
new text at the same offset. A synthetic AX query or screenshot is separate from
real keyboard/VoiceOver evidence. Structured math AX failure blocks a claim of
complete native parity; PM must decide further output work or explicitly scope
a temporary capability limitation.

= Quantitative measurement plan

All measurements below are unexecuted. They define data to collect, not promised
performance or product thresholds. NR05 owns the integrated verification matrix;
NR02 supplies representation-specific probes. Use the same immutable input,
compiler/fonts, machine/OS, width/font/zoom and release-build settings for A/B/C.
Separate compiler time from consumer time and engine reuse from new output cost.

- *Scale:* exercise 10, 100 and 1000 page equivalents for paged output, and
  1000/10000/100000 semantic blocks for flow; record actual characters, glyphs,
  formula/table/figure counts, resource bytes and loaded/visible fragments.
  Repeat with sparse versus math-heavy and unique versus repeated fonts/images.
  Record timeout/OOM/cancel as results rather than excluding them from summaries.
- *First usable content:* instrument monotonic milestones at request, compile
  completion, accepted publication, bytes received, decode/model ready, first
  layout, first visible paint and first usable selection/AX. Report compile,
  transfer and native consumer durations separately in ms; a placeholder or
  background decode completion is not first usable text. Candidate tooling is
  signposts/Instruments after SDK/tool availability is checked.
- *Incremental latency:* timestamp edit input, accepted revision, affected
  fragment invalidation, visible paint and geometry/AX adoption. Report p50/p95
  and max for at least 30 fixed edits after a cold run; report cold results
  separately. Measure one-character change, formula change, table row insert,
  figure relabel, page deletion, width/font reflow and held-selection release.
  Include ordered-delta payload sizes and total full-resync work.
- *Memory:* sample consumer and engine/service RSS and peak/physical footprint
  independently; count model, font/image, page/flow fragment and pending-delta
  cache bytes. Measure before open, first screen, end scroll, 100 edits and
  close/disposal. Report both idle retained bytes and peak transient coexistence
  of old/new accepted layouts. Fit bytes per block/page/resource and verify
  virtualization does not grow with every visited page after cache eviction.
- *Responsiveness:* measure input-to-selection-paint latency and main-thread
  blocked intervals during scroll, resize and update; report missed frame counts
  against the display's actual refresh interval. Count wrong hit-tests, invalid
  Unicode endpoints, wrong copy strings, stale publications and lost anchors.
  Correctness invariants require zero violations; latency budgets await PM and
  native measurements.
- *Power:* in a later authorized isolated run, use available Instruments energy,
  CPU/GPU activity and wakeup counters; collect idle, repeated scroll and fixed
  edit workloads for equal five-minute windows with documented power/thermal
  state, display brightness and background load. Repeat at least three times
  and report variation. Use joules only if a valid measured energy counter is
  available; CPU time or an energy-impact score is not joules. Separate
  recompile power from native rendering power and include reconnect idle behavior.

Every result must record task/proof ID, fixture hash, source and compiler SHA,
artifact/schema version, fonts, OS/SDK/hardware, actual command/exit code,
sample count, failed assertions and skipped prerequisites. Never turn a skipped
compiler, GUI or VoiceOver run into a pass. Numerical performance targets,
supported OS and tolerances remain PM/baseline decisions. Results determine
whether A continues, B receives an output-extension task, or C remains only a
comparison/export path.

= PM handoff

Propose P0 first with the four exact candidate files and five minimal contracts
above. Preserve accepted service/source authority; no native protocol or app
source manifest change is necessary for that proof. Follow with P1 engine
output/resource/semantic mapping proof and P2 actual native interaction/AX before
declaring the renderer implementable. A/B share a semantic contract and fixtures,
not an assumed universal renderer runtime. NR03/NR06 should own final service/IPC
and common-contract decisions; NR04 owns packaging and provenance; NR05 owns
cross-feature native verification. This document changes no product behavior or
accepted spec, and does not certify native feasibility, performance or parity.

= Verification of this deliverable

Preinstalled `typst 0.15.1 (unknown commit)` compiled this document to PDF through
stdout with `--root . --format pdf`; exit code 0, no diagnostics. This validates
document syntax only, not compatibility of that executable with Reader compiler
requests. HTML syntax export with `--features html --format html` also exited 0;
it reported the expected experimental-export warning and ignored page rule.
Output was discarded; HTML export is not a production contract or visual review.
No generated Markdown or other repository artifact is part of this task.
