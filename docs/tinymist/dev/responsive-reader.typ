= Responsive reader development

The independent reader modules are in `tools/flow-reader`. They generate HTML
from the saved Typst entrypoint, using a temporary package overlay. The installed
packages, paged service, and source documents are not rewritten by a reader build.

== Required reading behavior

All essential text, equations, figures, and annotations must be readable in the
continuous body at the chosen font size. Do not require zoom, horizontal panning,
slides, a next-section click, or a separate enlarged-equation view. Compose long
mathematics and figure layouts to the available width, preserving their meaning
and readable labels. Optional navigation and saved-highlight controls are allowed.

The current development prototype does not yet meet this contract: local equation
scrolling, unresolved drawing widths, label sizes, and overlapping relationships
still need work. Notes and relationships are now shown inline automatically.
A document-wide overflow check is insufficient; audit each component and every
required reading action before promotion.

== Adaptive CeTZ canvas

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
keeps an entire canvas together as an SVG; figure font and width policies still
need explicit validation before promotion.

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
project's unrelated media, caches, or cloud placeholders. A newly discovered
dependency graph is compiled again against a measured input snapshot before
publication. The served revision includes that snapshot, so changes to a dynamic
drawing invalidate the revision even when its placeholder HTML is unchanged.

The reader supports native text selection, a heading outline, font size changes,
local equation scrolling, visible inline annotations, reading anchors, and saved
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

The initial implementation recompiles the full source for an uncached graphical
request. On the PDE project this can take several seconds; nearby scenes start
loading automatically and failures retry without a reveal action. Cached results
are reused. Reusing a persistent compiler is a subsequent performance task.

Width diagnostics compare the full drawing with the actual body width. A
conservative collision diagnostic compares label rectangles with body text and
samples stroked connector paths against unmarked text. It is not a complete
collision solver: overlay-to-overlay intersections and opaque image content are
not covered. Explicit small label sizes still need a policy. Actual Jacobi formula
geometry at 320px remains wider than the body and intersects other text. Inline
delivery therefore does not establish responsive readability or permit promotion.

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

The isolated MathJax probe also distinguishes authored derivation alignment from
matrix/cases/vector structure. Its optional row composition moves original nodes
into separately breakable mathematical rows, preserving anchors and nested tables.
This candidate is not connected to the Reader. Ordinary MathML rendering still
has wide equations; cancellation/overline SVG islands, logical selection identity,
multi-fragment graphical anchors, and collision-free composition remain open.

The full PDE compile retains 102 decoration IDs; a separate compiler audit renders
two fragments for each one. The dedicated fixture verifies six decoration kinds,
including a custom two-layer callback and the note's marked-term preview. The
full original-package and overlay PDF comparison is byte-identical. Evidence is
under `dist/reader-semantic-checks`; see the research guide for the paired equation
corpus measurements and their limits.

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
Evidence is under `dist/reader-identity-checks`. This does not establish mathematical
visual fidelity, accessibility, or completed Reader integration: the installed
Reader still uses native MathML, and multi-fragment CeTZ relationship anchors
remain necessary before enabling the candidate renderer.

== Managed installation

The Reader lifecycle module belongs to this repository and reads the installed
Flow app's `--profiles` output on each start. Its configuration stores a parent
profile ID and Reader runtime/port options; it does not copy the project root,
fonts, entrypoint, or package settings. It installs its own LaunchAgent and does
not replace or restart the existing paged app or engine.

Install only from a clean commit:

```sh
python3 tools/flow-reader/install.py \
  --profile existing-flow-profile \
  --port 23627 \
  --public-url https://your-host.ts.net:23627/ \
  --start
```

During validation, add `--development` to retain the development notice and keep
the Reader out of the default mobile entry. The installer archives the committed
Reader sources into an immutable release under the Flow application support
directory. A stable launcher in `reader/bin/flow-reader` exposes `--profiles`,
`--launch-plan ID`, `--status ID`, and `--control start|stop|restart ID`. Reader IDs
append `-reader` to the parent ID. Port validation includes every saved Flow
profile, including projects that are currently stopped.

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
