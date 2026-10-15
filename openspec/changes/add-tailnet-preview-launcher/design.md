## Return from a clickable cross-reference

Wrap only the renderer's global `window.handleTypstLocation` entry point for internal links. Keep the container handler used for editor navigation unchanged. Validate that the clicked element and destination page belong to the active paged document before capturing the origin. Save the page number and normalized offsets at the scrollport origin so preview zoom or viewport resizing does not turn the return into a different passage. Restore with an instant scroll and request viewport rendering, then consume the single origin and hide the button. Following another link replaces the origin. A transport reconnection retains it while the renderer lives; renderer disposal, including a theme replacement, removes the action and restores the original global handler.

Put the return and deferred-change buttons in a shared vertical action group that respects safe-area insets and focus feedback, avoiding overlapping controls. Treat a return as a reader gesture so a simultaneous live edit can defer its navigation. Temporarily suppress browser scroll anchoring while the returned virtual page is populated, and restore the previous style after the completed render has painted or on disposal. Native touch tap forwarding already invokes the same internal-link handler; selection and long presses keep their existing behavior. This is a preview control and does not change exported PDF links.

## Context

### Home-screen web app foreground recovery

iOS can suspend page execution and leave a WebSocket either closed or apparently open. Listen to visibility, pagehide/pageshow and online events. Keep a healthy socket when leaving; cancel retry/probe timers while hidden. On return, immediately retry a disconnected transport or send one application-level ping to a responding socket. Advertise ping support in an additive `keepalive,true` binary frame following `current`; only upgraded clients send `ping`, which replies with `pong,` without compilation/render requests. Older engines are reused without sending unknown commands. Bound foreground probe time to three seconds and opening handshakes to ten seconds, with retries backing off from one to ten seconds. Guard all callbacks by current socket identity and remove lifecycle listeners/timers on renderer disposal.

Keep the WASM/DOM document initialized until a new full frame is merged. A fresh server renderer can send an unsolicited delta before its reply to `current`; discard these pre-baseline deltas and their navigation hints because the retained client model belongs to the old connection. Apply the replacement full frame through the existing selection hold and reading-position preservation path. Identical compiled documents produced different full-frame bytes in the isolated reconnect test; byte comparison is therefore not a useful document-resumption protocol. Full retransmission/export/render work after a real disconnect remains. No additional frame buffers are retained. Browser regressions cover open/closed/unresponsive transports, hidden retry suppression, stale callbacks, selection-held recovery and changed documents; physical iPhone suspension remains a separate check.

The preview data plane already accepts an explicit listen address through `--data-plane-host`. The preview frontend connects its WebSocket to the current page origin, and the server accepts that connection when the browser origin exactly matches the configured listen host and actual port. Consequently, binding with a host's Tailscale MagicDNS name provides both the required transport and a stable browser URL.

The unsafe-looking shortcut is `0.0.0.0`, but it is deliberately unsuitable here. It listens on LAN and other interfaces as well as Tailscale, while the browser uses the concrete Tailnet address in its Origin header and fails the server's fixed-origin check. Relaxing the check would weaken protection against malicious browser origins and DNS-rebinding-style attacks.

## Goals / Non-Goals

**Goals:**
- Provide one command for starting a preview that an iOS or iPadOS browser can reach over the same Tailnet.
- Bind through the exact MagicDNS name and keep the control plane local.
- Keep the browser URL stable and visible in terminal output.
- Reuse an existing release binary or an installed `tinymist`, with explicit environment overrides for automation and testing.

**Non-Goals:**
- Add authentication or authorization to the preview protocol.
- Configure Tailscale ACLs or grants.
- Support Tailscale Funnel, public Internet exposure, or wildcard listeners.
- Change the default direct HTTP origin policy.
- Change editor-integrated preview behavior or automatically open a browser on the host.

## Decisions

### 1. Add a repository launcher for direct Tailnet access

The launcher resolves the operational inputs that are missing from the existing command and then delegates to `tinymist preview`. Direct Tailnet access keeps the server's default origin policy. The separate HTTPS reverse proxy path uses an explicit allowed-origin setting.

Alternative considered:
- Add a new Rust `--tailnet` option. Rejected for now because it would couple the core CLI to the external Tailscale executable even though the existing bind option already provides all required server behavior.
- Accept the request `Host` header whenever it matches `Origin`. Rejected because it would make a wildcard listener vulnerable to DNS rebinding and weaken the existing fixed-origin policy.

### 2. Discover one MagicDNS hostname and fail closed

The launcher resolves the hostname from `TINYMIST_TAILNET_HOST` when explicitly supplied, otherwise from the local node's `Self.DNSName` in `tailscale status --json`. It removes the status API's trailing dot and validates that the result is one DNS hostname. Missing or malformed names stop startup with an actionable error. The launcher never substitutes `0.0.0.0`.

Passing the hostname, rather than its current IP address, makes Tinymist's fixed WebSocket Origin check match the stable URL opened by the mobile browser. Name resolution still binds the listener to a Tailnet address rather than a wildcard interface.

### 3. Keep network roles separate

The data plane listens on `<magic-dns-name>:<port>`, while the control plane uses `127.0.0.1:0`. The default data-plane port is `23625`, configurable with `TINYMIST_PREVIEW_PORT`. Local browser opening is disabled because the intended client is the mobile browser.

### 4. Resolve the binary predictably

`TINYMIST_BIN` takes precedence. Otherwise the launcher uses this checkout's `target/release/tinymist` when executable, then falls back to `tinymist` on `PATH`. This supports both repository development and installed releases without downloading or building anything implicitly.

## Risks / Trade-offs

- [Every allowed Tailnet peer can reach an unauthenticated preview] -> Document that Tailnet ACLs or grants must restrict access when the Tailnet contains untrusted peers.
- [MagicDNS is disabled or unavailable on a client] -> Require MagicDNS for the default workflow and allow an explicit hostname override for diagnostics.
- [A fixed port can already be occupied] -> Allow an explicit port override and let Tinymist report the bind failure.
- [Tailscale CLI availability differs by host] -> Support explicit `TINYMIST_TAILNET_HOST` and `TAILSCALE_BIN` overrides.

## Migration Plan

1. Add the launcher and source documentation.
2. Validate argument construction with a fake executable.
3. Start a real preview with the current host's MagicDNS name and verify HTTP plus an allowed-origin WebSocket handshake.
4. Remove the launcher and unset `TINYMIST_ALLOWED_ORIGINS` to roll back; the server's default origin policy remains unchanged.

## Open Questions

- None.


## HTTPS reverse proxy support

Tail Hosting runs the data plane on loopback and terminates TLS with Tailnet-only Tailscale Serve. `TINYMIST_ALLOWED_ORIGINS` is an opt-in comma-separated list of exact HTTPS origins. The request Origin must be a canonical HTTPS origin without credentials, path, query or fragment, and must match one configured value exactly. No wildcard or Host-derived allowance is added. Existing direct HTTP and editor integrations retain their defaults. The launcher remains a direct HTTP option; Tail Hosting supplies the HTTPS environment variable to its independent LaunchAgent.

Validation covers the configured Origin, a wrong hostname, a wrong port/scheme, malformed origins, and real TLS WebSocket document delivery. Background document access remains subject to macOS Documents privacy permissions.

## Bounded scrolling preview

For partial SVG document mode, derive the visible range from the scroll container and page metadata. Request visible pages plus one neighbor on each side; preserve offscreen renderer dummy groups and page dimensions. Do not rasterize dummy pages into canvases. Coalesce viewport events while preserving ordered document deltas. Shared glyph definitions and the document WASM model remain retained for diff correctness; this change bounds rendered page content, not total document data. Synchronous WASM rendering cannot be interrupted mid-call.

### Avoid redundant mobile work

Decode WebSocket envelopes using typed-array views of the received buffer. Every text consumer must respect the payload's offset and length; document bytes remain owned by the queued frame until merged. Keep malformed envelopes out of the render queue.

Track a monotonically increasing document generation after each successful merge and on reset. Cache page metadata and the last successfully applied partial SVG window for that generation. A viewport-only event within the same page window reuses the existing SVG; a changed generation, page range, renderer mode or missing/replaced SVG forces a fresh render. Retain the existing one-neighbor bound instead of retaining unbounded offscreen DOM. Cursor updates and resize anchoring still run. Initialize the selectable HTML overlay only after SVG content or its geometry relative to the host changes; ordinary scrolling moves both together and does not require rebuilding text nodes.

Once queued changes finish and the queue is empty, run completion callbacks in that animation frame. Reentrant updates from completion callbacks can schedule their own frame. A failed render, a live native selection or disposal must never report successful completion. Minify the embedded frontend using the existing Vite toolchain and preserve server-replaced argument strings.

Measure navigation-to-ready, document-frame-to-ready, source-edit-to-ready, render/merge call costs, byte counts and same-window scrolling work in an isolated browser fixture with disposable source and loopback ports. Include real document updates, scrolling across page boundaries, zoom, selection hold/release, theme switching and reconnection. Report engine/browser identity and distinguish local desktop timings from physical iPhone timings. Worker migration and persistent document caching require separate profiling evidence and renderer/protocol work; neither is assumed necessary to obtain these reductions.

## Follow the edited location

Each preview connection remembers visual fingerprints of the last rendered pages and the preceding compile view. On a successful incremental compilation, compare page frames and backgrounds; emit a `change,page x y` control frame only if the paged output changed. Resolve edited source spans against the new document when possible, and use the first changed page as a fallback. Full-current frames establish the baseline; without configured persistence they do not navigate.

Send the location hint before its document delta on the same ordered SVG channel. The frontend waits for the render completion callback before finding the page rectangle, then jumps directly to its scaled page position. This works with offscreen placeholder pages and avoids animating through the entire document. A recent touch, wheel, pointer, or key gesture defers the jump and exposes a small button so the reader can navigate when ready.

Bound each changed source by its common prefix and suffix, collect overlapping syntax spans plus enclosing equation/figure/heading spans, and inspect the rendered frames once. Prefer tagged body elements, then unlinked glyphs/shapes/images, then linked copies; exclude outline elements/entries from the body-element rank. This handles running headers as well as linked outline copies and covers code/math identifiers that the ordinary text-only cursor mapper cannot resolve. Freeze the previous dependency set before reading sources and consider newly included files' rendered spans as candidates, even when their old-world lazy read would now return identical bytes. Keep candidates from every changed file so an unrelated mapping on an unchanged page cannot hide a later match. Retain all candidate ranks so link-only source text and the changed-page fallback still work. Ordinary editor source navigation keeps its existing behavior. Frame/link hit testing uses its existing translated coordinates; transformed source mapping remains an upstream limitation.

### Persistent last-edit restoration

Theme transitions track completed renderer contexts separately from renderer allocation and module merging. Capture scroll/zoom only from a context that completed document rendering and initial navigation. Before the first such context, pass no reading state so the new theme accepts the server's resume hint. After reading has begun, retain the last captured position through any intermediate theme renderer that has not completed. Viewport callbacks while awaiting a full connection baseline do not mark a context complete or consume initial navigation. This addresses an initialization race; the reported physical-phone reboot sequence still needs device verification.

Standalone paged preview can opt in with `TINYMIST_PREVIEW_CHANGE_FILE`. Managed Flow profiles use a separate owner-only `changes/<profile>.json` file, never the explicit-tap focus file. A compilation watcher tracks successful visual changes even with no WebSocket clients. A shared atomic store is keyed by workspace/entry identity and keeps independent default/light/dark snapshots containing bounded page fingerprints, stable dependency fingerprints and the last page coordinates. Dependency identities use package/path and content, sorted independently of process-local file interning and discovery order. Matching source retains a valid last location while rebasing output fingerprints across process or renderer changes. Nonvisual edits update dependency fingerprints while retaining the position. A first compilation with changed source has no preceding source snapshot to resolve an edit, so it establishes a fresh baseline without inferring an edit from the first changed page. Legacy schema-1 history also establishes a new baseline because its saved coordinates may already be a startup fallback. Corrupt, oversized, incompatible, or different-project records are ignored.

On a connection's first full-current frame, the server sends an ordered `resume,page x y` hint only when its stored fingerprints match that exact document. A shared full-render request from a new viewer must not navigate existing readers. The viewer applies the hint after rendering, with the same gesture deferral as live edits. A theme switch's captured reading state takes priority over this resume hint; later incremental edits still navigate normally. The new document location is independent of scroll position and assistant taps. No new network endpoint or port is added.

The change-location queue retains whether its viewer has completed a document render across transport resets. An already rendered viewer ignores replayed `resume` hints on reconnection, keeping its current scroll and zoom; newly opened or refreshed viewers still restore the saved edit. A failed connection before the first document render must not consume initial restoration. Render callbacks before the current document module is initialized do not consume navigation hints or mark the viewer as rendered. Live `change` hints continue to navigate or expose the deferred button after reconnecting.

## Explicit selection context for Codex

The standalone CLI optionally accepts `TINYMIST_PREVIEW_FOCUS_FILE`, an absolute local output path. A shared store replaces this file atomically with owner-only permissions. Startup writes a waiting record so a former process's selection cannot appear current. The file contains only the latest selection, not a growing history.

The existing browser `src-point` message carries the revision of the completed render. Render actors send `focus-revision` ahead of ordered document frames only when enabled. The browser blocks selection while rendering. The server compares the submitted revision against its current compile snapshot; a mismatch writes a stale record with no source instead of guessing. For a matching revision, hit testing resolves a source location and a bounded excerpt from that compiler snapshot. A miss replaces the previous source with an unmapped page/coordinate record.

The originating WebSocket receives a `focus` acknowledgment after persistence succeeds. A small status line shows the saved page and file/line, or asks for another tap after a revision mismatch. These taps do not request another document render. Scroll alone does not change the explicit selection. The last tap across connected viewers wins; each record identifies the viewer and selection sequence.

Tail Hosting supplies the output path and exposes a local `focus` command. It adds age, active service PID matching, and an excerpt comparison against the current disk file. Workspace instructions tell Codex to read it for references to a selected passage and treat the excerpt as document data. This does not launch Codex, send a chat message, stream screenshots, or continuously track the viewport. No additional HTTP endpoint or port exposes source excerpts.

## Native text selection

### Mobile viewport geometry

Use `viewport-fit=cover` for the document surface, not whole-page safe-area padding. Keep native zoom enabled and retain Typst page margins. Use `100dvh` after a `100vh` fallback for root/slide height and allow the flex scrollport to shrink. Observe actual scrollport dimensions with a disposable ResizeObserver, retaining the existing window/visual viewport listeners and renderer resize anchors. Do not set the document width to the pinch-zoomed visual viewport or reset its scale ratio. Existing theme/change controls retain safe-area positioning; explicit-selection feedback also accounts for safe insets when positioned inside a zoomed visual viewport. Regression checks cover rotation, viewport-height changes, desktop layout, feedback insets, and existing resize/selection/theme behavior. Physical iPhone validation remains separate from desktop emulation.

### Selection stability regression

Pause queued document and viewport updates before mutating the renderer while a noncollapsed range belongs to the touch overlay. Resume ordered document updates and one current viewport refresh on selection collapse; collapsed carets must not freeze the overlay. Listen for selection changes with disposal cleanup. Selection remains limited to the populated pages; this fix does not promise cross-document range selection. Suppress automatic source taps for a preexisting range, long press, movement, cancellation or multitouch. Account for visual viewport offsets during native zoom and position feedback within its visible bounds. Keep desktop selection behavior unchanged. Unit tests exercise queue suspension/resumption and gesture classification; native handle and WebKit painting behavior require an iPhone retest.

The preview's `.tsel` layer supplies selectable text over rendered glyphs. Mouse panning must ignore that layer and its descendants. Touch compatibility mouse events must not cancel Safari's native selection gestures. Enable text selection and the native touch callout explicitly on `.tsel`; retain browser scrolling and the existing bounded renderer. iPhone testing showed that SVG `foreignObject` text selects at the wrong position and its handles cannot be adjusted. On coarse-pointer devices, mirror the rendered `.tsel` lines into an HTML layer outside the SVG, using their measured screen rectangles and fitting text width with letter spacing. Group text fragments into normal-flow rows in visual order so vertical handle drags extend through neighboring rows. Disable selection on the underlying SVG and keep the HTML layer hit-testable across gaps between lines so a dragged handle stays on one selection surface. Rebuild this layer after SVG rendering unless the current selection is anchored in it; forward short taps to the underlying SVG to retain source-location selection. Only populated virtual pages contribute text lines. iPhone handle behavior and selection across virtual page boundaries still require confirmation.

### Copy styled text fragments

Native selection serialization treats flex items as separate blocks, inserting a newline between each mirrored text fragment even when their rectangles share one visual row. Use block rows with inline-block fragments aligned to the top. Keep each fragment's measured width, height, horizontal margin and vertical offset; preserve explicit whitespace fragments and row boundaries. Browser checks must use native selection serialization in Chromium and WebKit, covering styled theorem titles, partial ranges, wrapped rows and alignment with the SVG text rectangles.

## Actions on a native text range

Use a separate fixed toolbar within the visual viewport's safe area. Observe `selectionchange`, capture only ranges whose endpoints belong to preview text, and retain the selected range while a toolbar button is pressed. Record text fragments and first/last selected glyph centers in page coordinates, independent of document zoom. Mobile mirrored lines carry their page number; desktop uses the SVG text layer. Do not replace the native menu or selectable text DOM.

Extend the existing revision-validated `src-point` request with an optional bounded selection containing exact rendered text and the end point. Keep the completed-render revision captured with the range, including when a toolbar press collapses the native selection. Adopt document identity and revision only after their corresponding document frame renders; a viewport-only render cannot adopt an incoming revision hint. Persist this data alongside the existing source context and acknowledge it only after writing the local record. An unmapped current range can still provide its text, while stale requests do not publish a current selection. Taps continue to use the old request shape.

An explicit `src-highlight` action is available only on focus-enabled previews. Validate the completed render revision and resolve both endpoints against the compiler snapshot. Prefer a callable `highlighted` binding exported by the source module, retaining document-specific math backgrounds and theme colors. Otherwise use standard `highlight` for literal text only. Match whitespace-normalized literal text around both mapped glyph offsets, or expand equation endpoints to complete equation syntax and allow a contiguous mixture of literal text, spaces and whole equations. Reject other markup/code and cross-file, package, stale or ambiguous selections.

Collect shaped text clusters from the compiled page frames using each glyph's source span and byte offset. Deduplicate multiple glyphs belonging to one shaped cluster, but retain repeated source uses at different rendered positions. Reject reused source origins within the candidate interval. Caret-side boundaries and the nearest rendered source origins within 128 bytes of an enclosing-content hint are checked against complete selection coverage; accept only one source interval. Single-use inline content inside a function or closure may be edited; definitions, loops, show/set rules and code blocks remain excluded. Verify exact normalized rendered text for plain ranges. For equations, compare all non-whitespace rendered characters with the selection, accounting for fractions/scripts being ordered differently from source notation while rejecting incomplete formula coverage. Native selection may omit scripts in a visually reordered mobile mirror, in which case it is conservatively rejected.

Inline references are an explicit exception to the other-markup restriction: accept whole `@label`, `ref(...)` or scoped `.ref(...)` nodes and their hash introducers, with endpoints still anchored in source text or complete equations. Imported helpers can give reference text a shared package span, so ordinary source glyph coverage cannot identify the invocation. Enumerate only the adjacent caret boundaries, compile each candidate between invisible metadata markers, and read its complete shaped text, including generated reference text. Require one matching source range and exactly one ordered marker pair across all pages; repeated occurrences, partial formulas/references and other calls remain rejected. Compare normalized text in ordinary text mode and non-whitespace character coverage in math-aware mode. The markers remain in the isolated world and are never saved.

Construct `#highlighted[...]` or `#highlight[...]`, parse it and compile the full unmarked candidate in an isolated shadow world before saving. This prevents helper errors or lexical unavailability from breaking the document. A helper iterating `body.children` must normalize singleton text/equation bodies to `(body,)` when the field is absent. Compare the full disk source to the compiler snapshot and replace it atomically while preserving permissions; the ordinary watcher compiles the saved edit. No edit is guessed from text alone. These compiler operations occur only for persistent highlighting; temporary red strikes retain their browser-only path.

Keep the submitted selection while the highlight request is pending and disable duplicate submissions. Collapse it on a successful or stale acknowledgment so held rendering can resume. Preserve a rejected range for Save for Codex, including when a native toolbar tap collapses the browser selection. A response to an older range must not clear a different selection the reader made while it was pending.

Red strikes use noninteractive HTML lines above the SVG, stored as page-local geometry with a page text/layout fingerprint. Keep this store separate from assistant context and Typst source. Repaint when layout finishes, remove marks from changed populated pages, and retain marks while an unchanged page is virtualized. Bound the store and expose undo/clear actions. A stable opaque workspace/entry identifier scopes browser persistence across theme variants and server restarts; storage failures fall back to memory. Physical iPhone testing is required for native callout/toolbar coexistence.

## Failed WebSocket sends

The native stream's `sink_map_err` adapter consumes its error mapper on the first sink failure. Retrying a send after that error panics, and the release profile aborts the whole engine. Treat every failed initialization, document, status, focus, highlight or pong send as the end of that connection. Initialization returns before creating renderers; an active viewer returns through the existing connection-owned renderer shutdown and viewer-demand guard. Do not alter protocol frames or origin policy. Regression coverage keeps the incoming stream open after an outgoing failure and verifies exactly one failed sink poll and release of the viewer and renderer subscriptions.

## Git candidates when startup has no usable location

Only the first successful compilation without a usable saved position consults Git. Compare tracked staged and unstaged changes against HEAD, include nonignored untracked source dependencies, and treat sources in an unborn repository as additions. Read only files inside the project and present in its successful compiled dependency set; require disk text to match that compiled snapshot. Parse separate zero-context new-side hunk ranges and map deletions to adjacent surviving source. Map candidates through Typst source spans, preferring authored body output over copied outline/internal-link output. Across body candidates choose ascending page, y, then x, independently of Git file order and edit chronology. Persist the chosen coordinate through the existing change store. Existing valid saved locations and subsequent live compilations bypass Git. Commands disable external diffs, text conversion and filesystem monitors, use literal pathspecs, and have bounded total time/output. Failures produce no Git navigation and never mutate the index, source or repository. No preceding source snapshots are newly persisted by this feature.

## Shared source history for idle palettes

The old persisted coordinates describe each palette's last successful compilation. A cold or stale palette cannot recover the latest offline edit from those coordinates: it either compares several accumulated edits or starts with cumulative Git changes. Keep a project-wide source history alongside the per-palette rendered baselines. Seed bounded local dependencies from successful compile snapshots without allowing an older palette result to replace newer source text. Filesystem reasons update this history before the compiler's viewer-demand admission check, using text differences without Typst evaluation or layout. Record the latest authored UTF-8 byte range and source hash; ignore comment/trivia-only changes and rebase an existing same-file anchor through them. Separate watcher turns establish observation order; coalesced file saves use modification times.

Map a shared anchor through the existing body-over-outline source-span mapper only when the compiled source hash matches. Each palette consumes the anchor sequence independently and persists its own coordinates. Delayed in-flight results cannot consume a newer anchor. Pending history suppresses an outdated resume coordinate; the updated compilation supplies navigation after its document is rendered. New viewers, previously unused palettes and restarts use the same source anchor. Rendering remains demand driven. Git is consulted only when neither a current saved coordinate nor an observed source anchor can supply a position. Source histories are owner-only, bounded to 256 dependencies and 2 MiB of text, and the entire record retains its 4 MiB limit. Existing schema-2 records without source history remain readable. A service that was stopped for several edits cannot establish their exact chronological ranges; tracking starts from available observed baselines.
