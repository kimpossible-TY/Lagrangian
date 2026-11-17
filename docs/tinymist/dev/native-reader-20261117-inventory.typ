#set page(paper: "a4", flipped: true, margin: 12mm)
#set text(size: 8.5pt)
#set par(leading: 0.5em)
#let src(path, lines) = text(size: 7pt, raw(path + ":" + lines))

= Native Reader migration inventory — NR01

Project: `kimpossible-TY/Lagrangian`. Baseline: `5d71618e7ee320edbe759511fe634024fc8104a6`.
Every source location below refers to that commit, inspected with `git show`, not a live installation.
This is the canonical condensed inventory of F01–F18 from the planning `MIGRATION.md`;
the planning evidence register is a locator, not proof of behavior. No duplicate blob register is maintained here.
“Current” means static implementation evidence; “Preserve” states migration acceptance, not native support already delivered.
“Open” requires a later design decision or proof. Final delivery must render the body and interactions natively;
WKWebView, an embedded web body, or a web shell does not satisfy that goal. One app need not mean one process.

== Feature transfer contract

#table(
  columns: (3.3fr, 2.4fr, 2.2fr, 1.7fr),
  align: top, inset: 5pt,
  table.header([*ID / current owner and fixed source*], [*Preserve in native*], [*Current support / explicit difference*], [*Open*]),
  [*F01 — Profiles, projects, home/settings* \
    ProjectService / SettingsStore; #src("apps/macos/ProjectService.swift", "13–62"); #src("apps/macos/FlowApp.swift", "25–29").],
  [Profile identity/schema; persist before UI adoption; validate before stopping; recover prior settings/service on update failure.],
  [AppKit profile management exists; the Reader Homepage is a separate host feature (F17), not an existing native document library.],
  [Window/tab model, last-document restoration, HTML-only profile inventory.],
  [*F02 — Read and readiness* \
    ReadingSessionController; #src("apps/macos/ReadingSessionController.swift", "108–145,238–299"); #src("apps/macos/FlowApp.swift", "10–18").],
  [Nonblocking requests; cancellation/generation/PID guards; one open per intent; distinguish command, process, available document and displayed native frame.],
  [Read currently invokes `NSWorkspace.shared.open` after readiness. Available engine output does not prove successful native presentation.],
  [Native document adoption/readiness acknowledgment and failed-frame recovery.],
  [*F03 — Semantic body and accepted sections* \
    Python document/server owners; #src("tools/flow-reader/flow_reader/document/sections.py", "125–144"); #src("tools/flow-reader/flow_reader/server/state.py", "84–135").],
  [Real text, headings/outline, paragraphs, links, anchors, tables, figures and notes; failed compilation retains the last accepted document.],
  [Accepted HTML sections carry semantic identity; they are not a ready-made native layout model. Publication includes saved-input validation.],
  [Native model input, normalization and explicit loss diagnostics.],
  [*F04 — Paged vector document* \
    Rust preview protocol / concrete renderer; #src("crates/typst-preview/src/protocol.rs", "3–37"); #src("docs/tinymist/dev/reader-architecture.typ", "9").],
  [Page order/coordinates, fonts/vector fidelity, ordered deltas and full-current reset; retain paged reading alongside reflow.],
  [`new,` resets state before merging; `diff-v1,` is incremental. Existing WASM/SVG consumption is not proof of native decoding.],
  [Native vector consumer and measurable fidelity; PDF alone cannot replace other actions.],
  [*F05 — Math, graphics, tables, annotations* \
    Concrete HTML renderers; #src("tools/flow-reader/web/rendering/math/renderer.js", "9–11,64–85"); #src("tools/flow-reader/web/rendering/graphics/canvases.js", "1–7"); #src("tools/flow-reader/web/rendering/tables.js", "34").],
  [Reflow with width/font changes; equation numbers/references, CeTZ, relations, decorations, authored annotations and footnotes; visible fallback/loss reporting.],
  [HTML uses MathJax and DOM/worker geometry. These implementations cannot be assumed interchangeable with native text layout.],
  [Native math/figure shaping, hit testing and supported fallback coverage.],
  [*F06 — Selection, copy and acknowledgment* \
    Concrete selection plus shared press/submission policy; #src("tools/typst-preview-frontend/src/features/selection/actions.ts", "4–22,107–129"); #src("tools/flow-reader/web/features/selection/controller.js", "130–175").],
  [Pointer/keyboard selection, Unicode/graphemes; verified whole-formula Typst copy; acknowledgments bound to the submitted selection and revision.],
  [HTML source-text lookup and paged coordinates differ. Glyph/pixel positions do not establish a source range; delayed results must protect newer selections.],
  [Native AX selection; partial/ambiguous math-copy failure behavior.],
  [*F07 — Source Highlight* \
    Python selection/snapshot/receipt owners; #src("tools/flow-reader/flow_reader/services/selection.py", "19–65"); #src("tools/flow-reader/flow_reader/services/accepted_snapshot.py", "20–31"); #src("tools/flow-reader/flow_reader/services/highlight_receipts.py", "28–46").],
  [Service/document/revision and saved-source freshness; existing lock order and verified writer; reconcile optimistic paint against durable results.],
  [This action modifies source. An unfinished durable receipt returns uncertain and must never execute automatically again.],
  [Native intent/paint recovery and user-visible uncertain outcome.],
  [*F08 — Review strikes* \
    BoundedReviewStore plus concrete geometry; #src("tools/reader-common/review-strikes/bounded-store.js", "2–64"); #src("tools/flow-reader/web/features/review-strikes/store.js", "26–35").],
  [Local paint only; bounds, undo/clear, storage failure handling and anchor validation. Keep source Highlight distinct.],
  [HTML uses `flow-reader:${id}:strikes:v1`; paged owns its mark geometry. Native storage cannot assume direct access to browser localStorage.],
  [Coexistence versus explicit import, storage format and migration consent.],
  [*F09 — Outline, references, return/change navigation* \
    Shared policy / concrete positions; #src("tools/reader-common/navigation/reference-return.js", "1–27"); #src("tools/reader-common/navigation/change-location.js", "2–24").],
  [One latest return origin consumed only by accepted completion; recent-change navigation remains independent; validate section/page destinations.],
  [Semantic anchors and page coordinates remain distinct; a common policy does not authorize invented coordinates.],
  [Native position representation and restoration across layout changes.],
  [*F10 — Source history and editor integration* \
    Rust project store / Python attachments; #src("crates/tinymist-project/src/source_history/store.rs", "13–31"); #src("tools/flow-reader/flow_reader/services/editor_sync.py", "16–30,102–140").],
  [Single saved-edit owner, locked project records preserving renderer metadata; exact editor attachments, verified source jumps/writes and unsaved-buffer safeguards.],
  [Native is another presentation consumer. Closing its view must not stop a shared service or revoke another editor's attachment.],
  [Native attachment/disposal protocol and terminal/editor regression fixtures.],
  [*F11 — Paragraph Ask and saved-focus compatibility* \
    ParagraphChat / HTML controller; #src("tools/flow-reader/flow_reader/services/paragraph_chat.py", "164–189,212–245"); #src("tools/flow-reader/web/features/selection/controller.js", "4–11,41–43"); #src("tools/typst-preview-frontend/src/features/selection/actions.ts", "76–78").],
  [Inline anchor, streaming/cancel, independent conversations/model selection, unresolved history; safe Markdown and completed-answer math. Preserve nonexpiring legacy records and exact project/entry lookup (#src("docs/tinymist/dev/reader-architecture.typ", "12")).],
  [HTML/terminal use Ask; paged still has Save for Codex, not Ask. `/api/focus` remains compatibility storage, not chat history or inference.],
  [Native chat geometry and paged/native adoption scope; never count paged Ask as existing parity.],
  [*F12 — Draft and lost-ack recovery* \
    Host chat store / local DraftRecovery; #src("tools/flow-reader/flow_reader/services/paragraph_chat.py", "247–285"); #src("tools/flow-reader/web/features/paragraph-chat/draft-recovery.js", "1–9,56–77").],
  [Explicit Send only; stable message-ID deduplication, frozen context, stale-send rejection; authoritative reread after lost ack without deleting newer drafts.],
  [Tab-local recovery is separate from host SQLite history/drafts. Uncertain Send must not trigger automatic duplicate dispatch.],
  [Bounded native recovery-copy location and reconciliation UX.],
  [*F13 — ChatAuth and account authority* \
    ChatAuth / HomeAccount; #src("tools/flow-reader/flow_reader/services/chat_auth.py", "1–4,91"); #src("tools/flow-reader/flow_reader/services/home_account.py", "20–49").],
  [Existing credential, PKCE/state/nonce/signature, refresh/revocation and authority owners; preserve private history/drafts and explicit login/logout.],
  [Document auth is read-only status/catalog. OAuth-only login/logout exception does not grant registration/management rights or remove request guards.],
  [Native authorization bridge and equivalent local authority proof.],
  [*F14 — Recovery, power and lifecycle* \
    Native environment/session and reader recovery adapters; #src("apps/macos/NativeReadingEnvironment.swift", "25–40"); #src("apps/macos/ReadingSessionController.swift", "303–313"); #src("docs/tinymist/dev/reader-architecture.typ", "19").],
  [Sleep/wake/network reconciliation, bounded reconnect, obsolete callback rejection and disposal; retain accepted content, viewport/zoom and selection-held replacement.],
  [Native lifecycle and browser page lifetime differ. Native service readiness alone does not restore a reading viewport.],
  [Native selection hold, hidden-view lifetime and power-aware rendering policy.],
  [*F15 — Appearance, zoom, settings and accessibility* \
    Concrete appearance owner / AppKit feedback; #src("tools/flow-reader/web/features/appearance/font-size.js", "5–31"); #src("apps/macos/FlowApp.swift", "231–243").],
  [Automatic/explicit themes, reading font/zoom with anchor-preserving preview/rollback; keyboard focus and semantic VoiceOver/selection/math access.],
  [AppKit status accessibility exists; it proves nothing about a future native body AX tree. Web visual review remains incomplete (below).],
  [Minimum OS, AX math representation and real native interaction verification.],
  [*F16 — Offline, download and export* \
    Accepted inventory / transactional cache; #src("tools/flow-reader/flow_reader/server/offline.py", "19–29"); #src("tools/flow-reader/web/features/session/offline-worker.js", "1–16,26–67").],
  [Last complete snapshot, atomic replacement, cancellation/failure recovery; read-only offline access; retain PDF export availability.],
  [Web cache is not native persistence. Offline content cannot authorize current source writes or establish current authentication.],
  [Native snapshot/asset format, protection policy and export UI/API.],
  [*F17 — Shared host and external consumers* \
    Routing / HomeInventory / ReaderManager; #src("tools/flow-reader/flow_reader/server/routing.py", "18–28"); #src("tools/flow-reader/flow_reader/services/homepage.py", "12–22,45–57"); #src("tools/flow-reader/flow_reader/services/manager.py", "51–58").],
  [Homepage `/`, `/d/<id>/`, registered `/p/<id>/`, old direct URLs/ports; web/mobile/terminal/editor and saved-focus compatibility; exact service ownership.],
  [The shared host is already distinct from native AppKit. A native view must not retire external consumers or gain credential authority implicitly.],
  [Native composition over existing services, compatibility/version boundaries.],
  [*F18 — Packaging and updates* \
    App packaging / workflow / hash owners; #src(".github/workflows/flow-engine.yml", "67,129–143"); #src("scripts/engine-input-hash.py", "29–32,63–82"); #src("scripts/reuse-engine-artifact.py", "65–89").],
  [Latest Swift/resources even on engine cache hits; engine provenance separate from reader headSha/checksums; same-run delivery, installed layout and rollback.],
  [Swift is outside engine hash; cache hit reuses the app too. HTML has a separate bundle; paged frontend/DOM and reader-common are engine inputs.],
  [App/resource artifact invalidation and installed-delivery proof before rollout.],
)

== Accepted contracts and active supersession

These are bounded interpretations for the later native OpenSpec delta, not edits to or archival of existing changes.

- *F01/F02/F14:* #src("openspec/specs/flow-macos-app/spec.md", "8–49") requires browser opening and reader-owned rendering. Native document opening must explicitly replace that presentation requirement while preserving async readiness, power and continuity. #src("openspec/specs/reader-architecture/spec.md", "8–45") retains shared policy, concrete geometry, delivery and freshness ownership; cross-language reuse shares contracts rather than requiring JavaScript inside native UI.
- *F03–F06/F15/F16:* #src("openspec/changes/add-responsive-reader/specs/responsive-reader/spec.md", "111,146–147,912–924") retains paged/PDF delivery, mathematical/annotation meaning, visible loss and last-complete offline snapshots. Its web mechanisms are not a native technology selection; native presentation needs explicit deltas without silently dropping fidelity.
- *F11/F17:* #src("openspec/changes/add-reader-paragraph-chat/design.md", "60,106,134") replaces HTML/terminal Saved for Codex UI with Ask, supersedes annotation coexistence only for active paragraph chat, and retains paged legacy UI plus `/api/focus`. #src("tools/flow-reader/flow_reader/server/http.py", "124,210") confirms the focus route survives.
- *F11/F12/F13:* #src("openspec/changes/refine-reader-paragraph-chat/design.md", "3–14,25–44,68–71") refines safe answer presentation, recovery and the read-only connection dialog. #src("openspec/changes/redesign-inline-chat/design.md", "5,9–40") supersedes folded-summary/distant-margin geometry with a paragraph logo and local capsule/flow fallback; recovery, source guards and model ownership remain. CSS pixel constants are explicitly web parameters, not native constants.
- *F13/F17:* #src("openspec/changes/unify-homepage-reader/specs/reader-host/spec.md", "9–36") replaces the old separate-Homepage-origin assumption; #src("openspec/changes/unify-preview-origin/specs/preview-proxy/spec.md", "9–27") adds registered preview HTTP/WebSocket paths. #src("openspec/changes/remove-homepage-host-proof/specs/homepage-account-auth/spec.md", "5–22") supersedes only the blanket host-proof gate for guarded local login without registration selection and logout, retaining management authority and protocol validation.
- *F11/F15:* Browser review is still unchecked in #src("openspec/changes/redesign-phase1-tokens-home/tasks.md", "11"), #src("openspec/changes/redesign-phase2-reader-chrome/tasks.md", "10"), #src("openspec/changes/redesign-phase3-chat-panel/tasks.md", "11–12"), and #src("openspec/changes/redesign-phase4-preview/tasks.md", "8"). Checked implementation tasks do not complete those reviews or any native GUI gate.

== Verification boundary

NR01 verifies document syntax and fixed-source traceability only. It does not establish product behavior, GUI/VoiceOver correctness,
native decoder feasibility, performance, live authentication, installed delivery or device coverage. The open cells remain decisions/proof gates
for subsequent design tasks; no renderer technology or data migration is approved by this inventory.
