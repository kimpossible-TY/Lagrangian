# Spec Delta

## Purpose

Provide a loss-aware native reading document and guarded interaction contract while retaining existing compiler, source, conversation and authentication authority.

## ADDED Requirements

### Requirement: Ordered semantic snapshots
The reader SHALL retain accepted section order, exact Unicode scalars, headings, styles, links, mathematical structure and numbering, table cells and spans, figure assets and labels, and annotation anchors. Unsupported meaning SHALL reject the candidate with a bounded diagnostic instead of silently replacing content.

#### Scenario: Import an accepted compiler document
- **WHEN** an accepted document crosses transport section boundaries
- **THEN** native nodes retain logical order and distinct repeated-paragraph identities
- **AND** mathematical, tabular and graphical semantics remain available independently of paint support

#### Scenario: Preserve Unicode and mapping uncertainty
- **WHEN** composed, decomposed, supplementary or joined characters are imported
- **THEN** exact scalar sequences and explicit UTF8/codepoint/UTF16 maps are preserved
- **AND** selection uses extended grapheme boundaries and source correspondence remains explicitly unmapped until the source owner verifies it

#### Scenario: Unknown semantics or capability
- **WHEN** a candidate contains an unknown required capability, unsupported element, duplicate anchor or invalid offset
- **THEN** the whole candidate is rejected without replacing accepted content

### Requirement: Guarded native operations
Native operations SHALL bind document, service, revision, view, generation and selection ticket. Local correlation SHALL NOT replace server freshness, authorization or durable receipts. Source, chat, authentication and service lifecycle SHALL retain their existing owners.

#### Scenario: Late result or selected content
- **WHEN** a cancelled generation completes, another view responds, or replacement arrives during a held selection
- **THEN** the accepted native document remains unchanged
- **AND** acknowledgment for an old ticket cannot release a newer selection

#### Scenario: Uncertain mutation
- **WHEN** a source highlight or explicit chat Send loses its response after dispatch
- **THEN** its effect remains unknown and recovery queries the existing owner without automatically repeating the mutation

### Requirement: Native object evidence remains bounded
The reader SHALL distinguish object calculation, native paint, semantic fidelity, inline breaking, accessibility and GUI verification. Missing local helper dependencies SHALL remain blocked. Placeholder or PDF-only output SHALL NOT establish complete native reading support.

#### Scenario: Existing compiler object probe
- **WHEN** actual compiler SVG or PDF is decoded and painted on the host
- **THEN** evidence records compiler inputs, widths, primitives, native paint outcome and command exits
- **AND** untested formula fidelity, runtime compatibility, selection and accessibility remain explicit gates

### Requirement: Loss-aware image layout negotiation
Schema-1 snapshots SHALL preserve effective compiler image dimensions and units,
intrinsic aspect behavior, inline/block placement and validated loading/decoding
hints in typed image metadata. Snapshots using this meaning SHALL dynamically
require image-layout-v1. Unsupported CSS, units, values or incomplete metadata
SHALL reject atomically through import, transport and generic recovery decoding.

#### Scenario: Actual raw compiler image and labeled vector
- **WHEN** accepted compiler HTML includes sized PNG/JPEG images or symbol overflow
- **THEN** original attributes and digest-bound assets remain preserved
- **AND** native paint uses effective authored dimensions and inline/block order
- **AND** SVG visible/hidden symbol overflow retains the existing painter's clip semantics
- **AND** glyph paths do not acquire invented label-level source or accessibility text

#### Scenario: Old client and cached supplemented snapshot
- **WHEN** a semantic-tree-v1-only client requests a supplemented document, asset or action
- **THEN** the server explicitly rejects unsupported required capability even on a cache hit
- **AND** an old document without new meaning remains available to old and new clients

#### Scenario: Restore and rebind an image document
- **WHEN** a complete snapshot passes through HTTP, Codable disk recovery, session candidate or host fixture generation rebinding
- **THEN** every image supplement and required capability remains identical
- **AND** unknown fields, missing required metadata or invalid combinations fail without replacing accepted content

#### Scenario: A hidden symbol has distinct native instances
- **WHEN** hidden symbols use different viewports, viewBox origins, aspect alignment, transforms or nested clip references
- **THEN** the sole native SVG owner preserves each viewport clip with exact native pixel-mask evidence
- **AND** generated safe serialization retains reference identity without duplicate content IDs
- **AND** it revalidates generated nodes, depth, work and composed transforms before native decode
- **AND** unresolvable symbol viewport sizes are explicitly unsupported

#### Scenario: Compiler emits a base64 SVG image
- **WHEN** newly compiled accepted HTML carries a supported SVG base64 data image
- **THEN** the importer validates strict encoding, size, SVG references and content before publication
- **AND** original SVG asset bytes and authored image layout survive HTTP, recovery and native paint


### Requirement: Retained native presentation survives rejected work
The native reader SHALL separate retained layout authority from current request generation, preserve accepted body/selection/accessibility during held reflow, and reject stale geometry/source operations. Fallible candidate composition SHALL preserve the previously painted publication. Explicit close SHALL permit safe same-profile reopening without stale callbacks.

#### Scenario: Reflow while a newer candidate is held
- **WHEN** a new request completes while the accepted document is selected and layout inputs change
- **THEN** current-key preparation restores the retained document's native layout without adopting the pending candidate
- **AND** source operations continue rejecting stale/pending contexts until explicit release and fresh adoption

#### Scenario: Rejected candidate or closed selected window
- **WHEN** candidate B has missing/invalid object preparation after A was painted
- **THEN** A remains the published native body and accessibility document
- **WHEN** the user explicitly closes a selected window and reads the same profile again
- **THEN** the new request can complete and old close/cancel callbacks cannot cancel it

### Requirement: Local display selection and remote submission have distinct bounds
Ordinary native selection, hold, plain copy and accessibility selection SHALL support all accepted document blocks. Source/chat submission SHALL retain the existing 32-fragment and payload limits. Over-limit submission SHALL reject explicitly without copying or submitting an earlier short selection.

#### Scenario: Select a long document
- **WHEN** a user selects 32, 33 or 100 blocks through native range, Select All, drag, Shift or accessibility operations
- **THEN** plain copy and accessibility retain the exact full selected text
- **AND** more than 32 source/chat fragments are rejected before dispatch without releasing the display selection

### Requirement: Lost Send recovery uses identical actor and UI evidence
Authoritative history SHALL confirm a pending Send only when UUID, user role and exact stored content match. Confirmation SHALL permit a new message UUID/question. Missing/mismatched content SHALL permit only an explicit original UUID/question/model retry. Recovery SHALL never automatically send, and acknowledgment SHALL preserve newer private drafts.

#### Scenario: Confirm or retain an uncertain Send
- **WHEN** history contains the exact pending user message
- **THEN** adapter and UI clear the unknown state and allow a fresh explicit question
- **WHEN** history omits it or its role/content differs
- **THEN** a new UUID/question remains blocked and only the original explicit retry is permitted

#### Scenario: Recover through an explicit native control
- **WHEN** a pending Send blocks Send or a stream disconnects
- **THEN** the native Refresh conversation control permits an explicit read without inference or retransmission
- **AND** busy, cancelled, disposed, superseded, unauthorized or older history cannot clear pending state
- **AND** an absent conversation is reported as unavailable rather than completed
- **AND** recovery preserves the original bounded pending question/model separately from a newer local draft, with optional defaults for old snapshots

### Requirement: Block image placement reaches final native text layout
A supported block image SHALL have presentation line boundaries before and after its final TextKit attachment. These added boundaries SHALL NOT enter canonical/source text, plain copy or logical accessibility offsets. Inline images SHALL preserve inline placement when space permits.

#### Scenario: Prose surrounds a block or inline image
- **WHEN** an accepted paragraph contains before, image and after content
- **THEN** final native glyph line fragments place block image content on three ordered lines
- **AND** the inline control remains on one line while both preserve exact logical selections/copy/AX text

### Requirement: Original pages preserve reflow authority boundaries
Original PDF display SHALL compose the existing canonical store and prepared adoption. Display-only PDF text/bounds and offline PDF recovery SHALL NOT grant semantic source/chat authority. Hidden mode preparation or paint SHALL NOT acknowledge visible-mode Read success. Native reflow's retained layout and fresh source-operation guards SHALL remain intact.

#### Scenario: Enter original mode and return to reflow
- **WHEN** the reader switches between original pages and native reflow
- **THEN** each mode owns its geometry/selection and only its visible actual draw acknowledges paint
- **AND** source actions in original mode are explicitly unsupported while validated reflow actions keep their original path


### Requirement: Offline preparation uses explicit validated assets
Offline restoration SHALL pass the validated snapshot's assets explicitly through the pending candidate's existing fallible preparation and atomic adopter, including a fresh managed controller without accepted asset cache. Live target, document and asset closures SHALL remain unused and restored source/chat operations SHALL remain read-only.

#### Scenario: Restore assets with transport unavailable
- **WHEN** a valid compiler snapshot with objects is restored into a fresh offline controller
- **THEN** native preparation and adoption use only the validated captured assets
- **AND** invalid recovery assets cannot replace a previously accepted view or grant source/chat authority

### Requirement: Formula copy preserves token count and order
Plain copy of completed native math answers SHALL restore each selected formula's authored text once per selected attachment boundary, retaining order and multiplicity independently of adjacent attribute-string equality.

#### Scenario: Adjacent identical formulas
- **WHEN** two or more identical formulas are adjacent in a full or partial selection
- **THEN** plain copy includes every selected formula exactly once in order
- **AND** it does not merge equal formula strings or send inference


### Requirement: Reachable native local reading controls
The app SHALL expose local review add/undo/clear, typed Contents/reference Back and window-local theme/font/zoom through actual native controls. Controls SHALL delegate to existing local review, mapping, geometry and appearance owners without source writes or global settings changes.

#### Scenario: Review or navigate the accepted native document
- **WHEN** a native control marks, undoes, clears, navigates or changes appearance
- **THEN** the corresponding native pixels/viewport/render key change while logical copy and AX selection remain exact
- **AND** same-snapshot reflow retains review marks while accepted replacement/cancel revokes obsolete marks and return state

### Requirement: Reachable verified offline library
The app SHALL offer profile-bound save/list/open and a home offline entry without service startup. RecoveryStore SHALL own typed recovery; LayoutCache SHALL own disposable layouts. NativeReaderSnapshotStorage SHALL share schema/hash envelopes and atomic writes, with validation/budgets retained by each store. Offline restoration SHALL reuse native preparation/paint read-only, without live target/network/assets calls or automatic inference.

#### Scenario: Save and open an offline native document
- **WHEN** an accepted document is saved and opened through native controls into a fresh view
- **THEN** its validated assets and native-reflow normalized viewport, held selection, review marks and bounded pending/newer draft state are restored
- **AND** only matching native draw acknowledges paint while source/chat/account remain unavailable offline
- **AND** another profile cannot list/open that namespace

#### Scenario: Unsupported saved state or obsolete disk operation
- **WHEN** native-reflow selection exceeds32 fragments, native-reflow zoom is below0.5, bytes fail validation, or a disk request is cancelled/closed/superseded
- **THEN** the previous durable file is retained and the app does not claim successful save/restore from an obsolete callback
- **AND** the full ordinary local display selection is not truncated to make save succeed


### Requirement: Candidate-bound recovery attachments and current conversation state
The native host SHALL apply validated recovery attachments once at the same candidate's actual adoption completion, after restored selection, including layout retries and held release. Pending recovery SHALL remain cancellable. Initial recovered drafts SHALL be consumed separately from current conversation drafts maintained through existing persistence callbacks.

#### Scenario: Recovery preparation changes while A is accepted
- **WHEN** resize/font changes or a new selection holds B during its preparation
- **THEN** A remains accepted until explicit release permits B's actual adoption
- **AND** B's marks, pending/newer draft fields, zoom and viewport attach once to B; cancel/close cannot replay them on A or a later request

#### Scenario: Reopen a confirmed conversation with a newer private draft
- **WHEN** exact history confirms pending M and the user edits N2 then reopens the same conversation
- **THEN** N2 and its model survive and the resolved pending UUID/question/model do not resurrect
- **AND** only explicit Send can infer

### Requirement: Reachable local display preview and original PDF export
The reflow reader SHALL expose Light/Dark/Automatic and font/zoom preview, cancel and apply controls through its existing render-key and viewport owners. Automatic SHALL inherit only the reader window. Export PDF SHALL atomically publish the exact accepted Original PDF bytes through an explicit native action and save chooser.

#### Scenario: Preview, cancel and apply reading appearance
- **WHEN** the user previews appearance changes then cancels or applies
- **THEN** cancellation restores the previous window-local appearance and renderer anchor/selection, while apply commits current prepared layout
- **AND** PDF print colors/glyphs, source mappings and global OS settings are unchanged

#### Scenario: Export current original bytes or reject an obsolete choice
- **WHEN** the user explicitly exports the accepted Original PDF
- **THEN** the same publication/input/digest bytes are validated, staged, PDFKit-reopened and atomically saved after current snapshot/operation checks
- **AND** cancel/stale/dispose/tamper/invalid destination or an observed precommit directory identity/metadata fingerprint mismatch rejects publication and preserves the previous file in those paths
- **AND** same-metadata content changes and an external rename after that check have no atomic compare-and-swap guarantee
- **AND** PDF recovery scale remains separately bounded to0.1–8 by its geometry/raster budgets
- **AND** offline PDF recovery stores only identity/digest/page/scale/unscaled offsets, does not store PDF selection, and does not enable offline mode switching

### Requirement: Explicit native editor movement has a separate effect receipt
The native reader SHALL distinguish verified source correspondence from actual
editor movement. Locate Source SHALL compose the existing saved-source mapping,
private service-bound attachment and final Neovim jump owner, with zero source
writes. FlowApp SHALL require explicit local editor selection and consent without
process discovery, default opt-in or HTTP registration authority.

#### Scenario: Explicit move to compiler-verified saved source
- **WHEN** a current native selection requests Locate Source through a consented managed editor
- **THEN** production local HTTP dispatches only to its exact locally registered executable/address
- **AND** jumped is reported only after the existing editor owner returns jumped
- **AND** mapping-only locate retains its previous result contract
- **AND** private source coordinates, paths, hashes, address and token remain outside product feedback and accessibility

#### Scenario: Changed source, attachment or view before effect
- **WHEN** source/input/service/view/generation/selection/request/consent/attachment or prepared source span changes, the owner/control lifetime ends, or a newer selection is invalid
- **THEN** pending work fails closed without guessing coordinates, overwriting buffers or releasing another selection
- **AND** native service restart requires new explicit editor consent
- **AND** a foreign attachment cannot close another view or change its pending selection

#### Scenario: Dirty buffer, duplicate UUID or lost acknowledgment
- **WHEN** the target has unsaved contents or the request's response is lost, cancelled or late
- **THEN** modified, stale, error and unknown effect remain distinct from jumped
- **AND** a private bounded receipt is committed before dispatch and a duplicate UUID never repeats the effect
- **AND** Check Editor Result performs a bounded read without automatic redispatch
- **AND** another dirty buffer, source bytes, user editor lifetime and other attachments are preserved

#### Scenario: Independent headless and GUI acceptance
- **WHEN** the native action is exercised against an isolated compiler/production HTTP/actual Neovim fixture
- **THEN** an independent raw editor RPC oracle verifies file, one-based line and zero-based UTF-8 byte column (range and UTF-8 character-boundary checked by the existing private owner) plus unchanged buffers/source bytes
- **AND** injected transport faults, fake callbacks and actual effects are identified separately
- **AND** headless success does not complete real native interaction, visual or OS runtime acceptance

#### Scenario: Movement consent cannot authorize a source writer
- **WHEN** a native movement-only attachment is supplied to an existing source-write endpoint or the native Highlight operation
- **THEN** the attachment/source adapter refuses it before any source or buffer write
- **AND** legacy terminal source-write attachments retain their existing explicit contract
- **AND** host close/dispose revokes native consent even during pending managed resolution while document reopening remains possible

#### Scenario: The same token names a replaced registration after movement
- **WHEN** an effect receipt is read or its prepare/jump is duplicated after registration address/file or control-file replacement
- **THEN** its persisted pre-effect registration fingerprint fails and the result remains unknown without redispatch to either editor
- **AND** an older database row without the fingerprint also remains consumed and unknown

#### Scenario: Local movement proof and actual offscreen controls
- **WHEN** HTTP supplies a consent UUID with a legacy token or a nonboolean nativeJumpOnly marker
- **THEN** native synchronization is unavailable and performs no effect, while existing legacy writes retain their explicit contract
- **WHEN** prohibited-activation hidden-window AppKit selects text and invokes Locate then Check Result after a lost response and repeated Locate
- **THEN** production callbacks query the original receipt UUID without another jump
- **AND** a raw independent editor oracle verifies actual file/line/UTF-8 column and preserved buffers/source bytes
- **AND** this evidence is reported separately from real GUI acceptance


### Requirement: Live Read environment and display transitions retain their owners
The app SHALL separate initial storage completion from native readiness. Dev-root tracing SHALL record values only in its isolated root without retaining the app or changing guards. Environment events SHALL reach only a current explicit native Read ticket/profile/generation. Native Session SHALL own interruption, retained read-only content and bounded constrained-power retries.

#### Scenario: Preview baseline crosses a new accepted snapshot
- **WHEN** a previewed theme is retained by a new accepted snapshot and a later font preview is cancelled
- **THEN** menu, window, render key, viewport and the next preview baseline agree on the retained display

#### Scenario: Automatic returns from Original PDF
- **WHEN** this window's effective appearance changes during Original PDF and Reflow is selected
- **THEN** the Reflow preparation resolves current Automatic colors in either direction without recoloring the PDF or changing global appearance

#### Scenario: An environment event has no live Read intent
- **WHEN** an unread profile, closed/cancelled view or disposed request receives an event
- **THEN** the app SHALL NOT start reading, infer, restart a service or adopt a late result

### Requirement: Optional editor failure preserves valid body actions
New selection SHALL revoke old pending editor work before optional synchronization. Valid accepted body selection SHALL remain usable for Source, mapping-only locate and Ask when editor ownership, control/registration or sync transport becomes unavailable. Actual editor Locate SHALL fail unavailable; true stale document/input/context and invalid selections SHALL remain rejected.

#### Scenario: Editor disappears after a prepared selection
- **WHEN** the editor owner exits, its control/registration disappears, or sync transport fails before a valid newer body selection
- **THEN** Source and Ask use that newer selection with zero editor effects and no reuse of the old pending jump

### Requirement: Native registration has an exact local lifetime
The native resolver SHALL retain its manager-issued lease through resolution and retire only its own native token on disconnect/dispose/replacement or failed/cancelled/superseded/late resolution. Existing local owners SHALL preserve other tokens, control/editor/service lifetimes and the32 quota; HTTP SHALL NOT delete arbitrary paths.

#### Scenario: Native attach fails before the manager response
- **WHEN** timeout, cancellation, exception, lost/late response or manager termination occurs after registration but before plan adoption
- **THEN** the pre-existing caller operation lease SHALL withdraw only its durably bound registration
- **AND** the existing local owner SHALL atomically publish only a complete record, reject collision/replacement and preserve other native/terminal registrations and service/editor/source state

#### Scenario: Cleanup cannot confirm absence yet
- **WHEN** exact local cleanup fails under lock contention or command failure after resolve throws
- **THEN** the shared production caller owner SHALL retain that exact pending operation for a subsequent explicit bounded connect/Read/close retry without an externally supplied nonce
- **AND** confirmation alone removes the lease; no scan or automatic retry loop SHALL revive effect authority

#### Scenario: Pending editor retirement does not revoke body authority
- **WHEN** a previous editor operation remains pending under local manager lock contention and an editor-free explicit Read resolves the same accepted document
- **THEN** body, verified Source and Ask SHALL remain available without retrying or confirming editor retirement and without editor consent or movement authority
- **AND** a subsequent new consented editor grant SHALL still require exact pending recovery by the retained production caller

#### Scenario: Preparation and state confirmation share a caller budget
- **WHEN** native attach, pending retry or follow-up HTTP state is slow
- **THEN** the resolver SHALL include pending retry, prepare/ack, state validation and cleanup in its ten-second budget, shorten subcall deadlines and reject late success while reserving cleanup time
- **AND** process cancellation SHALL wait for only the owned manager process; it does not imply shared-service rollback or OS real-time scheduling guarantees

#### Scenario: Current source component has bounded recovery scope
- **WHEN** assessing the new operation-backed native production path against historical299
- **THEN** the old resume2 timeout/SIGKILL leaks and desired exit1 SHALL remain historical evidence, not be overwritten
- **AND** actual malformed-journal, crash, deadline and production pending-client witnesses SHALL be bound in external `native-reader-identity-ui-v5/resume5-handoff.md`
- **AND** explicit known-operation local recovery after an entire app crash SHALL NOT be presented as automatic app-restart recovery; journals remain retained without automatic pruning
- **AND** compatible legacy direct native-consent without operation remains response-token-only, while production FlowApp supplies the operation and final App/GUI/F10 acceptance remains separate

#### Scenario: Reconnect without consuming other registrations
- **WHEN** the same live editor reconnects and disconnects at least33 times, with concurrent terminal/native registrations
- **THEN** its retired registrations do not accumulate and the other tokens and editor remain intact

#### Scenario: Jump already waits at the effect gate
- **WHEN** a transmitted jump waits at the real edit_lock and a newer invalid selection or explicit cancellation revokes its lease
- **THEN** releasing that gate cannot execute the old movement or adopt its obsolete acknowledgment



### Requirement: Explicit local descriptor provenance remains private
The local manager SHALL export only the four explicit chooser fields from a live private existing editor registration. The native chooser SHALL require explicit selection and consent; HTTP SHALL NOT register editor executables, addresses or arbitrary paths.

#### Scenario: Choose the manager-provided editor descriptor
- **WHEN** the user exports a registered editor descriptor locally and explicitly selects that generated private file
- **THEN** the existing descriptor validator and consent owner SHALL bind the same live editor identity without source-write or account authority


#### Scenario: Slow-drip final state response cannot extend native lifetime
- **WHEN** the final state response continues delivering bytes past the operation deadline
- **THEN** the actual owned URLSession request SHALL be cancelled and its termination awaited with cleanup/grace remaining inside the caller budget
- **AND** late response data SHALL NOT adopt a plan or preserve its exact native registration

#### Scenario: Issuance alias is removed, renamed or retargeted before withdrawal
- **WHEN** a known native operation is withdrawn after its original root/entry alias changes
- **THEN** the local owner SHALL validate the stable original request/reader binding and private registration digest/inode without resolving the alias again
- **AND** fresh attachment validation SHALL still require the current actual registered document and unchanged service/source guards

#### Scenario: Equivalent document spelling cannot bypass pending retirement
- **WHEN** a new consented native editor grant uses equivalent spelling or a supported alias of a document with pending cleanup
- **THEN** the resolver SHALL use the existing manager's verified registered document/reader scope to block that grant until exact cleanup confirmation
- **AND** it SHALL retain original withdrawal arguments, preserve independent document/reader scopes and leave editor-free body/Source/Ask authority independent


### Requirement: Managed canonical-equivalent paths preserve registered authority
The manager SHALL accept canonical-equivalent resolved Unicode root/entry only
when the actual existing directory and regular file identities and project scope
match the registered document. It SHALL return the original registered profile
without migration, retain ambiguity rejection and exact explicit service ID,
and SHALL NOT equate different-root or differently named hardlinks by inode alone.

#### Scenario: NFC and NFD name the same registered filesystem objects
- **WHEN** supplied root and entry have canonical-equivalent Unicode spelling and the same actual objects
- **THEN** the existing attachment/document/service and source guards use the unchanged registered profile
- **AND** different files, escaping symlinks, missing paths, wrong types and ambiguous unselected registrations remain refused

#### Scenario: Source disappears before native lease retirement
- **WHEN** the exact manager-issued native token is retired after its source is renamed or deleted
- **THEN** the local withdrawal-only path may reuse its bounded private registration data to retire only that token
- **AND** it SHALL NOT approve a new attachment/descriptor, modify another token, stop an editor/service or grant source authority


### Requirement: Native reading hierarchy preserves command reachability
The native host SHALL keep mode, outline and search in a stable primary area and
retain auxiliary source/review/display/offline/account commands through a
keyboard-accessible scrollable disclosure. Existing selectors, enabled guards,
consent, source/account and persistence authority SHALL remain with their owners.

#### Scenario: Collapse a focused auxiliary command
- **WHEN** the user closes the auxiliary area while a child owns focus
- **THEN** focus SHALL return to the disclosure trigger, the current mode SHALL remain identified and the hidden commands SHALL remain reachable by reopening it

### Requirement: Visible mode and pending intent remain distinct
Native status SHALL distinguish the accepted visible mode from requested mode,
explain actual selection holds with explicit release/reattempt, and prioritize
failure/retained-result/refresh guidance over a pending preparing message.

#### Scenario: Requested Original PDF fails while body remains visible
- **WHEN** an Original PDF request fails before successful adoption
- **THEN** status SHALL identify the retained body and requested PDF, explain the previous result and explicit refresh action, and SHALL NOT imply indefinite preparation or automatically approve a mode

#### Scenario: Search query remains after display selection release
- **WHEN** the user explicitly releases a PDF hit's actual display selection and requests another mode
- **THEN** the query text alone SHALL NOT be treated as selection authority and existing transition/freshness guards SHALL decide adoption

#### Scenario: Recovered copy receives refresh target action
- **WHEN** a restored offline copy is displayed
- **THEN** the refresh control SHALL be disabled and its callback SHALL preserve the copy without live target/document operations or new authority


### Requirement: Native editor issuance binds queried manager scope
The managed native caller SHALL provide its queried expected scope with the
operation. The manager SHALL reject mismatching actual registered document/reader
scope before reservation or registration, including when no response is received.

#### Scenario: Alias changes after scope query
- **WHEN** the caller queries A and its alias names B before attach
- **THEN** the expected-A operation SHALL NOT publish a B registration
- **AND** pending exact cleanup SHALL keep its original caller binding without granting new authority

### Requirement: Original withdrawal expression preserves symlink semantics
The manager SHALL retain symlink-sensitive dot components in the original caller
expression and use actual registered scope for document equivalence.

#### Scenario: Independent documents separated by a symlink and dotdot
- **WHEN** `link/../main.typ` resolves to B while `main.typ` resolves to A
- **THEN** their request bindings SHALL remain distinct and B pending cleanup SHALL NOT block independent A
- **AND** original alias disappearance or retarget SHALL NOT prevent exact own withdrawal

### Requirement: Minimal unified reflow toolbar and immediate appearance popover
The native reflow reader SHALL present one toolbar row with a ghost outline toggle, sliding mode pill, SF Symbol search and overflow buttons, and opaque immediate Aa popover. Paper SHALL extend to both window edges. Valid selection actions SHALL float at the viewport bottom without resizing the window. At 640pt Reflow SHALL retain an icon-only outline toggle and compact mode switch.

#### Scenario: Unified toolbar, immediate Aa popover, selection capsule, and narrow width
- **WHEN** the reflow reader renders at standard or 640px narrow width, opens `Aa`, or transitions between empty and valid text selection
- **THEN** the single-row toolbar omits any subtitle, keeps 85–90% document area, and collapses secondary items into `•••` at 640px
- **AND** `Aa` renders an opaque popover with immediate theme/font-size/`오프라인 저장`/`PDF 내보내기` controls and no `보기 미리 보기/적용/취소` buttons
- **AND** `복사` appears in the bottom selection capsule; persistent held states expose an explicit `선택 해제` action when needed

### Requirement: Disposable owner-scoped viewed layout cache
LayoutCache SHALL be a disposable ownerID-scoped optimization in the existing profile-shared directory. Combined document/window/staging bytes SHALL be capped at 64 MiB with LRU eviction. Corrupt matching, unsafe and legacy entries SHALL be unlinked without affecting other owners. Cached copies SHALL stay read-only until current live identity/revision and layout inputs are confirmed.

#### Scenario: Save unchanged viewed content
- **WHEN** key, viewedBlockIDs and the layout key set match the last successful save
- **THEN** ordinary position changes do not rewrite the cache
- **AND** close/cancel immediate save persists the latest restoration
- **AND** the full document is stored separately at most once per retained identity/revision

#### Scenario: Filter before decoding and recover safely
- **WHEN** save or latest examines the shared cache
- **THEN** sha(owner)-sha(document)-sha(key) filenames filter candidates before decoding other entries
- **AND** corrupt matching or unsafe disposable entries are deleted without disabling valid cached content
- **AND** a cached copy cannot grant source, chat or editor authority
- **AND** NativeReaderViewedLayouts retains at most 256 successful viewed layouts

### Requirement: Current document and math batch bounds
Document JSON SHALL be capped at 64 MiB. Nodes SHALL preserve validated listItemNumber, percentage image dimensions and mark: anchors. Swift and the mathml-batch helper SHALL share the bounded item/byte contract below. Batch timeout/stdout SHALL scale within bounded caps. Timeout/budget/input-limit retries SHALL halve chunks within one shared deadline; a failing single item or output-limit SHALL terminate.

#### Scenario: Retry a large math batch
- **WHEN** a batch exceeds its time or byte budget
- **AND** helper limits are 1–512 items, 64 MiB batch input/output, 256 KiB item input, 65536-byte source and 8 MiB item output
- **THEN** preparation retries smaller halves in order without publishing partial results
- **AND** a failing single-item chunk stops rather than retrying indefinitely
- **AND** all attempts share a deadline of twice the initial chunk timeout, each child timeout fits the remaining time, and snapshot preparation stays atomic if any sub-range fails
- **AND** a helper output-limit error fails immediately without re-splitting

#### Scenario: Preserve current wire semantics
- **WHEN** a valid accepted snapshot includes ordered list numbering, percentage image dimensions or mark: anchors
- **THEN** import, decode and recovery preserve those values under the 64 MiB document cap
- **AND** invalid values or duplicate anchors reject atomically

### Requirement: Native outline drawer and active section
The reader SHALL use NativeOutlineDrawerView as a glass overlay below the toolbar, mutually exclusive with Aa and logo popovers. The outline toggle SHALL show a truncated active section title above 680pt and only its icon at or below 680pt. Empty outlines and Original PDF SHALL disable navigation.

#### Scenario: Keyboard outline navigation and dismissal
- **WHEN** the user presses Cmd+Shift+O in Reflow with headings
- **THEN** the drawer focuses its table and tracks the viewport baseline plus 96pt
- **AND** arrows move rows, Return or Space navigates and returns body focus, and Escape restores prior focus without clearing selection
- **AND** the drawer uses a rounded glass panel and a content-only scrim

### Requirement: Centered pass-through notification capsules
Notice and status overlays SHALL use content-sized centered NativeFloatingGlassView capsules, at least 160pt wide and at most min(520pt, contentWidth minus 48pt), 10pt below the toolbar. NativeOverlayPassThroughStack SHALL pass empty-margin hits through. Persistent states SHALL suppress lower-priority notices and never auto-dismiss or steal firstResponder.

#### Scenario: Persistent held selection or recovery failure
- **WHEN** a mode request is held, an operation fails, or recovery offers retry or cancel
- **THEN** a semantic icon and 24pt inline action pills explain the next operation
- **AND** an explicit circular xmark dismiss control has a 28pt hit target
- **AND** ordinary reading clicks outside painted capsules reach the document

### Requirement: Bottom selection tools preserve renderer authority
NativeFloatingCapsule SHALL use a 64pt glass surface with 28pt continuous corners, centered 16pt above the viewport bottom and no wider than min(560pt, viewportWidth minus 32pt). Vertical 54pt tiles SHALL show 17pt symbols above 11pt medium labels. Selection and deselection SHALL never change window.frame; renderers SHALL reserve bottom insets and reveal selected ink above the tools.

#### Scenario: Reflow selection actions and review strikes
- **WHEN** a valid Reflow selection is active
- **THEN** available tiles are Copy, Highlight, Ask, red Strike, Source and Editor, with Source and Editor in overflow at 640pt or narrower
- **AND** a rule divider precedes the circular dismiss control, which preserves selection and restores focus
- **AND** review marks in writable Reflow show a 40pt upper glass capsule with Undo and Clear All, 8pt above the tools
- **AND** a 32-block limit uses a 26pt mini pill; stale bindings cannot act on newer tickets

### Requirement: Interactive brand and accepted mode switch
NativeBrandMarkControl SHALL open Home through FlowApp.showWindow on hold or rightward swipe and expose status, Home and Refresh on tap. NativeModeMorphSwitch SHALL keep its thumb on the accepted mode during asynchronous requests or held selections. Wide Reflow SHALL center a labeled 140x32pt pill; compact Reflow and wide online PDF SHALL use 80x32pt icon-only pills.

#### Scenario: Responsive PDF mode controls
- **WHEN** the reader displays online PDF at 640pt or less
- **THEN** the switch and disabled outline toggle collapse into overflow while page navigation remains centered
- **AND** offline PDF hides the switch and retains the exact `오프라인 PDF` badge
- **AND** existing reflowMode and pageMode selectors remain available with native radio semantics

### Requirement: Reader shortcut ownership and layered Escape
The reader SHALL route Cmd+backslash, Cmd+1/2, Cmd+Shift+O, Opt+Cmd+0, Cmd+R, Shift+Return, Cmd+Shift+S/H/K and Opt+Cmd+A to existing mode, outline, zoom, refresh, strike, highlight, Ask and capsule owners. Cmd+0 SHALL remain FlowApp Home. Escape SHALL dismiss Find, drawer, Aa or logo, tools retaining selection, then PDF selection, in that order.

#### Scenario: Capsule keyboard loop and reopen
- **WHEN** the user presses Opt+Cmd+A with a retained selection
- **THEN** the capsule reopens for the current binding and focuses its first available action
- **AND** Tab, Shift+Tab, Left and Right cycle only available visible actions
- **AND** refresh with a held selection focuses explicit selection release rather than silently replacing the document
