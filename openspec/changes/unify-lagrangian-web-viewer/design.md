## Context and scope

Lagrangian is the canonical native macOS product and feature contract. Lagrangian Web Viewer is its web-optimized projection, composed from `tools/flow-reader/web/`, the existing `flow_reader` backend and renderer-independent `tools/reader-common` policy. Internal paths, packaging names, CLI flags and protocols remain compatible.

WV01R provides the existing branding. WV02C implements the read-only Python cross-project preview service and static-only handler repair. WV03C is the separately tracked, **unimplemented** web preview/jump/Back adapter described below. The `/d/<id>/` full-page routing host already exists; this change does not replace it with a SPA.

`apps/macos/` is unchanged in this change. Its native Swift `CrossProjectCatalog`, `CrossProjectSnippetExtractor`, `CrossProjectNavigationStack`, managed session adoption and editor consent owners remain authoritative for native clients. Native preview may use its existing managed-service startup path. The Python web service never starts services or migrates native consumers. The native stack's existing 64-entry policy is distinct from the planned web stack's 32-entry limit. Earlier proposal/architecture-delta language about native consumption describes a later integration, not WV02C delivery.

## WV02C: catalog and resolution

`tools/flow-reader/flow_reader/services/cross_project_refs.py` owns `CrossProjectCatalog.load(package_path, max_bytes=16*1024*1024)`, `resolve(project_key=None, label=None, href=None, link_text=None)`, `extract_snippet(...)` and `CrossProjectPreviewService`.

The source state's configured `Project.packages` is the sole catalog root. Load only `local/project-references/0.1.0/projects.json` under that root. Resolve the real path and require containment; walk the resolved relative path through directory file descriptors with no-follow opens to prevent swapped path components from escaping. Read regular files only, with a bounded read of at most the configured limit plus one byte. The positive limit cannot exceed 16 MiB. An internal symlink is permitted after containment; escaping links, directories, oversized files and missing files fail with a fixed error containing no filesystem paths.

Strict JSON parsing rejects duplicate keys, invalid UTF-8/scalars, nonfinite constants and invalid schema types. Require integer `schema: 1` (not bool), a `projects` object, and each project's string `title`, string `pdf_url`, object `references` and string-array `ambiguous_labels`. Each reference requires positive signed-64-bit integer `page` and string `text`; optional nullable `x`/`y` must be finite numbers, never booleans. Unknown fields do not alter resolution, matching Swift's decoder compatibility.

Explicit project key and label are exact and take precedence over href resolution. An `ambiguous_labels` entry returns `ambiguous` even when no reference entry is published. Otherwise an existing entry is `unique`; missing identities are `unresolved`. Href resolution requires a positive `#page=N`, exact PDF URL before the fragment, and optional exact link text matching either reference text or `text + " of " + project title`. Candidates are ordered by project key and label. One candidate is unique only if its label is not producer-marked ambiguous; multiple matches or marked matches are ambiguous. Responses bound candidate metadata to 32 entries and metadata strings to 1024 characters. PDF metadata exposes only safe HTTP(S) URLs, never filesystem or executable URLs; the server never fetches PDFs.

## WV02C: peer lookup and accepted snippets

`server/routing.py::peer_registry` freezes a read-only registry of configured profiles and mounted `ReaderState` instances. `ReaderRuntime` in `server/cli.py` supplies parent project titles and profile metadata after constructing the states, and injects the same lookup into document handlers on the admin and public proxy listeners. Direct routed-handler construction derives a registry from the mounted states and loaded inventory. Standalone `serve.py` uses an empty peer registry.

Lookup prefers an exact nonempty explicit `projectRefKey`, then an exact profile `id` among unconfigured profiles, then normalized project key/title against root basename or project title among unconfigured profiles. Normalization lowercases, trims and collapses whitespace/underscore/hyphen runs to one hyphen. Explicit keys remain authoritative. Any duplicate match fails closed. A successful lookup returns only the mounted state and trusted `/d/<id>/` route to the service; inventories, source roots, service commands and editor descriptors never cross the wire. There is no arbitrary filesystem or HTTP target lookup.

`CrossProjectPreviewService` resolves the catalog and consults this injected read-only lookup. While holding the target state's publication lock, it imports only the already-accepted `SectionBundle` with canonical `document/native_document.py::import_accepted_document`, using target document/service identity. It does not recompile, open source files, start a manager service, mutate state or populate native asset caches. An unmounted, uncompiled or currently compiling target, failed import or missing match preserves unique catalog metadata with `snippet: null` and `truncated: false`. `targetUrl` remains available for a mounted target even when no snippet can be extracted; an unmounted target has `targetUrl: null`.

`extract_snippet(native_document, label, reference_text=None, max_chars=600, max_blocks=4)` searches top-level blocks in canonical manifest order, including recursive child `anchors` and `id`. Anchor matches take precedence over whitespace-normalized case-insensitive reference-text matches against display/canonical text. Starting there, take at most four blocks in the same section and stop before a subsequent heading. Prefer trimmed display text, falling back to canonical text, separated by blank lines. Bound the result to 600 characters, including `...` on character truncation; `truncated` also marks a block-limit cutoff with further eligible content. No match returns no snippet. The result is plain text, never raw HTML/MathML; consumers must render text via textContent or equivalent.

## WV02C: HTTP and capability contract

`handler_for(state, peer_lookup=...)` exposes read-only `GET /api/cross-project/preview`; the shared host delegates `/d/<id>/api/cross-project/preview` to the same implementation. Existing Host validation and ingress scope remain in force. Accept exactly one of:

- `project` plus `label`;
- `href` plus optional `text`.

Decode strict UTF-8 once. Every value must be nonblank, free of control characters and at most 1024 decoded characters. Reject repeated, unknown, missing, mixed-form, malformed percent-encoded or oversized parameters. Bound the encoded query before parsing and allow at most three fields. Malformed/oversized input returns **400** JSON. A resolved request returns **200** JSON for all three semantic statuses, including missing/invalid catalogs as unresolved. **503** means there is no document state. Missing snippets do not change a unique resolution into an HTTP error.

The response shape is:

```json
{"status":"unique","projectKey":"book","projectTitle":"Book","label":"theorem","refText":"Theorem 1","title":"Theorem 1","snippet":null,"truncated":false,"targetUrl":"/d/book/#theorem","anchor":"theorem","pdfUrl":"https://example.test/book.pdf"}
```

All common fields are present, with null metadata for unresolved/ambiguous results; ambiguity adds bounded `candidates` (possibly empty). `title` is the catalog reference's display text; `projectTitle` is the catalog project title. `anchor` is the label. The service percent-encodes that anchor and strictly validates `targetUrl`: a relative same-origin `/d/<id>/#<anchor>` route, or the same route on an explicitly configured, `reader_url`-validated allowed origin. Reject credentials, path traversal, encoded route components, noncanonical leading slashes (including `///d/<id>/` network-path references), extra queries/fragments, javascript/file URLs and arbitrary hosts. A target URL grants no editor or source-write authority.

`ReaderState.public()` and `/api/state` add `viewer: {"name": "Lagrangian Web Viewer", "crossProject": <bool>}`. The boolean reflects successful bounded catalog loading; it can be true in standalone mode with no peers because catalog metadata previews still work. It does not promise that a target is mounted or compiled.

`handler_for(None)` constructs neither `NativeReaderService` nor `NativePageService`. Explicitly allowlisted static assets remain available; document APIs, including `/api/native-*` and `/api/cross-project/preview`, return 503 without dereferencing absent state. Static traversal and unregistered assets remain unavailable.

## WV03C: planned full-page jump and Back return

The web adapter will first show a popover without navigating. A second explicit activation of its jump control uses the validated `targetUrl` to perform a full-page navigation to `/d/<id>/#<anchor>`. Each document bootstraps its own existing reader, API scope and service worker. There is no SPA `pushState` document swapping, staged DOM adoption, shared active-reader object or compensating `history.go` protocol.

`tools/reader-common/navigation/cross-project-return.js` will own `CrossProjectReturnStack` with **max 32 entries**. Inject capture, availability, navigate and restore operations; DOM geometry stays in `tools/flow-reader/web/features/navigation/cross-project-preview.js`. Store only serializable route/document identity, title, semantic anchor/block and finite viewport offset, never source paths, DOM nodes or credentials.

Before jumping, capture the origin and persist the bounded return stack in tab-local `sessionStorage` under `lagrangian:cross-project-return:v1`. Use `lagrangian:cross-project-pending:v1` as the one-shot pending restore/transition record. The destination checks its identity and readiness before accepting the pending transition. Back peeks the origin, records its expected restoration and navigates its full-page route; the origin consumes the pending restore once after ready and restores its semantic position, then acknowledges consumption of that return entry. Failed readiness or restoration must leave retained history recoverable; stale transitions cannot consume newer entries. A failed full-page load may leave a browser error page, so the design promises retained restoration state, not an impossible atomic in-place document swap. Missing/nonunique mounts are skipped without guessing. Oldest entries are evicted at 32; malformed storage is empty and storage failure must not silently promise a recoverable Back action.

Explicit Homepage document open resets cross-project stack and pending state. Reload within the same tab retains the stack. Ordinary in-document `#fragment` navigation and existing `ReferenceReturn` remain independent: the adapter adds no `popstate` handler that consumes fragment history. Cross-project Back is an explicit reader action; browser Back retains normal full-page history semantics.

WV03C must explicitly register **both** `reader-common/navigation/cross-project-return.js` and `features/navigation/cross-project-preview.js` in `tools/flow-reader/web/assets.json` before importing them. Verify source and installed shared-tree delivery. These modules, registrations and browser interactions are planned and are not implemented by WV02C.

## Verification and delivery boundaries

`test_cross_project_refs.py` covers strict schema/bounds/path containment, Swift resolution parity, canonical snippets, registry ambiguity, safe URLs, metadata-only fallbacks, standalone and routed HTTP, capability and static-only handlers. Run the following headless checks from the repository root. The slow Typst graphics suite `test_serving.py` runs separately and is omitted here; no graphics-suite result is claimed.

```sh
PYTHONPATH=tools/flow-reader:tools/flow-reader/tests /opt/homebrew/bin/python3 -B -m unittest tools/flow-reader/tests/test_cross_project_refs.py tools/flow-reader/tests/test_routing.py tools/flow-reader/tests/test_homepage.py tools/flow-reader/tests/test_sections.py test_install.ReaderInstallTests.test_clean_release_works_and_rejected_updates_preserve_installed_files -v
/opt/homebrew/bin/openspec validate unify-lagrangian-web-viewer --strict
```

Also run the complete `test_install.py` suite to verify static delivery and release-preservation behavior. Use isolated temporary state, headless CLI only, no Rust builds, no app/launchd installation or restart. WV03C remains unchecked pending its implementation and interaction/delivery verification. Native files and native behavior are unchanged.
