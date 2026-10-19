= Reader and application architecture

The repository maintains feature policy separately from renderer geometry, transport and service operations. Use this map together with scoped `AGENTS.md` files and current OpenSpec contracts. Update it when responsibility moves. A directory is justified by an existing implementation, not a planned empty extension point.

= Feature ownership

- Selection: `tools/reader-common/selection/submission.js` owns pending-submission tickets and acknowledgment policy. Each reader captures its own native selection and owns toolbar interaction in `features/selection/`.
- Source Highlight: HTML `features/source-highlight/` invokes its verified source action; the paged reader uses its preview protocol. Server-side source checks live in `flow_reader/services/source_highlight.py` and the existing Rust preview tool implementation.
- Saved for Codex: HTML `features/codex-context/` submits explicit context to `flow_reader/services/codex_context.py`. HTML Codex and editor navigation share `services/source_mapping.py`: it resolves accepted compiler-carried ranges and retains literal fallback. Paged preview retains `crates/typst-preview/src/focus.rs` and its existing source-position protocol. Both preserve service, source and revision validation without inventing PDF coordinates for semantic HTML. Saved records have no time-based expiry. The companion `apps/macos/tail-hosting-reader-focus.patch` owns cross-reader lookup: after resolving one project and entry document, it chooses the latest saved text before tap-only positions, identifies its reader and preserves stale/error evidence. It does not merge writers or select other documents by recency.
- Review strikes: `tools/reader-common/review-strikes/bounded-store.js` owns persistence limits and storage failure handling. Each `features/review-strikes/` adapter owns its mark format, geometry, invalidation and paint. Existing browser storage keys remain compatible.
- Navigation: `tools/reader-common/navigation/change-location.js` owns pending last-change policy. Concrete `features/navigation/` modules resolve native destinations, references and outline/reading positions.
- Editor synchronization: the paged `features/editor-sync/` adapter retains its originating-editor channel and protocol. The HTML terminal bridge delegates existing selection actions and guarded section navigation; `flow_reader/services/navigation.py` validates accepted snapshots and uses the same source mapping as Codex. `services/editor_sync.py` delivers final verified edits to Neovim. Only capabilities actually implemented by a reader are exposed.
- Appearance: each `features/appearance/` owns its actual theme mechanism. HTML CSS recoloring and engine-generated paged theme variants have different lifecycles.
- Session: each `features/session/` owns document composition and connection lifecycle. HTML section mounting is distinct from the paged engine connection.

The terminal frontend reuses the HTML Reader's actions, review storage and rendering. Its supported command remains `tools/flow-reader/terminal.mjs`; implementation lives under `terminal/`: `options.mjs` owns argument validation and stable profile identity, `service.mjs` owns the started Reader process, `browser-session.mjs` owns dedicated Chromium state, `editor-bridge.mjs` connects saved-source navigation, `host.mjs` translates terminal input and image frames, `protocol.mjs` encodes the native graphics/input protocol, and `cli.mjs` composes their lifecycle. `editors/neovim/lua/tinymist/reader.lua` owns optional editor commands and native-pane launch. It delegates reading actions instead of implementing another reader.

See #link("terminal-reader.typ")[the terminal Reader guide] for prerequisites, native terminal support and conservative source-navigation limits.

= Dependency direction

Concrete reader composition imports its feature adapters and shared policy. Shared policy never imports a concrete reader. Geometry, semantic positions and transport enter through explicit operations. Do not turn similar syntax into a shared abstraction when behavior differs.

Rust and Python implementations share externally observable contracts and test cases rather than a new universal runtime. Source Highlight writes verified source; Saved for Codex records explicit context without starting an assistant turn; review strikes remain browser-local paint. Do not reintroduce the retired quotation library.

= HTML Reader package

`tools/flow-reader/{build,serve,manage,focus}.py` remain executable launchers. The maintained implementation lives in `flow_reader/`:

- `compiler/project.py` validates project inputs; `packages.py` prepares overlays; `build.py` compiles isolated snapshots; `dynamic.py` owns the incremental compiler process; `inputs.py` fingerprints bounded filesystem inputs.
- `compiler/audit.py` is the single owner of normalization order, content auditing and accepted diagnostics for isolated and incremental compilation.
- `compiler/inputs.py` owns bounded workspace source enumeration and read-only shadow inputs shared by source mapping and highlight verification. `compiler/source_map.py` owns isolated source carriers and matching their emitted ranges to accepted block identities/text. Carriers and candidate HTML never reach workspace sources or served documents; `document/sections.py` binds the resulting private map to accepted passages. Context and editor actions read that map without compiling.
- `document/` owns HTML normalization primitives, figure identities, semantic passages and transport sections.
- `rendering/` owns each geometry format and `service.py` owns dynamic rendering cache/worker lifecycle.
- `services/selection.py` checks accepted snapshots and orchestrates source and Codex actions. Source mutation, read-only mapping, focus record, visual-change history and managed lifecycle each have their own module.
- `server/state.py` publishes accepted snapshots; `watch.py` coalesces saves; `http.py` handles the HTTP contract; `assets.py` validates static delivery.

A failed compile retains the accepted document. Dynamic paint, selection actions and asynchronous acknowledgments continue checking document revision and saved inputs. Preserve the existing lock ownership and ordering when changing these boundaries.

= Asset and installation boundary

`web/assets.json` is an explicit route-to-file allow-list for first-party browser code. MathJax retains its separately reviewed vendor manifest. The server does not expose arbitrary filesystem paths. `web/reader-common` links the shared source directory; immutable release archives include both `tools/flow-reader` and `tools/reader-common` so the same relative imports resolve after installation and behind the Reader origin.

Changing a file path requires checking imports, test fixtures, build inputs, static routes and release packaging. Verify the installed layout with the installation test; source-tree success alone does not prove deployability.

= Engine compiler

`crates/tinymist-project/src/compiler.rs` is the public facade. `compiler/artifact.rs`, `report.rs`, `coordinator.rs`, `instance.rs` and `execution.rs` own compile data, reports, event coordination, instance state and execution respectively. Existing `scheduling.rs` and `eviction.rs` retain task lifetime and cache policy. Private tests live under `compiler/tests/`, including lifecycle, cache, filesystem and matrix fixtures.

Keep public crate APIs and revision/handler ordering stable. A completion belongs to its original task ticket; moving tests must not require public implementation fields.

= Native application

`apps/macos/sources.json` is the single explicit source list shared by packaging and tests. Profile validation, environment paths, settings storage, command execution, LaunchAgents, engine launch, CLI and AppKit each have a dedicated source. `ProjectService` owns validate-before-stop updates and recovery; its injected collaborators let tests verify rollback without running the user's services. UI callbacks gather inputs and invoke that service.

= Validation

Run `yarn test:readers` for the shared Node, HTML Node, Python and paged Vitest gate after changing a shared feature. Use actual Typst integration fixtures with `FLOW_READER_PACKAGES`; verify frontend build and browser interactions when moving browser code. Run project compiler warning-denying tests/clippy and native app tests for their changes. Development builds and fixtures use temporary projects and do not install or restart the user's services.
