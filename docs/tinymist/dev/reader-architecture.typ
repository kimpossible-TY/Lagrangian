= Reader and application architecture

The repository maintains feature policy separately from renderer geometry, transport and service operations. Use this map together with scoped `AGENTS.md` files and current OpenSpec contracts. Update it when responsibility moves. A directory is justified by an existing implementation, not a planned empty extension point.

= Feature ownership

- Browser rendering: `tools/reader-common/rendering/scheduler.js` owns coalesced animation frames, asynchronous serialization, selection holds, debounce and cancellation/disposal. `tools/typst-dom/src/typst-doc.mts` supplies ordered document deltas, WASM rendering and its touch-selection adapter; HTML `web/rendering/math/renderer.js` supplies nearby MathJax composition, identities and current geometry checks. Completion runs after releasing the scheduler so navigation can enqueue another frame. Cancellation prevents obsolete completion and waits for running work before the next task; it cannot interrupt synchronous renderer calls. HTML figure label placement remains browser-local, while custom decorations and graphical relationships retain their validated server rendering path. Shared scheduling does not make these distinct renderers interchangeable or move Typst compilation to the phone.
- Selection: `tools/reader-common/selection/submission.js` owns pending-submission tickets and acknowledgment policy; `selection/press.js` owns the shared pressed-selection, deferred release and click-consumption lifecycle. Each reader captures its own native selection and binds DOM toolbar events in `features/selection/`. Concrete capture/update guards and action effects remain local; disposing the shared press state cancels pending release work.
- Source Highlight: HTML `features/source-highlight/` invokes its verified source action; the paged reader uses its preview protocol. Server-side source checks live in `flow_reader/services/source_highlight.py` and the existing Rust preview tool implementation.
- Saved for Codex: HTML `features/codex-context/` submits explicit context to `flow_reader/services/codex_context.py`. HTML Codex and editor navigation share `services/source_mapping.py`: it resolves accepted compiler-carried ranges and retains literal fallback. Paged preview retains `crates/typst-preview/src/focus.rs` and its existing source-position protocol. Both preserve service, source and revision validation without inventing PDF coordinates for semantic HTML. Saved records have no time-based expiry. The companion `apps/macos/tail-hosting-reader-focus.patch` owns cross-reader lookup: after resolving one project and entry document, it chooses the latest saved text before tap-only positions, identifies its reader and preserves stale/error evidence. It does not merge writers or select other documents by recency.
- Review strikes: `tools/reader-common/review-strikes/bounded-store.js` owns persistence limits and storage failure handling. Each `features/review-strikes/` adapter owns its mark format, geometry, invalidation and paint. Existing browser storage keys remain compatible.
- Navigation: `tools/reader-common/navigation/change-location.js` owns pending last-change policy. `navigation/reference-return.js` owns the single return origin, replacement/consumption, action visibility and click/disposal lifecycle used by both readers. Concrete `features/navigation/` modules capture/restore page coordinates or semantic anchors, validate navigation completion and retain native scroll anchoring, section loading and URL/history effects.
- Editor synchronization: the paged `features/editor-sync/` adapter retains its originating-editor channel and protocol. The HTML terminal bridge delegates existing selection actions and guarded section navigation; `flow_reader/services/navigation.py` validates accepted snapshots and uses the same source mapping as Codex. `services/editor_sync.py` delivers final verified edits to Neovim. Only capabilities actually implemented by a reader are exposed.
- Appearance: each `features/appearance/` owns its actual theme mechanism. HTML CSS recoloring and engine-generated paged theme variants have different lifecycles. HTML `font-size.js` owns transient font previews, the original reading anchor, rollback and final preference persistence. `navigation/reading-navigation.js` coalesces live pinch updates into animation frames and signals preview/commit/cancel. Renderer adapters retain their interaction hold and resume against the final font rather than requesting server geometry for every movement.
- Session: `tools/reader-common/session/activity.js` and `activity.css` own the activity precedence, localized notice controller, selection-release interaction, wait feedback, visual-viewport placement and styles extracted from the paged reader. Both readers use this implementation. Concrete `features/session/` adapters retain document composition, connection lifetime and native signals: the paged engine's WebSocket/DOM events and native desktop/touch selection, or HTML HTTP compiler state, sequenced section publication and reading interactions. Paged `reading-recovery.ts` owns guarded full-frame viewport restoration using existing page fingerprints and navigation geometry; selected text holds replacement until explicitly released. HTML `features/session/recovery.js` owns bounded retry, online and page-lifetime signals; its transport bounds requests, and publication validates document, revision and service identity. Theme colors and toolbar offsets remain local. HTML mathematical and figure composition retain their own feedback.

The terminal frontend reuses the HTML Reader's actions, review storage and rendering. Its supported command remains `tools/flow-reader/terminal.mjs`; implementation lives under `terminal/`: `options.mjs` owns argument validation and stable profile identity, `session.mjs` validates editor-owned remote session arguments, `service.mjs` owns the started Reader process, `browser-session.mjs` owns dedicated Chromium state, `editor-bridge.mjs` connects saved-source navigation, `host.mjs` owns shared browser input/capture ordering and lifetime, `native-transport.mjs` owns full native-terminal modes, `editor-transport.mjs` owns versioned bounded Neovim frame/input pipes, `protocol.mjs` encodes the native graphics/input protocol, `sixel.mjs` decodes Chromium screenshot PNGs and encodes Windows Terminal's SIXEL frames, and `cli.mjs` composes their lifecycle and exclusive session attachment. `editors/neovim/lua/tinymist/reader.lua` owns optional editor commands, source RPC, native-pane launch and explicit private session preparation. Its default `reader_view.lua` owns the same-connection right-hand window, input, positioned TUI frames, geometry generations and disposal. `reader_terminal.lua` owns bounded Neovim `TermResponse` queries, recognized Windows SIXEL geometry and Kitty logical viewport selection. Neovim retains TTY input ownership; capability queries never stop/resume the TUI or change shell foreground ownership. The integration delegates reading actions instead of implementing another reader.

See #link("terminal-reader.typ")[the terminal Reader guide] for prerequisites, native terminal support and conservative source-navigation limits.

= Dependency direction

Concrete reader composition imports its feature adapters and shared policy. Shared policy never imports a concrete reader. Geometry, semantic positions and transport enter through explicit operations. Do not turn similar syntax into a shared abstraction when behavior differs.

Rust and Python implementations share externally observable contracts and test cases rather than a new universal runtime. Source Highlight writes verified source; Saved for Codex records explicit context without starting an assistant turn; review strikes remain browser-local paint. Do not reintroduce the retired quotation library.

= HTML Reader package

`tools/flow-reader/{build,serve,manage,focus}.py` remain executable launchers. The maintained implementation lives in `flow_reader/`:

- `compiler/project.py` validates project inputs; `packages.py` prepares overlays; `build.py` compiles isolated snapshots; `dynamic.py` owns the incremental compiler process; `inputs.py` fingerprints bounded filesystem inputs.
- `compiler/audit.py` is the single owner of normalization order, content auditing and accepted diagnostics for isolated and incremental compilation.
- `compiler/inputs.py` owns bounded workspace source enumeration, stat signatures, content fingerprints and read-only shadow inputs shared by accepted publication, source mapping and highlight verification. `compiler/source_map.py` owns isolated source carriers and matching their emitted ranges to accepted block identities/text. Carriers and candidate HTML never reach workspace sources or served documents; `document/sections.py` binds the resulting private map to accepted passages. Context and editor actions read that map without compiling.
- `document/` owns HTML normalization primitives, figure identities, semantic passages and transport sections.
- `rendering/` owns each geometry format and `service.py` owns dynamic rendering cache/worker lifecycle.
- `services/accepted_snapshot.py` owns the captured accepted-document/input freshness contract used by verified source actions and saved-source navigation. Capture occurs under the existing publication lock; callers retain lock ordering and response/error policy. `services/selection.py` orchestrates source and Codex actions, while `services/navigation.py` resolves saved-source destinations. Source mutation, read-only mapping, focus record, visual-change history and managed lifecycle each have their own module. Revision-only locate and accepted-output geometry retain their distinct validation contracts.
- `server/state.py` publishes accepted snapshots; `watch.py` coalesces saves; `http.py` handles the HTTP contract; `assets.py` validates static delivery.

A failed compile retains the accepted document. Dynamic paint, selection actions and asynchronous acknowledgments continue checking document revision and saved inputs. Preserve the existing lock ownership and ordering when changing these boundaries.

= Asset and installation boundary

`web/assets.json` is an explicit route-to-file allow-list for first-party browser code. MathJax retains its separately reviewed vendor manifest. The server does not expose arbitrary filesystem paths. `web/reader-common` links the shared source directory; immutable release archives include both `tools/flow-reader` and `tools/reader-common` so the same relative imports resolve after installation and behind the Reader origin.

Changing a file path requires checking imports, test fixtures, build inputs, static routes and release packaging. Verify the installed layout with the installation test; source-tree success alone does not prove deployability.

= Engine compiler

`crates/tinymist-project/src/compiler.rs` is the public facade. `compiler/artifact.rs`, `report.rs`, `coordinator.rs`, `instance.rs` and `execution.rs` own compile data, reports, event coordination, instance state and execution respectively. Existing `scheduling.rs` and `eviction.rs` retain task lifetime and cache policy. Private tests live under `compiler/tests/`, including lifecycle, cache, filesystem and matrix fixtures.

Keep public crate APIs and revision/handler ordering stable. A completion belongs to its original task ticket; moving tests must not require public implementation fields.

= Native application

`apps/macos/sources.json` is the single explicit source list shared by packaging and tests. Profile validation, environment paths, settings storage, command execution, LaunchAgents, engine launch, CLI and AppKit each have a dedicated source. `ProjectService` owns project creation defaults, profile selection/persistence and validate-before-stop updates/recovery; its injected collaborators let tests verify failures without running the user's services. UI callbacks gather inputs and adopt successfully saved settings returned by the service; failed creation/selection preserves prior UI settings. `LaunchAgentService` produces the executable arguments once for both plist generation and ownership checks.

`ReadingSessionController.swift` owns asynchronous service requests, serialized settings mutations, readiness deadlines, cancellation, stale-result guards and power-aware status polling. `PreviewReadiness.swift` verifies document availability through the existing loopback WebSocket protocol; HTTP success or command acceptance alone does not establish readiness. `NativeReadingEnvironment.swift` adapts AppKit sleep/wake notifications, network path changes, power-source changes, Low Power Mode and thermal state to that policy, and disposes its observers with the app. AppKit owns controls and accessible inline feedback; it never performs blocking process or settings operations in an event callback. Browser rendering and reading-state recovery remain with the concrete readers.

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
