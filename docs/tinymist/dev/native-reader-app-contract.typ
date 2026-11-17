#set page(paper: "a4", margin: 16mm)
#set text(size: 9pt)

= Native Reader app contract — NA01

Schema 1 belongs to NA01. The commit containing this file is the shared contract
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
  [F04], [NA03/06], [Separate paged vector/glyph consumer linked by revision.], [Unsupported here: deltas, page fidelity, selection; PDF-only fails final gate.],
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
