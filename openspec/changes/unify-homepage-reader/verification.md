# Verification

## Scope and delivered behavior

Developed only in `/Users/taeyoung/Developer/lg-homepage-unify` on
`feat/homepage-reader-unify`, starting and finishing at HEAD `e8904733`.
No commits, pushes, Rust builds, live launchd/app/Reader changes, live OAuth,
provider inference or TLS/Tailnet activation were performed.

`serve.py --managed --data <config-directory>` now serves Homepage at `/` and
all configured HTML Readers under `/d/<reader-id>/`. `home.py` aliases this
runtime. Optional `shared` manager configuration selects a common launch plan,
label and PID; existing direct document CLI remains supported during migration.
Old document ports are redirect-only listeners in this same process. The paged
entry redirects to its existing native view; paged engine/protocol migration is
explicitly excluded. One ChatAuth/provider is injected into document states.

## Passed checks

| Command | Result |
| --- | --- |
| `openspec validate unify-homepage-reader --strict` | Passed. |
| `PYTHONDONTWRITEBYTECODE=1 PYTHONPATH=tools/flow-reader/tests python3 -m unittest test_homepage test_chat_storage test_paragraph_chat test_routing test_reader_runtime test_manager -q` | 89 passed, no skips: Homepage 14, storage 11, paragraph-chat 22, routing 9, runtime 8, manager 25. |
| `PYTHONDONTWRITEBYTECODE=1 PYTHONPATH=tools/flow-reader/tests python3 -m unittest test_homepage test_chat_storage test_paragraph_chat test_routing test_reader_runtime test_manager test_audit_reports test_source_history -q` | Earlier integration run: 102 tests, 95 passed, 7 optional real-engine tests skipped. Later required run above covers the final added runtime cases. |
| `node --test tools/flow-reader/tests/test_*.mjs tools/reader-common/tests/*.mjs` | 281 passed, none skipped. Includes delivered Homepage proof handling and legacy worker retirement. |
| `node --test tools/reader-common/tests/architecture.mjs` | 2 passed; also included in the aggregate Node run. |
| Reader ESLint command from `package.json` using the temporary dependency installation | Passed with zero warnings/errors. Final new worker/account tests also linted. |
| Prettier 3.6.2 check of modified/new JS | Passed. |
| `typst compile --root . docs/tinymist/dev/reader-architecture.typ /tmp/homepage-unify-architecture.pdf` | Passed with the preinstalled compiler. |
| `typst compile --root . docs/tinymist/dev/terminal-reader.typ /tmp/homepage-unify-terminal.pdf` | Passed with the preinstalled compiler. |
| Terminal guide HTML export and text inspection | Passed; shared routes, migration and retained source/navigation sections present. |
| `node scripts/link-docs.mjs --check` | Passed; generator ran without derived-file changes. |
| `git diff --check` and backup comparison against HEAD | Passed. `manager.py.bak` exactly preserves the original plist generator. |

The checkout lacked Node dependencies. Test/lint dependencies were installed
only beneath `/tmp/homepage-unify-browser`; a temporary ignored `node_modules`
symlink was used for module resolution and removed after verification.

## Contract evidence

- Routing tests exercise Homepage and two real synthetic ReaderStates on one
  listener, separate document identities, relative assets, section/offline APIs,
  worker scope, canonical slash, missing IDs and traversal rejection.
- Prefixed chat open/status uses existing accepted snapshots. Cross-document and
  stale revisions return 409; document login/cancel/logout return 403; prefixed
  admin routes return 404.
- Every account operation returns 403 for a simulated non-loopback transport peer
  and proxy ingress even with copied capability, cookie and CSRF. Genuine local
  proof/session/CSRF succeeds. Cookie/CSRF without capability cannot mutate or
  disclose account registration identities.
- Runtime fixtures bind Homepage/document and old-port listeners in one PID,
  share one provider/auth, observe loaded states without launchctl/probes, and
  dispose state/lease/capability on startup or bind failure before compilation.
  Real state construction verifies lazy conversations borrow the shared owner.
- Manager fixtures verify one job label and `--serve-all` plist arguments,
  preserved per-document compiler/focus settings, conflicting-port rejection,
  and prefixed terminal attachment with existing PID/document checks.
- Delivered Homepage module tests exercise unlock, login, cancel, sign-out and
  restart recovery. Proof stays in module memory and is cleared from the input,
  on logout and disposal. Legacy worker execution removes only its old scope's
  caches and unregisters, preserving other documents' caches.

## Broader checks and limits

`openspec validate --all --strict` reported **40 passed, 4 failed**. The new
change passed. Unmodified existing failures are:

- `change/add-tinymist-rust-tool-skill`: requirement exceeds 500 characters.
- `spec/configuration-wide-client-options`: requirement exceeds 500 characters.
- `spec/output-path-patterns`: missing Purpose/Requirements sections.
- `change/rename-product-lagrangian`: requirement exceeds 500 characters.

`PYTHONDONTWRITEBYTECODE=1 python3 scripts/test-reader-services.py` reported
**333 tests: 269 passed, 61 skipped, 3 errors**. The final required feature suites
were run separately after additional runtime tests and all 89 passed. Broad-suite
errors are in unchanged existing fixtures:

- `test_editor.NeovimWriterTests.test_real_neovim_rpc_rejects_dirty_buffer_then_saves_verified_edit`: Neovim `edit!` RPC exits 2.
- `test_neovim_view.NeovimViewTests.test_interactive_shell_keeps_editor_in_foreground_during_start`: sandbox denies `ps`.
- `test_neovim_view.NeovimViewTests.test_unknown_sixel_geometry_preserves_editor_and_job_control`: sandbox denies `ps`.

The skips require optional compiler packages, a compatible prebuilt engine or
companion Tail Hosting checkout. No Rust build was attempted to supply them.

`home-browser.mjs` and the updated prefixed `paragraph-chat-browser.mjs` were
attempted using Playwright 1.56.1 and installed Chrome. Chrome aborts at launch
with SIGABRT / EPERM under this sandbox, so browser interactions and physical
devices are **not verified**. Fake-provider HTTP and delivered-module tests pass.
No bypass or live-browser/service modification was attempted.

## Activation, rollback and remaining risks

No activation was performed. Canonical terminal-reader guidance and design.md
specify saving config/launcher/plists, stopping old jobs, selecting shared mode,
generating one shared Reader job and preserving old ports for redirects. No
second Homepage job is required. Restore saved config/launcher/plists and the
previous immutable release for rollback; credentials/history/drafts need no
schema migration. `manager.py.bak` is the requested worktree backup, not a live
LaunchAgent backup.

Operator verification remains for actual installed-layout activation, occupied
ports, HTTPS proxy ingress, browser worker retirement and physical devices.
Inventory is captured at startup; configuration changes require restarting the
shared job. A shared-process failure affects every HTML Reader. Paged engines
remain native processes. Cross-origin browser review/position preferences remain
on their old origin; private conversation history/drafts retain document identity.

PR #16 S1/S2 follow-up: `--managed` (including the `home.py` shim) requires explicit `config.shared` before resolving documents or binding ports; shared per-document stop/restart is refused unless explicitly requested with `--control stop-shared|restart-shared ID`; shared start and ownership guards are preserved.

PR #16 S3 follow-up: flow-app install/rollback/recovery and migrated-reader restarts deduplicate shared jobs by label and use explicit stop-shared/restart-shared controls (including recovery guidance); waits, health checks and starts use one representative ID; 8 focused and 3 existing isolated migration tests passed.
