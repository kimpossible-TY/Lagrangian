# Design

## Context

NA01 starts from `f8058a29735dea6b40a5c1362a14ae12aad3396a` (authorized fast-forward from `3e5a05c66bb0fdcffb19a90fd70e1bc2bd2cd9e2`). P0's four files are inherited inputs, untouched; their independent review/testing remains pending. See proposal.md for motivation and `docs/tinymist/dev/native-reader-app-contract.typ` for the F01–18 handoff. No native HTTP endpoint currently exists; NR03 B09 and P0 are not service implementations.

## Goals / Non-Goals

**Goals:** one executable semantic schema and narrow async operations, real accepted compiler translation, immutable shared input for NA02/03/04/05, bounded object feasibility evidence.

**Non-Goals:** full application, general formula/paged fidelity, GUI/AX acceptance, new runtime dependencies, transport implementation, source/auth/history ownership, P0 acceptance or macOS13 runtime certification.

## Decisions

### Frozen shared API (NA01 is the sole change owner)

The commit containing this change is the common contract SHA; consumers record `git rev-parse HEAD` after accepting it. Later shared changes return to NA01. No consumer copies or edits the shared sources.

- `apps/macos/NativeReaderDocument.swift`: `NativeReaderDocument.decode(_:capabilities:) throws -> NativeReaderDocument`, `validate(capabilities:) throws`, `NativeTextOffsets.init(_:)`, `NativeReaderNode.orderedNodes`, `graphemeBoundariesUTF16`.
- Schema 1 JSON: `{schemaVersion, identity:{documentID,serviceID,revision,scope:service|fixture}, generation, requiredCapabilities:["semantic-tree-v1"], blocks:[NativeReaderNode], assets:[{id,sha256,mime,byteCount}], diagnostics:[{code,nodeID}]}`. All arrays retain reading order. Asset IDs are content digests plus extension, never paths.
- Node: `{id,sectionID,kind,canonicalText,displayText,rangeUTF16:[start,end],offsets:{scalars,cpToUTF8,cpToUTF16},children,anchors,annotationTargets,visible,mapping}` plus typed optional `passageKey,direction,language,headingLevel,math:{mathML,normalizedText,display},cell:{rowSpan,columnSpan,header,scope},link,assetID,alt`. `kind` is the Swift closed enum; unknown values fail. IDs are unique within a snapshot, not cross-revision identities. `passageKey` reuses `sections.py` identity for existing server resolution. No invented source ranges.
- `tools/flow-reader/flow_reader/document/native_document.py`: `import_accepted_document(bundle: SectionBundle, *, document_id: str, service_id: str, generation: int, identity_scope: str="service", required_capabilities=("semantic-tree-v1",)) -> ImportedNativeDocument`. Return `.document` is JSON-ready and `.assets` maps digest IDs to bytes. `NativeImportError` contains a bounded code. The caller supplies an **already accepted** bundle under existing publication discipline; this function cannot establish acceptance/freshness. It orders sections by manifest, not dictionary insertion order. Unknown semantics/attributes fail atomically. SVG subset is explicit; further primitives return to this owner.
- `apps/macos/NativeReaderOperations.swift`: `NativeReaderRequestContext(requestID:UUID,viewID:UUID,generation:Int,target:NativeDocumentIdentity)`; `NativeReaderSelection(ticket:UUID,fragments:[Fragment])`, each fragment `{blockID,rangeUTF16:Range<Int>,exact:String}`, local display selection may cover all accepted top-level blocks; `validateLocal(in:) throws` retains exact scalar/grapheme/order guards. Remote source/chat submission remains 1–32 fragments via `validate(in:) throws`. Convenience single-fragment initializer also exists. Fragments preserve their exact text; joining or Typst copy is an explicit consumer operation, not an implicit source reconstruction.
- `NativeReaderDocumentProviding.document(for:) async throws -> NativeReaderDocument`; `NativeReaderSourceOperations.perform(_:) async throws -> NativeReaderSourceResult` for `.excerpt/.locate/.highlight`. Request binds context, selection and receipt UUID. Result echoes local context/ticket and bounded status (`verified/unmapped/ambiguous/stale/unsupported/uncertain/rejected`), optional verified excerpt or opaque destination anchor. Adapter validates actual server response before wrapping; echo is not a server freshness proof.
- `NativeReaderChatOperations.perform(_:context:) async throws -> NativeReaderChatState` and `observe(conversation:context:) -> AsyncThrowingStream<NativeReaderChatState,Error>`. Commands: open(selection), draft(UUID,version,text), explicit send(UUID,version,messageUUID,question,model), cancel(UUID). State retains context/conversation/version/sequence/ordered typed messages. NA04 rejects stale context or regressing conversation version/sequence, bounds stream buffers and disposes only its own subscription. List/account/session presentation stays in NA04 over existing owners; these protocols grant no credential authority.
- `@MainActor NativeReaderDocumentStore(viewID:)`: `beginRequest() throws -> Int`, `adopt(_:for:) throws`, `holdSelection(_:) throws`, `releaseSelection(ticket:)`, `cancel()`, `dispose()`. Adopt requires matching view/target/generation and validated document, and rejects while selection is held. Rejected candidates leave accepted content intact. Caller retains only the latest candidate if it chooses to retry after release. Cancel increments local generation before cancelling transport; dispose prevents all adoption. It does not stop shared services.

### Units, geometry and operation lifetime

Canonical text is the exact accepted HTML descendant scalar sequence, not raw Typst. Display text currently equals canonical scalars, including math text; there are no object placeholders. MathML retains mathematical hierarchy while the plain string alone does not describe a fraction. Whitespace normalization is only the explicitly named `math.normalizedText`. NFC/NFD scalars are preserved. UTF8 maps count bytes, codepoints mean Unicode scalars, UTF16 maps count code units. Node ranges are half-open **block-local** UTF16; per-node offset maps are local to that node's string. Child ranges partition the parent's range in order. User endpoints are extended grapheme boundaries, computed by Swift; surrogate/combining/ZWJ splits are invalid. Source offsets remain in the existing private mapping owner, never conflated with display offsets.

Semantic model contains no UI geometry. NA02 owns top-left AppKit point geometry and text/AX; NA03 owns object metrics, native paint and hit-testing under explicit width/font inputs. Trees preserve inline order, table groups/rows/cells, numbering, labels and annotation relationships so paint/selection/AX can use the same IDs. `visible` and `mapping` are explicit; unsupported visibility semantics are rejected, never guessed. Current importer emits visible/unmapped nodes only. Paged coordinates are separate and require an accepted revision match.

Contract errors: invalidDocument, unsupportedSchema, unsupportedRequiredCapability, wrongTarget, staleGeneration, selectionHeld, disposed, invalidSelection. Adapter failures: rejected(bounded code), unavailable, unsupported, cancelledBeforeDispatch, unknownEffect. A timeout/cancel after dispatch of highlight/Send remains unknownEffect; query existing receipt/message owner before any explicit retry. Stale selection ack must not release a newer ticket. Request cancellation cannot imply rollback or cancel shared OAuth. No automatic Send.

### Existing owners and future transport candidate

NA04 may implement an additive `GET /d/<registered-id>/api/native-document` under existing Host/Origin and exact service/document/revision checks, using this importer and existing revision-bound assets. This is a **candidate for NA04 implementation and negative testing**, not an existing endpoint or shipped transport. Bind service incarnation to the observed manager instance (not PID alone); generation is local correlation. Limit JSON to 32 MiB, individual sections to 16 MiB, tree depth 128/nodes 100000; enforce transport limits before decoding. Current importer handles complete snapshots, not streaming deltas. Request/stream timeouts, asset budgets, chat/action payload limits and reconnect backpressure remain explicit NA04 implementation gates, preserving stricter existing owner limits.

Reuse `accepted_snapshot`, `source_mapping`, `highlight_receipts`, ParagraphChat, ChatAuth/HomeAccount, ReaderManager and Rust `source-history`. Server recomputes accepted inputs/source freshness and retains locks; client hashes only bind evidence/assets. Account authorization follows existing management/session/CSRF/consent boundaries, never copied privileged headers. No source writer, credential store or conversation database in the UI. Existing web/mobile/terminal/editor URLs and owners remain compatible.

### Reproducible validation and object helper boundary

From repository root (preinstalled tools, no installation):

```sh
export TMPDIR=/Volumes/devSSD/Developer/lagrangian-native-20261117/tmp/contract
export CLANG_MODULE_CACHE_PATH=/Volumes/devSSD/Developer/lagrangian-native-20261117/cache/contract/clang
export SWIFT_MODULECACHE_PATH=/Volumes/devSSD/Developer/lagrangian-native-20261117/cache/contract/swift
# NA01_OUTPUT must name a fresh directory below test-output/contract.
NA01_OUTPUT=/Volumes/devSSD/Developer/lagrangian-native-20261117/test-output/contract/recheck python3 -B -m unittest discover -s tests/flow-app/native-reader-app -p test_contract.py -v
```

The test copies existing package cache to DevSSD and runs `compile_project` through a deny-network/read-only-input wrapper, checks content gate, calls `split_document(max_blocks=2)`, imports, retains HTML/sections/assets/report/commands/hashes, compiles production Swift plus `ContractTests.swift` with `-swift-version 5 -warnings-as-errors -target arm64-apple-macosx13.0 -module-cache-path "$SWIFT_MODULECACHE_PATH"`, then executes its 320/640/960pt × 14/18/24pt CoreText matrix and adoption negatives. `fixtures/contract.expect.json` is author-written independently of the importer; formal external oracle review is pending. `map_sources=False` deliberately leaves source mapping unverified.

```sh
node tests/flow-app/native-reader-app/probe_objects.mjs --output /Volumes/devSSD/Developer/lagrangian-native-20261117/test-output/contract/objects-recheck --compiler /absolute/path/to/recheck/offline-typst --native /absolute/path/to/recheck/native.json
swiftc -parse-as-library -swift-version 5 -warnings-as-errors -target arm64-apple-macosx13.0 -module-cache-path "$SWIFT_MODULECACHE_PATH" tests/flow-app/native-reader-app/ObjectProbe.swift -o /Volumes/devSSD/Developer/lagrangian-native-20261117/test-output/contract/ObjectProbe
/Volumes/devSSD/Developer/lagrangian-native-20261117/test-output/contract/ObjectProbe /Volumes/devSSD/Developer/lagrangian-native-20261117/test-output/contract/objects-recheck/probe.json
```

Node extracts actual fixture formula/shape expressions and calls the prebuilt compiler with three explicit widths; native Swift consumes each SVG/PDF via NSImage/cgImage or CGPDFDocument into a bitmap. It also paints the accepted-HTML importer’s figure asset. Compiler point viewport metadata must be passed to AppKit explicitly: CSS em sizing alone produced only a few pixels in the first imported-asset probe; the explicit 48×24pt viewport yields the expected 1152 blue pixels. It tests nonempty ink and independently specified blue rectangle color/area; it does **not** measure formula visual fidelity. `probe.json` records primitives/modules/fonts/commands/exits; `native-paint.json` records actual paint. Successful calculation does not imply successful paint. Node exit 2 for blocked MathJax is intentional and must be preserved separately from compiler and native exits. Test-produced `offline-typst` wrapper needs the test's package-cache environment for package-using documents; isolated probe objects use no package imports.

## Risks / Trade-offs

- Accepted HTML does not expose every authored style/vector semantic → explicit import rejection; request a bounded extension from NA01 rather than silently dropping meaning. Full F03/F05 remains gated on broader fixtures.
- General math, arbitrary SVG, paged fidelity, inline breaking, AX and GUI are unverified → NA03/NA07 and later formal app gates. PDF paint alone is insufficient.
- Existing MathJax 4.1.3 vendor is CHTML; local source/input/SVG/liteAdaptor/font modules and advertised node-main are missing → blocked, not adopted. Follow-up authorization would need `@mathjax/src@4.1.3` and `@mathjax/mathjax-newcm-font@4.1.3` complete transitive module/font resources, package manifests and Apache-2.0 notices, verified offline digests, a Node runtime/helper resource delivery plan owned by NA03/NA05/06, and a separately approved vendor/assets/packager/lock write scope. Candidate module paths are recorded in `probe_objects.mjs`; no dependency changes here. Official direct/linebreaking docs: https://docs.mathjax.org/en/v4.0/server/direct.html and https://docs.mathjax.org/en/v4.0/output/linebreaks.html . Browser inline line breaking is not a native facility.
- Initial exploratory compiler invocation auto-fetched tiptoe into the new isolated DevSSD cache → retained in `exploration/compile.log`; all acceptance runs instead use existing cache copies and deny network. No repository dependency/vendor/lock edits.

## Migration Plan

NA02/03/04/05 start from this commit and implement only their own files. NA05/06 adds sources/resources to canonical packaging lists; NA01 intentionally does not edit those lists. NA06 integrates and builds with the prebuilt engine, NA07 independently tests, PM allocates GUI/review/audit gates. No app install/restart, CI dispatch or push occurs here. Rollback is dropping this unintegrated commit; no live state was migrated.

## NA09 shared image supplement (2026-11-17)

The frozen NA01 API remains source-compatible. NA09 temporarily owns the shared
model/importer and metadata propagation under the PM's original 21-file correction
scope, plus the explicitly transferred NativeReaderObjectRenderer.swift clip owner
for the bounded v2 correction. The original plan JSON/ID remains immutable.
The existing host/shared store/PreparedAdoption and PDFKit original-page component
remain their respective owners; this change does not replace them. The initial
probe/runtime/transport status above describes historical NA01 evidence, not the
current integrated component state.

Schema 1 adds optional node `imageLayout`. It contains required `naturalUnit`
(`px` or `pt`), `placement` (`inline` or `block`), `fit` (`fill`), optional
`width`/`height` (`{value,unit}` with `px`, `pt`, or `em`), optional `loading`
(`lazy`, `eager`) and `decoding` (`async`, `sync`, `auto`). Values must be finite,
positive and at most 4096; resolved native dimensions are also bounded by 4096pt.
CSS px means 72/96 logical AppKit points, pt means one logical point, and em uses
the current native text font size. Pixel dimensions of decoded rasters remain
separate from authored dimensions. Two specified dimensions fill the authored box;
one dimension derives the other from the intrinsic aspect ratio. Natural sizes
use `naturalUnit`. No implicit max-width shrink overrides explicit dimensions.
Native inline images stay indivisible; oversized inline images are diagnosed.
Block images flush preceding/following inline pieces. Existing page-object and
asset/decompressed-pixel budgets still apply.

The importer accepts only image HTML width/height numeric attributes and CSS
width/height in px/pt/em plus display:inline/block. CSS overrides the matching
HTML attribute; the other attribute remains effective. In particular, actual
compiler width-only styling can coexist with an explicit natural height attribute:
32pt style width plus HTML height=12 means 32x9pt, not an inferred 32x16pt. This
adapter preserves accepted HTML semantics; it does not repair compiler/source
aspect discrepancies. Loading/decoding hints are retained and validated; native
preparation fully decodes bytes before adoption, so lazy/async are satisfied by
eager preparation rather than permitting an unpainted adopted placeholder.
General CSS, percentages, calc(), cover/contain, external URLs and unknown hints
remain unsupported. Compiler inline SVG em/pt/px sizing and display:block are
translated to the same typed supplement; validated SVG paint bytes remain intact.

`image-layout-v1` is dynamically required when image attributes/layout or symbol
overflow need the supplement. Once required, every image has explicit layout
metadata (legacy images retain their previous point-sized natural behavior).
An old semantic-tree-v1-only document/request remains supported. A client lacking
the required supplement is explicitly refused before document, asset, or action
publication, including cache hits. Cache identity remains accepted revision/input/
service, independent of requested capability order. Native transport advertises
the supported set and validates dynamic response requirements. Unknown/missing
supplement keys, invalid combinations, missing capability and lost per-image
metadata reject through both the public decoder and generic Codable recovery.
Defaulted memberwise initialization preserves existing source callers.

SVG `overflow` grammar is limited to `symbol`, with visible/hidden. At 4f1b88ae,
the independent hidden-clip oracle exposed CoreSVG painting 800 blue pixels rather
than the required 400; that evidence and its temporary importer rejection remain
in the original evidence directory. PM explicitly transferred the one painter
file to this same NA09 session for v2. The earlier read-only boundary was the PM's
initial file allocation, not a user prohibition on fixing the native painter.

The sole NativeSafeSVG owner now resolves each hidden use's bounded viewport,
viewBox origin, meet/slice/none alignment and transform. It serializes shared
content groups and per-instance clips/matrices for the existing native decoder;
there is no second painter. Original symbol overflow declarations remain present,
and caller HTML/asset bytes remain unchanged. Existing IDs are moved, not copied;
fresh internal clip IDs cannot collide with input IDs. Reference-root transforms,
use-local clips, symbol clips and parent clips retain their distinct coordinate
systems. Generated nodes/references/matrices pass the same validation again,
including depth, expanded work, composed transforms and node limits. Implicit or
font-relative symbol viewports without resolvable numeric dimensions remain
explicitly unsupported; unitless/px/pt use or symbol dimensions are resolved.

The compiler's SVG base64 data images pass through the same importer asset owner
as revision-addressed SVG: strict MIME prefix/base64/UTF8 and an 8MiB byte limit,
then the existing SVG validation, with original digest-bound bytes retained.
No raster data-image separator or source/transport authority is duplicated.
Native pixel/decompressed limits and MIME/hash checks remain unchanged.

Visible compiler SVG and its root sizing/overflow style remain supported. Hidden
import is enabled only after the independent 800/400 clip proof passes. Seventeen
independent native pixel masks cover viewport alignment, transforms, multiple use
instances, nested symbols/use references, ID collision, local/parent/symbol clip
intersection and isolated opacity. Eleven dedicated negatives include generated
node/depth and viewport-transform budgets. A newly compiled source also embeds the
original hidden SVG bytes: raw import and full-plan native paint retain its exact
400-pixel mask, separately from controlled rich snapshots. Arbitrary CSS/overflow,
entities, external/unresolved references and cycles still reject. No glyph path
becomes inferred text, source range or label-level accessibility semantics.

Generation rebinding has one model copy operation. Transport, session candidates,
host fixture provider, generic disk recovery and native layout consume the same
metadata. RecoveryStore and Operations are unchanged. The full raw host probe
also exposed an empty compiler alt being used as an invalid prepared-object label;
the host now uses its existing generic image-role fallback for empty alt, while
the model's original empty alt and absence of label/source meaning remain intact.
No source/chat/auth/lifecycle owner changes. Evidence is newly compiled
raw HTML through SectionBundle/import/Swift/native paint, kept separately from
controlled rich-asset fixtures, and actual HTTP/import/session/restore behavior.
The original-page and unchanged-HTML/input-refresh compiler regressions remain.
Required test skips fail; actual commands/exits/counts/hashes/paint are retained
under `test-output/contract-closure/NA09/v2` outside the worktree. The original
69-pass/1-error report and raw binding remain intact. Host integration consumes
the newly compiled raw fixture; it is offscreen component proof, not full app/GUI
acceptance. Unaffected TextInteraction/ReadingSession evidence remains explicitly
bound to v1 instead of being relabeled as v2 execution.

NA10 may consume the existing native object interfaces for a separate TeX answer
branch with explicit asynchronous preparation and lifetime guards. NA09 does not
change the frozen MathML helper or any public painter/operation API; only the
transferred internal clip normalization changes. TeX, F04 ordered vector
deltas/full original-page fidelity, full app/GUI/VoiceOver and runtime delivery
remain separate gates. Existing PDF component evidence is preserved.


## NA06 core review corrections (F1–F6 / LS01)

- Retained document layout and transport request generations have separate authority. `NativeReaderTextView.retainedPreparationKey(for:context:)` requires the exact current accepted document, its accepted context, view, identity and snapshot generation; it does not authorize a new adoption or source operation. Retained reflow reuses the accepted snapshot's previously verified asset bytes. New candidates still require the latest store/request generation, and source authorization still rejects pending/stale requests. Selection holds latest candidate adoption through resize/font/theme/find-bar changes. Pending geometry/draw receipts are revoked while logical text/map/AX/selection remain; current-key preparation restores geometry without reusing stale coordinates.
- Candidate composition and object-metric checks precede all publication/focus/viewport mutation. Cache miss or invalid metrics for B leave already-painted A's render key, body, map, context, AX and focus intact. Actual draw receipts remain exact-key bound.
- Explicit window close ends that view's selection lifetime. Transport failures, cancellation, source acknowledgments and history reads do not release selection. Reopening the same controller/profile creates a fresh request ticket; callbacks retained from an old close/cancel cannot cancel the new request.
- `NativeReaderSelection.validateLocal(in:)` and store hold support all accepted document blocks (bounded by the existing document limit). Ordinary selection, plain copy and AX use this local contract. `validate(in:)`, transport payload guards and server policy retain the remote 32-fragment limit. Over-limit source/chat actions reject explicitly; adapter selection invalidates a previous actionable ticket before rejecting a new over-limit selection. No old short selection is silently copied/submitted.
- Actor/UI recovery share `NativeReaderChatState.confirmsUserMessage(_:question:)`: only the same UUID, user role and exact stored Unicode scalars acknowledge a lost Send. Confirmation clears unknown state and permits a new UUID/question. Missing/mismatched history permits only an explicit same UUID/question/model retry; history never sends. A newer local draft is not cleared by an older acknowledged message, and answer-math/private-copy owners remain unchanged.
- A block image inserts presentation-only line boundaries before/after its TextKit attachment. These boundaries have no canonical/source spans; the existing map retains logical offsets, plain copy, AX text and selection endpoints. Inline placement remains inline. Verification uses the actual native host's glyph line fragments, not object-plan flush alone.
- The host calls NA10 `configureMath(worker:context:)` with a pinned explicit worker and accepted identity/snapshot/layout/width/font/theme. Reflow updates the context; replacement disposes stale conversation presentation. Missing runtime clears prepared answer math with an explicit diagnostic. This is bounded host injection, not runtime delivery, GUI, source authority or full math fidelity acceptance.

The task is `NA06-core-review-fixes-v1`, based on `9b2dc87651eb16a809bb48dbe4539614cfe30d6a`; frozen helper/worker and server/packaging inputs are read-only. Fresh before/after commands, exact source hashes, native bitmaps, selections and guards live under `test-output/core-review-fixes/v1`. Earlier review/LS01 evidence is immutable. NA06 overall, C/NA12, D/NA13, delivery and GUI/VoiceOver gates remain open.

The native **Refresh conversation** control explicitly reads authoritative history;
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

## NA12 original PDF publication and native mode

`server/native_pages.py` is the full-PDF publication adapter over
`AcceptedSnapshot.capture/current` and `Project.execute(CompileRequest(target='pdf'))`.
It captures the accepted HTML input, stabilizes the union of HTML and discovered
PDF dependencies, and rechecks signatures and content fingerprints before
publishing. Compilation holds a separate nonblocking compiler lock, never the
publication lock. Failed/stale candidates retain the last immutable publication.
The publication has a service-bound random incarnation and monotonic sequence;
a byte digest alone is not authority. Same HTML/PDF bytes with a new saved input
receive a new publication. Scoped manifest/resource GETs retain the existing
registered-prefix, Host/Origin, exact field, UUID and budget guards.

The native contract is `original-pdf-full-v1`, schema 1, delivered by
`api/native-pages` and its exact returned `api/native-pages/<publicationID>/<sequence>.pdf`.
The manifest binds document/service/revision, request/view/generation, union,
HTML and PDF input fingerprints, PDF SHA256/count, incarnation/sequence and
explicit `sourceAnchors: unsupported`. This is an immutable PDF full snapshot/reset.
The engine raw diff-v1 stream has no verified native consumer in this change.

`NativeReaderOriginalPageTransport.swift` validates the service attachment,
publication envelope and exact resource before local geometry inspection.
`NativeReaderOriginalPageView.swift` displays one viewport using a serial PDFKit
worker. Geometry preflight is bounded to 2048 pages, 16MiB PDF bytes and 100000
reachable PDF objects. Production preparation retains geometry without eager
rasters/text/character boxes. Raster cache: at most 3 entries/16MiB; text cache:
at most 8 pages/1MiB, at most 250000 UTF16 units per page. Search scans one page at
a time, with at most 256 exact results, a 256-unit query, 4Mi scanned UTF16 units and a cooperative five-second deadline. Unsupported/budget
failures are explicit; PDFKit internal allocations are separately observed by RSS.
The previous eager component path remains bounded to 32 pages for its old tests.

WindowController composes these through the existing Session.PreparedAdoption and
single canonical semantic store. It prepares before publication, validates page
adoption before canonical mutation, then synchronously installs. Requested mode
and visible mode differ until adoption succeeds. Only actual draw in the visible
mode can acknowledge Read. Hidden reflow preparation/draw cannot acknowledge an
original page. Page text selection is local display evidence, separately holding
session replacement. Mode changes, zoom and navigation require explicit release.
Cancel/dispose revoke late work; the retained accepted view survives failures.
Reflow retainedPreparationKey, local display versus remote32 selection, explicit
close/reopen and chat/math ownership remain unchanged.

URI and GoTo annotations become inert validated data, then explicit native
callbacks. HTTP/HTTPS/mailto without credentials or controls are allowed; GoTo
requires the same prepared artifact, finite coordinates and an in-range page.
No PDFView.performAction, JavaScript, forms, launch, embedding or remote actions
are executed. PDF text/bounds are display/search evidence, never glyph/source
ranges. Page mode hides/guards source/highlight/chat commands so it cannot send
hidden old reflow selections. Verified reflow source actions keep their existing
owner. Prebuilt engine probes document the tested CLI surface; engine Rust API
source is not evidence of a successful source-anchor invocation.

An optional typed PDF/viewport supplement uses NativeReaderRecoveryStore's
existing bounded, hashed atomic envelope, permissions and file limits. It retains
accepted PDF bytes/metadata and a matching page/scale, no new credentials or source
excerpts. Old schema1 defaults and pending question/model bounds remain. Offline
restoration uses the same prepare/adopt path and remains read-only.

The preceding C ownership/standalone evidence is historical. Fixed input
09c5186bff1850b17f6e85fe2f3115153520bc94 registers both original-page Swift files
and combines core, page-service, GUI inspection and portable delivery inputs.
The review-fix source is not yet staged into that application. Source/app
rebinding and final GUI/VoiceOver and official review acceptance remain pending;
a headless component paint is not packaged application acceptance.


Native original pages use an NSScrollView viewport over the single page document
view. Document extent follows the prepared raster at logical zoom; viewport width
changes fit preparation independently, so zoomed page bottoms remain reachable.
Recovery retains bounded unscaled page-display offsets with optional old-schema
defaults, clamps them to the restored viewport, and does not create source ranges.
Pointer release checks the original snapshot/page/operation before selection.


## Current guarded native wire and recovery budgets

NativeReaderTransport/Actions own GET api/native-document and api/native-assets/{id},
POST api/native-action (excerpt/locate/highlight/receipt/last-change), POST
api/native-chat (open/draft/send/cancel/list/events), and existing POST api/chat/auth
status/models, at the owned root or registered /d/{id}/ prefix. Requests bind
schemaVersion/capabilities and documentID/serviceID/revision/requestID/viewID/generation;
validated lowercase 64-hex x-native-input-id from document response becomes inputID
on action/chat. Document identity/generation/capabilities and action/chat/event echo
envelopes are checked independently of server source/input freshness. Selections
carry ticket plus blockID/rangeUTF16/exact fragments, preserving the remote32 cap.
Source receipt lookup and exact UUID/user-content chat history never redispatch a
mutation. Service, source, auth, provider and model policy owners remain unchanged.

Document JSON is bounded to32MiB, each asset16MiB, generic JSON request256KiB and
response2MiB; existing account reads have256KiB responses. SSE total16MiB,
event2MiB and framing4096 extra bytes are bounded. Observation buffers newest1,
tries at most4 with1/2/4-second reconnect delays and authoritative history reads.
Session adds at most3 transport retries with1/2/3-second delays (constrained power
4/8/12); preparation failure retains the candidate without automatic network
request. These budgets do not impose new tool-round/document-read model limits.
The canonical native-reader-app-contract.typ records endpoints, envelopes and
current local-versus-recovery storage limits; exact implementation owners remain
the authority for validation.

## Final review corrections N1–N5 and current verification boundary

Page-store begin is idempotent only for the identical still-current in-flight
ticket/binding. A newer request, a different binding at the same generation,
cancellation or a consumed ticket cannot be revived. Thus selection beginning
during PDF preparation retains candidate B until explicit release and can adopt
the same B without a new network refresh.

Offline restore captures validated recovery assets on the pending candidate's
preparation operation. Live target/document/assets closures are not consulted.
The existing fallible prepare/synchronous atomic adopter remains the only
publisher. Assets become accepted only after successful adoption and source/chat
stay read-only. Initial layout notifications without any retained publication
rely on that preparation's bounded exact-key recheck, rather than revoking an
awaited first restoration.

Original-page accessibility projects only the current bounded cached page text,
UTF16 ranges, local display selection and inert safe links. Snapshot, page,
layout generation and operation identify the projection; late/stale children
cannot read, select or activate. Tab/Shift-Tab focus and Enter/Space activation
reuse the same safe action owner. PDFKit text index/grapheme verification and
one-page/lazy cache bounds remain; no PDF offset becomes Typst source authority.
Find selection and same-artifact GoTo defer target reveal until the matching
raster is installed, then use the existing crop/rotation/zoom transform and
actual clip bounds. Cancel/mode/page changes revoke late reveal.

Answer plain copy enumerates attachment boundaries, restoring each selected
formula's authored delimiter text in order, including adjacent equal formulas.
String equality is not token identity. Full and partial selections use the same
owner; helper, parser, math calculation and source policies are unchanged.

The canonical Typst contract now records exact current wire endpoints/envelopes,
request/response/SSE/assets limits, observation and transport retry budgets,
local versus typed-recovery bounds and F01–18 receipt gates. Local 33+ block
selection and 0.25 reflow zoom do not extend typed recovery's 32 fragments and
0.5–4 zoom. Recovery rejection retains old durable state; it is not silent
successful persistence. The synthetic 256-page and current 37-paragraph fixtures,
host OS27.2.1, target13 and single partial GUI Read/AXPress -25200 interruption
are distinct evidence. Actual OS13, complete GUI/AX, official final code/docs
review and a restaged final app remain gates. NA/ B/C/D/882/C19/G1 labels and
current inspection entrypoints are defined in the canonical verification guide.
