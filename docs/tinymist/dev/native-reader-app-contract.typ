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
extended grapheme endpoints across ordered accepted blocks for local display. Remote source/chat submission remains limited to 1–32 fragments. NFC/NFD, surrogate pairs and ZWJ
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
conversation database or credential owner. The original NA01 transport proposal was historical; current implemented wire
operations and limits are specified below. B09 denotes the earlier browser
contract and P0 the accepted server security review, neither a native endpoint. Retain Host/Origin,
service/revision, source lock/input validation and consent/session/CSRF guards.

== F01–18 implementation and gate map

All rows remain final product gates. “Model” means retained data, not delivered UI.

#table(columns: (0.6fr, 1.1fr, 2.4fr, 2.5fr), inset: 4pt, align: top,
  table.header([ID], [Owner], [Native representation], [Remaining verification / unsupported scope]),
  [F01], [NA05/06], [Home/project/settings/document windows; existing ProjectService.], [Persistence/recovery and isolated shell/app tests.],
  [F02], [NA04/05/06], [Request → service → accepted document → painted frame.], [Cancellation, nonblocking UI, one open; no readiness from command exit.],
  [F03], [NA01/02/06], [Ordered typed tree, heading/style/link/anchors; real importer.], [NA01 fixture contract tested; broader content, paint/outline/AX remain.],
  [F04], [NA03/06], [Integrated immutable full-PDF lazy viewport plus semantic reflow.], [Raw vector deltas, general page fidelity and independent GUI remain. Historical09c restaging is not the current binding; see the external d7/v4 packet below.],
  [F05], [NA03/06], [MathML+text/number, cell/span/header, vector asset/caption/annotation.], [Fixture paint feasible; general math/CeTZ/decoration/reflow fidelity unverified.],
  [F06], [NA02/04/06], [Grapheme selection fragments and ticket-bound verified excerpt.], [Pointer/keyboard/copy/AX and service ack; no source reconstructed from math.],
  [F07], [NA04/06], [Explicit native request to the existing guarded source-highlight owner.], [Server freshness/lock/receipt, uncertain result, no automatic resend.],
  [F08], [NA04/06], [Mark for review / Undo review / Clear review over native range geometry; source untouched.], [Typed32-fragment mark budget; independent GUI/pixel fidelity and browser coexistence remain scoped.],
  [F09], [NA02/04/06], [Contents popup, native anchors, Back and guarded Last Edit.], [Current target/mapping and independent GUI; exact editor delivery requires existing owner attachment.],
  [F10], [NA04/06], [Read existing saved source-history/editor attachment owner.], [Freshness/unsaved buffer defenses and exact editor delivery.],
  [F11], [NA04/06], [Native composer, typed conversation messages/versions/sequence.], [Streaming/cancel/model selection and safe Markdown+math paint.],
  [F12], [NA04/06], [Bounded recovery copy; explicit Send/message UUID.], [Lost ack reread and newer-draft protection; no automatic Send.],
  [F13], [NA04/06], [Native account presentation over ChatAuth/HomeAccount.], [Consent/authority/credential boundary; no live login tested.],
  [F14], [NA04/05/06], [Existing lifecycle/power operations plus generation/selection hold.], [Bounded reconnect/sleep/network, late callback and view lifetime.],
  [F15], [NA02/03/05/06], [Window-local Theme/Text size and Zoom/Fit controls; native AX tree.], [Bounded headless text/object/current-page AX checks; independent GUI/VoiceOver/fidelity pending.],
  [F16], [NA04/06], [Save Offline / saved-document list / Open Saved; explicit Export PDF of the accepted Original PDF.], [Atomic/cancel/read-only limits and pending-draft recovery; independent full app resume remains pending.],
  [F17], [NA04/06], [Existing manager/origin/prefix and external consumers retained.], [Web/mobile/terminal/editor/service lifetime regression.],
  [F18], [NA05/06], [Canonical source/resource packaging with external engine provenance.], [Historical09c delivery is retained. Current frozen d7/v4 delivery is bound separately; later v5 component changes require PM integration and a fresh binding; no live install here.],
)

Current external artifact locator: `test-output/native-app-corrections-v4/`
`REPORT.md`, `final-binding.json` and `inspection-manifest.json` under the DevSSD
native-reader workspace bind source d7cd069f2249a405061bf220cfd7e0184f75c7fe to
its v4 App. Historical09c and review-fix restaging notes are prior evidence, not
current artifact status. The external `native-reader-identity-ui-v5/`
`resume5-handoff.md` describes the v5 unregistered, unpackaged successor component
and a separate frozen-d7 fixture; it does not replace the d7 App or GUI gates.
`resume2-*` is historical failed/intermediate evidence. The later v6 source-only
component is bound separately by external `native-reader-lifetime-v6/REPORT.md`;
neither component is registered/packaged into the frozen d7 App.

== Historical NA01 executed scope and evidence

This section records the original component probe at its own revision. Its
MathJax/resource and P0 pending statements are historical, not the current
portable-runtime or security-review status. P0 review/testing was accepted
separately by PM; final native app review/GUI acceptance is still pending. See
current runtime, inspection and receipt-gate sections below.

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
The original 4f1b88ae proof observed hidden painting 800 pixels rather than 400.
That report remains immutable. PM transferred the one native painter file to the
same NA09 session for v2; the earlier read-only limit was file allocation, not a
user prohibition. The sole NativeSafeSVG owner now emits explicit per-instance
viewport clips and viewBox matrices for the existing native decoder. Original
asset bytes and symbol overflow declarations remain unchanged; internal shared
content and collision-free clip IDs avoid per-instance content duplication.
Generated references, transforms, depth, work and node budgets are revalidated.
Seventeen independent pixel masks verify visible 800/hidden 400, transform/aspect
alignment, multiple instances, nested clips/symbols/use references and opacity.
Eleven dedicated negatives include generated node/depth and viewport-scale limits.
Unresolvable implicit or font-relative symbol viewport sizes remain explicitly
unsupported; unitless/px/pt numeric dimensions resolve from use or symbol.
Compiler SVG base64 data images retain their original bytes through strict MIME,
base64, UTF8, 8MiB and SVG checks in the existing importer asset owner. Native
pixel/decompressed and digest checks remain unchanged. Newly compiled raw source
embeds a hidden SVG; its actual full native plan paints the exact 400-pixel mask.
Compiler root style overflow:visible remains preserved. Entities, unresolved or
external references, cycles, arbitrary overflow/CSS and invalid MIME/hash/budgets
still reject.
Glyph label paint does not create source ranges, text or label-level AX meaning.

The dynamic required capability is `image-layout-v1`. Every image in a supplemented
snapshot carries metadata; legacy images keep their old point natural-size policy.
Old semantic-tree-v1 documents remain valid. Old clients explicitly fail on new
meaning, even for warmed document/asset/action caches. New clients advertise the
supported set and decode dynamic requirements. Public and generic Codable decoders
reject unknown/missing supplement fields or missing capability. Defaulted Swift
memberwise initialization preserves old callers. One rebinding operation preserves
metadata across session and host copies; generic RecoveryStore roundtrips use the
same model without a duplicate store or new operation. The host's prepared object
uses its existing generic image-role fallback when compiler alt is empty; the raw
model still retains empty alt, without inventing a content label or source meaning.

Evidence: `/Volumes/devSSD/Developer/lagrangian-native-20261117/test-output/contract-closure/NA09/v2`.
The original 69-pass/1-error report is preserved. The affected Contract, Objects,
Services and actual raw-fixture host entrypoints run for v2. Unchanged text and
ReadingSession evidence retains its v1 revision and is not counted as a v2 run.
Commands, actual exits/counts/skips, source/asset hashes and offscreen paint remain
separate from unsupported scope. Contract/Objects/Services and affected native
interaction/ReadingSession/recovery behaviors run on the current host with Swift 5,
warnings-as-errors, arm64 macOS13 target. This is not macOS13 runtime certification.
NA10's separate TeX answer path may use existing object interfaces with asynchronous
lifetime guards; the frozen MathML helper and public painter API remain unchanged.
Only the explicitly transferred internal clip preparation changes. Full app,
GUI/VoiceOver, F04 ordered deltas/full page fidelity, TeX and runtime delivery remain
open gates. No live installation, service restart, push, Rust or Cloud build occurs.


== Core review correction contract — NA06 <core-review-ec2>

Retained layout authority is the exact currently accepted snapshot and its
accepted view/context, independently of the newest transport request generation.
`retainedPreparationKey` never grants source authority or new-candidate adoption.
New adoption and source checks retain their latest-generation/pending guards.
Previously verified assets remain snapshot-bound during retained reflow. Selection
holds replacement through resize, font/theme and Find-bar changes. Pending layout
revokes old geometry and paint receipts while retaining logical body, map, AX and
selection; only current-key preparation restores geometry.

Fallible composition and object metric validation happen before changing the
published render key, body, context, map, focus or viewport. Rejected B leaves
painted A intact. Explicit close ends a view's selection lifetime and permits a
fresh same-profile Read. Old close/cancel tickets cannot cancel the new request.
Network/source acknowledgments do not release selection.

`NativeReaderSelection.validateLocal` permits ordinary display selection and hold
across all accepted blocks, bounded by the existing document limit. Exact scalar,
grapheme, range and reading-order checks remain. Plain copy and AX use this local
selection. `validate` and source/chat transport/server boundaries retain the
32-fragment and existing payload limits. Over-limit actions reject explicitly,
invalidating an older actionable ticket rather than silently submitting it.

A lost Send is confirmed only by the same user-message UUID and exact stored
Unicode scalars. Actor and UI share this predicate. Confirmation clears unknown
state and permits a fresh UUID/question. Missing or mismatched history permits
only an explicit identical UUID/question/model retry; history never starts
inference. A newer private draft survives acknowledgment of an older message.

Block images add TextKit presentation line boundaries before and after the
attachment. Added characters carry no canonical/source spans; logical copy, AX
text and endpoints remain unchanged. Inline images retain one-line placement
when space permits. Native host glyph/line-fragment and selection checks are
required; an object-plan flush alone is insufficient evidence.

The host injects NA10 answer math through `configureMath` using a pinned explicit
worker and the same accepted target/snapshot/layout generation, width, font and
theme. Context changes reconfigure or dispose the old view. Missing runtime
remains an explicit unsupported state, never a prepared-formula success.
Headless native paint is not GUI/VoiceOver, shipping-runtime or full F01–18 proof.


The native *Refresh conversation* control explicitly reads authoritative history;
it is available while an uncertain Send blocks Send, and disabled during another
operation. It never infers or retransmits. Missing conversations, cancelled/disposed
views, invalid current authority, superseded operation epochs and older history
versions cannot clear pending state or replace presentation. Only exact UUID/user
content confirmation permits a fresh question; otherwise the original explicit
UUID/question/model retry remains required. Recovery retains the bounded original
pending question/model separately from a newer private composer draft. Optional
fields decode older schema-1 snapshots without changing document/input/revision,
hash, atomic-write, privacy or source authority checks. No credentials or source
excerpts are added. Supplement evidence is under `test-output/core-review-fixes/v2-ui`.

== NA12 original PDF supplement

The original-page capability is `original-pdf-full-v1`, a scoped immutable PDF
full-snapshot/reset contract over the existing accepted HTML owner. See
#link("native-reader-original-pages.typ")[the original-page contract] for exact
publication bindings, native composition, bounds, actions and verification.
Reflow retained layout, fresh source operations, local display versus remote32
selection and pending question/model recovery retain the #link(<core-review-ec2>)[Core review correction contract], recorded at historical full source `ec2c4af91988f0db66d494cea97a551ffd7cf180` (ec2). This historical source identifier is not the current app build.
Only visible-mode actual paint acknowledges Read. PDF text/bounds grant no source
authority; page source actions are unsupported. Raw engine diff-v1 native
consumption, final registry/app/delivery and actual GUI/VoiceOver remain separate
gates. The optional typed PDF recovery supplement reuses the existing atomic store.


== Current wire operations and recovery budgets

Native transport (`NativeReaderTransport.swift`, `NativeReaderActions.swift`)
uses GET `api/native-document`, GET `api/native-assets/<digest-id>`, POST
`api/native-action`, POST `api/native-chat` and the existing account status/model
routes, either at the owned root or its registered `/d/<id>/` prefix. A document
request binds documentID, serviceID (PID plus incarnation), revision, requestID,
viewID, generation, schemaVersion and explicit capabilities. The validated native
document response must carry a lowercase 64-hex `x-native-input-id`; subsequent
asset/action/chat operations bind that accepted context and action/chat payloads
carry `inputID`. Document JSON is the semantic snapshot with exact service-scoped
identity, generation, schema and supported required capabilities. Action/chat
JSON and event envelopes echo exact documentID/serviceID/revision/requestID/
viewID/generation; echoed fields never substitute for server source freshness.

Source selections carry a ticket and ordered fragments with blockID, half-open
rangeUTF16 and exact text, still capped at32 fragments for remote operations.
POST `api/native-action` uses operation excerpt/locate/highlight, receiptID,
selection and optional existing editorAttachment. Its last-change operation reads
the existing saved-source navigation owner. Its receipt operation reads
that same receiptID without invoking a writer; statuses distinguish verified
located/highlighted, unmapped, ambiguous, stale, unsupported, uncertain and
rejected. Only a verified excerpt may return source text.
POST `api/native-chat` uses open with selection, draft with conversationID/version/
draft, send with conversationID/version/messageID/question/model, cancel with
conversationID/version, list (authoritative history), or events. Responses contain bounded typed
conversations; versions, sequence, frozen target and selection remain guarded.
The wire response is an object with a `conversations` array, at most128 records
and unique UUID `conversation_id` values. Every record has nonnegative `version`
and `sequence`, neither regressing from the previously accepted record; `thread`
has at most256 messages and `draft` at most8000 Swift characters. Every message
has a unique UUID `id`, `role` equal to `user` or `assistant`, `text` at most80000
Swift characters, and string `status`. `streaming` means incomplete; other status
strings are represented as complete. `attachment.state == "attached"` is the
attached flag; other values do not grant Send authority. The whole batch is
validated before any record is adopted. Example (UUIDs are fixture identifiers):

```json
{"conversations":[{"conversation_id":"9e5e59b4-0e45-4c64-99a4-579214d41c10",
 "version":2,"sequence":3,"thread":[{"id":"5926b26e-e9de-47b1-adb5-76224e74774b",
 "role":"user","text":"Question","status":"complete"}],"draft":"Next question",
 "status":"idle","attachment":{"state":"attached"}}]}
```

These client string budgets use Swift `String.count` (extended grapheme
clusters), not UTF8 bytes; JSON/SSE/asset byte budgets below are independent.
ChatView separately bounds an adopted transcript to256 messages and512KiB total
UTF8 text. Backend validation remains with its existing owner. These are not new model/tool
round-trip, document-reading, eight-round/24-call/96k inference limits.
UUID plus exact stored user-message content is required to confirm a lost Send;
a missing/mismatched message requires the original explicit UUID/question/model
retry, never automatic retransmission. Existing POST `api/chat/auth` status/models
reads bind documentID/revision/service and have a256KiB response limit. They do
not add login/logout, credentials or inference authority to the host.

Document JSON is bounded to 32MiB; individual native assets to 16MiB. Generic
mutation JSON requests are at most 256KiB and responses 2MiB. `events` is a POST
chat subscription: SSE total is at most 16MiB, each event 2MiB and pending framing
has only 4096 bytes extra. Native observation buffers the latest one state. It
makes at most four observation attempts, reading authoritative history between
attempts, with 1/2/4-second reconnect delays. Contract/identity failures cannot
reconnect to another target. Source receipt lookup never dispatches a highlight;
history confirms lost Send only by exact UUID, user role and stored scalars.

Session transport recovery adds at most three retries, after 1/2/3 seconds or
4/8/12 seconds under constrained power. Preparation/adopter failure does not
request the network automatically; the newest candidate is retained for explicit
preparation retry. These are transport and UI recovery budgets, not new limits
on model tool rounds or document reading. Published provider policy is unchanged.

== Local display versus stored recovery

Native reflow display zoom is 0.25–4; local selection may span all accepted
blocks. The typed recovery store independently accepts at most 32 selection
fragments, offset 0–1 and reflow zoom 0.5–4. Thus a 33+ fragment selection or
0.25 display state is not a supported stored/resumed reflow state. Do not silently
truncate a selection, increase source authority, clamp stored zoom or call that
application autosave/recovery verified.

Recovery retains at most 128 drafts, each at most 8000 characters (including a
separately bounded original pending question), model strings at most 120. Assets
are at most 16MiB each and 64MiB total; the hashed envelope is at most 128MiB.
The directory allows at most eight documents and 256MiB total. Exceeding a limit
rejects save before replacement, preserving the previous file; it does not
truncate or automatically evict. Original PDF bytes/viewport have their own
validated supplement and remain subject to the enclosing store budgets.

== Receipt gates and feature evidence

The seven receipt gates described in
#link("native-reader-delivery.typ")[native delivery] map to these obligations:
#table(columns:(1fr,1.2fr,3fr),inset:4pt,align:top,
 table.header([Receipt gate],[Feature rows],[Required evidence / unsupported boundary]),
 [source],[F01–F18],[Exact fixed source/app/runtime/reader/engine identities, protected-owner bytes.],
 [runtime],[F04,F05,F11,F18],[Portable resource/inventory/signature/relocation proof; current-host execution is not actual OS13.],
 [requiredtests],[F01–F18],[Actual affected fixtures, regressions, exits and zero required skips, with explicit unsupported coverage.],
 [code-review],[F01–F18],[Official matching task/revision/diff review and finding resolution; execution logs alone are not review.],
 [docs],[F01–F18],[Current canonical contracts, owner map, reproduced commands and accurate limitations.],
 [nativeGUI],[F01–F18],[Independent actual native interactions/paint/selection/recovery; headless callbacks and partial Read are insufficient.],
 [AX],[F03–F06,F09,F11,F15],[Current-page/body ranges, selection and link access plus independent AX/VoiceOver coverage; internal APIs alone do not certify speech.],
)
An unsupported feature requires an explicit PM disposition with scoped evidence;
it is not a passed gate, an automatic waiver or a fabricated receipt. The receipt
validator checks binding and integrity, not review quality, PM authority or user
approval. Final official and GUI acceptance remain incomplete.

== Historical role names and current baseline

NA01 is the shared semantic contract; NA02 text/selection, NA03 object/PDF paint,
NA04 guarded service/source/chat/recovery, NA05 shell, NA06 host integration.
B/NA10 is answer TeX math (#link("native-reader-chat-math.typ")[contract]);
C/NA12 is original PDF publication/lazy native pages
(#link("native-reader-original-pages.typ")[contract]); D/NA13 is portable delivery
(#link("native-reader-delivery.typ")[contract]). 882 means the historical
`882e3ea48044eeeae95ad34e4c97f1319797af8c` integrated core. C19 is the accepted
page-component 19-path input recorded as `C19Exact` in the fixed
`test-output/delivery-production/NA13/final-app-v1/final-binding.json`; G1 is the isolated GUI-fixture owner prepared at
`1e32419dd2cb448fb183ce563e39736cf64a1fca`. The staged integrated baseline is
`09c5186bff1850b17f6e85fe2f3115153520bc94`; subsequent review fixes need new
source/app binding and are not implicitly part of that old app. See
#link("native-reader-app-verification.typ")[current inspection entrypoint].


== Native local feature controls — NA06 wiring

Model/data presence alone is not delivered UI. The document window now exposes
Mark for review, Undo review and Clear review through NativeReaderLocalReview.
Its paint callback draws current-key red strikes over actual TextKit range
rectangles. It never changes the attributed logical text, selection/AX offsets,
source files or browser marks. Reflow retains marks on the same accepted
snapshot; a newly adopted snapshot or cancellation clears old paint. A review
mark uses the existing typed32-fragment bound and rejects an oversized mark
without truncating the ordinary display selection. A collection has at most256
marks with unique UUIDs. A257th mark, duplicate ID or wrong identity is rejected
without changing the selection, accepted marks or previous file. Save/load and
LocalReview share collection validation, including validation before adoption.

Contents is a native heading popup populated only from the accepted typed tree.
Selection delegates to TextView's node-to-presentation mapping. Internal links
and annotation references retain their existing anchor owner; Back consumes one
saved native viewport. New adoption invalidates an old return. Last Edit reads
only the existing guarded last-change API and navigates an actually mapped
anchor. Locate Source uses the existing source operation, not invented file or
PDF coordinates. External links use an explicit native activation and the
existing safe URI policy; no automatic URL open occurs.

Theme offers Light, Dark and Automatic; the initial resolved theme remains
Light. Text size choices are12/14/16/18/24/32 points, initially14; reflow zoom
starts at1 and is0.25–4. Automatic inherits the reader window's effective
appearance; the concrete render key contains resolved light/dark colors. It
never changes OS or global app appearance. Preview Display starts a window-local
transaction; changing Theme/Text size or reflow Zoom/Fit also starts a preview.
Apply Display commits it; Cancel Display restores the previous controls, local
window appearance, font/zoom and renderer-owned viewport anchor on the same
accepted snapshot, preserving exact logical/AX selection. A new snapshot revokes
obsolete preview/viewport state. Apply waits for current layout; Cancel can
revoke pending preparation. These controls concern reflow reading appearance,
not recoloring/resynthesizing the Original PDF print glyphs. Reflow Fit resets
zoom to1; Original PDF Fit uses its separate width-fit geometry and0.1–8 scale
owner, retaining its selection-hold/raster-budget guards. Font/theme are not
persisted via a new settings schema; typed reflow recovery independently keeps
its0.5–4 zoom bound. Object/math preparation stays asynchronous with accepted
snapshot assets.

Save Offline captures accepted document/assets, native-reflow renderer-owned
normalized viewport and exact held selection, local review marks and the current typed
composer recovery (including original uncertain question/model separately from
a newer draft). Refresh Saved and Open Saved enumerate/load only an explicitly
composed profile/target namespace below AppEnvironment.support. RecoveryStore
alone decodes/validates the existing envelope, SHA256, identity, assets and
budgets; there is no second JSON validator, database or migration. Each entry
is validated before display and again when opened. Invalid/cancelled saves
preserve the previous atomic file. Selection33+ and display0.25 remain valid
local reflow states but cannot be saved through typed32/zoom0.5 limits. Original
PDF recovery instead stores identity/input fingerprint/digest, page, optional
scale and unscaled display offsets; it does not store PDF display selection.
Install clears PDF selection. A recovered copy does not support offline mode
switching; PDF positions are never promoted to Typst source authority.

The home window/menu offers a local offline library action without entering
service start, manager attachment or live Read. It composes a separate local
reader and does not close the user's live document/service. Opening a saved
copy uses captured validated assets with zero live target/network/assets
operations. Source, chat and account actions remain disabled and authorization
still rejects them. Saved drafts are visible read-only; pending UUID/question/
model are retained without inference or automatic Send. Reattaching a matching
authorized conversation may explicitly restore its draft; authoritative history
and the original retry guards still own lost-Send recovery. Initial saved drafts
are consumed once per matching conversation; current private state uses existing
persistDraft/recoveryDraft callbacks. Reopening the same conversation must retain
N2 and a history-confirmed clearing of pending M, not replay initial M/N. The
preferred model is retained while the current model catalog is still loading.

Storage work is asynchronous and injectable as concrete typed save/list/load
operations. Busy controls and Cancel, window lifetime, operation epoch and
request tickets reject obsolete completions. Cancelling after an already
committed atomic save does not claim rollback. Command completion, accepted
snapshot and layout remain distinct from the matching visible-mode native draw
receipt. Offscreen target/action tests do not establish real GUI acceptance.

F10 retains separate mapping and editor-effect contracts. The existing
native-action locate operation returns a verified display anchor only;
SavedSourceNavigation owns source correspondence and the native envelope omits
file/line/editor data. It does not dispatch an editor jump. The separate explicit
native-editor jump/receipt operation uses the existing saved-source and Neovim
owners; only their confirmed effect establishes that the editor moved.

FlowApp now composes a NativeReaderManagedEditor after its native Connect Editor
chooser selects an existing private four-field descriptor (address, executable,
ownerPID, controlFile) and the user explicitly consents. The local manager's
existing private registration owner supplies that descriptor; a fixture-written
JSON file alone does not establish this production path. SF1 separates optional
editor synchronization from valid native selection adoption: editor-only failure
leaves Source/excerpt/mapping and Ask available, while an actual editor jump is
unavailable and old pending work is revoked. SF2 now creates a caller-known opaque operation and cleanup lease before calling
the local manager. The existing EditorAttachments owner durably reserves its exact
token/target intent before publishing a complete record atomically. Cancellation
persists a tombstone before exact digest/inode-bound retirement, so late issuance
or adoption cannot revive the operation. Same-profile resolver copies and later
ManagedClients share retained leases: a failed command/probe/parse cleanup remains
pending after resolve throws. The next explicit connect/Read/close can perform
one bounded pending attempt; only confirmed absence removes it. No operation scan,
automatic retry loop, quota expansion or editor/service/other-token deletion is
introduced. Only a new consented editor grant is gated by pending cleanup.
The read-only manager scope query binds that gate to a verified registered
reader/document, including equivalent entry spelling and supported aliases;
Swift consumes opaque bindings. Original request arguments remain with each
retained lease for withdrawal after alias deletion/rename/retarget. Withdrawal
validates the private original operation and registration digest/inode without
consulting the current alias; a different document never becomes its target.
Exact CLI formats/boolean confirmation and legacy record compatibility are in
#link("native-reader-editor-actions.typ")[the local operation interoperability contract].
An editor-free body Read does not attempt or confirm that retirement: accepted
body, Source and Ask remain available while the prior editor cleanup is pending.
It receives no editor consent or movement authority.

The ten-second native resolve budget includes pending retry, preparation/ack,
follow-up state verification and cleanup. Preparation gets at most6.5 seconds,
its owned process at most7, and cleanup at most2.5; each is shortened by remaining
deadline and final state verification reserves2.75 seconds of cleanup/grace.
The actual URLSession task is cancelled at that absolute operation deadline and
its completion is awaited, including slow-drip bodies; idle bytes cannot extend
it. Late state success is refused and ordinary network timeouts are unchanged. These are bounded budgets and measured fixture elapsed times, not
OS real-time scheduling guarantees. CommandRunner cancellation terminates/waits
only its own manager process. It does not roll back a previously started shared
service or automatically recover an entire crashed app.

Historical299 source had no pre-response cleanup binding (actual timeout/SIGKILL
left two active registrations); `resume2-*` witnesses remain immutable. Current
v5 source-only evidence is external `native-reader-identity-ui-v5/resume5-handoff.md`.
Current v6 lifetime counterexamples and bounded after results are external
`native-reader-lifetime-v6/REPORT.md`; H5 evidence is immutable.
A surviving app caller retains pending operations; after both app and manager
crash the explicit exact-operation local recovery API is tested, but automatic
app-process restart recovery is not implemented. Private bounded operation
journals/tombstones are retained without a background sweeper. Legacy direct
native-consent calls without an operation remain compatible with response-token
cleanup only; they do not obtain the new crash-gap guarantee. Production FlowApp
always supplies the operation. This component is not registered or packaged in
the frozen d7 App and does not establish final F10 or GUI acceptance.

Actual chooser/consent/focus interaction and overall F10 acceptance remain
unverified. The frozen d7 App retains its NFC/NFD manager matching gap. The later v5
source-only component verifies canonical-equivalent spelling plus actual identity
and scope, including real Unicode manager/HTTP/headless-editor movement. It is
not registered or packaged into d7; its tests do not close the App's F10 gate. The host never fabricates
coordinates or opts into an arbitrary editor. F13 native login/cancel/logout
remains unimplemented NA16 work: the adapter reads status/models and exposes an
explicit configured Homepage action, without native credential operations.
Status or opening a URL does not establish authentication management. Current
source/app binding is reported by the new external delivery handoff, separately
from immutable historical packets; F01–18 official/GUI/AX acceptance is pending.


== Candidate completion and original PDF export

A validated recovery snapshot's marks/drafts/pending UUID/question/model and
reflow zoom/viewport are bound to the same Session candidate. They are applied
once only after its actual PreparedAdoption publication and selection restoration,
including resize/font retries or selection hold/release. The initial await or
matching identity alone is not completion. While held, the native Cancel control
continues to revoke that candidate. Cancel/close cannot attach its metadata to A
or resurrect B via a later layout retry.

== Accepted Original PDF export <native-export-pdf>

Export PDF is a native explicit control for the currently accepted Original PDF.
The production chooser is an NSSavePanel; isolated tests inject only its result
without displaying a panel. Existing accepted publication/input/digest-validated
bytes are staged by RecoveryStore, reopened with PDFKit, then published by atomic
rename after exact snapshot/request/operation checks. They are the original bytes,
not a screenshot or a regenerated PDF. No source/chat/auth authority is granted.
Cancel, stale snapshot, disposal, tampered bytes, symlink/nonregular/wrong-extension
or missing-parent destinations are rejected. Commit rechecks the observed
directory identity and destination metadata fingerprint (device/inode/size/mtime);
a mismatch rejects publication and preserves the prior file in those tested
failure paths. Same-metadata content changes and an external rename after that
check are not covered by a compare-and-swap guarantee. Open directory descriptors bind the destination and
bounded temporary files are removed on failure. Native Print is not newly added.
These source/offscreen checks still require final app binding and independent
actual GUI/export/AX/VoiceOver inspection.


== Current window lifecycle and display corrections

Only a still-live explicit Read ticket receives laptop sleep/wake, connectivity
and constrained-power events from FlowApp through ReadingSessionController into
the native session. Pending settings work completes independently; sleep during
save revokes its pending Read intent. No unread profile is opened by these events.
The native session retains accepted content read-only during interruption and
owns bounded transport retry/backoff; close/cancel/profile replacement reject late
effects. Recovery never implies an automatic chat Send or service restart.
A new snapshot retaining previewed colors adopts the same menu/window baseline
for subsequent previews. Reflow entry resolves Automatic against this window's
current effective appearance after Original PDF; PDF print colors remain unchanged.
Actual laptop/GUI acceptance is independent of injected offscreen events.

Profile names are display labels, not unique IDs. The native picker retains every
validated profile in settings order, including identical names, so selection
persists the exact chosen profile ID. Repeated cancellation of an already closed
native Read ticket is idempotent; it cannot advance accepted-view authority or
revive that ticket through a later environment signal.


== v7 native toolbar and mode feedback (source component)

The host keeps native mode buttons, Contents/Back, page navigation and PDF search
in a fixed leading-aligned primary area. Copy and explicit selection release stay
near the current/requested mode and next-action text. Source/review, display,
offline and account controls remain their existing AppKit controls and selectors
inside the initially collapsed “읽기 도구” area. It scrolls independently and
has a native Command–Option–T equivalent; collapsing a focused child returns
focus to the disclosure button. This does not promise popup focus behavior in a
real GUI: the prior Dogfood popup/foreground concern remains unverified here.

Major commands and mode/state presentation use Korean. Document content, source
coordinates, wire enums, errors and receipts are not translated or reinterpreted.
Raw diagnostics remain in the auxiliary area, separate from human mode/status
text. Existing enabled conditions, consent and persistence owners remain intact.
The “새로고침” (refresh) button invokes only the explicit existing refresh path; a
recovered offline copy disables it and the callback independently rejects live
refresh while the existing session reports a recovery copy. A read-only retained
view after a live failure may explicitly retry. No new consent, automatic Read,
service start/restart or source/account authority is added.

Requested mode is presentation intent, not accepted mode. The visible mode only
changes on the existing atomic adoption. Body selection and immutable-PDF display
selection still block mode changes through NativeReaderSession.hasSelection.
Search results alone do not hold selection; the host search command explicitly
selects a hit through the original PDF owner, which does hold it. A search-hit
explanation is tied to the actual display selection ticket, not a nonempty query.
Release does not automatically approve a blocked mode; the user presses the mode
again. The bounded offscreen case keeps its query while explicitly switching
after release; this is not proof of the old GUI observation's cause or resolution.
A failed request/preparation takes priority over the pending intent and identifies
the previous visible result plus an explicit refresh action, rather than saying
that the requested mode is still preparing indefinitely.

No full-window minimum-width contract was found: the prior NSWindow.minSize
was0×32 and contentMinSize0×0; neither is raised. The measured window matrix is
980×752 and640×752, reader text14/32pt, plus injected control-font13/32pt stress
in Light/Dark. It is distinct from NA01's320/640/960pt CoreText-only matrix and
is not a claim that every smaller window works. Popup titles retain the existing
bounded menu text and full selected title as help when their native cell narrows.
External DevSSD `test-output/native-reader-ui-v7/REPORT.md` and final input binding
record actual frame/content measurements, failed attempts and final regressions.
These are offscreen AppKit checks, not new App/GUI/AX-input/VO/actual macOS13
acceptance. Frozen d7/v4 captures remain only their own partial unverified evidence;
PM integration/sourcepin/delivery and full125case/NA16 remain separate.


= v8 source-only editor scope correction

The consented native manager call includes the previously queried expected scope.
A query-A/alias-retarget-B race is rejected before reservation or registration,
not merely by comparing the returned plan. Stable original withdrawal expressions
retain symlink-sensitive dot components; manager-owned actual scope still binds
equivalent document spellings. Command/parse/shape query failure preserves pending
cleanup and rejects new editor consent; plain body/Source/Ask remain independent.
This component does not replace the frozen d7 App, update sourcepin or establish
new GUI/VO/OS13/NA16/full125/PM-receipt acceptance.
