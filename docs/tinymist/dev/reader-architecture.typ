= Reader and application architecture

The repository maintains feature policy separately from renderer geometry, transport and service operations. Use this map together with scoped `AGENTS.md` files and current OpenSpec contracts. Update it when responsibility moves. A directory is justified by an existing implementation, not a planned empty extension point.

= Lagrangian web viewer

Lagrangian is the native macOS app and canonical product and feature contract. Lagrangian Web Viewer, in `tools/flow-reader/web/`, is its web-optimized projection. Both use the single `flow_reader` backend and `tools/reader-common` shared policy; renderer-specific presentation, geometry and transport remain with their adapters. Internal paths and protocol and packaging identifiers retain their existing names.

= Feature ownership

- Paragraph draft recovery: `tools/flow-reader/web/features/paragraph-chat/draft-recovery.js` owns a bounded tab-local copy of unacknowledged composer text and pending message identity. The controller reconciles it against host acknowledgment, presents recovered text for explicit saving or sending, and guards volatile edits when tab storage is unavailable. This copy contains no source context, conversation history or credentials; the host retains history and model-dispatch authority.

- Browser rendering: `tools/reader-common/rendering/scheduler.js` owns coalesced animation frames, asynchronous serialization, selection holds, debounce and cancellation/disposal. `tools/typst-dom/src/typst-doc.mts` supplies ordered document deltas, WASM rendering and its touch-selection adapter; HTML `web/rendering/math/renderer.js` supplies nearby MathJax composition, identities and current geometry checks. Completion runs after releasing the scheduler so navigation can enqueue another frame. Cancellation prevents obsolete completion and waits for running work before the next task; it cannot interrupt synchronous renderer calls. HTML figure label placement remains browser-local, while custom decorations and graphical relationships retain their validated server rendering path. Shared scheduling does not make these distinct renderers interchangeable or move Typst compilation to the phone.
- Selection: `tools/reader-common/selection/submission.js` owns pending-submission tickets and acknowledgment policy; `selection/press.js` owns the shared pressed-selection, deferred release and click-consumption lifecycle. Each reader captures its own native selection and binds DOM toolbar events in `features/selection/`. Concrete capture/update guards and action effects remain local; disposing the shared press state cancels pending release work. HTML `features/selection/` also owns copy composition, touch formula snapping and verified-excerpt caching; `flow_reader/services/source_mapping.py` owns the read-only accepted excerpt exposed by `/api/source-text`. HTML selection (`web/features/selection/controller.js`) bounds background formula excerpt prefetching (`MAX_PREFETCH_FORMULAS=128`, `MAX_PREFETCH_CONCURRENCY=4`), and the shared `MAX_SELECTION_SEGMENTS=128` per-fragment segment limit disables source highlight when exceeded in `web/features/selection/controller.js`, is enforced for `/api/highlight` in `flow_reader/services/source_highlight.py`, and is enforced in `NativeReaderService.fragments()` in `flow_reader/server/native_reader.py`. Copy policy never reconstructs source from rendered mathematics or compiles during the action.
- Source Highlight: `tools/reader-common/source-highlight/optimistic.js` owns immediate temporary paint lifetime through acknowledgment, accepted snapshot replacement, failure and disposal. Concrete `features/source-highlight/` renderers retain semantic DOM/page geometry; native selection releases after paint while submitted context remains guarded. HTML invokes its verified source action; the paged reader uses its preview protocol. Server-side source checks live in `flow_reader/services/source_highlight.py` and the existing Rust preview tool implementation.
- Legacy saved context: HTML retains the `/api/focus` compatibility protocol through `flow_reader/services/codex_context.py`; its retired saved-context frontend is removed. HTML Codex and editor navigation share `services/source_mapping.py`: it resolves accepted compiler-carried ranges and retains literal fallback. Paged preview retains `crates/typst-preview/src/focus.rs` and its existing source-position protocol. Both preserve service, source and revision validation without inventing PDF coordinates for semantic HTML. Saved records have no time-based expiry. The companion `apps/macos/tail-hosting-reader-focus.patch` owns cross-reader lookup: after resolving one project and entry document, it chooses the latest saved text before tap-only positions, identifies its reader and preserves stale/error evidence. It does not merge writers or select other documents by recency.
- Paragraph chat: HTML and terminal replace the saved-context UI with Ask through `web/features/paragraph-chat/controller.js`, reusing `features/selection/` capture and the accepted selection/source validators. `tools/reader-common/paragraph-chat/state.js` owns snapshot-safe view adoption and literal question/answer summary extraction. `geometry.js` owns HTML ink measurement, annotation-local capsule placement, bounded margin spill and collision checks. Attached conversations retain an inline logo annotation at every width. The concrete `content.js` adapter owns keyed message/context DOM, allowlisted Markdown token rendering and completed-answer base/AMS math through the existing MathJax loader. One shared read-only connection dialog links to the Homepage; composers retain independent model selection. Expanded panels reuse the same DOM beside the paragraph when actual margin space fits, or follow it otherwise; unresolved history remains accessible outside the canonical article. `services/paragraph_chat.py` owns UUID conversations, combined anchor evidence, private SQLite history/drafts, independent message lifetimes and bounded accepted-document search/read tools. `chat_auth.py` owns SIWC public-client PKCE, loopback consent, protected isolated registrations, signature verification through the fixed Node crypto helper, rotating refresh and revocation. `chat_provider.py` owns direct Responses SSE and the explicit function-tool loop. Neither exposes arbitrary paths or shell to the model. `chat_storage.py` owns private filesystem primitives outside source projects. HTTP retains origin checks and accepted document/service/revision checks; document account management is replaced by a configured Homepage link; document auth status/catalog remains revision-bound and read-only; HTTP checks the explicit loopback/configured HTTPS Host allowlist. The paged adapter is a follow-up requiring remote Rust verification; its existing saved-context UI is retained until then.
- Review strikes: `tools/reader-common/review-strikes/bounded-store.js` owns persistence limits and storage failure handling. Each `features/review-strikes/` adapter owns its mark format, geometry, invalidation and paint. Existing browser storage keys remain compatible.
- Navigation: `tools/reader-common/navigation/change-location.js` owns pending last-change policy. `navigation/reference-return.js` owns the single return origin, replacement/consumption, action visibility and click/disposal lifecycle used by both readers. Concrete `features/navigation/` modules capture/restore page coordinates or semantic anchors, validate navigation completion and retain native scroll anchoring, section loading and URL/history effects.
- Shared saved edits: `crates/tinymist-project/src/source_history.rs` owns bounded authored-edit policy; `source_history/store.rs` serializes project record transactions under a cross-process file lock. It selects an exact managed Flow profile or a deterministic root/entry record and preserves renderer-owned metadata. The paged `change.rs` owns palette fingerprints and coordinates using that store; `source_change.rs` preserves the upstream preview type names. The engine's `source-history` command exposes the same owner without compilation. HTML `services/source_history.py` invokes it before compilation and registers exact stable accepted source snapshots, so HTML-only sessions advance the common history. There is no separate HTML visual-edit chronology. `services/edit_location.py` validates saved source and resolves paths read-only, including the engine's `--path-only` lookup; `edit-location.py` exposes that result to Neovim. HTML `services/source_mapping.py` maps the range into accepted source carriers, and `server/state.py` publishes late navigation metadata without another compile. Neovim `reader.lua` performs asynchronous guarded restoration through its existing jump contract. Local editor marks remain fallback when no verified shared position is available.
- Editor synchronization: the paged `features/editor-sync/` adapter retains its originating-editor channel and protocol. The HTML terminal bridge delegates existing selection actions and guarded section navigation; `flow_reader/services/navigation.py` validates accepted snapshots and uses the same source mapping as Codex. `services/editor_sync.py` delivers final verified edits to Neovim. Only capabilities actually implemented by a reader are exposed.
- Appearance: each `features/appearance/` owns its actual theme mechanism. HTML CSS recoloring and engine-generated paged theme variants have different lifecycles. HTML `reading-settings.js` owns panel placement and dismissal for native popovers and their fallback; CSS supplies its preferred width, and `theme.js` owns the early palette, stored choice and theme controls. HTML `font-size.js` owns transient font previews, the original reading anchor, rollback and final preference persistence. `navigation/reading-navigation.js` coalesces live pinch updates into animation frames and signals preview/commit/cancel. Renderer adapters retain their interaction hold and resume against the final font rather than requesting server geometry for every movement.
- Session: `tools/reader-common/session/activity.js` and `activity.css` own the activity precedence, localized notice controller, selection-release interaction, wait feedback, visual-viewport placement and styles extracted from the paged reader. Both readers use this implementation. Concrete `features/session/` adapters retain document composition, connection lifetime and native signals: the paged engine's WebSocket/DOM events and native desktop/touch selection, or HTML HTTP compiler state, sequenced section publication and reading interactions. Paged `reading-recovery.ts` owns guarded full-frame viewport restoration using existing page fingerprints and navigation geometry; selected text holds replacement until explicitly released. HTML `features/session/recovery.js` owns bounded retry, online and page-lifetime signals; its transport bounds requests, and publication validates document, revision and service identity. HTML `features/session/status-logo.js` presents the approved toolbar mark and refresh action from that activity owner; offline/highlight details retain their original writers. Theme colors and toolbar offsets remain local. HTML mathematical and figure composition retain their own feedback.

The terminal frontend is a presentation adapter over the managed HTML Reader's service, actions, review storage and rendering. `flow_reader/services/manager.py` resolves exact canonical project/entry identity and retains the single managed launch plan, compiler/font/semantic-canvas/WASM settings and service lifetime. `services/editor_sync.py` owns locally registered private editor attachments bound to the current document/service and host/control-file lifetime; `services/selection.py` rechecks the attachment before the existing verified Neovim writer. HTTP cannot register an executable or address. Closing a view revokes only its own attachment, not the shared service. Explicit URL/fixed-editor attachment remains supported.

The supported terminal command remains `tools/flow-reader/terminal.mjs`; implementation lives under `terminal/`: `options.mjs` owns presentation argument validation and stable browser-profile identity, `session.mjs` validates editor-owned remote session arguments, `service.mjs` attaches through the HTML manager without constructing compiler arguments, `browser-session.mjs` owns dedicated Chromium state, `editor-bridge.mjs` connects saved-source navigation, `host.mjs` owns shared browser input/capture ordering and lifetime, `native-transport.mjs` owns full native-terminal modes, `editor-transport.mjs` owns versioned bounded Neovim frame/input pipes, `protocol.mjs` encodes the native graphics/input protocol, `sixel.mjs` decodes Chromium screenshot PNGs and encodes Windows Terminal's SIXEL frames, and `cli.mjs` composes their lifecycle and exclusive session attachment. `editors/neovim/lua/tinymist/reader.lua` owns optional editor commands, source RPC, native-pane launch and explicit private session preparation. Its default `reader_view.lua` owns the same-connection right-hand window, input, positioned TUI frames, geometry generations and disposal. `reader_terminal.lua` owns bounded Neovim `TermResponse` queries, recognized Windows SIXEL geometry and Kitty logical viewport selection. Neovim retains TTY input ownership; capability queries never stop/resume the TUI or change shell foreground ownership. The integration delegates reading actions instead of implementing another reader.

See #link("terminal-reader.typ")[the terminal Reader guide] for prerequisites, native terminal support and conservative source-navigation limits.

= Dependency direction

Concrete reader composition imports its feature adapters and shared policy. Shared policy never imports a concrete reader. Geometry, semantic positions and transport enter through explicit operations. Do not turn similar syntax into a shared abstraction when behavior differs.

Rust and Python implementations share externally observable contracts and test cases rather than a new universal runtime. Source Highlight writes verified source; legacy saved-context protocol records context without starting a turn, while HTML/terminal Ask opens a paragraph composer and Send explicitly starts inference; review strikes remain browser-local paint. Do not reintroduce the retired quotation library.

= Shared Reader host

`server/cli.py` composes one ReaderRuntime: Homepage at `/`, document states at
`/d/<reader-id>/`, registered native previews at `/p/<preview-id>/`, and
redirect-only old HTML-port listeners in the same process.
`home.py` is a compatibility alias for `serve.py --managed`; it no longer owns
an independent Homepage runtime. `server/routing.py` selects exact configured
IDs, strips only that prefix and delegates to existing document/Homepage handlers.
Relative APIs, allowlisted assets and offline workers retain document-local scope.
The managed `/d/<id>/paged/` entry redirects to its registered parent `/p/<id>/`.
Native engines retain their processes, protocols and original direct ports.

`services/manager.py` remains the inventory, compiler-plan and lifecycle owner.
The optional `shared` configuration maps all HTML profiles to one shared job and
prefixed URL. `document_arguments` retains each document's existing font, compiler,
source-history, focus and output settings. Terminal attachments validate the same
process PID and exact document identity. The runtime starts configured compilers
at service startup; Homepage requests themselves never compile or infer.

`services/homepage.py` projects the loaded manager inventory and document states
without probing or controlling launchd in shared mode. Group by parent ID, sanitize
names and source paths, and retain truthful empty/error/unavailable states. Paged
readiness is never inferred from HTML state. The host asset manifest is separate;
Homepage/account responses use no-store and have no offline fallback.

`services/home_account.py` owns ephemeral browser authority and CSRF, while one
shared ChatAuth owns provider credentials, PKCE, callback, refresh and revocation.
Injected conversation providers borrow this owner; closing a document cancels its
conversation work without cancelling shared OAuth. One process lease protects the
credential directory. Only OAuth login start and logout may use an explicitly
requested OAuth-only browser session without the per-start 0600 capability.
Cancel and privileged account-status reads retain the explicitly entered
capability and management session. Mutations retain session/CSRF, exact
Host/Origin, genuine 127.0.0.1 admin socket peer and no forwarding headers.
OAuth-only session rotation never grants management or account identity authority.

Paths on one origin are not a security boundary. Capability stays in Homepage
module memory, never URLs or browser storage; remote status remains sanitized.
Document account APIs are revision-bound and read-only. The separate optional
proxy ingress always denies account mutations, even with copied proofs. It serves
the same Homepage/document routes under the exact configured HTTPS origin.
TLS, Tailnet and viewer grants require separate activation; no per-viewer roles
or paged protocol migration is implied. See the terminal guide for launchd
migration, redirect-worker retirement and rollback without data migration.

= Shared preview transport

`server/preview_proxy.py` owns the fixed parent-profile ID/loopback-port registry,
HTTP forwarding, WebSocket handshake/relay, bounded buffers and connection disposal.
`server/routing.py` selects only `/p/<id>/`; unknown IDs, traversal and arbitrary
upstream destinations never select a connection. `server/cli.py` injects the
registered manager parent inventory and closes relays before Reader shutdown.
It never starts or stops engines. Homepage links preview-only profiles as well
as HTML parents, without claiming native readiness from HTML status.

The proxy checks shared Host/Origin before translating a valid Origin to the
engine's exact loopback origin. An allowlist removes cookies, provider/account
credentials, host proofs and forwarding headers. Editor-host `/_editor/` routes
and admin namespaces are unavailable through preview routes; viewer sockets
retain Origin. Existing Homepage loopback, capability, session and CSRF authority
is unchanged. Proxy teardown closes both socket ends without touching engine jobs.

The current embedded single-file client builds root and theme WebSocket paths.
Proxied HTML injects `web/preview-proxy.js` before client scripts to scope those
constructors, root-relative HTML/CSS assets and redirects to the registered prefix.
No global asset or theme catch-all is exposed. Opaque JavaScript, new engine
transports and future root ES-module imports are not broadly rewritten; they need
a prefix-aware frontend release. No Rust source edit is needed for the current
compatibility bridge, and engine rendering still needs remote/isolated validation.

Migration is additive: retain native launchd jobs, old URLs/ports and their direct
Origin settings. Normal Reader deployment activates the new paths. Registration
changes require Reader restart; a rollback restores the previous Reader bundle
without changing engines or credentials. Live activation, TLS/Tailnet and native
editor/device verification remain separate from isolated transport tests.

= HTML Reader package

`tools/flow-reader/{build,serve,manage,focus}.py` remain executable launchers. The maintained implementation lives in `flow_reader/`:

- `compiler/project.py` validates project inputs; `packages.py` prepares overlays; `build.py` compiles isolated snapshots; `dynamic.py` owns the incremental compiler process; `inputs.py` fingerprints bounded filesystem inputs.
- `compiler/audit.py` is the single owner of normalization order, content auditing and accepted diagnostics for isolated and incremental compilation.
- `compiler/execution.py` defines raw compile requests/results and the local CLI executor. `Project.execute` injects execution into base HTML, private source carriers and highlight HTML/PDF candidates; replacing execution does not replace the Python acceptance or source-write policies. Mobile executors must capture filesystem inputs before transmitting a job.
- `compiler/snapshot.py` captures bounded immutable dependencies, package manifests, explicit fonts and settings; candidate roots and maintained package overlays retain their current bytes. `compiler/pool.py` owns foreground worker registration, heartbeat leases, deadlines, reassignment, stale/duplicate rejection and native fallback. It never publishes documents or writes source.
- `crates/tinymist-web-compiler/` reuses the maintained compiler universe with a memory-only filesystem/package registry. `web/compiler/runtime.js` applies verified input changes to its persistent evaluator; `worker.js` isolates computation; `client.js` owns foreground registration, transport and termination on page lifetime changes. Server normalization, audits and source correspondence remain in Python. `server/compiler_assets.py`, the build script and installer own content-identified generated WASM delivery. See #link("web-computation.typ")[browser computation and measurement].
- `compiler/inputs.py` owns bounded workspace source enumeration, stat signatures, content fingerprints and read-only shadow inputs shared by accepted publication, source mapping and highlight verification. `compiler/source_map.py` owns isolated source carriers and matching their emitted ranges to accepted block identities/text. Distinct invocation carriers verify complete callout/figure containers for navigation, rejecting independent competing outputs. Carriers and candidate HTML never reach workspace sources or served documents; `document/sections.py` binds private selection ranges to passages and navigation ranges to accepted anchors. Context and editor actions retain the narrower selection map without compiling.
  Literal and computed labels remain attached to their original equations and
  invocations when inserting private carriers, preserving reference targets. `source_map.py` (`markup_ranges`) also emits `reference` carriers for `@label` references (with optional `[...]` supplements) while opaquely skipping `canvas`, `<ident>.canvas` and `html.frame` calls as well as Typst code keywords (`let`, `set`, `show`, `if`, `for`, `while`, `import`, `include`, `context`).
- `document/` owns HTML normalization primitives, figure identities, semantic passages and transport sections. `document/passages.py` (`PassageIndex`) records `equation_number_ranges` for non-excluded `.flow-equation-number` elements and exposes `in_equation_number` so `PassageIndex`, `CarrierPassages` and `MarkedPassages` share identical excluded-block, nested-tag and void-tag guards.
- `rendering/` owns each geometry format and `service.py` owns dynamic rendering cache/worker lifecycle. Browser `rendering/graphics/canvas-layout.js` owns pure measured figure placement shared by a dedicated Worker and its local fallback. `canvas-computation.js` bounds outstanding work and owns timeout, failure, document reset and disposal; `canvas-labels.js` owns DOM measurements and publishes only matching width/font/label measurements after selection holds release. `canvases.js` composes their lifetime. The Worker has no server publication or source-write authority.
- `services/accepted_snapshot.py` owns the captured accepted-document/input freshness contract used by verified source actions and saved-source navigation. Capture occurs under the existing publication lock; callers retain lock ordering and response/error policy. `services/selection.py` orchestrates source and Codex actions, while `services/navigation.py` resolves saved-source destinations. Source mutation, read-only mapping, focus record, common-history transport and managed lifecycle each have their own module. Revision-only locate and accepted-output geometry retain their distinct validation contracts.
- `web/features/source-highlight/intents.js` persists explicit, bounded requests under independent browser storage keys and retries their original identities after reconnect. `services/highlight_receipts.py` records payload digests and results durably; `selection.py` serializes receipt execution with verified source actions. An unfinished receipt is uncertain and never executes again automatically. Neither the queue nor a receipt bypasses document/service/revision/source validation, and background acknowledgments cannot dismiss a newer selection.
- `server/state.py` publishes accepted snapshots; `watch.py` coalesces saves; `http.py` handles the HTTP contract; `assets.py` validates static delivery.
- `server/offline.py` inventories accepted public sections/assets and versions the web app shell from the explicit asset manifests. HTML `web/features/session/offline-worker.js` owns complete snapshot downloads, atomic cache-pointer replacement and offline GET recovery. `offline.js` owns registration, save requests and page feedback. The last complete snapshot remains available after interrupted downloads, quota errors and revision changes; offline content never authorizes source writes. Static math chunks/fonts are cached for offline reflow, and unsupported dynamic geometry retains its online rendering path.

A failed compile retains the accepted document. Dynamic paint, selection actions and asynchronous acknowledgments continue checking document revision and saved inputs. Preserve the existing lock ownership and ordering when changing these boundaries.

= Asset and installation boundary

`web/assets.json` is an explicit route-to-file allow-list for first-party browser code. MathJax retains its separately reviewed vendor manifest. The server does not expose arbitrary filesystem paths. `web/reader-common` links the shared source directory; immutable release archives include both `tools/flow-reader` and `tools/reader-common` so the same relative imports resolve after installation and behind the Reader origin. `scripts/package-reader-bundle.py` and `scripts/reader_bundle.py` own the CI reader bundle (`reader-bundle.json`, per-file SHA-256, `bundleChecksum`); `scripts/fetch-reader-bundle.py` verifies and stages it, and `install.py` rechecks the copied trees against that manifest. The Mac updater installs the reader from that bundle, not from a local checkout.

Changing a file path requires checking imports, test fixtures, build inputs, static routes and release packaging. Verify the installed layout with the installation test; source-tree success alone does not prove deployability.

= Engine compiler

`crates/tinymist-project/src/compiler.rs` is the public facade. `compiler/artifact.rs`, `report.rs`, `coordinator.rs`, `instance.rs` and `execution.rs` own compile data, reports, event coordination, instance state and execution respectively. Existing `scheduling.rs` and `eviction.rs` retain task lifetime and cache policy. Private tests live under `compiler/tests/`, including lifecycle, cache, filesystem and matrix fixtures.

The pinned `vendor/typst/` core owns layout convergence. Its `src/history.rs`
retains shared HTML/paged introspectors between attempts, releasing previous output
containers; other output types preserve their original lifetime. All introspection
iterations remain available for failure diagnostics. This is independent of the
process-wide memoization eviction policy. See `vendor/typst/FLOW-PATCH.md` for
upstream provenance and #link("layout-history.typ")[layout history verification].

Keep public crate APIs and revision/handler ordering stable. A completion belongs to its original task ticket; moving tests must not require public implementation fields.

= Native application

`apps/macos/sources.json` is the single explicit source list shared by packaging and tests. Profile validation, environment paths, settings storage, command execution, LaunchAgents, engine launch, CLI and AppKit each have a dedicated source. `ProjectService` owns project creation defaults, profile selection/persistence and validate-before-stop updates/recovery; its injected collaborators let tests verify failures without running the user's services. UI callbacks gather inputs and adopt successfully saved settings returned by the service; failed creation/selection preserves prior UI settings. `LaunchAgentService` produces the executable arguments once for both plist generation and ownership checks.

`ReadingSessionController.swift` owns asynchronous service requests, serialized settings mutations, readiness deadlines, cancellation, stale-result guards and power-aware status polling. `PreviewReadiness.swift` verifies document availability through the existing loopback WebSocket protocol; HTTP success or command acceptance alone does not establish readiness. `NativeReadingEnvironment.swift` adapts AppKit sleep/wake notifications, network path changes, power-source changes, Low Power Mode and thermal state to that policy, and disposes its observers with the app. FlowApp routes those events through the
ReadingSessionController explicit native Read ticket to NativeReaderWindowController
and NativeReaderSession; the native owner retains accepted content and controls
its own interruption/retry/backoff. Closed/cancelled/offline copies and unread
profiles do not recover through live transport. The original main/delegate lifetime structure is preserved; its offscreen
startup completes. A dev-root-only value timeline records the storage worker and
main completion without changing generation/disposal guards or retaining the app. AppKit owns controls and accessible inline feedback; it never performs blocking process or settings operations in an event callback. Body rendering and reading-state recovery remain with the concrete readers described below.

= Native cross-project references

`CrossProjectReference.swift` owns read-only CrossProjectCatalog identity/profile
resolution, bounded CrossProjectSnippetExtractor excerpts and
CrossProjectNavigationStack return locations. Swift remains the semantic owner.
WV02C adds a conforming read-only Python web adapter below; `apps/macos/`
is unchanged, including native session adoption and editor consent.
`NativeCrossProjectPreviewPopover.swift` owns NativeCrossProjectPreviewView and
its shared floating surface, icon/body activation and presentation.
NativeReaderTextView owns semantic link geometry and exact location capture;
NativeReaderWindowController owns preview lifetime, guarded async snippets and
anchor/block/scroll restoration. Explicit ambiguous references suppress
activation; unresolved references use only the original safe external URL.

FlowApp composes profile matching, the existing managed client's target-document
load and transactional window adoption. First-click snippets may start the target
reader service through ReaderManager; only committed second-click navigation
replaces the origin and pushes history. Back uses the fixed `돌아가기` action,
skips deleted profiles and restores the next valid entry. New explicit Read and
profile selection reset history. Candidate editor reservations commit at
windowInitialized and return on failure/cancel only before consented attach,
without replacing origin tracking. Starting attach consumes the reservation;
disposal retires it and later attempts require fresh consent.
Existing source, service and consent owners retain authority.

The Typst HTML producer `packages/local/flow-reader/0.1.0/lib.typ` exports user
labels on headings/figures/equations; `document/content.py` normalizes label-only
wrappers and `document/sections.py` retains label anchors separately from DOM ids.
`document/native_document.py` validates optional link projectRef metadata and
rejects invalid-project-ref/duplicate-anchor candidates. There is currently no
separate projectRef capability; strict old decoders require coordinated app and
backend delivery.

= Validation

Run `yarn test:readers` for the shared Node, HTML Node, Python, paged and DOM Vitest gate after changing a shared feature. Use actual Typst integration fixtures with `FLOW_READER_PACKAGES`; verify frontend build and browser interactions when moving browser code. Run project compiler warning-denying tests/clippy and native app tests for their changes. Development builds and fixtures use temporary projects and do not install or restart the user's services.


= HTML local mathematical paint

The maintained mannot `src/reader-paint.typ` exports explicit supported primitive
descriptions; `local/flow-reader` supplies resolved cancellation properties.
HTML `web/rendering/math/decoration-paint.js` validates those descriptions and
creates per-fragment SVG/layout values from measured geometry. The existing
`MathDecorations` controller owns capability choice, interaction holds, paint
lifetime, annotation anchors and server fallback. Point/em units stay explicit
until the current reading font is known. Unsupported callbacks and styles retain
`flow_reader/rendering/decorations.py` and its validated dynamic compiler/cache.
This HTML-specific drawing code does not enter reader-common or the paged reader.

= Device computation verification

HTML compiler/pool.py owns public connection identities, bounded execution evidence
and pinned leases. compiler/diagnostics.py compares explicit device checks against
native execution of identical immutable inputs without publication.
web/compiler/diagnostics.js presents readiness, results and recovery in reading
settings. Raw completion and server adoption remain distinct events.

Device diagnosis also retains the latest bounded worker phase and heartbeat timing.
client.js owns optional tab-local public-identity checkpoints; the pool correlates
client-reported recovery with recent pinned failures. Runtime phase observations
do not transfer publication authority or expose source bodies.

OfflineReader also owns waiting-shell update notification and explicit activation.
The Service Worker activates only on that request, and the page reloads after
controller change. Compiler diagnostics require the current declared evidence
contract before dispatch; ordinary execution retains legacy compatibility.

= Native original PDF pages

`server/native_pages.py` owns immutable full-PDF publications over AcceptedSnapshot
and Project.execute, including stable HTML/PDF dependency bindings and scoped
manifest/resources. The existing HTTP owner retains Host/Origin/prefix guards.
`NativeReaderOriginalPageTransport.swift` validates that service publication;
`NativeReaderOriginalPageView.swift` owns viewport paint, display selection,
search and explicit safe URI/GoTo callbacks. The private PDFKit worker/cache and
safety scan remain in `NativeReaderPagedLayout.swift`. WindowController composes
both native modes through Session.PreparedAdoption and the canonical semantic
store. Session holds replacements for local page selection independently of
semantic/source selection. NativeReaderRecoveryStore owns typed recovery with an
optional bounded accepted-PDF/viewport supplement. NativeReaderLayoutCache owns
disposable viewed layouts; both use NativeReaderSnapshotStorage for schema/hash
envelopes and atomic disk publication. PDF text and
coordinates never supply source authority. Full reset is implemented; engine raw
diff-v1 native consumption is unverified. Packaging/source registry remains the
delivery owner's responsibility; headless paint is separate from GUI acceptance.


= Native reflow and original-page ownership

#table(columns:(1.5fr,3fr),inset:4pt,align:top,
 table.header([Existing owner],[Responsibility]),
 [`NativeReaderTextView` / `NativeReaderSelection`],[Native body, logical↔presentation mapping, grapheme selection, ordinary copy, geometry and semantic AX.],
 [`NativeReaderSession`],[Newest candidate, request/selection hold, retry and read-only typed recovery/cached-copy promotion through one atomic adopter.],
 [`NativeReaderRecoveryStore`],[Typed offline document/assets/restoration/draft/review/PDF validation, profile namespace and recovery budgets.],
 [`NativeReaderLayoutCache` / `NativeReaderViewedLayouts`],[Disposable ownerID-scoped, profile-shared 64 MiB disk LRU and a bounded 256-layout in-memory viewed working set; hashed filename filtering, separate per-revision document and window storage, identical-content write suppression and immediate close-position flush.],
 [`NativeReaderSnapshotStorage`],[Shared schema/SHA-256 envelope encode/verify, optional bounded compression and descriptor-relative O_EXCL temporary write, synchronization, rename and directory fsync; callers retain typed validation and budgets.],
 [`NativeReaderTransport` / `NativeReaderActions`],[Accepted input binding, scoped HTTP/assets, source receipts, exact conversation history and cancellation.],
 [`NativeReaderObjectRenderer` / `NativeReaderPagedLayout`],[Math/object preparation and native pixels; serial PDFKit access, page geometry and bounded lazy caches.],
 [`NativeReaderChatView`],[Native composer, completed-answer TeX preparation, attachment/token copy boundaries and pending-Send UI.],
 [`NativeReaderOriginalPageView`],[One current PDF page's viewport, display selection, AX ranges/links and deferred Find/GoTo reveal.],
 [`NativeReaderWindowController`],[Compose those owners and explicit validated offline assets, separate visible modes, acknowledge matching actual paint.],
 [`document/native_document.py`],[Import only existing accepted SectionBundle publication; preserve source/auth/chat/security owners.],
)
See #link("native-reader-app-contract.typ")[wire/local/recovery contracts],
#link("native-reader-original-pages.typ")[PDF limits] and
#link("native-reader-chat-math.typ")[answer math]. The final source list includes
the page view/transport at historical staged09c5186b. The current frozen
source/App is d7cd069f2249a405061bf220cfd7e0184f75c7fe, bound by the external
DevSSD `test-output/native-app-corrections-v4/final-binding.json` and handoff.
The v5 successor is a source-only component, not registered or packaged into that
App. PM integration and new delivery binding remain required after its fixed SHA;
no common writer, credential owner or framework is introduced here.


= Native local interaction composition

FlowApp composes NativeReaderWindowController with profile/target-namespaced
RecoveryStore operations from AppEnvironment. Its separate explicit offline
library action never starts a live service or resolves an attachment. HostWindow
owns native controls and delegates policy to TextView (outline/reference return,
appearance, normalized viewport), NativeReaderLocalReview (bounded mark history)
and RecoveryStore (typed list/load/save, hashes, privacy and recovery budgets).
NativeReaderLayoutCache separately owns disposable layout persistence in the
existing shared directory with ownerID scope. NativeReaderViewedLayouts records
only successfully prepared viewed objects. NativeReaderSnapshotStorage shares
envelope verification and atomic writes between these stores. Corrupt matching,
unsafe and legacy disposable cache entries are deleted; read-only cached-copy
promotion remains guarded by the session's live publication and layout inputs.
TextView paints local review lines through its current-key range geometry;
logical text, source mappings and accessibility offsets are unchanged. The
controller serializes local storage actions, cancels obsolete operations and
binds restore/paint to the exact view request. ChatView exposes only its existing
typed draft/pending state for explicit saved recovery, with no new token/auth DB.
Native source/history and account actions still use NativeReaderActions and
existing endpoint/consent owners. See the canonical native contract and
verification guide for reachable controls and conditional editor/auth gaps.


Session candidate completion owns publication-correlated recovery attachments;
WindowController consumes that completion once and composes existing LocalReview,
viewport and typed draft owners. ChatView persistDraft/recoveryDraft supplies the
current conversation state; initial saved drafts are not a repeated override.
HostWindow owns only native event routing, window-local display preview controls
and explicit Export PDF chooser composition. RecoveryStore owns validated original
bytes staging, no-follow directory descriptors and guarded atomic output. PDFKit
inspection stays native; OriginalPageView keeps link key traversal and current
page/operation freshness, while its geometry/print colors remain independent of
reflow font/theme. No new auth/editor APIs, conversation DB or model/tool limits
are created here.


= Native explicit editor effects

`NativeReaderActions.perform(.locate)` still resolves correspondence only;
`jump(_:query:)` and `NativeReaderEditorReceipt` separately own native effect
requests and bounded feedback. FlowApp composes an explicitly chosen private
editor descriptor and fresh consent through the local manager into the real
managed client. The new `/api/native-editor` adapter coordinates selection leases,
ten-second preparations and durable no-replay effect receipts over existing
AcceptedSnapshot, SavedSourceNavigation, EditorAttachments and NeovimEditor.
The unchanged terminal/Lua owner performs the final saved-source cursor move.
Source coordinates and registration details remain private to those owners;
no source writer or HTTP registration authority is added. Native service restart
requires new editor consent. See #link("native-reader-editor-actions.typ")[NA15
contracts, bounds, headless evidence and pending delivery/GUI acceptance].

The NA15 receipt coordinator also persists the pre-effect private registration
fingerprint and treats replaced control/registration lifetimes and legacy rows
without that proof as unknown without replay. Native sync requires a locally
registered boolean nativeJumpOnly marker; HTTP consent alone cannot promote a
terminal attachment. FlowApp shares descriptor/consent adoption and native Read
composition with prohibited-activation, hidden-window AppKit control fixtures;
those exercise production callbacks without claiming real GUI acceptance.


Native editor selection adoption remains independent of optional editor sync.
NativeReaderActions revokes prior pending work before accepting a new body
selection; missing editor ownership/control/registration affects editor Locate
only. NativeReaderManagedResolver retains a local cleanup lease through probes
and epoch/cancellation checks, then transport owns it. ReaderManager and
EditorAttachments retire exactly that native token and export a live existing
registration's four-field private chooser descriptor; HTTP never owns arbitrary
registration/deletion or path discovery. Shared terminal tokens/controls and the32
quota remain with the original owner. See native-reader-editor-actions.typ.


= v5 managed identity and home feedback component

ReaderManager alone resolves canonical-equivalent existing Unicode root/entry
spellings with both actual filesystem identities and scope/type validation. It
returns the original registered profile and retains ambiguity and explicit
service selection. The separate withdrawal-only local path retires an exact
private native token after a missing source without granting new attachment,
descriptor, source or account authority. EditorAttachments still owns private
record/native-only removal; document_identity and accepted/source/Lua owners
remain unchanged. No source spelling migration or parallel identity store exists.

FlowApp derives home feedback from existing mutation/snapshot/active state.
Loading explains waiting, the later usable step and safe close/reopen if it
persists; empty/error/busy feedback avoids disabled actions. Service labels name
service start/stop/restart separately from Read. Existing enabled/selector/action,
service readiness probes and Read intent behavior remain unchanged. Offscreen
actual AppKit controls are compared against frozen d7 semantics, with fake
service operations and prohibited activation. These are source-component checks;
v4 App, delivery/sourcepin, real GUI and NA16 are separate unchanged boundaries.


= Native local issuance and retained cleanup

`services/editor_sync.py` owns private durable native-operation intents, exact
native-token retirement and atomic complete registration publication;
`services/manager.py` serializes them with its existing lock and validates managed
document/service identity. These are local-only operations, not HTTP authority.
`NativeReaderManagedResolver` and its shared retained-lease actor preserve exact
caller-known pending operations across failed resolve and later explicit clients;
`NativeReaderManagedClient` and FlowApp compose that owner. `CommandRunner` owns
bounded cancellation/exit of its manager subprocess. No directory scan, source
writer, new daemon or credential owner is added. The ten-second resolve budget
includes pending retry, prepare/ack, final state and cleanup with late-adoption
rejection. Exact-process restart recovery is a separate unsupported automation:
private journals support explicit known-operation recovery, not automatic nonce
rediscovery after the entire app dies. Historical299 response-only cleanup gaps
and current source-only evidence are distinct in external
`native-reader-identity-ui-v5/resume5-handoff.md`. Frozen d7 App/GUI and final
registration/build/PM acceptance remain separate.


= v6 operation lifetime boundaries (source component)

NativeReaderTransport owns one absolute-deadline URLSession data request and
reserves2.75seconds before the final request, then cancels and awaits its actual
task termination before exact cleanup.
ReaderManager owns the read-only opaque registered document/reader scope query;
the resolver uses it to gate pending editor grants across equivalent spellings.
Each lease still holds its stable original request for withdrawal. EditorAttachments'
operation owner separates that request from the actual issuance document and
verifies private journal/registration digest and inode without re-resolving aliases.
These responsibilities add no Source, account, terminal or HTTP deletion power.
Plain body/Source/Ask remain independent of pending editor retirement. See
#link("native-reader-editor-actions.typ")[the exact local interoperability and compatibility limits].
The external `test-output/native-reader-lifetime-v6/REPORT.md` binds this source
component, not the frozen d7/v4 App or a new GUI result. PM integration, registry
and delivery remain separate; legacy without-operation cleanup, automatic whole
app restart recovery and journal pruning are not upgraded by these changes.


= v8 pre-issuance scope correction (source component)

The manager CLI, not Swift, owns expected-scope validation before durable intent
and editor registration. The resolver supplies its queried scope with the opaque
operation and retains that lease before invocation; response loss cannot create
a differently scoped issuance. Original request expressions retain symlink-sensitive
dot components. Actual document equivalence remains in the read-only manager
query. Frozen d7 App and v7 UI evidence are separate; this source component is not
registered, packaged or GUI-accepted by these tests.


= Web cross-project previews and full-page return

WV02C implements `flow_reader/services/cross_project_refs.py` as the web backend
owner. `CrossProjectCatalog.load(package_path, max_bytes=16*1024*1024)` loads only
`local/project-references/0.1.0/projects.json`, with resolved package-root
containment, no-follow directory-descriptor opens, regular-file checks and a
16 MiB bounded read. Strict schema-1 parsing requires projects, title, pdf_url,
references and ambiguous_labels, positive integer pages and finite optional
coordinates. Errors never expose filesystem paths. Explicit project/label and
PDF href/text resolution preserve Swift unique/ambiguous/unresolved semantics;
candidate metadata is limited to 32 entries and 1024-character strings.
Catalog data is published externally by the project-references package publisher,
which owns reference publication and ambiguous-label markers. This checkout
implements no catalog generator; the viewer never edits it. The change design's
configuration example is hand-authored, not claimed generator output.

`server/routing.py` builds a read-only peer registry; `server/cli.py` ReaderRuntime
injects configured profiles and mounted states into both ingress handlers.
Swift-owned matching prefers exact nonempty projectRefKey, then normalized key
against root basename or native profile name among unconfigured profiles; empty
normalized keys and duplicate matches fail closed. IDs and catalog titles are not
aliases. Python and Swift read `tests/fixtures/cross-project-resolution.json`.
A match yields a mounted ReaderState and `/d/<id>/`, never an arbitrary path or
service command. Standalone serve.py has an empty registry.

`CrossProjectPreviewService` imports a target's already-accepted SectionBundle
through canonical `import_accepted_document` outside its publication lock, after
capturing AcceptedSnapshot and document/service identity under the lock. A
per-target single-entry cache coalesces concurrent imports by document/revision/
service and reuses native expanded-document/asset caps; stale results are omitted.
CatalogAvailability shares one parsed catalog by file signature with state discovery.
It never starts services, compiles or opens unmounted source files. Snippet
extraction follows Swift recursive-anchor and normalized display/canonical-text
matching, prefers display over canonical plain text, stops at section/heading boundaries and bounds
output to 600 grapheme clusters / 4 blocks, with a truncated boolean. Python uses
stdlib clustering for common combining/emoji/Hangul sequences; uncommon Indic/
prepend rules and Unicode/Foundation version differences remain documented in
the web-viewer design and do not alter Swift behavior. No raw HTML is
injected. Unmounted, uncompiled, compiling, failed-import or unmatched targets
retain unique catalog metadata with `snippet: null`; targetUrl is present only
for a safely mounted route. Exception: a resolved catalog label longer than
1024 characters returns bounded unique metadata before peer lookup, with null
targetUrl, anchor and snippet even for a mounted peer. A short href request can
resolve such a label; a direct oversized project/label request is HTTP 400.
Catalog labels are lookup identities, not navigable
anchors: anchor starts null and metadata-only mounted routes have no fragment.
Anchorless mounted routes still enable the web jump, using normal initial
position hints. Successful extraction may supply a manifest-backed reader anchor. Safe URLs are
relative same-origin `/d/<id>/` with an optional extracted anchor fragment, or
that route on the configured reader_url-validated origin. The single
CrossProjectPreviewService.allowed_origin comes from handler_for(public_url),
injected by routed --public-origin / manager shared.publicURL or standalone
--public-url; current peer registries emit relative routes.
Executable/file URLs, arbitrary hosts and traversal are rejected.

HTTP owns read-only `GET /api/cross-project/preview`, also available under
`/d/<id>/api/cross-project/preview`. Exactly project+label or href+optional text
is accepted, with strict decoding, no duplicates/unknowns and a 1024-character
limit per value. Responses use 200 for unique/ambiguous/unresolved (including
metadata-only fallback), 400 for malformed/oversized input, and 503 without
state. JSON carries status, projectKey, projectTitle, label, refText, title,
snippet, truncated, targetUrl, anchor, pdfUrl and optional bounded candidates.
`ReaderState.public()` / `/api/state` add
`viewer: {"name": "Lagrangian Web Viewer", "crossProject": <bool>}`;
the boolean reflects catalog availability, not target readiness.
`handler_for(None)` creates neither NativeReaderService nor NativePageService;
allowlisted static assets work and document/native/preview APIs return 503.

WV03I implements `reader-common/navigation/cross-project-return.js` and its
`.d.ts` contract. CrossProjectReturnStack owns validation, oldest-entry eviction
at max 32, injected storage and LIFO push/pop/peek/canGoBack/clear. SessionStorage
`lagrangian:cross-project-return:v1` stores
`{version:1,entries:[{path,documentTitle,sectionId,anchor,scrollOffset}]}`;
`lagrangian:cross-project-pending:v1` stores
`{version:1,transitionId,entry}`. Paths are canonical origin-relative paths,
sectionId is nonempty, anchor is string or null and scrollOffset is finite.
Corrupt/invalid records recover empty and are removed best effort; storage
exceptions do not commit failed mutations. Wrong path or transition never
consumes pending. The native Swift stack remains independently owned at 64.

The concrete `features/navigation/cross-project-preview.js` owns
CrossProjectPreview and createCrossProjectPosition. `reader.js` injects storage,
capability, document/service/revision identity and section reading-position
operations, plus `(url, options) => transport.get(url, options)` from the existing
ReaderTransport owner. Its no-store requests have a default ten-second timeout;
transport AbortError displays an error for explicit links unless the caller
signal was cancelled; failed implicit preflights preserve native navigation.
Explicit project/label metadata wins over href/text, including
fragment hrefs. Otherwise enabled capability allows safe absolute HTTP(S)
positive-page-fragment candidates, excluding same-origin viewer routes.
Pointerover/focusin preflights cache one result bound to link, exact query and
document/service/revision identity. Only a cached unique or ambiguous result
intercepts a click. Cold/in-flight, unresolved and failed candidates keep native
href/target navigation without another activation or asynchronous popup.
For intercepted ambiguous or unique-but-unjumpable references, the card offers
the original PDF href including its page fragment and original target (default
`_self`), before server PDF metadata; no return history is recorded.
Ordinary fragments, relative/non-page links, downloads and modified clicks stay
native. Popovers use named nonmodal dialog semantics, textContent-only canonical
snippets and cream/dark theme tokens. The jump button or noninteractive card
performs full-page navigation only for a unique canonical same-origin
`/d/<id>/` target, never SPA swapping. Unavailable, ambiguous and unresolved
states disable the jump and explain why; safe PDFs and unique cross-origin
viewer URLs open externally without tab return state. Request generations,
AbortController and document/service/revision guards suppress stale success
and failure. Escape, close, outside click and dispose cancel work; focus is
restored without stealing an outside control's focus. Dispose removes listeners.
Detached source links dismiss loading on either success or failure. Dismiss
clears the preflight cache; dispose removes the preflight listeners too.
Pagehide aborts preview work even for cached pages. Persisted pageshow
dismisses old cards, releases the navigation latch and reloads
the stack from storage so Homepage resets and other documents remain authoritative.

JUMP captures the exact origin route/query/hash, title, ready section, semantic
anchor and section-relative offset, persists the stack, then assigns the target.
For both JUMP and BACK, a destination with current pathname and query (including
fragment-only and identical URLs) calls location.reload immediately after
location.assign. This forces bootstrap, releasing the old navigation latch and
running pending restoration. Ordinary fragments keep their existing owner.
BACK writes a pending record with a fresh UUID before popping/persisting the
stack and assigning the origin path. Synchronous assignment failure rolls back
best effort; later load failure leaves pending recoverable by browser navigation
or reload. On initial bootstrap, pending selects the saved section ahead of
fragment, section query and normal reading state. Client revision starts null;
renderDocument fills it from the accepted manifest before section mounting.
The initial !revision condition chooses entry hints, not compiler readiness.
A matching current state/manifest
session, non-busy article and exact ready section are required. Restoration
scrolls to finite section document top plus saved scrollOffset, requires actual
scroll within one CSS pixel, then holds the current semantic anchor and focuses
the article without scrolling. The final scroll must still meet that tolerance.
Only then is the matching path/transition consumed
once. Failed readiness/geometry or pending removal retains the record for
retry. reader.js retains load sequence, snapshot and transition, schedules nearby
section loading and retries after mounted-section changes and article resize
notifications in a coalesced animation frame. This runs after ContinuousSections
restores its own mutation anchor. Navigation, session/revision change, a newer
pending transition or disposal invalidates the attempt. Success stops retries;
disposal disconnects the observer and cancels its frame.
`features/navigation/reading-position.js::createReadingPosition` owns the semantic
anchor and hold: block key/text/section/viewport offset, canvas identity/fraction
or parked-section fraction plus origin URL. Cross-project restoration releases
the old hold, restores the exact section-relative pixels and captures/holds a
fresh semantic anchor. Failed final pixel checks release that hold. Subsequent
composition, font and width changes or continuous-section mutations can adjust
the viewport to keep the same passage; user gestures release the hold.
Homepage explicit document/variant open clears both records; reload retains tab
history. Variant controls are wa-dropdown-item hosts in each document card's
ellipsis menu, offering alternative viewers/variants; both host and nested
document link clicks reset history.
Cross-project Back has its own labeled navigation-action button.
In-document ReferenceReturn still holds one semantic origin. The HTML adapter's
finishReferenceReturn updates history/focus only on success but consumes the
matching origin even when restoration fails. That behavior and existing
fragment/popstate handling are unchanged; retry-preserving consumption here
applies only to cross-project pending returns.

ReaderRuntime maps stable manager service IDs to mounted states and routes;
`/d/<id>/` IDs are not documentID. The latter hashes resolved root/entry;
service identifies process pid/startedAt and revision identifies accepted output.
Each full-page bootstrap obtains and validates those identities afresh. Stored
return routes do not authorize old revision/service reuse. Profiles inherit
Project.packages and projectRefKey from their parent Flow profile; a key in a
Reader services entry alone does not override it. Registry fallback applies
only to unconfigured profiles: exact ID, then normalized key or catalog title
against root basename or profile title, rejecting duplicate tiers. Profile title
uses explicit title, parent name, profile name, then empty. A mounted state with
no profile can fall back to route ID/root basename; inventory-only/unmounted
profiles cannot supply a peer. The change design contains concrete configuration,
full JSON schemas, transition ordering and the exact create/modify/delete map.

Both runtime modules are explicitly registered in sorted `web/assets.json`;
existing install.py, server/assets.py and reader-bundle tooling deliver them
without changes. `reader-common/tests/cross-project-return.mjs` and
`flow-reader/tests/test_cross_project_preview.mjs` cover policy and headless DOM
transitions, cancellation, literal text, exact return, Homepage reset and wiring.
Regressions cover same-document jump/Back bootstrap, detached-link loading
cleanup, native unresolved/failed implicit links and original PDF page/target
fallback for ambiguous/unmounted results. The DOM suite also executes isolated
Python service fixtures for the oversized-label exception and anchorless jumps.
Run all shared and flow-reader Node tests, focused Python cross-project service,
install and bundle tests, reader lint and strict OpenSpec validation. These are
headless checks, not native GUI or visual review. Native files and app/service
installation are outside WV03I.
= Native reader floating chrome (NRD01B)

`apps/macos/NativeReaderWindowController.swift` composes the reader toolbar and
floating overlays. `NativeOutlineDrawerView.swift` owns the content scrim,
indented table, active section and keyboard navigation. The host computes the
active heading from the viewport baseline plus 96pt and coordinates mutual
exclusion with the opaque Aa surface and logo status popover.

`NativeBrandMark.swift` retains Home's passive vector view and adds the reader's
`NativeBrandMarkControl`. `FlowApp.swift` injects its Home operation into both live
and offline windows. `NativeModeMorphSwitch.swift` owns the sliding track and
thumb, responsive labeled/icon slots, request arc and held-selection feedback;
accepted mode and capability policy remain with the existing host/session.

`NativeAppDesign.swift` owns `NativeFloatingGlassView`: clear outer layer,
rounded continuous inner clip, within-window material, semantic tint and
separate ambient/contact shadows. Increased Contrast and Reduce Transparency
replace the inner material with opaque panel and stronger boundary. Outer
corners stay transparent. Paper/panel surfaces and Aa remain opaque.

`NativeFloatingCapsule.swift` owns selection-ticket-bound vertical tool tiles,
compact overflow, PDF/limit mini pill and the circular keyboard focus loop.
The host places tools at bottom center without resizing the window; Reflow's
104pt bottom inset and PDF's temporary inset plus renderer selection rectangles
support scroll-to-reveal. Review Undo/Clear uses a separate 40pt glass capsule.
`NativeOverlayPassThroughStack` and compact `NativeReaderPillButton` are local
host presentation helpers for centered notifications and explicit inline actions.
They own no source, inference, math preparation or PDF printed-ink operations.
The host routes command key equivalents through the toolbar and intercepts
ordinary Shift+Return keyDown only for its own reader window before text inputs.
The PDF search field delegates Escape to that same dismissal order, preserving
its selection ticket; its explicit cancel button retains selection release.
Mode transitions cancel retained Reflow layout tasks; body geometry callbacks
cannot invalidate a pending or accepted PDF publication.

`tests/flow-app/native-reader-app/NativeDesignParityTests.swift` and its Python
runner generate isolated semantic/PDF inputs and compile with an isolated
module cache. Five offscreen cases exercise drawer, notifications, toolbar/mode/
brand, bottom tools and keyboard/PDF paths. They do not assert interactive GUI,
installed-layout, VoiceOver or live service acceptance.
