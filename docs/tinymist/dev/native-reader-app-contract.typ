#set page(paper: "a4", margin: 16mm)
#set text(size: 9pt)

= Native Reader app contract — NA01 / NA09

NA01 established schema 1; NA09 owns the bounded image supplement correction. The commit containing this file is the shared contract
input for NA02 text, NA03 objects, NA04 services and NA05 shell. Record that exact
SHA before implementing; return shared-model changes to NA01. The executable API
and compile commands are fixed in `openspec/changes/implement-native-reader-app/design.md`.
This is an implementation handoff, not final application acceptance.

== Data and authority

`NativeReaderDocument.decode` validates ordered, unique semantic nodes and explicit
capabilities. `import_accepted_document` translates an already accepted SectionBundle
in manifest order, returning JSON plus digest-addressed asset bytes. Repeated content
has distinct node IDs; IDs are snapshot-local. Section/passage identity stays with
`sections.py`. Semantic trees preserve headings, strong/emphasis, links, MathML and
normalized math text, equation numbers, table cell/header/spans, figure asset/caption,
and annotation/mark anchors. Unsupported elements, attributes, classes, primitives
or required capabilities reject the whole candidate with a bounded code.
Unknown meaning never becomes a placeholder or a successful paint capability.

Canonical text is exact accepted HTML descendant Unicode scalars; display currently
retains those same scalars. It is neither raw Typst nor a reconstructed source excerpt.
UTF8 means bytes, codepoints mean Unicode scalars, UTF16 means code units; maps are
node-local. Half-open node ranges are block-local UTF16. Selection fragments use
extended grapheme endpoints in 1–32 ordered blocks. NFC/NFD, surrogate pairs and ZWJ
sequences remain distinct as authored. Source offsets/freshness remain private to
existing service owners; current import emits explicit visible/unmapped state.

Geometry is external to common data: NA02 owns AppKit top-left point text geometry,
selection and AX; NA03 owns object geometry/paint. Children retain reading order for
both. Paged geometry needs a separately verified accepted revision. Plain math text
cannot replace MathML structure; PDF paint alone cannot replace selection or AX.

`NativeReaderDocumentStore` requires matching view, document/service/revision and
local generation, validates before atomic adoption, holds replacement during selection,
and rejects cancelled/disposed callbacks. Ticket-specific release protects newer
selections. Transport cancellation is not mutation rollback. Highlight/Send after
dispatch may have unknown effect; reconcile existing receipts/message UUIDs, never
automatically resend. Local hashes and echoed correlation fields cannot prove server
freshness, authority or durable effects.

NA04 reuses accepted_snapshot, source_mapping, highlight_receipts, ParagraphChat,
ChatAuth/HomeAccount, ReaderManager and source-history. No UI source writer,
conversation database or credential owner. A native-document HTTP route is an explicit
NA04 candidate only; B09/P0 are not existing endpoint responses. Retain Host/Origin,
service/revision, source lock/input validation and consent/session/CSRF guards.

== F01–18 implementation and gate map

All rows remain final product gates. “Model” means retained data, not delivered UI.

#table(columns: (0.6fr, 1.1fr, 2.4fr, 2.5fr), inset: 4pt, align: top,
  table.header([ID], [Owner], [Native representation], [Remaining verification / unsupported scope]),
  [F01], [NA05/06], [Home/project/settings/document windows; existing ProjectService.], [Persistence/recovery and isolated shell/app tests.],
  [F02], [NA04/05/06], [Request → service → accepted document → painted frame.], [Cancellation, nonblocking UI, one open; no readiness from command exit.],
  [F03], [NA01/02/06], [Ordered typed tree, heading/style/link/anchors; real importer.], [NA01 fixture contract tested; broader content, paint/outline/AX remain.],
  [F04], [NA03/06], [Existing isolated PDFKit original-page component plus semantic reflow.], [Ordered vector deltas/full page fidelity and integrated source/GUI gates remain; NA09 preserves PDF/input-refresh tests.],
  [F05], [NA03/06], [MathML+text/number, cell/span/header, vector asset/caption/annotation.], [Fixture paint feasible; general math/CeTZ/decoration/reflow fidelity unverified.],
  [F06], [NA02/04/06], [Grapheme selection fragments and ticket-bound verified excerpt.], [Pointer/keyboard/copy/AX and service ack; no source reconstructed from math.],
  [F07], [NA04/06], [Optimistic native mark over existing guarded highlight.], [Server freshness/lock/receipt, uncertain result, no automatic resend.],
  [F08], [NA04/06], [Bounded local review paint/store; source untouched.], [Undo/clear/failure and explicit browser-mark coexistence policy.],
  [F09], [NA02/04/06], [Outline, semantic anchors, one return, independent edit navigation.], [Current-target validation and resize/reflow restoration.],
  [F10], [NA04/06], [Read existing saved source-history/editor attachment owner.], [Freshness/unsaved buffer defenses and exact editor delivery.],
  [F11], [NA04/06], [Native composer, typed conversation messages/versions/sequence.], [Streaming/cancel/model selection and safe Markdown+math paint.],
  [F12], [NA04/06], [Bounded recovery copy; explicit Send/message UUID.], [Lost ack reread and newer-draft protection; no automatic Send.],
  [F13], [NA04/06], [Native account presentation over ChatAuth/HomeAccount.], [Consent/authority/credential boundary; no live login tested.],
  [F14], [NA04/05/06], [Existing lifecycle/power operations plus generation/selection hold.], [Bounded reconnect/sleep/network, late callback and view lifetime.],
  [F15], [NA02/03/05/06], [Native theme/font/zoom/focus and semantic AX tree.], [9 headless text conditions only; GUI/VoiceOver/object semantics unverified.],
  [F16], [NA04/06], [Complete snapshot+assets, transactional native offline copy/export.], [Atomic cancel/failure/read-only; offline never authorizes source writes.],
  [F17], [NA04/06], [Existing manager/origin/prefix and external consumers retained.], [Web/mobile/terminal/editor/service lifetime regression.],
  [F18], [NA05/06], [Canonical source/resource packaging with external engine provenance.], [Source list/helper delivery/isolated installed layout; no live install here.],
)

== Executed scope and evidence

Evidence root: `/Volumes/devSSD/Developer/lagrangian-native-20261117/test-output/contract`.
The unittest entrypoint is `tests/flow-app/native-reader-app/test_contract.py`.
It runs real compile_project/split_document/importer and production Swift 5 with
warnings-as-errors and arm64 macOS13 deployment target. The author-written oracle
is separate from implementation; formal independent oracle review is pending.
The 320/640/960pt × 14/18/24pt matrix checks headless CoreText coverage/units and
selection invariants, not GUI interaction. Current host execution is not a macOS13
runtime test. Source mapping remains unavailable in this fixture run.

`probe_objects.mjs` computes fixture equation/rectangle SVG and PDF using the existing
compiler; `ObjectProbe.swift` consumes them through NSImage/cgImage and CGPDFDocument
into real CoreGraphics bitmaps. Three widths × two objects × two formats paint
nonempty ink; the rectangle also checks independently specified blue area. An additional
accepted-HTML imported SVG passes native paint after explicit compiler point viewport
metadata replaces AppKit’s interpretation of HTML CSS em sizing. General
formula visual fidelity, inline breaking, object hit testing/selection/AX and GUI
remain unsupported/unverified. The prior 32pt circle decode is separate PM evidence,
not used as an oracle for these actual compiler artifacts.

MathJax is blocked, not adopted: existing 4.1.3 vendor is CHTML and lacks node-main,
SVG/liteDOM and the complete local source/font module set. Node helper exit 2 records
that partial gate even when compiler/native paint succeed. The official
#link("https://docs.mathjax.org/en/v4.0/server/direct.html")[direct Node] and
#link("https://docs.mathjax.org/en/v4.0/output/linebreaks.html")[linebreaking] documents
do not make browser inline breaking native. Any follow-up needs authorized complete
4.1.3 source/newcm modules, transitive offline resources/digests and Apache-2.0 notices,
plus NA03/05/06 helper/runtime packaging and separate dependency write scope.
No dependencies, lockfiles, P0 source, source list, HTTP server or installed services
are modified. P0 independent review/testing and final native app/fidelity/GUI gates
remain with PM and later owners.


== NA09 image/layout supplement

The historical executed scope above records NA01's original probe. Current NA09
recompiles the raw rich fixture and exercises the production importer, Swift model,
HTTP transport, session candidate, host fixture generation copy, generic recovery
and native painter. Controlled rich assets remain independent evidence. No raw HTML
attributes are deleted to pass import. External SVG bytes retain their digest;
inline SVG retains the accepted normalized serialization.

Schema 1 adds `imageLayout` to image nodes. Required fields are `naturalUnit`
(px/pt), `placement` (inline/block) and `fit` (fill). Optional width/height are
value/unit pairs (px/pt/em); loading is lazy/eager and decoding is async/sync/auto.
Numbers must be finite, positive, at most 4096; native resolved sides are at most
4096pt. CSS px is 72/96 logical points, pt is one point, and em follows current
native font size. Natural raster pixels remain separate from logical dimensions.
Two specified dimensions fill that box; a single dimension uses intrinsic aspect.
CSS overrides only its matching HTML attribute. Raw width-only style 32pt plus
HTML height=12 is 32×9pt, preserving both original attributes. Compiler/source
aspect discrepancies are not inferred away. Explicit sizes are not silently
shrunk to fit a line. Inline objects remain indivisible; block images flush the
line before and after paint. Existing page/pixel/byte budgets remain enforced.

Only numeric HTML width/height and CSS width/height in px/pt/em plus
`display: inline`/`display: block` are supported. Unknown CSS, percentages, calc,
object-fit cover/contain and external resources reject. Loading/decoding hints
survive as typed metadata; native preparation fully decodes before adoption.
Compiler SVG root em sizing uses this same model. Symbol overflow attributes
allow visible/hidden only on symbol; the existing safe SVG painter owns clipping.
The frozen painter currently ignores hidden clipping: the independent oracle
observes 800 blue pixels instead of 400. Import therefore explicitly refuses hidden
with `unsupported-svg-symbol-hidden-clip` until that read-only owner is corrected.
The required native hidden-clip test remains failed, not skipped or diluted.
Visible raw compiler import and paint pass. Compiler root style overflow:visible is preserved. Entities, unresolved/external
references, cycles, arbitrary overflow/CSS and invalid MIME/hash/budgets reject.
Glyph label paint does not create source ranges, text or label-level AX meaning.

The dynamic required capability is `image-layout-v1`. Every image in a supplemented
snapshot carries metadata; legacy images keep their old point natural-size policy.
Old semantic-tree-v1 documents remain valid. Old clients explicitly fail on new
meaning, even for warmed document/asset/action caches. New clients advertise the
supported set and decode dynamic requirements. Public and generic Codable decoders
reject unknown/missing supplement fields or missing capability. Defaulted Swift
memberwise initialization preserves old callers. One rebinding operation preserves
metadata across session and host copies; generic RecoveryStore roundtrips use the
same model without a duplicate store or new operation.

Evidence: `/Volumes/devSSD/Developer/lagrangian-native-20261117/test-output/contract-closure/NA09`.
Commands, actual exits/counts/skips, source/asset hashes and offscreen paint remain
separate from unsupported scope. Contract/Objects/Services and affected native
interaction/ReadingSession/recovery behaviors run on the current host with Swift 5,
warnings-as-errors, arm64 macOS13 target. This is not macOS13 runtime certification.
NA10's separate TeX answer path may use existing object interfaces with asynchronous
lifetime guards; NA09 does not edit the frozen MathML helper/painter. Full app,
GUI/VoiceOver, F04 ordered deltas/full page fidelity, TeX and runtime delivery remain
open gates. No live installation, service restart, push, Rust or Cloud build occurs.
