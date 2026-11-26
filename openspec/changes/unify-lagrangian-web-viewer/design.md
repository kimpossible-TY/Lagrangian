## Context and scope

Lagrangian is the canonical native macOS product and feature contract. Lagrangian Web Viewer is its web-optimized projection, composed from `tools/flow-reader/web/`, the existing `flow_reader` backend and renderer-independent `tools/reader-common` policy. Internal paths, packaging names, CLI flags and protocols remain compatible.

WV01R provides the existing branding. WV02C implements the read-only Python cross-project preview service and static-only handler repair. WV03I implements the shared return stack and web preview/jump/Back adapter described below. The `/d/<id>/` full-page routing host already exists; this change does not replace it with a SPA.

`apps/macos/` is unchanged in this change. Its native Swift `CrossProjectCatalog`, `CrossProjectSnippetExtractor`, `CrossProjectNavigationStack`, managed session adoption and editor consent owners remain authoritative for native clients. Native preview may use its existing managed-service startup path. The Python web service never starts services or migrates native consumers. The native stack's existing 64-entry policy is distinct from the web stack's 32-entry limit. Earlier proposal/architecture-delta language about native consumption describes a later integration, not WV02C delivery.

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

## Peer configuration example and identity mapping

This is an illustrative existing configuration, not an instruction to change live settings. The parent Flow manager's `--profiles` output includes:

```json
{"profiles":[
  {"id":"notes","name":"Notes","root":"/work/notes","entry":"main.typ","packages":"/work/packages","fonts":[],"port":31001},
  {"id":"book","name":"Book Title","root":"/work/book","entry":"main.typ","packages":"/work/packages","fonts":[],"port":31002,"projectRefKey":"book-key"}
]}
```

The Reader manager config includes these fields in addition to its existing executable paths and schema:

```json
{"schemaVersion":1,"shared":{"port":8769},"services":[
  {"id":"notes-reader","parentID":"notes","port":32001},
  {"id":"book-reader","parentID":"book","port":32002}
]}
```

`ReaderManager.profiles()` inherits root, entry, packages and `projectRefKey` from each parent; a key placed only in a Reader `services` entry is not an override. `document_arguments()` supplies `--package-path` to construct `Project.packages`. Both projects may share `/work/packages`, but each source independently reads its own configured package root. For example `/work/packages/local/project-references/0.1.0/projects.json` can contain:

```json
{"schema":1,"projects":{"book-key":{"title":"Book Title","pdf_url":"https://example.test/book.pdf","references":{"thm":{"page":4,"text":"Theorem 1"}},"ambiguous_labels":[]}}}
```

The registry contains only mounted states: an inventory entry/profile alone cannot start or mount a peer. `ReaderRuntime.documents["book-reader"]` maps to the target `ReaderState`; `HomeInventory(loaded=(parents, profiles, documents))` describes the same mounts for Homepage. A directly composed routed handler uses that loaded inventory if available. When no configured profile exists for a mounted state, its route ID and `state.project.root.name` remain usable fallbacks, with an empty title. When profiles exist but have no nonempty `projectRefKey`, exact route/profile ID wins, then normalized key **or catalog project title** may match root basename or profile title. Profile title is selected in order: `profile.title`, parent name via `parentID`, `profile.name`, empty string. At each tier any duplicate blocks lookup; there is no fallback past an ambiguous tier. A nonempty explicit key excludes that profile from all fallback tiers, even if its directory name matches. Unmounted profiles, unknown keys and standalone `serve.py` (empty registry) yield metadata-only previews. No peer lookup reads target roots or starts a service.

The route ID is the stable manager service ID (`book-reader`), restricted to `[a-z0-9][a-z0-9-]{0,63}`; it is not `documentID`. `/d/book-reader/` delegates its API and sections to the corresponding mounted state. That state's `documentID` is the first 24 hex characters of SHA-256 over Python `json.dumps([str(resolved_root), relative_entry])`. Its `service` is `{pid, startedAt}` from `FocusStore`; revision identifies its accepted compiler snapshot. `/api/state` and `/api/manifest` expose these identities, and section loads validate them. Preview importing binds the target accepted bundle to `document_id` and service ID `reader:<pid>:<startedAt>` while holding the target publication lock. The client does not infer any of these identities from the route ID. A full-page target bootstrap obtains its own identities and API scope. Persisted returns bind only to the exact route/query/hash and section; they deliberately do not persist or compare an old revision/service that may change while away. Reusing a route ID for another document is not proven safe by stored state; absent saved sections fail restoration and retain pending state.

## WV03I: adapter wiring and link matching

`reader.js` composes `CrossProjectPreview`, a storage-backed `CrossProjectReturnStack`, and `createCrossProjectPosition`. SessionStorage operations are lazy wrappers so denied storage access is caught by shared policy. The adapter receives capture/restore, capability, document/service/revision identity, request, location, external-open and transition-ID operations. `createCrossProjectPosition` alone owns DOM section geometry and delegates stable semantic holding to the existing reading-position owner. Shared policy imports no renderer or transport. The preview never starts a reader service.

An unmodified primary click is eligible unless already prevented or on a download link. Exact `a[data-project-ref-project][data-project-ref-label]` metadata wins over href and text, even when href is a fragment and capability is currently false; it is always prevented and requested as `project` + `label`. Otherwise `viewer.crossProject === true` (the adapter's `enabled()` operation) permits absolute safe HTTP(S) href candidates with positive `#page=N`, on either origin, excluding same-origin mounted viewer routes. The request sends `href` plus trimmed nonempty link text as `text`. The backend applies the exact PDF URL/text rules above. Ordinary fragments, relative paths, non-page external URLs, mail/executable schemes, downloads, modified clicks and disabled-capability hrefs remain native. A candidate's default action is temporarily prevented for asynchronous resolution; unresolved results or request failure resume its original href using `location.assign`, or external open for a non-self target. No return entry is recorded for that fallback.

First click opens a nonmodal, named `role="dialog"` popover anchored below the link, clamped to the viewport, using cream/dark `theme.css` tokens. It renders project title, label/reference text and canonical snippet exclusively through `textContent`. Explicit links immediately show loading feedback. Unique results with no snippet show a clear unavailable-body message. A unique same-origin canonical `/d/<id>/#<anchor>` target enables the `해당 문서로 이동` button; clicking that button or the noninteractive preview card captures the origin, persists it, then calls `location.assign(target)`. Queries, missing trailing slash, credentials, encoded route IDs, traversal and noncanonical URLs are rejected as jump targets. There is no SPA document swap. The button is disabled for ambiguous, unresolved, error or unavailable-route states. A safe PDF fallback opens externally; a unique cross-origin HTTP(S) viewer URL opens externally with `target="_blank" rel="noopener noreferrer"` and never enters tab return history. In-viewer jumps and Back are restricted to same-origin `/d/<id>/` routes. If neither viewer nor PDF is usable, the card explains that the web route is unavailable; ambiguity never chooses a candidate.

Every new request/dismiss increments the request generation and aborts the previous controller. Both success and failure must still match generation and captured document/service/revision identity; detached source links cannot publish or trigger fallback navigation. `update()` dismisses previews when identity changes. Escape, outside click (including while loading) and close dismiss. Focus returns to the connected source link on Escape/close/dispose; outside click restores it only if focus would otherwise remain in the removed card, preserving focus on outside controls. `dispose()` aborts requests, removes all registered listeners, hides Back and prevents late publication. Pagehide always dismisses/aborts preview work; disposal runs on non-persisted `pagehide`. A bfcache page keeps its normal lifecycle, and persisted `pageshow` dismisses old previews, releases the navigation latch, reloads the stack from storage and updates Back visibility. This prevents another document or Homepage reset from leaving stale in-memory history. No new `popstate` handler is installed.

## WV03I: persisted schemas and transition ordering

The stack key `lagrangian:cross-project-return:v1` contains precisely this JSON envelope (zero to 32 oldest-to-newest entries):

```json
{"version":1,"entries":[{"path":"/d/notes-reader/?section=section-2#origin","documentTitle":"Notes","sectionId":"section-2","anchor":"origin","scrollOffset":134.5}]}
```

The one-shot key `lagrangian:cross-project-pending:v1` contains:

```json
{"version":1,"transitionId":"2dc28c7a-a22d-4e86-8fa3-68743e5b5512","entry":{"path":"/d/notes-reader/?section=section-2#origin","documentTitle":"Notes","sectionId":"section-2","anchor":"origin","scrollOffset":134.5}}
```

Version must be numeric `1`; title is a string (possibly empty), sectionId is a nonempty string, anchor is a string or null, and scrollOffset is a finite number (including negative/fractional values). Unknown entry fields are discarded by copying those five fields. `path` is a canonical origin-relative path beginning with one `/`, never `//`, an absolute/executable scheme, backslash, whitespace/control character, traversal or encoded route escape. The shared validator accepts relative paths in general; the web adapter further requires the `/d/<id>/` pathname for captured origins and Back, while retaining the origin's exact query/hash. Maximum depth is 32 (a smaller injected limit is supported), evicting oldest entries. Constructors validate all entries, trim excess and treat corrupt JSON, primitive envelopes, unsupported versions or any invalid entry as empty and remove the corrupt key on a best-effort basis. Invalid pending records are similarly removed. Storage exceptions never escape. A failed set/remove does not commit the corresponding in-memory mutation or report successful consumption. Null storage supports in-memory policy use; the web always injects sessionStorage and requires successful writes before navigating.

Transitions are:

1. **JUMP**: capture `{path,documentTitle,sectionId,anchor,scrollOffset}` from the current ready section; push/write stack before `location.assign(target)`. Capture or persistence failure leaves the document current and shows a save-position error. Repeated activation while navigating is ignored. Synchronous assign failure pops the newly pushed entry and displays an open error (best-effort rollback; already evicted oldest entries are not reconstructed).
2. **BACK**: peek top; create a fresh `crypto.randomUUID()` transition ID; write pending **before** popping/writing stack, then assign the saved exact path. If pending write fails, do not pop or navigate. If pop fails, remove that transition's pending record and stay. A synchronous assign failure pushes the entry back and removes that pending record, best effort. A later network/load failure leaves the one-shot pending origin recoverable through browser navigation/reload; full-page navigation is not an atomic DOM transaction.
3. **RESTORE**: `peekPending(current pathname+search+hash)` accepts only the exact destination, version and nonempty transitionId. Wrong-document reads leave it intact. On initial render (`!revision`), its section takes precedence over saved reading state, fragment and section query, and is loaded only if present in the manifest. It also suppresses automatic last-change jumping. Normal update anchoring cannot override that saved section. The render callback must still match load sequence and snapshot. Readiness requires a manifest with matching state documentID/revision/service, article `aria-busy` not `true`, and a mounted `[data-reader-section]` with the exact sectionId and `data-section-state="ready"`.
4. **CONSUME**: release the previous reading hold; compute finite `top = scrollY + section.getBoundingClientRect().top + scrollOffset`, scroll instantly and require actual scrollY within one CSS pixel of top. Then hold the newly captured semantic reading anchor and focus the article without scrolling; verify the final scrollY still meets that tolerance after holding/focus. Only a successful restoration removes pending, and only if its exact path **and transitionId** still match. Failed readiness, absent section, nonfinite geometry, clamped or shifted scroll, or failed remove retains pending for recovery/reload; it never consumes a newer transition. Repeated consumption returns null. No timer claims an unverified restoration; automatic layout retry beyond that render is not implemented. The saved `anchor` preserves semantic metadata; section-relative scrollOffset is the exact initial restoration authority, not a guessed anchor offset.
5. **HOME-OPEN**: explicit document link or alternative variant item activation removes both keys, with storage denial contained. Homepage refresh alone and document reload do not clear history.

Back visibility comes from `stack.canGoBack`, labeled `← <documentTitle>` or `← 원래 문서로`. It shares the existing navigation-action button styles. In-document `ReferenceReturn` is independent: it holds one renderer-native origin when a local reference is followed, replaces that origin on a new reference, and consumes it only after the existing semantic restoration succeeds. Its `원래 위치로` button, fragment history, `navigationHistory()` and `popstate` behavior are unchanged. Cross-project Back is a separate explicit action; browser Back retains normal full-page semantics.

## Exact WV03I file map

| Operation | Paths | Responsibility |
| --- | --- | --- |
| Create | `tools/reader-common/navigation/cross-project-return.js`, `tools/reader-common/navigation/cross-project-return.d.ts` | Validated bounded persistence, LIFO API and one-shot pending schema/types |
| Create | `tools/reader-common/tests/cross-project-return.mjs` | Policy, validation, eviction, corruption and storage-failure tests |
| Create | `tools/flow-reader/web/features/navigation/cross-project-preview.js` | Preview lifecycle, safe route validation, capture/restore geometry, jump and Back adapter |
| Create | `tools/flow-reader/tests/test_cross_project_preview.mjs` | Headless DOM events, cancellation, safe text, navigation, pending consumption, Homepage reset and manifest wiring |
| Modify | `tools/flow-reader/web/reader.js` | Inject adapter operations, pending section precedence/restoration, identity update and disposal |
| Modify | `tools/flow-reader/web/index.html`, `tools/flow-reader/web/reader.css` | Hidden Back control and themed accessible preview styling |
| Modify | `tools/flow-reader/web/home/home.js` | Explicit-open reset of both sessionStorage keys |
| Modify | `tools/flow-reader/web/assets.json` | Sorted explicit routes for both new runtime modules |
| Modify | `openspec/changes/unify-lagrangian-web-viewer/design.md`, `openspec/changes/unify-lagrangian-web-viewer/specs/web-viewer/spec.md`, `openspec/changes/unify-lagrangian-web-viewer/tasks.md`, `docs/tinymist/dev/reader-architecture.typ` | Implemented contracts, ownership, task completion and verification |
| Delete | None | Existing native/backend and ReferenceReturn owners remain intact |

The asset manifest registers **both** `reader-common/navigation/cross-project-return.js` and `features/navigation/cross-project-preview.js` in exact sorted order. Existing `install.py`, `server/assets.py` and reader-bundle packaging deliver/validate both shared and concrete trees without changes. Native Swift retains its 64-entry stack and adoption/editor-consent behavior.

## Executable verification checklist

Run from the repository root, headless CLI only, with isolated temporary state. Do not build Rust, install/restart apps or launchd, or modify live configuration. DOM fixtures exercise the required paths; they do not claim native GUI or visual review.

```sh
/opt/homebrew/bin/node --test tools/reader-common/tests/*.mjs
/opt/homebrew/bin/node --test tools/flow-reader/tests/test_cross_project_preview.mjs tools/flow-reader/tests/test_web_viewer_branding.mjs tools/flow-reader/tests/test_home_account.mjs tools/flow-reader/tests/test_reading_navigation.mjs tools/flow-reader/tests/test_reader_links.mjs
PYTHONPATH=tools/flow-reader:tools/flow-reader/tests /opt/homebrew/bin/python3 -B -m unittest tools/flow-reader/tests/test_cross_project_refs.py test_install.ReaderInstallTests.test_clean_release_works_and_rejected_updates_preserve_installed_files tests/flow-app/test_reader_bundle.py -v
/opt/homebrew/bin/openspec validate unify-lagrangian-web-viewer --strict
npm run lint:readers
/opt/homebrew/bin/node --test tools/flow-reader/tests/test_*.mjs
PYTHONPATH=tools/flow-reader:tools/flow-reader/tests /opt/homebrew/bin/python3 -B -m unittest test_install -v
/opt/homebrew/bin/typst compile --root . docs/tinymist/dev/reader-architecture.typ /tmp/lg-reader-architecture.pdf
```

Policy tests cover exact field preservation, 32-entry eviction, safe paths, invalid/corrupt data, one-shot destination/transition checks and denied storage. DOM tests cover preview-before-navigation, full-page jump and durable origin, stale success/failure, dismissal/disposal, literal XSS-safe text, metadata-only/ambiguous/unresolved/external states, Back ordering, exact section-relative offset and single consumption, Homepage reset, manifest completeness and bootstrap wiring. Service tests cover the existing bounded catalog, peer/profile fallback, snippets and HTTP behavior; install and bundle tests cover source and installed asset delivery. All flow-reader Node tests supply regression coverage for fragments, reading navigation and Homepage. Optional full service/compiler/physical-device integrations remain separate; no result is implied by this checklist.
