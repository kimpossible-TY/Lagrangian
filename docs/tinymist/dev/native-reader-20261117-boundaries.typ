= Native Reader: service, authority and lifetime boundaries

Task: `lagrangian-native-reader-20261117-plan-v1:NR03:7875a1dbc32e`.
Project: `kimpossible-TY/Lagrangian`.
Evidence baseline: `5d71618e7ee320edbe759511fe634024fc8104a6` (2026-11-17).
All evidence paths and line numbers below refer to that commit, not a future
implementation. Planner MIGRATION and source-evidence were discovery aids;
the cited implementation and specifications were inspected at the fixed source.

This is a design investigation, not a product implementation or an approved new
protocol. Recommend a native presentation adapter over the existing managed
services first. Native text, layout, selection, accessibility and inline chat must
be implemented as native presentation; WKWebView wrapping is not the final
solution. Reusing HTTP does not require rendering HTML in a web view.
The feasibility and fidelity of the native document representation belong to
the representation proof, and are not established by this boundary recommendation.

No external API currency was verified. No Apple API availability claim depends
on an SDK-header inspection. No network, live account/data access, GUI run,
Rust compilation, performance experiment, installation, service restart or
CI/Cloud execution was performed. Static evidence does not establish native parity.

= Recommendation and alternatives

*B01 — Keep presentation outside authority.* One app may contain or connect to
several processes. Retain ReaderManager's exact project/entry resolution and
normal service lifecycle, Python accepted-publication/source/chat owners and the
Rust project history and paged source-action owners. Add only native operations for transport, immutable
view adoption, native selection-to-fragment conversion and view-local recovery.
Do not add a second source writer, credential owner, conversation database or
saved-edit chronology. App composition and future cross-language schema/fixtures
have one integration owner, Lagrangian; feature owners remain those in E01–E12.
No native module/file list or new endpoint is fixed by this document.

#table(
  columns: (1fr, 2fr, 2fr),
  [Candidate], [Reuse and cost], [Decision / proof gate],
  [Existing loopback HTTP, SSE and preview WS],
  [Reuses manager resolution, JSON source/chat actions, account guards and existing
   paged data plane. Process boundaries and external clients remain intact. Native
   decoding/layout still needs proof; baseline payloads are not a native render tree.],
  [Preferred first proof. Bound requests/streams, validate service identity and
   preserve exact authority rules. Loopback and a supplied Origin are not native
   executable authentication.],
  [Separate local IPC: Unix socket, XPC or framed helper channel],
  [Could provide a private control channel and peer verification. Adds bootstrap,
   framing, versioning, cancellation, backpressure and shutdown contracts. Python
   bridging and packaging/entitlements are unproven.],
  [Defer until a demonstrated gap. Must delegate to the same service methods and
   retain the HTTP facade for other clients. Same user or socket path alone is
   insufficient proof of a trusted executable.],
  [Direct library / in-process FFI],
  [Potentially avoids serialization, but Python owners, Rust runtime lifetime,
   locks, crash isolation, ABI and callbacks must still be preserved. A Rust
   compiler library does not replace Python acceptance/source validation.],
  [Do not choose for the initial adapter. No performance evidence justifies
   moving authority. A later library extraction needs an explicit OpenSpec delta,
   substitutable contracts and cross-client regression proof.],
)

For every transport, document ID, service incarnation, accepted revision and
server-checked input fingerprint remain independent checks. Cancellation is not
rollback; ordered publication is not guaranteed merely by ordered socket bytes;
selection holds are a presentation policy, not a source permission. IPC or FFI
must preserve those distinctions just as HTTP does. Transport cannot resolve the
native renderer question by silently substituting a screenshot or PDF-only UI.

= Existing owners and mandatory delegation

*B02 — Accepted publication.* ReaderState accepts compiler output, checks saved
inputs, then publishes bundle/revision/source stamp/input fingerprint under its
lock (E02). Failed compilation updates diagnostics and retains the last accepted
document. AcceptedSnapshot captures under that publication lock and tests revision,
compiling state, source stat signature and content fingerprint (E01). A native
view may keep an older accepted document for reading; source/chat mutations still
fail freshness checks when compiling or when saved inputs change. A client hash,
matching text, HTTP 200 or engine PID cannot replace those checks.

*B03 — Mapping and writer.* Native hit testing yields native positions, then a
validated adapter produces existing logical fragments: key, exact, prefix, suffix
and complete math segments when supported. Do not send guessed file ranges from
glyphs, normalize source bytes in Swift, or manufacture paged coordinates.
Read-only source mapping remains in source_mapping/navigation; private compiler
carriers, hashes, dependency allowlists, ordered ranges and literal fallback keep
their current meaning (E03). Partial math/reference coverage can be unmapped.
Navigation-only container ranges do not grant selection/highlight coverage.

SelectionActions owns highlight serialization and takes its edit lock before
capturing under the state lock. apply_highlight retains candidate compilation,
whole-body/selected-interval checks, final HTML and paged compile proof, freshness,
original-byte comparison and its final writer (E04). Native must not replace this
with a direct file edit, a source snippet search or an editor RPC chosen by UI
payload. Receipt execution wraps the existing validation, not its inverse.
Keep the existing action-specific stale/error responses and lock order; do not
hold the UI thread or a presentation actor while awaiting those operations.

These AcceptedSnapshot/fragment/receipt details describe the HTML service, not a
universal paged protocol. Paged source Highlight already has a separate Rust
owner: its WS actor checks the current view revision; the engine resolves page
positions/glyph evidence, rejects package/out-of-root sources, compiles a shadow
candidate and delegates to its serialized exact-byte writer (E25). Preserve that
owner and native page positions. Baseline paged highlight does not expose the
HTML durable-receipt or editor-attachment contract. Do not claim those guarantees
for it or tunnel a paged selection into HTML using invented fragments. Initial
native source-mutation proof should target the HTML accepted-service path only;
paged mutation remains unsupported in the new adapter until its identity,
uncertain-outcome and editor contract is separately proved. Existing paged clients
and their writer stay compatible; this is a native readiness gate, not removal.

*B04 — Durable highlight receipts.* Use the existing requestID-bearing
highlight-intent path. Freeze the complete wire request before first dispatch,
including document, service, revision, fragments and editor attachment choice.
The receipt hashes the entire sorted JSON request; adding a retry timestamp or
changing an optional field under the same ID causes a digest conflict (E05).
Its committed empty-result row precedes execution. A crash before or after the
write can leave the same `uncertain` state: never execute that unfinished receipt
again automatically, never report it saved and never generate a replacement ID
as a background retry. Same ID/same payload may retrieve the stored result via
the existing action; an unfinished result stays uncertain. There is no separate
receipt-query endpoint in this recommendation. Completed-result replay does not
authorize a new write or permit paint on a different service/revision.

The adapter's pending-intent store is a bounded recovery copy, not the receipt
authority. Preserve uncertain payload/identity across native quit. Expose manual
inspection/reselection; a new explicit action needs fresh validation and a clear
warning that the old effect is unknown. `receipt-limit`, stale, editor-mismatch,
unsupported, unmapped and error remain distinct from success. Optimistic native
paint is temporary and reconciles with the original intent only.

*B05 — Editor attachments and saved source edits.* ReaderManager resolves canonical
root/entry plus optional explicit service ID, starts only through its normal plan,
and checks the actual managed PID, startedAt and documentID (E06). Never select
the newest service or an arbitrary responding port. EditorAttachments registration
stays local to the manager; HTTP accepts only an opaque already-registered token.
Tokens remain document/service/live-owner/private-file bound. Resolve again at
final write time; revocation or editor replacement must not fall back to disk
writing. Neovim remains responsible for refusing modified buffers and changed
original bytes (E07 and E18). Native without an editor uses only the existing
validated service writer, not another native writer.

Rust source_history owns saved-edit sequence and UTF-8 ranges; its store owns
project identity, path resolution, reload-under-file-lock and atomic persistence
with other renderers' metadata preserved (E08). Python SourceHistoryClient only
transports observations and reaps its own helpers. A native viewport position is
not a new authoritative source edit. Missing source-history capability blocks the
dependent feature with an upgrade explanation; it does not start a Swift or
Python chronology.

*B06 — Conversations, drafts and explicit inference.* ParagraphChat remains the
owner of document-scoped UUID conversations, accepted selection/context, attachment
evidence, optimistic mutation version, stream sequence and SQLite transactions
(E09). Ask/open, selection, draft save, import, reconnect and login must not start
inference. Only an explicit Send invokes the existing send mutation. Preserve
the chosen model, bounded question, immutable per-message original context,
current revision, attached paragraph and conversation version checks.
Ambiguous/missing anchors remain unresolved history, without a guessed attachment.
Model document tools remain bounded accepted-document reads/search, not arbitrary
paths, source writes or shell. Private source evidence stays out of model history.

Persist a stable message ID and question before Send. Baseline accepts a bounded
string; a UUID is the native generation candidate, not a newly asserted baseline
validator. Duplicate ID with the same question returns the existing record;
different text is rejected. Do not mutate a pending message's question/model or
context on reconnect. Baseline duplicate matching checks role/text, not model,
so the native pending record must freeze all of them itself.

If acknowledgment is lost, read authoritative list/history for that document and
match user-message ID and exact question before clearing recovery text. A matching
record resolves acceptance, even if streaming later failed. Absent, stale,
unreachable or conflicting history leaves Send unresolved; do not automatically
resend, create another message ID, or infer that a timeout means no inference.
Only a subsequent explicit user decision may retry the frozen ID after current
guards pass. Reopening a new revision first requires current history and
reselection; do not silently rewrite the old message context. A later draft edit
must survive an acknowledgment for the older text. Stream disconnect cancels the
subscription, not the host run (E10).

= Authentication and private data

*B07 — Reuse ChatAuth, including its lease.* ReaderRuntime borrows one shared
ResponsesProvider/ChatAuth into document owners and holds claim_host for the
credential directory (E11). ChatAuth alone owns PKCE verifier, state, nonce,
one-use callback/generation, fixed-helper signature verification, issuer/audience
checks, isolated registrations, cross-process locked rotating refresh and logout
revocation uncertainty (E12). Native receives sanitized status or a validated
consent URL, never provider tokens or credential-file contents. Exactly one
consent navigation owner must be chosen; server and native must not both open it.
Native consent should use the system consent/browser flow rather than a reading
WKWebView. Its API choice/minimum OS is undecided and unverified here.

Native presentation does not create a new authentication authority. For the first
HTTP proof keep the existing exact Host/Origin, genuine admin 127.0.0.1 socket peer,
no forwarding headers, expiry, session and CSRF checks (E13). Native supplies the
configured canonical Origin as required; that header is protocol context, not
proof of executable identity. Use isolated native session/cookie memory, with no
web browser cookie harvesting. Credentials stay server-side. Do not broaden
allowed origins, suppress guards when Origin is absent, or send proof to a redirect.

Login without registration selection and logout have the scoped OAuth-only
exception; it still requires explicit OAuth session purpose, local request guards
and matching CSRF. Cancel, registration selection and private account identity
still require current host capability plus management session/CSRF (E13/E14).
Paths on one origin do not isolate trust. An OAuth-only token plus host proof
does not become management. Credential changes invalidate session authority;
server restart invalidates it as well. Remote/proxy ingress remains sanitized
and cannot mutate even with copied proofs. Document auth endpoints remain
revision-bound status/models only and reject login/cancel/logout (E10).

The smallest native adapter can retain this HTTP account contract without a new
permission model. Management proof acquisition is *not solved*: keep management
disabled until an explicit owner-mediated, per-start bootstrap is specified and
proved, or preserve the existing explicit proof entry workflow. Never discover
and ingest arbitrary files in the private credential directory merely because
the app runs locally. A later IPC control channel needs an explicit trusted-peer,
scope/expiry/revocation contract and the same HomeAccount/ChatAuth owner; removing
browser-specific headers there requires a reviewed equivalent authority contract,
not bypassing HomeAccount. No new native authorization endpoint is approved here.

*B08 — Preserve data authority and rollback.*

#table(
  columns: (1.1fr, 1.8fr, 2fr),
  [Data], [Current authority], [Native boundary candidate],
  [Credentials / registrations],
  [ChatAuth private host directory; 0700 directories, 0600 regular files, owner,
   symlink/source/Git location checks, auth lock and host lease (E11/E12/E15).],
  [Reuse in place through owner. No Swift token copy, automatic Keychain migration,
   second owner, export or browser-profile scan. Keychain is a future decision.],
  [History and host drafts],
  [ParagraphChat ConversationStore, private history.sqlite3, document IDs and
   serialized transactions; logout preserves them (E09/E12/E14).],
  [Read/mutate through service. Do not open SQLite directly, mirror history as a
   new authority, or downgrade schema. Native draft edits use version conflicts.],
  [Unacknowledged composer text],
  [DraftRecovery tab sessionStorage contains bounded text and pending message ID,
   not context/history/credentials (E16).],
  [Separate private native recovery copy, identity-scoped and bounded. Compare
   exact acknowledgment; preserve newer text and warn on storage failure. No Send
   on recovery. Native storage durability/retention must be proved.],
  [Review / appearance / reading position],
  [Browser-origin local data. HTML marks have document keys and text validation;
   appearance and position are browser preferences (E17).],
  [Independent native namespace. Default coexistence. Explicit user export/import
   through the originating reader may be designed; app cannot read arbitrary
   browser localStorage, sessionStorage, profiles or retired quotation stores.],
  [Offline documents / pending highlight intents],
  [Web worker owns complete cache commits; server receipts own highlight outcome
   (E05/E19). These are different from native recovery files.],
  [Native immutable cache requires complete identity-checked atomic commit and
   cancellation/quota recovery proof. Offline never authorizes source/chat writes.
   Do not delete browser caches or receipts during native adoption/rollback.],
)

For any future explicit import, require a versioned bounded file, declared origin,
document identity and source/revision/anchor evidence; validate types, units,
size/counts and duplicate/conflicting records before previewing the import.
Reject malformed/foreign entries, keep ambiguous marks unresolved, and make a
native staging-to-commit transaction that preserves an existing native copy on
failure. Import text is inert and cannot select a path, attachment, credential or
Send intent. Position import must not override a newer gesture. Browser UTF-16
offsets, service normalized-Unicode positions and native string indices need an
explicit conversion fixture; do not reinterpret integers across those units.

Coexistence is the initial migration: retain IDs, storage and normal browser
behavior; no shared browser/native synchronization is claimed. Future export is
performed by the originating reader with explicit user action, not by disk
scraping. Rollback reselects the previous presentation/bundle and leaves server
data, browser data and native recovery intact. No automatic schema migration,
cleanup or replay occurs. The existing legacy-worker retirement is restricted to
its own browser scope (E20); it does not authorize native cache deletion.

= Candidate request/response contract for a proof

*B09 — Envelope is a proposal.* The following is an adapter-local schema candidate,
not JSON already accepted at a new HTTP endpoint. Translate only known operations
to unchanged existing request bodies; do not send all envelope fields into the
highlight receipt digest. A separate schema/bridge would require future approval.
The native request ticket is separate from durable requestID/messageID and from
server conversation version/sequence.

```json
{
  "adapterSchema": 1,
  "requestID": "local-correlation-uuid",
  "operation": "source.highlightIntent",
  "target": {
    "managerServiceID": "configured-reader-id",
    "documentID": "accepted-document-id",
    "service": {"pid": 123, "startedAt": 456},
    "revision": "accepted-revision"
  },
  "view": {"id": "native-view-uuid", "generation": 4, "selectionTicket": 9},
  "deadlineMs": 15000,
  "requiredCapabilities": ["durable-highlight-intent"],
  "payload": {
    "requestID": "stable-highlight-intent-uuid",
    "documentID": "accepted-document-id",
    "service": {"pid": 123, "startedAt": 456},
    "revision": "accepted-revision",
    "fragments": [{"key": "accepted-key", "exact": "text", "prefix": "", "suffix": ""}]
  }
}
```

Copy the *whole* baseline service object, not just these illustrative members.
Validate envelope target against payload and resolved service; only the frozen
payload goes to the existing highlight action. Optional editorAttachment is
omitted unless obtained by the local manager. Its absence, explicit null and an
opaque token are not interchangeable. Never accept an editor executable/address
or arbitrary destination URL in a browser/native document action. The service
captures/checks its own accepted source_stamp/inputs/dependencies on each action.
A future server-issued opaque input identity may be echoed for stronger correlation;
the baseline does not expose a universal fingerprint token/handshake, and a
client-supplied fingerprint must never replace the existing server recomputation.

```json
{
  "adapterSchema": 1,
  "requestID": "local-correlation-uuid",
  "target": {"documentID": "accepted-document-id", "revision": "accepted-revision",
             "service": {"pid": 123, "startedAt": 456}},
  "view": {"id": "native-view-uuid", "generation": 4, "selectionTicket": 9},
  "outcome": "completed",
  "result": {"status": "highlighted", "revision": "accepted-revision"},
  "error": null
}
```

The wrapper echoes client correlation, never pretends the server echoed fields
it did not send. Preserve the raw domain result and HTTP status. Wrapper outcomes
are proposed `completed`, `rejected`, `cancelled-before-dispatch` and `unknown`;
`completed` means a response was received, not necessarily a successful effect.
An HTTP timeout after dispatch has unknown effect even if local work was cancelled.
Error candidates carry a bounded code, retry disposition and sanitized explanation,
without tokens, source bodies, private account identity or arbitrary exception text.

Minimum operation mapping for PM proof allocation:

- `document.observe`: existing state/manifest/section reads; result is an immutable
  accepted document candidate with document/service/revision. The native semantic
  representation and asset identity must be specified by the representation proof.
- `source.locate` / `source.excerpt`: existing locate/source/source-text, logical
  fragments and revision; return service-validated locations or explicit unmapped,
  ambiguous/stale/unsupported. Copy never reconstructs Typst from rendered math.
- `source.highlightIntent`: existing requestID-bearing highlight; result is its
  domain status/receipt result. Request size remains at most the existing 262144
  bytes; receipt IDs retain the baseline 16–80 permitted-character constraint.
- `chat.list` / `chat.open`: existing document/service/revision plus fragments for
  open; no inference. Response carries conversations, attachment state, mutation
  version and stream sequence.
- `chat.draft` / `chat.send` / `chat.cancel`: existing conversationID/version;
  draft has bounded text, Send adds stable messageID/question/model, cancel targets
  the existing conversation job and must not mean global auth cancellation.
- `chat.observe`: existing POST events SSE; native applies only matching target
  and non-regressing conversation version/sequence. Stream termination means
  resubscribe/list, not automatic Send. It is not a generic event-log cursor.
- `account.observe` / explicit login/logout/management: retain separate root
  Homepage account/session operations, session/CSRF and authority scopes; document
  endpoints never become an account-management tunnel. Existing home request
  framing and 4096-byte bound remain distinct from document action limits.

No generic filesystem, SQL, process, arbitrary RPC or shell operation is needed.
Timeouts, response size, stream backpressure and recovery-store budgets must be
explicit proof parameters rather than silently inherited unbounded defaults.

*B10 — Negotiation and publication guards.* Baseline has specific capability
checks, e.g. editorAttachments equals 1 and source-history help support (E06/E08),
not a universal version negotiation endpoint. Initial proof uses a pinned
adapter/server compatibility fixture and known capabilities. Candidate future
negotiation offers supported protocol majors/minors and required/optional
capabilities, returns selected version, service incarnation and explicit supported
operations; it grants no authority. Choose a common major, allow only compatible
minor additions, fail closed on unknown required capabilities or mutation fields,
and ignore unknown optional response fields only when semantics remain defined.
No common major or missing required feature produces an upgrade/unsupported
state, with read-only fallback only for independently supported reading operations.
Never probe mutation support by executing a mutation, fabricate a success with
dummy methods, or silently use the legacy no-receipt highlight path.

Native adoption requires all of these guards:

+ Resolve exact managed document and service, then pin the complete service
  incarnation. Verify PID again where lifecycle readiness requires it; PID or port
  reuse alone is insufficient. Service restart invalidates attachment/session and
  in-flight generation assumptions even if content revision is unchanged.
+ Serialize adoption per native document view. Tag asynchronous conversion,
  geometry, transport and completion with request/view generation and immutable
  accepted identity. Reject late callbacks after document switch/close. Keep
  service publication, received candidate and visible native document distinct.
+ A selection/pressed-action ticket holds replacement. Retain the latest valid
  pending replacement, not an unbounded queue. Release explicitly, then atomically
  adopt it and restore only a still-valid position. A held old selection can be
  read/copied as appropriate; it cannot bypass current source mutation checks.
+ Paginated deltas retain their own order/base/full-reset rules. Missing base or
  reconnect requires a supported reset, not applying a diff to another revision.
  Chat version governs mutation concurrency; chat sequence governs stream progress.
  Neither is a universal document ordering counter.
+ Acknowledgment reconciles the original durable intent/ticket. It cannot clear a
  newer native selection or draft, paint a different revision, or turn an unknown
  effect into success. Cancelling rendering suppresses completion but does not
  promise interruption of synchronous work or an already dispatched writer.

= Lifetime and external compatibility

*B11 — Presentation lifetime is not service lifetime.* On document-view close,
invalidate its generation; stop its timers/requests/streams, native layout work
and owned recovery observers; release only its own editor attachment and local
resources. Do not call ReaderState.close, shared ChatAuth.close, or manager stop
because one window closed. Multiple native views, web/mobile and terminal/editor
consumers may still depend on the same service. A hidden view suspends/reduces
retry/layout work; it is not a command to stop requested previews.

On app quit, apply the same view disposal and persist bounded pending draft/intent
recovery before exit when possible. A request already dispatched may finish;
retain unknown outcome for reconciliation on next launch. Closing SSE alone does
not cancel host inference. Default recommendation is detach and preserve its
history; any “cancel my response on close” product policy needs an explicit
versioned cancel of the user's conversation and must be decided before implementation.
Do not cancel another view's job or shared OAuth to implement that preference.

Only the existing service lifecycle owner may stop/restart a managed service.
Shared runtime shutdown closes relays, listeners/document work and shared auth
lease through its owner; ParagraphChat closes its own jobs and borrowed auth stays
alive, while SourceHistoryClient reaps only its own helpers (E08/E09/E11).
Opening/closing a view does not make it the service owner even if it requested
normal manager startup. Configuration changes requiring service restart remain
explicit service operations, with validate-before-stop and recovery preserved.

Sleep/wake/network recovery reuses existing ReadingSessionController generations,
readiness and bounded power-aware reconciliation (E21). Retain accepted content,
zoom/position and selection hold. Reconnect observes current service identity
before actions; never auto-start an explicitly stopped service, reopen duplicate
windows, or retry unknown writes as part of a reconnect loop.

*B12 — Preserve other consumers.* Keep Homepage `/`, documents `/d/<reader-id>/`,
registered previews `/p/<parent-id>/`, legacy HTML redirect ports, original native
preview direct ports/allowed origins and existing CLI/environment contracts.
No native-only URL registry replaces ReaderManager. Fixed preview registry and
header allowlists keep account credentials/proofs, admin and editor-host routes
out of preview forwarding (E20/E22). A native client must not follow an arbitrary
redirect while carrying credentials or proofs. Resolve canonical service URLs
before mutations; retain legacy link compatibility independently.

Web/mobile retain existing browser readers and read-only remote account policy;
terminal remains its existing browser-backed presentation, with its own storage
origin and editor attachment lifetime (E18). The native macOS destination does not
silently rewrite the terminal contract to native drawing. Existing saved-focus
readers and `/api/focus` remain compatible, freshly validated and free of automatic
inference. HTML/terminal Ask and paged legacy saved-context are different current
capabilities, not proof of paged chat parity. Native source/history delivery must
coexist with Neovim and other engine clients. An unsupported native capability
must be visible without disabling an existing external client.

Accepted reader-architecture ownership/freshness contracts stay in force (E23).
Accepted flow-macos-app browser-opening/rendering wording needs an explicit later
native delta; asynchronous lifecycle and continuity remain requirements (E21).
The active unify-homepage-reader design's earlier paged-origin limitation is
extended by unify-preview-origin; remove-homepage-host-proof supersedes only its
blanket proof requirement for the scoped login/logout exceptions (E14/E22/E24).
Do not rewrite those active changes as if this investigation implemented them.

= Negative scenarios and proof handoff

*B13 — These are required fixtures to assign, all unexecuted here.* Each proof uses
isolated fake providers, temporary project/storage and scripted consumers; no real
account, browser profile or installed service. They are acceptance candidates for
follow-up tasks, not new dispatched work IDs.

#table(
  columns: (0.55fr, 1.8fr, 2.4fr),
  [Proof], [Adversarial input / interruption], [Required observable result],
  [P1],
  [Same port/PID reused; wrong document/service; file content changes with stable
   rendered text; compilation starts during action; old layout completes late.],
  [Manager rejects mismatches; server snapshot/source guards reject the write;
   last accepted document remains readable. Late work cannot publish or clear a
   new selection. Include multi-file fingerprints and failed compilation. B02/B10.],
  [P2],
  [Hold selection while two replacements arrive; close/switch view during layout;
   paged delta missing base; old acknowledgment after a new selection.],
  [One latest pending replacement, ordered adoption only after release; no stale
   paint/callback; supported full reset after gap. Native geometry/Unicode and
   paged fixtures must share observable guards without fabricated coordinates. B10.],
  [P3],
  [Crash before receipt insert, after insert before writer, after writer before
   result, after result before response; replay changed payload/same ID.],
  [Stored completed result is recoverable; committed unfinished receipt is
   uncertain and never reexecutes. New service cannot authorize old intent.
   No background new ID. Digest conflicts/receipt limit are visible. B03/B04.],
  [P4],
  [Two editor attachments; revoke one during verification; dead owner; dirty
   buffer or saved file changes before final write; forged registration input.],
  [Only original live service-bound attachment reaches its fixed editor; dirty
   buffer/file preserved; no disk fallback, executable choice or other attachment
   deletion. Concurrent HTML/paged observations preserve Rust sequence/metadata. B05.],
  [P5],
  [Send lost before/after SQLite commit; process dies before dispatch; reconnect
   after revision changes; duplicate/different question; later local draft edit.],
  [Authoritative read resolves ID/text when present; absent/unavailable remains
   unresolved without automatic inference. Context/model stay frozen; stale Send
   fails; newer draft survives old ack; interrupted history remains visible. B06.],
  [P6],
  [Wrong/missing/duplicate Host/Origin; proxy/Forwarded/claimed loopback; copied
   proof/cookie/CSRF; expired session; OAuth-only token requests cancel/identity.],
  [Existing independent guards fail before auth effects; 421/403 or sanitized
   fallback preserved. No native blanket bypass. Invalid callback state/nonce,
   signature or PKCE and refresh/logout failures preserve owner policy. B07.],
  [P7],
  [Second credential owner; private path symlink/foreign owner/source or Git
   location; SQLite concurrent mutation; restart/refresh invalidates session.],
  [Lease/path checks reject unsafe ownership before writes; no token copy;
   mutation version conflict requires reload; logout retains history/drafts and
   reports unconfirmed remote revocation. B07/B08.],
  [P8],
  [Explicit import malformed/oversized/wrong origin/document/offset unit; quota
   failure mid-commit; duplicate conflicting mark; rollback after native edits.],
  [Reject or stage unresolved data without source/auth/inference effects; previous
   native copy and all browser data intact. Round-trip Unicode/anchor fixtures,
   cancel/partial import and inert pending-send recovery. B08.],
  [P9],
  [Close one native view/app during source write, SSE, OAuth or source-history
   observation while browser/mobile/terminal/editor views remain connected.],
  [Only view resources detach; dispatch uncertainty persists; shared work/auth
   stays owned. Explicit service shutdown reaps only owned helpers and releases
   lease. Old callbacks cannot reopen UI; sleep/wake has one recovery loop. B11.],
  [P10],
  [Old/new server, absent negotiation, unknown required capability, optional field,
   removed prefix or down engine; direct and proxied clients at the same time.],
  [Pinned compatibility or explicit version result; unsupported is truthful;
   no mutation probe/fallback without receipts. Existing routes/ports, focus,
   editor, remote account policy and non-native clients remain compatible. B09/B12.],
)

PM can first assign P1/P2/P10 as a read-only native transport/representation
proof against isolated baseline fixtures; then P3/P4/P5/P6/P7 against the existing
service owners before enabling mutations or account management. P8/P9 cover
recovery/migration and lifetime together. Go only when exact proof revision,
capabilities, fixture inputs and observed results are recorded. No source/chat
mutation go decision follows from a rendering success or successful HTTP decode.
Real native rendering/selection/AX, installed-layout delivery, physical devices,
external API auth and performance remain separate subsequent gates.

Unresolved decisions for the integration owner:

- Native semantic representation and supported paged/HTML feature set; how one
  immutable accepted identity accompanies native text/source/anchor/geometry.
- Management bootstrap and, only if needed, native IPC peer trust, scope/expiry,
  revocation and consent navigation API/minimum OS. Do not enable management
  before this proof; OAuth-only login is not the answer to management authority.
- Negotiation location/schema, compatibility range and legacy read-only fallback;
  fingerprint-token exposure, response/stream budgets and cancellation API.
- Default inference policy on close; pending-intent retention, secure native
  recovery format, no-loss quit feedback, native offline format and import UX.
- Whether an IPC or library proof is justified by measured limitations. No
  throughput/latency advantage is assumed; preserving owners is the default.
- Paged-native source-action parity: preserve its Rust writer while deciding how
  to prove durable outcome and editor safety without conflating it with the HTML
  receipt contract. A native paged reading proof alone cannot enable source writes.

= Fixed-source evidence register

Each locator is `path:line` at the baseline stated above; ranges identify the
inspected implementation. Descriptions are static observations, not test results.

- E01: `tools/flow-reader/flow_reader/services/accepted_snapshot.py:9–31` —
  frozen snapshot, lock precondition and source freshness.
- E02: `tools/flow-reader/flow_reader/server/state.py:84–173` — acceptance,
  input-bound revision, atomic publication and failed-compile preservation.
- E03: `tools/flow-reader/flow_reader/services/source_mapping.py:151–205` —
  accepted source-range coverage, dependency paths, hashes and source units;
  `tools/flow-reader/flow_reader/services/source_mapping.py:13–19` — literal limits.
- E04: `tools/flow-reader/flow_reader/services/selection.py:19–81` — intent
  identity, edit-lock/state-lock capture, editor resolution and existing writer;
  `tools/flow-reader/flow_reader/services/source_highlight.py:161–300` — compile
  proof, exact selection, freshness and final write.
- E05: `tools/flow-reader/flow_reader/services/highlight_receipts.py:13–47` —
  entire-request digest, committed unfinished receipt and uncertain/no replay.
- E06: `tools/flow-reader/flow_reader/services/manager.py:204–248` — retained
  document plan; `tools/flow-reader/flow_reader/services/manager.py:250–309` —
  exact matching, managed PID/incarnation and local attachment registration.
- E07: `tools/flow-reader/flow_reader/services/editor_sync.py:16–94` — private,
  service/owner-bound tokens; `tools/flow-reader/flow_reader/services/editor_sync.py:111–140`
  — fixed Neovim verified-write delivery.
- E08: `crates/tinymist-project/src/source_history.rs:30–89` — source hash,
  UTF-8 ranges and bounded history; `crates/tinymist-project/src/source_history/store.rs:27–47`
  — serialized project-owned transactions;
  `tools/flow-reader/flow_reader/services/source_history.py:28–122` — transport,
  capability check and disposal of owned helpers only.
- E09: `tools/flow-reader/flow_reader/services/paragraph_chat.py:31–59` — SQLite;
  `tools/flow-reader/flow_reader/services/paragraph_chat.py:164–310` — snapshots,
  conversation attachment, open/draft/send/cancel and deduplication;
  `tools/flow-reader/flow_reader/services/paragraph_chat.py:342–441` — guarded
  tools/events, version versus sequence, newer drafts and borrowed auth lifetime.
- E10: `tools/flow-reader/flow_reader/server/http.py:35–96` — chat routes,
  Origin and read-only document auth; `tools/flow-reader/flow_reader/server/http.py:122–185`
  — highlight receipts, errors and SSE disconnect lifetime.
- E11: `tools/flow-reader/flow_reader/server/cli.py:89–145` — shared runtime
  composition, auth lease, provider borrowing and per-start capability;
  `tools/flow-reader/flow_reader/server/cli.py:171–182` — runtime shutdown;
  `tools/flow-reader/flow_reader/server/home.py:19–27` — process lease.
- E12: `tools/flow-reader/flow_reader/services/chat_auth.py:78–89` — fixed Node
  signature helper; `tools/flow-reader/flow_reader/services/chat_auth.py:118–187`
  — discovery, PKCE and consent opener; `tools/flow-reader/flow_reader/services/chat_auth.py:205–258`
  — callback validation; `tools/flow-reader/flow_reader/services/chat_auth.py:279–340`
  — refresh lock, token clearing, revocation uncertainty and generation.
- E13: `tools/flow-reader/flow_reader/server/home.py:55–89` — Host/peer/proof/cookies;
  `tools/flow-reader/flow_reader/server/home.py:106–169` — guarded account routes;
  `tools/flow-reader/flow_reader/services/home_account.py:20–138` — credential
  invalidation, session expiry, OAuth/management scope and sanitized status.
- E14: `openspec/changes/remove-homepage-host-proof/specs/homepage-account-auth/spec.md:5–107`
  — active scoped exceptions, independent guards, management and remote denial.
- E15: `tools/flow-reader/flow_reader/services/chat_storage.py:11–89` — private
  storage location, ownership, symlink/Git/source exclusion, mode and atomic JSON.
- E16: `tools/flow-reader/web/features/paragraph-chat/draft-recovery.js:1–78` —
  tab-local bounded copy and exact acknowledgment matching.
- E17: `tools/flow-reader/web/features/review-strikes/store.js:3–36` — bounded
  mark shape, namespace and text reconciliation;
  `tools/flow-reader/web/features/appearance/theme.js:3–38` — browser appearance;
  `tools/flow-reader/web/features/session/document-storage.js:1–19` — browser
  preference namespace. These are not host SQLite authority.
- E18: `openspec/specs/terminal-reader/spec.md:19–50` — stable storage/service
  and private attachments; `openspec/specs/terminal-reader/spec.md:87–119` —
  conservative navigation, dirty-buffer protection and legacy quotations;
  `openspec/specs/terminal-reader/spec.md:191–241` — Rust saved-edit ownership.
- E19: `tools/flow-reader/web/features/session/offline.js:10–92` — worker-scoped
  registration, explicit update, complete-save acknowledgment and disposal.
- E20: `tools/flow-reader/flow_reader/server/routing.py:18–79` — fixed prefix
  dispatch; `tools/flow-reader/flow_reader/server/routing.py:87–123` — scoped
  retirement and redirect-only compatibility ingress.
- E21: `openspec/specs/flow-macos-app/spec.md:8–68` — asynchronous readiness,
  continuity, selection hold and disposal;
  `apps/macos/ReadingSessionController.swift:242–263` — generation and PID recheck;
  `apps/macos/ReadingSessionController.swift:350–376` — cancellation/invalidation.
- E22: `openspec/changes/unify-preview-origin/design.md:17–60` — fixed upstreams,
  protocol/header boundaries and relay lifetime;
  `openspec/changes/unify-preview-origin/design.md:84–102` — direct-port coexistence,
  rollback and same-user loopback trust limitation.
- E23: `openspec/specs/reader-architecture/spec.md:8–45` — one policy owner,
  native location preservation, selection scheduling and lock/freshness contracts.
- E24: `openspec/changes/unify-homepage-reader/design.md:20–59` — shared routing,
  revised authority and lifecycle; its later preview routing extension is E22.
- E25: `crates/typst-preview/src/actor/webview.rs:256–290` — paged request/revision
  validation and status response; `crates/tinymist/src/tool/preview/compile.rs:209–332`
  — page/source resolution and isolated compile proof;
  `crates/tinymist/src/tool/preview/highlight.rs:470–524` — serialized original-byte
  checks and final source replacement, separate from HTML receipts/attachments.

= Verification record

The NR03 acceptance items map to B01/B09/B10 (transport and identity), B03–B05
(source/receipts/editor/history), B06/B07 (explicit Send and auth), B08
(storage/coexistence/rollback), and B11/B12 (lifetime/version/external clients).
P1–P10 are the negative-scenario and migration proof plan. E01/E05/E09/E15/E13
respectively anchor the required snapshot/receipt/chat/storage/account-guard review.

Executed minimum syntax check: preinstalled `typst 0.15.1`,
`typst compile --root . docs/tinymist/dev/native-reader-20261117-boundaries.typ -`
with output discarded, exit 0 and no diagnostics. Fixed-baseline path/line-range
validation also passed; it checks locator existence, not behavioral correctness.
Document scope and whitespace were checked separately before commit.
No generated Markdown or other
repository file is changed. Implementation, GUI/accessibility, real accounts,
performance and cross-client runtime compatibility remain unexecuted. Full docs
generation/checking is not claimed by the minimum syntax check.
