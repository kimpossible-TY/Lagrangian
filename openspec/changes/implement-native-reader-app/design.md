# Design

## Context — Historical NA01

This opening context records NA01 planning, not current endpoint/P0 status. See Current wire and the later component sections for implemented behavior; final App/GUI acceptance stays separate.

NA01 starts from `f8058a29735dea6b40a5c1362a14ae12aad3396a` (authorized fast-forward from `3e5a05c66bb0fdcffb19a90fd70e1bc2bd2cd9e2`). P0's four files are inherited inputs, untouched; their independent review/testing remains pending. See proposal.md for motivation and `docs/tinymist/dev/native-reader-app-contract.typ` for the F01–18 handoff. No native HTTP endpoint currently exists; NR03 B09 and P0 are not service implementations.

## Goals / Non-Goals

**Goals:** one executable semantic schema and narrow async operations, real accepted compiler translation, immutable shared input for NA02/03/04/05, bounded object feasibility evidence.

**Non-Goals:** full application, general formula/paged fidelity, GUI/AX acceptance, new runtime dependencies, transport implementation, source/auth/history ownership, P0 acceptance or macOS13 runtime certification.

## Decisions

### Frozen shared API (NA01 is the sole change owner)

The commit containing this change is the common contract SHA; consumers record `git rev-parse HEAD` after accepting it. Later shared changes return to NA01. No consumer copies or edits the shared sources.

- `apps/macos/NativeReaderDocument.swift`: `NativeReaderDocument.decode(_:capabilities:) throws -> NativeReaderDocument`, `validate(capabilities:) throws`, `NativeTextOffsets.init(_:)`, `NativeReaderNode.orderedNodes`, `graphemeBoundariesUTF16`.
- Schema 1 JSON: `{schemaVersion, identity:{documentID,serviceID,revision,scope:service|fixture}, generation, requiredCapabilities:["semantic-tree-v1"], blocks:[NativeReaderNode], assets:[{id,sha256,mime,byteCount}], diagnostics:[{code,nodeID}]}`. All arrays retain reading order. Asset IDs are content digests plus extension, never paths.
- Node: `{id,sectionID,kind,canonicalText,displayText,rangeUTF16:[start,end],offsets:{scalars,cpToUTF8,cpToUTF16},children,anchors,annotationTargets,visible,mapping}` plus typed optional `passageKey,direction,language,headingLevel,math:{mathML,normalizedText,display},cell:{rowSpan,columnSpan,header,scope},link,assetID,alt,listItemNumber,projectRef:{project,label,title?,page?,text?}`. `kind` is the Swift closed enum; unknown values fail. IDs are unique within a snapshot, not cross-revision identities. `passageKey` reuses `sections.py` identity for existing server resolution. No invented source ranges. `projectRef` is optional and valid only on links, with non-empty project/label and optional positive page. Import errors `invalid-project-ref` and `duplicate-anchor` reject the whole candidate. There is currently no dedicated projectRef capability; old strict node-key decoders reject this supplement. App and backend must be delivered together; this is not negotiated backward compatibility.
- `tools/flow-reader/flow_reader/document/native_document.py`: `import_accepted_document(bundle: SectionBundle, *, document_id: str, service_id: str, generation: int, identity_scope: str="service", required_capabilities=("semantic-tree-v1",)) -> ImportedNativeDocument`. Return `.document` is JSON-ready and `.assets` maps digest IDs to bytes. `NativeImportError` contains a bounded code. The caller supplies an **already accepted** bundle under existing publication discipline; this function cannot establish acceptance/freshness. It orders sections by manifest, not dictionary insertion order. Unknown semantics/attributes fail atomically. SVG subset is explicit; further primitives return to this owner.
- `apps/macos/NativeReaderOperations.swift`: `NativeReaderRequestContext(requestID:UUID,viewID:UUID,generation:Int,target:NativeDocumentIdentity)`; `NativeReaderSelection(ticket:UUID,fragments:[Fragment])`, each fragment `{blockID,rangeUTF16:Range<Int>,exact:String}`, local display selection may cover all accepted top-level blocks; `validateLocal(in:) throws` retains exact scalar/grapheme/order guards. Remote source/chat submission remains 1–32 fragments via `validate(in:) throws`. Convenience single-fragment initializer also exists. Fragments preserve their exact text; joining or Typst copy is an explicit consumer operation, not an implicit source reconstruction.
- `NativeReaderDocumentProviding.document(for:) async throws -> NativeReaderDocument`; `NativeReaderSourceOperations.perform(_:) async throws -> NativeReaderSourceResult` for `.excerpt/.locate/.highlight`. Request binds context, selection and receipt UUID. Result echoes local context/ticket and bounded status (`verified/unmapped/ambiguous/stale/unsupported/uncertain/rejected`), optional verified excerpt or opaque destination anchor. Adapter validates actual server response before wrapping; echo is not a server freshness proof.
- `NativeReaderChatOperations.perform(_:context:) async throws -> NativeReaderChatState` and `observe(conversation:context:) -> AsyncThrowingStream<NativeReaderChatState,Error>`. Commands: open(selection), draft(UUID,version,text), explicit send(UUID,version,messageUUID,question,model), cancel(UUID). State retains context/conversation/version/sequence/ordered typed messages. NA04 rejects stale context or regressing conversation version/sequence, bounds stream buffers and disposes only its own subscription. List/account/session presentation stays in NA04 over existing owners; these protocols grant no credential authority.
- `@MainActor NativeReaderDocumentStore(viewID:)`: `beginRequest() throws -> Int`, `adopt(_:for:) throws`, `holdSelection(_:) throws`, `releaseSelection(ticket:)`, `cancel()`, `dispose()`. Adopt requires matching view/target/generation and validated document, and rejects while selection is held. Rejected candidates leave accepted content intact. Caller retains only the latest candidate if it chooses to retry after release. Cancel increments local generation before cancelling transport; dispose prevents all adoption. It does not stop shared services.

### Units, geometry and operation lifetime

Canonical text is the exact accepted HTML descendant scalar sequence, not raw Typst. Display text currently equals canonical scalars, including math text; there are no object placeholders. MathML retains mathematical hierarchy while the plain string alone does not describe a fraction. Whitespace normalization is only the explicitly named `math.normalizedText`. NFC/NFD scalars are preserved. UTF8 maps count bytes, codepoints mean Unicode scalars, UTF16 maps count code units. Node ranges are half-open **block-local** UTF16; per-node offset maps are local to that node's string. Child ranges partition the parent's range in order. User endpoints are extended grapheme boundaries, computed by Swift; surrogate/combining/ZWJ splits are invalid. Source offsets remain in the existing private mapping owner, never conflated with display offsets.

Semantic model contains no UI geometry. NA02 owns top-left AppKit point geometry and text/AX; NA03 owns object metrics, native paint and hit-testing under explicit width/font inputs. Trees preserve inline order, table groups/rows/cells, numbering, labels and annotation relationships so paint/selection/AX can use the same IDs. `visible` and `mapping` are explicit; unsupported visibility semantics are rejected, never guessed. Current importer emits visible/unmapped nodes only. Paged coordinates are separate and require an accepted revision match.

Contract errors: invalidDocument, unsupportedSchema, unsupportedRequiredCapability, wrongTarget, staleGeneration, selectionHeld, disposed, invalidSelection. Adapter failures: rejected(bounded code), unavailable, unsupported, cancelledBeforeDispatch, unknownEffect. A timeout/cancel after dispatch of highlight/Send remains unknownEffect; query existing receipt/message owner before any explicit retry. Stale selection ack must not release a newer ticket. Request cancellation cannot imply rollback or cancel shared OAuth. No automatic Send.

### Historical NA01: existing owners and future transport candidate

NA04 may implement an additive `GET /d/<registered-id>/api/native-document` under existing Host/Origin and exact service/document/revision checks, using this importer and existing revision-bound assets. This is a **candidate for NA04 implementation and negative testing**, not an existing endpoint or shipped transport. Bind service incarnation to the observed manager instance (not PID alone); generation is local correlation. The historical 32 MiB JSON limit is superseded by the current 64 MiB cap below; bound individual sections to 16 MiB, tree depth 128/nodes 100000; enforce transport limits before decoding. Current importer handles complete snapshots, not streaming deltas. Request/stream timeouts, asset budgets, chat/action payload limits and reconnect backpressure remain explicit NA04 implementation gates, preserving stricter existing owner limits.

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

Document JSON is bounded to64MiB, each asset16MiB, generic JSON request256KiB and
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
review and a restaged final app remain gates. NA/B/C/D/882/ec2/C19/G1 labels are defined in `docs/tinymist/dev/native-reader-app-contract.typ` under Historical role names/Core review correction; current inspection entrypoints are in the canonical verification guide.


## NA06 native local feature wiring (fixed24666 follow-up)

Native controls consume existing owners: LocalReview add/undo/clear paints current
TextView range geometry without modifying text/source/AX; Contents and Back use
canonical node/anchor mappings; Theme/Text size/Zoom/Fit reuse local appearance
and render keys without OS preferences/schema changes. New snapshot/cancel revokes
old marks/return while same-snapshot reflow preserves logical selection and marks.

FlowApp composes an explicit profile+target namespace under support for the sole
typed RecoveryStore. Its list operation reuses the exact envelope/hash/document
validator also used by load. Save Offline captures current renderer restoration,
accepted assets, marks and typed chat pending/newer-draft fields. UI save/list/open
are injected operations delegated to that actor. Busy/cancel/close/request epochs
reject obsolete callbacks and bounded atomic save retains prior files on failure.
The home offline action composes a separate native reader without live startup
or managed attachment; restore remains read-only with zero live fetch operations.
Typed32 fragments/zoom0.5–4 are not widened to match local33+/0.25 display. Saved
drafts are read-only offline; no history read, restore or layout sends inference.
Only actual matching visible-mode draw acknowledges paint.

Historical fixed24666 reachability: Last Edit and mapping-only Locate Source used
Actions/source-history and TextView anchors; that revision lacked the explicit
editor descriptor composition and separate dispatch/receipt. This is not the
current NA15 status: see “NA15 explicit native editor actions” and “v4 NA15 review
corrections” below for the private descriptor chooser, consented movement-only
composition and guarded effect receipt. Native-action locate still returns only
a verified display anchor. F13 remains open NA16 work: status/models and an
explicit configured Homepage action do not implement native login/cancel/logout,
credentials or source authority.

Reachability and actual target/action/pixel/storage tests are separate from final
GUI/AX/official review and new app/resource binding. Delivery/archive producer
paths and old evidence remain untouched; no app build/staging in this assignment.


## Closure review v2: candidate, current draft, keyboard and explicit local UI

Recovery attachments are candidate-local completion data, applied once after actual
PreparedAdoption and restored selection, surviving layout retries/holds. Initial
await return or matching identity is not publication. Held restore remains
cancellable; close/cancel drops completion with the candidate. Initial saved drafts
are consumed separately from current per-conversation state, using the existing
persistDraft/recoveryDraft callbacks before ChatView replacement. Exact history
confirmation of M and newer N2/model survive reopen and resave; no automatic Send.
Current-page PDF link traversal exits to normal next/previous key views at its
boundaries, keeping stale-page guards. Actual Full Keyboard Access/VO remains
independently unverified.

The native wire uses conversations<=128 unique UUID conversation_id, nonnegative
nonregressing version/sequence, thread<=256 unique UUID id messages with role
user|assistant, text<=80000 and status (streaming=incomplete), draft<=8000, and
attachment.state==attached for attached authority. Entire batches validate first.
String limits are Swift String.count; payload bytes remain separate. See canonical
contract JSON example. These are not new inference round/tool limits.

Reflow Light/Dark/Automatic (initialLight), Text size12/14/16/18/24/32 (initial14),
window-local Preview/Apply/Cancel and Zoom/Fit preserve canonical selection and
renderer-owned anchors. Automatic inherits the window, never changes OS settings.
Reflow Fit means zoom1; PDF Fit means width-fit, without changing PDF print colors
or glyph authority. Stored exact selection/normalized viewport apply to reflow32
and zoom0.5–4. PDF recovery stores publication/digest/page/scale/unscaled offsets,
not PDF selection; offline mode switching remains unsupported.

Explicit Export PDF uses accepted Original PDF publication/input/digest bytes,
existing typed validation and atomic disk ownership, native save chooser and
snapshot/operation rechecks before publication. Tests inject chooser results only.
Cancel/stale/dispose/tamper/invalid destination and observed precommit directory
identity/metadata fingerprint mismatches reject publication in the tested paths.
Same-metadata content changes and external rename races are not an atomic CAS
guarantee. Production PDFKit reopens staging; final-output reopen is a test witness.
Review marks retain per-mark32 and total256 unique UUID budgets checked before
adoption; browser marks/source authority are unchanged. The old18-case design is
immutable history; Planner's new125-case design supersedes it without creating
assignments or passes. No current app/GUI/VO/OS13/live completion is inferred.

## NA15 native editor effects

The Locate Source control calls `NativeReaderActions.jump(_:query:)`; existing
`perform(.locate)` remains mapping-only. Its independent typed effect receipt can
say jumped only after the existing `tinymist.reader.jump` owner returns jumped.
Native feedback receives no source coordinates, private paths, tokens or address.

FlowApp consumes one explicitly chosen private local descriptor and user Connect
consent into `NativeReaderManagedClient`. The manager's additive local
`--native-editor-consent` validates the exact executable/private control before
normal registration and acknowledges `nativeEditorActions: 1`. Native service
restart cannot renew that consent. Legacy terminal registrations remain compatible.
HTTP cannot choose or register executable/address/path/coordinates.

`/api/native-editor` retains native transport guards and additionally requires a
real loopback peer and loopback Host. `services/native_editor_actions.py` owns
selection synchronization, prepare, dispatch, read-only receipt and revoke/close.
It reuses AcceptedSnapshot/SavedSourceNavigation/EditorAttachments/NeovimEditor;
source mapping/navigation, terminal and Lua remain unchanged. Prepare and final
dispatch must agree on the verified private source span and exact registration,
control and executable identities. Client/server also bind document/service/
revision/input/view/generation/full selection/request/receipt/consent/sequence.
Newer failed selection updates revoke old pending work; foreign attachments cannot
close another view. Edit-lock then publication-lock order is preserved.

A ten-second prepare and bounded 128 view/tombstone, 128 pending and 4096 consumed
receipt capacities fail closed on exhaustion. The private SQLite store commits
unknown before RPC, then persists the result. Duplicate UUIDs cannot redispatch,
including after lost acknowledgments. A 2.5-second RPC timeout or late cancellation
leaves effect unknown; one explicit Check Editor Result read may recover it.
An obsolete result cannot adopt into newer selection/view state. Native invalidation
revokes locally before a bounded best-effort server notification. No editor, shared
service, other attachment, source bytes or clipboard is disposed or changed.

Dedicated tests use real saved compilation, Swift action/production HTTP/local
registration and actual headless Neovim; raw Neovim RPC independently observes
file/line/UTF-8 byte column and buffer preservation. Fault gates/response loss are
injected and must be reported separately from the actual effect. Real GUI, visual,
VoiceOver/OS13 runtime and final installed delivery remain unverified. The existing
source registry already includes all modified Swift; the helper and exact source
correction inventory require integration-owner delivery rebinding before shipping.
NA16 inherits these shared API/bytes sequentially without widening account authority.

Native registrations carry an additive `nativeJumpOnly: true` marker. The existing
attachment write resolver rejects that marker, so the unmodified source-write
owner cannot use a movement-only token. Connection acknowledgment checks the
private record without granting write authority. Swift also rejects Highlight
under this consent. Legacy terminal records retain their fields and behavior.
Host close/dispose explicitly revokes native editor consent and supersedes pending
managed resolution; reopening the document does not silently restore consent.

### NA15 supervised receipt lifetime and control-event evidence

Consumed UUID rows also bind the exact private pre-effect registration fingerprint,
including control/executable/registration file identities. Receipt or duplicate
prepare/jump after replacement returns unknown and cannot redispatch. A nullable
column migrates old rows; missing fingerprints never adopt historical success.
Native sync additionally requires `nativeJumpOnly is True` on the local record;
HTTP consent cannot promote a legacy token. Existing terminal writes retain their owner.

Offscreen tests use NSApp .prohibited, show:false and avoidActivation:true. They
select the actual TextView and invoke production Locate/Check Result controls,
through shared FlowApp Read/descriptor adoption, production HTTP and actual Neovim.
An independent Python RPC oracle observes the effect and byte preservation.
Only inventory/consent decision and fault delivery are injected. The already
implemented original-receipt preservation is exercised, not duplicated. Actual
chooser/alert, foreground GUI and final installed-app acceptance remain open.


## v4 startup/lifecycle/display corrections

Independent and integration offscreen runs complete with the original optimized
main/delegate structure; the GUI loading blocker remains unverified. Dev-root-only
value tracing records load/worker/completion and hashed selection readiness without
retaining the app, logging private text or weakening guards.
ReadingSession storage completion is distinct from environment-driven native
recovery. A still-live explicit Read ticket routes sleep/wake/network/power to
NativeReaderSession; unread profiles, closed/cancelled windows and offline saved
copies are excluded. Session retains accepted content and owns bounded retries.
Snapshot replacement adopts the retained display baseline consistently; returning
from Original resolves Automatic using this window before Reflow preparation.
The fixture manager embeds its exact setup root/identity and owner hash so argv-only
app launch does not require environment forwarding. None of this is a real GUI,
VoiceOver, macOS13 or PM acceptance receipt.

## v4 NA15 review corrections

NativeReaderActions separates validated body selection from optional editor sync,
revoking prior pending work first. Source/mapping/Ask remain available after an
editor-only failure; stale contexts/inputs and invalid selections are not relaxed.
Historical299 NativeReaderManagedResolver only retained a response-bound token
lease, leaving pre-response timeout/SIGKILL untracked; its actual2 leaks and
exit1 desired oracle remain historical in resume2 evidence. The current source
creates a caller-known operation and retained lease before attach. The manager
serializes a durable private operation intent and EditorAttachments publishes only
complete fsynced records atomically with exclusive token collision semantics.
Cancel tombstones precede exact operation/digest/inode retirement. Malformed
reserved/prepared/issued state is not confirmed absence. Shared resolver copies
retain failed pending leases for a later explicit connect/Read/close; confirmation
alone removes an entry, and a live lease is not retried or revoked by a new Read.
Pending cleanup gates only a new consented editor grant. Plain editor-free body
Read leaves that retirement pending and retains accepted Source/Ask operations,
without inferring editor authority. A ten-second resolve budget covers pending
retry, prepare/ack, final HTTP state
and cleanup. Subcall ceilings are shortened by remaining time; late success is
rejected. Actual cancellation terminates/waits for only the owned manager process,
not its shared service. There is no background retry, directory scan or new
credential/source authority. Private bounded journals/tombstones are retained;
automatic pruning and automatic entire-app restart recovery are not implemented.
The known-operation recovery API is tested after process death, separately from
surviving production caller reentry. Legacy native-consent without an operation
remains response-bound; normal terminal register stays compatible. Current
witnesses are external resume5 evidence; no App build/GUI acceptance is implied.
 The local manager/EditorAttachments own token retirement and the four-field
private chooser descriptor export. There is no HTTP deletion/registration API,
quota increase, source writer or editor/service/control termination. Gated tests
observe a transmitted jump's committed unknown row while the actual edit_lock is
held, revoke it, and independently compare editor/source state after release.


## v5 managed Unicode identity and narrow home feedback

ReaderManager compares canonical-equivalent resolved root/entry spellings only
alongside actual directory/regular-file device+inode identity and project scope.
It preserves registered spelling/IDs, exact resolved legacy aliases, explicit
service selection and ambiguity rejection. No casefold/NFKC, inode-only hardlink
authority, source mapping formula, document migration or backend effect policy
is added. Missing source is refused for attachment/descriptor. Local withdrawal
may still select its registered spelling, read only its exact bounded private
native lease and reuse EditorAttachments retirement; that prior record supplies
no current source/editor authority. Live records retain document_identity checks.

FlowApp's existing snapshot/mutation state drives honest loading/ready/error/
empty/busy text, and service labels distinguish lifecycle from Read. Enabled
policy, targets/actions, service readiness probes and readingIntent are unchanged.
A read-only d7 FlowApp fixture is instrumented in owned output; wording assertions
are separate from baseline semantics. Isolated busy never suggests disabled Stop.
Actual filesystem/compiler/HTTP/Neovim and offscreen AppKit evidence remain
separate from GUI, v4 artifacts, sourcepin/delivery registration and NA16. The PM
receives a fixed source-only component and exact Git-blob delta, not a new App.


## v6 lifetime correction over H5 (source component)

SF2-B1: final native state receipt owns a per-operation URLSession data task.
An absolute deadline at caller deadline minus2.75s cancels it and awaits actual
completion before exact cleanup. Request idle bytes cannot postpone this;
ordinary shared session timeouts remain unchanged. CommandRunner preparation,
pending retry, final probe and cleanup still share the original ten-second budget.

SF2-P1: operation issuance captures the verified actual document separately from
its stable original caller request and reader ID. Withdrawal checks the private
operation and exact registration digest/inode without re-resolving root/entry
aliases. Existing v1 records retain their earlier resolved-binding compatibility;
missing alias spelling never captured by v1 is not guessed or migrated.

V501: a readonly manager CLI query returns opaque registered document/reader
scope and stable request binding. The shared resolver gates new consent on this
scope, including equivalent entry spellings and supported aliases, and retains
original withdrawal arguments for disappeared/retargeted aliases. It does not
copy path policy into Swift, scan journals, stop services or revoke body/Source/Ask.
Other actual document/reader scopes remain independent. Exact input/output types,
including64 lowercase hex operation, finite epoch reservation deadline and single
boolean `released` confirmation, are canonical in native-reader-editor-actions.typ.

The original acceptance design is
`/Users/taeyoung/Documents/Codex/2026-11-08/task/openmausbot-setup/bot-workspaces/lagrangian/native-reader-20261117/app-plan-native-actions-acceptance/acceptance-plan.json`,
plan_id `lagrangian-native-app-actions-acceptance-20261118-v1`,
design_source_revision `09e78630a6afb51436e45da140c3588c82c295f5`.
That revision is an immutable design identifier, not current artifact source.
PM binds its unchanged125 cases to final source/artifact and actual independent
results later. v6 REPORT/handoff under the external DevSSD test-output directory
are component evidence only. Historical H5/resume5 and earlier failed queued-cancel
results remain unchanged. No App build, GUI/VO/actual OS13, F04 raw-delta, F13/NA16,
live-provider, real receipt or complete125case acceptance is implied.


## v7 host hierarchy and mode-state presentation

The existing NativeReaderHostWindow composes wrapping native command rows and a
bounded scrollable disclosure. Mode/outline/search and current/requested/status
remain primary and leading aligned; source/review/display/offline/account retain
native controls/selectors and existing enabled/consent/IO owners. No web body,
CSS/ARIA port, framework, shared model or source-authority policy is introduced.
NativeReaderControlRow owns only repeated measured control layout; title/font
changes invalidate that layout at existing host update points. The host does not
raise the existing window minimum to make a size test pass.

A requested-mode value records UI intent only. Existing session selection guards
and atomic adoption own actual transition. Search provenance references an actual
PDF display-selection ticket; query strings are never selection authority.
Failure/retained-result guidance outranks requested-mode preparing text while
showing both visible and requested mode. Explicit refresh reuses existing Read
lifetime; recovery-copy state disables the control and rejects its callback,
without changing the shared session or transport. Native key equivalents/focus
return are exercised offscreen; real popup/foreground, AX-input and VO remain open.

Apple-design interaction/content principles and web guidelines pinned at
434b7f91364665f2f733b310ec54809bf8f37937, SHA256
d246b026f4f29b5823a9cc857f9edf3d2507002e055e32040cadeaf3b38e0234, inform
hierarchy/labels/focus only. No CSS/ARIA is translated into AppKit policy.
The requested lagrangian-parallel-planning skill was not found in the stated
searches (also recorded by the existing PM contract); it is not claimed as read.
Existing single-writer/fixed-plan/shared-Swift-lock rules apply without delegation.

Before/after fixed-input frames, real AppKit controls, compiler-accepted semantic
and PDF input, failures, scope and final Git-blob deltas are external DevSSD
`test-output/native-reader-ui-v7/REPORT.md` and handoff. Historical d7 GUI52 partial8/
notrun44/passed0 and visual18 unverified8/notrun10/passed0 remain unchanged, not
v7 evidence. No sourcepin/App build/full125 acceptance or NA16 work occurs here.


## v8 pre-issuance scope and original request expression

The production resolver passes `--native-editor-expected-scope` (queried opaque
64lowercasehex) with its native operation. The manager validates it against the
actual registered document/reader before reservation, rechecks freshness before
publication and echoes the captured issuance scope. Optional-field legacy callers
retain prior compatibility, not this pre-response race guarantee. Stable withdrawal
keeps original absolute/NFC request expressions including symlink-sensitive `..`;
manager scope owns equivalence. No new HTTP authority, journal scan, service restart
or automatic retry is introduced. The managed Swift CommandRunner sets a 1-second
execution timeout for scope queries, shortened to `min(1, deadline-now-0.2)`
when given a finite future epoch. On timeout it requests termination and waits
for exit, forcing termination if the child is still running after the 0.2-second
grace window. The direct CLI checks the supplied finite-future deadline on entry.
Failure preserves pending leases and denies a grant. Null scope can correlate
original withdrawal only.
The final state request reserves 2.75s first, cancels/awaits actual task completion,
then performs exact cleanup. Frozen App/GUI and full acceptance remain PM gates.

## Current fixture and conversation integration

The exact chat repair source `8e57062ea768320c3fe64f266eb50f40f53d16c1` has
26 offscreen checks, not actual GUI acceptance. Actual host Ask reentry restores
the latest draft/model and original pending message identity through shared
adopt/persist; explicit history/retry owns uncertain Send resolution. Selection
registration remains separate from initial local Ask effects. Stale selection
blocks a new Send without revoking same-context conversation Stop/history; Stop
requires an accepted streaming conversation; local preparation alone supplies no
Stop target.

The existing dev-root/no-activate/native-fixture arguments now select local
fixture and bundled math only. Dev configuration, child environment, OS-effect
and private-copy composition remain with their existing native app owners.
No manager/editor or external invocation authority is supplied in fixture mode.
Tests with a virtual ordinary home and offscreen injected operations distinguish
that boundary from full AppKit/LaunchServices IO isolation, actual startup and
same-app GUI/VoiceOver. Normal nonfixture services and renderer/authority owners
are unchanged.

The fixture keeps the existing local offline recovery library under its dev-profile
root, including saved drafts. Offscreen construction respects the existing
showNativeWindow input; it does not grant manager, editor or external effects.

## Review repair: known conversation presentation and fixture effects

Within a living Reader context, bounded associations for exact passages let already
created conversations reuse the existing current/recovered draft adoption path.
They restore local text/model and original pending identity without owner/HTTP
resolution and never grant selection or Send authority. First uncreated drafts
and app restart are outside this immediate presentation guarantee. Unknown Send
requires successful explicit Refresh first: confirmed original history permits a
new explicit question, otherwise retry is limited to the original question/model/UUID.
A failed Refresh retains pending uncertainty. Stop presents its accepted result
only after lifetime/epoch/context/conversation and monotonic record checks.
An unconfirmed pending Send restored by closing and reopening the composer needs
another successful explicit Refresh before retry. Refresh requires an open
conversation and no other conversation action in flight. Exact-range associations
reference UUIDs with one latest display snapshot per UUID, including multiple
ranges in the same paragraph. In-flight Stop rejects duplicate button/handler
entry while preserving its first completion and all late-response guards.

Fixture settings/search/composer responders refuse standard system clipboard
editing, while the existing home/body/PDF Copy operation remains private. Fixture
offline PDF restoration retains native reading but denies Export at UI, callback,
chooser and staging entry. Normal AppKit editing and verified PDF export remain
unchanged. Optional startup diagnostics perform filesystem work only on an owned
queue, without init/deinit flush waits; first-window acceptance remains separate.

## Minimal redesign preservation and file-split notes

- **Shared design tokens and brand presentation**:
  - `apps/macos/NativeAppDesign.swift` canonical tokens: Cream Light (`#F7F2E8` / `#FFFCF5` / `#292722` / `#514A83`) and Warm Dark (`#24231F` / `#302E29` / `#F7F2E8` / `#C6BEFF`).
  - `apps/macos/NativeAppDesign.swift` also owns the sage running-state token and `.ghost` icon-button role.
  - `apps/macos/NativeBrandMark.swift` owns the vector mark and `statusImage(phase:)` menu-bar rendering with its running dot.
  - `apps/macos/sources.json` remains the single source registry; these UI additions stay in existing Swift files.
- **Preserved public signatures and service/session owners**:
  - `NativeChrome.install(on:)` and `NativeChrome.apply(to:)` public signatures remain unchanged.
  - `ProjectService`, `ReadingSessionController`, `NativeReaderSession`, and `NativeReaderActions` ownership and contracts remain unchanged.
- **Preserved interaction, accessibility, and layout invariants**:
  - Keyboard shortcuts (`⌥⌘T`, `⌘F`, `Esc`, arrow keys, `\r`) remain intact.
  - VoiceOver/AX semantics and WCAG 2.1 SC 1.4.11 (3:1 or higher non-text contrast) are required invariants pending external GUI and visual verification.
  - Selected PDF ink stays clear of bottom floating tools through renderer scroll insets and reveal, without window resizing.
- **File-split note**:
  - Settings sheet presentation is separated in `FlowApp.swift`. Home has a compact brand header with add/settings icons, a project selector and primary `읽기` action, and a `.ghost` icon dock for service start/stop, browser, address copy, offline documents and overflow. A sage dot marks the running service; stopped state uses the play icon. The path caption, service card and bottom settings/login bar are removed.
  - The status-bar menu exposes project/service summary, home, `읽기 시작`, browser/offline reading, service start/stop/restart, editor consent, copy/logs, project settings, login, guide/about and quit. `statusImage` supplies its branded state icon; settings Save stays in the sheet.

## Disposable viewed layout cache (r1-S1, r1-S3)

NativeReaderLayoutCache is a disposable optimization, separate from typed offline
recovery owned by NativeReaderRecoveryStore. The existing shared
native-reader/layout-cache directory serves profiles with exact ownerID scope;
no recovery namespace or installed path is migrated. NativeReaderViewedLayouts
holds at most 256 successful viewed math layouts. Unread content never invokes a
provider merely to populate the cache.

Filenames are sha(ownerID)-sha(documentID)-sha(key).layout. Save filters by owner
and document prefix; latest filters by owner prefix before decoding. A separate
.document envelope stores the full accepted document at most once per identity
and revision while retained, independent of window state. The window stores its
key, identity/generation, viewed blocks, bounded layouts/assets and restoration.
Identical key, viewed-block IDs and layout key set skip writing; position-only
changes flush on close/cancel's immediate save. Geometry/revision changes revoke
old windows of that owner/document. Other profiles/documents are not decoded by
save. Superseded or unreferenced document files are disposable.

Both stores use NativeReaderSnapshotStorage for schema-1 SHA-256 envelopes and
O_EXCL/no-follow temporary write, synchronization, rename and directory fsync.
Compression is an envelope option; typed validation and budgets stay with each
store. The layout namespace is locked, private and limited to 64 MiB including
staging bytes, with LRU document/window-group eviction. Corrupt matching entries,
unsafe non-regular/hard-linked cache entries and legacy monolithic entries are
unlinked and skipped. A bad disposable entry cannot disable all caching.

A validated cached window may paint a read-only cached copy without a math
runtime. Source/chat/editor authority requires live accepted publication. Cached
content promotes only after current document identity/revision and layout inputs
are confirmed; failed or stale preparation preserves the retained copy.

## Contracts delivered by 20ad89a5 (r1-S5)

The document JSON cap is 64 MiB in the backend and Swift decoder. Ordered list
items retain optional positive listItemNumber. Image dimensions support percent
(`%`) as well as px/pt/em with existing image-layout-v1 negotiation; percentage
values are positive and at most 100. Anchors accept mark: identifiers alongside
existing accepted anchors, with uniqueness still enforced.

The pinned math helper accepts kind mathml-batch with 1–512 items and at most
64 MiB JSON input/output. Each item has at most 256 KiB JSON input, a 65536-byte
source and 8 MiB output. Swift/helper bounds are cross-checked by Python tests;
the helper bytes and existing pins are unchanged. Swift caps batch stdout at
min(64 MiB, itemCount × 8 MiB) plus the terminating newline, and scales the base
timeout by min(itemCount, 6). Timeout/input-limit/budget failures halve chunks
within an overall per-chunk deadline of twice the initial timeout. Each child
receives at most the remaining time. Deterministic per-item output-limit fails
without splitting. A failing single item or exhausted deadline throws; atomic
snapshot preparation does not publish successful sub-ranges of a failed batch.
Other errors do not trigger splitting.


## NRD01B reader integration

NativeReaderHostWindow composes the NRD01A NativeOutlineDrawerView,
NativeBrandMarkControl, NativeModeMorphSwitch and NativeFloatingGlassView.
FlowApp injects Home for live and offline readers; no service lifecycle moves
into chrome. Existing mode selectors remain the request entrypoints and the
switch thumb follows only accepted displayMode, including selection holds.
Mode transitions cancel retained Reflow layout work; hidden body layout callbacks
cannot revoke an in-flight or accepted PDF publication.

The edge-to-edge document stack retains toolbar-only 16pt horizontal padding.
The toolbar hairline fades after a 4pt scroll offset. Reflow keeps a visible
icon-only outline toggle at 680pt or below; online PDF moves the compact switch
left and at 640pt moves it and the disabled outline into overflow. Offline PDF
keeps the exact `오프라인 PDF` badge. Aa remains an opaque NativeDesignSurface.

NativeOverlayPassThroughStack centers content-sized notice/status glass capsules
10pt below the toolbar. Empty margins pass events through. Persistent actionable
states suppress transient notices without timers or first-responder changes.
NativeReaderPillButton owns compact circular ghost/inline action geometry.
Notice tones select semantic symbols and colors explicitly. Ghost cell
replacement preserves target/action, key equivalents and native accessibility;
constraints account for AppKit alignment insets to retain actual 32x30pt bounds.

NativeFloatingCapsule owns ticket-bound action presentation and its keyboard
loop, with 54pt vertical tiles on 64pt glass, bottom-center at 16pt. Source and
Editor collapse at 640pt; red Strike uses the existing review owner. A 26pt
mini pill preserves exact PDF footnotes or, for more than 32 selected fragments, explains the existing 32-fragment remote-submission limit. Highlight, Ask, Source and Editor are unavailable; Copy remains available, and Strike remains enabled when review is available but can reject the over-limit selection. Writable
Reflow with review marks shows a separate 40pt Undo/Clear capsule. Host placement
uses Reflow's 104pt bottom inset and PDF's temporary bottom inset with existing
selection geometry to scroll ink clear. No selection path changes window.frame,
and no top dock or dock-height state remains.

Keyboard routing stays in the host via the toolbar's native key-equivalent path.
Shift+Return uses a reader-window-scoped local keyDown monitor before text inputs
consume the event; other windows retain their normal input routing.
Cmd+\ toggles the outline; Cmd+Shift+O opens and focuses it without closing an open drawer. Cmd+0 belongs to FlowApp Home; Opt+Cmd+0 resets zoom. Escape closes Find, outline,
Aa/logo, tools without releasing selection, then PDF selection. Explicit tool
reopen and action dispatch retain request-context and selection-ticket guards.
The PDF search field delegates Escape to this order before AppKit can invoke
the search cancel button; explicit cancel retains its existing release behavior.
Refresh while selected presents and focuses the explicit release action; release
does not implicitly refresh, and the user can repeat the refresh command.
No math placeholder/batch implementation or PDF printed ink is changed.

NRD01B verification is headless CLI and offscreen AppKit only. The self-contained
NativeDesignParityTests harness generates temporary semantic/PDF fixtures and
uses an isolated module cache without an external lock prerequisite. Its nine
cases cover drawer/focus/scroll, notifications/pass-through, brand/mode/toolbar,
bottom tools/review/tickets, existing and first review, horizontally offset document-end selection, pending Strike, and keyboard/PDF selection. This is source-component
verification; interactive GUI, actual OS13 and live installation are separate.

### Redesign boundaries and verification

Chrome and placement belong to `apps/macos/NativeReaderWindowController.swift`;
shared design controls remain in `apps/macos/NativeAppDesign.swift` and registration
in `apps/macos/sources.json`. Tests belong in
`tests/flow-app/native-reader-app/NativeDesignParityTests.swift` and
`tests/flow-app/native-reader-app/test_native_design_parity.py`; contracts and
checklists belong in `openspec/changes/implement-native-reader-app/`.
The exact commands and remaining independent acceptance gates are recorded in tasks.md.
