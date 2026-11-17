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
- `apps/macos/NativeReaderOperations.swift`: `NativeReaderRequestContext(requestID:UUID,viewID:UUID,generation:Int,target:NativeDocumentIdentity)`; `NativeReaderSelection(ticket:UUID,fragments:[Fragment])`, each fragment `{blockID,rangeUTF16:Range<Int>,exact:String}`, 1–32 distinct ordered top-level blocks; `validate(in:) throws`. Convenience single-fragment initializer also exists. Fragments preserve their exact text; joining or Typst copy is an explicit consumer operation, not an implicit source reconstruction.
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
metadata. RecoveryStore and Operations are unchanged. Evidence is newly compiled
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
