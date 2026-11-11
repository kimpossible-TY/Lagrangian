# Tasks

- [x] Separate message/context/composer presentation and shared settings entry.
- [x] Preserve geometry, selection, drafts and host authority.
- [x] Add token-based Markdown and bounded base/AMS math with source fallback.
- [x] Verify Node policy, fake-provider browser interactions, asset delivery and installation.
- [x] Inspect desktop/mobile source-rendered screenshots and record results.
- [x] Integrate shared account settings with the completed Homepage implementation.
- [x] Preserve focused Reader links across periodic inventory updates.
- [x] Reject source-local private storage, including case/Unicode path aliases.
- [x] Reconstruct publication ancestry without private local implementation commits.
- [x] Obtain independent final content/history privacy clearance. Cleared 2026-11-06 on main `eb22c529` (after #13/#14): reviewed `chat_storage.py` / `paragraph_chat.model_context` / `chat_auth.logout`, and re-ran focused suites `test_chat_storage` 11 OK, `test_homepage` 14 OK, `test_paragraph_chat` 22 OK. Evidence in verification.md. Live OAuth/TLS/Tailnet and physical devices remain out of scope for this clearance.
- [x] Avoid showing the submitted draft twice during streaming, while retaining recovery and new follow-up drafts.
- [x] Reduce composer footprint and localize known provider progress.
- [x] Verify locally with focused tests and an isolated browser, including interruption and mobile layout.
- [x] Preserve rejected-request notices and explain stale-context reselection; verify retry and draft recovery in local browsers and the installed Reader.
- [x] Recover unacknowledged drafts across reload/client updates without overwriting host drafts or resending accepted messages; verify server-rejected autosave, storage failure and reload recovery in Chromium/WebKit. Installed-browser fault injection remains unverified; see verification.md.
- [x] Measure live provider/tool/local-processing latency using bounded content-free diagnostics.
- [x] Reduce duplicate full source checks during streaming while preserving event/tool guards and idle cancellation; verify locally and in the installed Reader.

## Document exploration limits (2026-11-11)

- [x] Accept round 9 and later in the existing content-free timing report while retaining its independent 96-event bound.
- [x] Verify that diagnostic saturation does not terminate exploration; record Python gates, optional skips and remaining GUI/live coverage.

Verification: focused Python 38 OK without skips; reader-services 380 tests OK with 61 optional skips. The 18-tool-round turn completes after the 96-event report fills, and the report includes round 9 and later without content. Commands, skip causes and remaining GUI/live coverage are recorded in [the matching exploration follow-up](../add-reader-paragraph-chat/tasks.md#document-exploration-limits-2026-11-11).
