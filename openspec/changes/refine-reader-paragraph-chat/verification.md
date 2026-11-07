# Verification

## Local dogfooding follow-up

An actual Reader question on 2026-11-07 exposed a duplicated submitted draft,
English progress labels and an oversized composer. The isolated local Reader was
then exercised through Chrome with the fake provider; the question appeared once,
the composer was empty during streaming, and Korean progress was visible.
The local browser suite passed 42 checks, including interruption, lost
acknowledgment, a new draft during streaming and 390px viewport overflow. This
does not measure live inference latency or verify the previous Ask-open failure.

On a further live Reader check, the same prose-and-inline-math selection again
failed to open chat with HTTP 400; the response did not identify the validation
failure. A plain-text follow-up completed by the 9-second observation, compared
with the earlier 26.5-second observation after document reading. These are single
observations, not a controlled latency comparison. The mobile layout now skips
document-ink scanning when margin placement cannot be used. Local Chromium
verified the mobile scan is absent and retained wide margin placement (43 checks,
zero page errors); live device performance and the 400 cause remain unverified.

The live 400 was traced to a selection-context boundary splitting a UTF-16
surrogate pair in a mathematical character. The request's suffix contained an
unpaired surrogate, and saving that context raised UnicodeEncodeError. A local
browser fixture reproduced the HTTP 400 before the fix. After adjusting selection
and context boundaries to preserve complete Unicode characters, both prefix and
suffix boundary cases open successfully; the Chromium suite passes 45 checks.
The original affected paragraph was also loaded into an isolated local Reader
with disposable storage and a fake provider. Selecting the same prose and
inline-math range through Chrome opened the composer successfully with the
modified frontend; no live Reader or user conversation store was changed.

For latency triage, three read-only samples of the actual PDE project's accepted
inputs (187 dependencies, warm local filesystem) gave median 4.5 ms for source
signature and 8.4 ms for content fingerprint (maxima 4.6 and 30.7 ms). These
operations recur during streaming; this small sample does not establish their
aggregate cost or explain the live first-answer delay.

Run 42359100049 installed Reader revision `afa20501` on 2026-11-07. The existing
browser tab initially retained the previous service worker after a normal reload;
using the Reader's update action activated the new client. In the installed
Reader, selecting the previously failing prose-and-math range opened the chat,
and a real GPT-6-Luna question displayed its first answer by the 9-second
observation and completed by 15 seconds. The submitted question was not repeated
in the composer. This one request does not isolate provider and transport times.
iPhone Mirroring could not connect, so physical-device verification remains open.

A later live follow-up after run 42360343415 exposed a recovery failure: the
accepted document changed while a draft was open, and subsequent send requests
returned HTTP 409 without adding a message. The draft survived reopening, but
the generic request error was overwritten by the old answer's completed status.
The composer now explains required reselection before enabling Send for an old
context, and rejected-request notices survive ordinary renders until recovery.
The new browser regression timed out on the original implementation, then passed
all 49 checks in each of Chromium and WebKit after the fix. The lost-acknowledgment
fixture now waits for its rejection to be delivered before removing interception,
avoiding a WebKit test race. Focused Node checks (19), ESLint, changed-JS
Prettier and strict OpenSpec validation pass. Existing unrelated formatting drift
in reader.css remains; the changed status selector follows Prettier formatting.
Installed-Reader recovery verification is pending.

The publication branch starts at the existing remote Homepage proposal and merges
only current public main before applying the sanitized final implementation as a
fresh commit. Earlier local implementation commits remain intact outside this
publication ancestry. The implementation was subsequently pushed and merged to
main without the independent final content/history privacy review at merge time.
That review was completed on 2026-11-06; see the clearance record below.
The implementation checks below used no application install/restart, live sign-in
or model inference.

- Node HTML/shared policy and architecture tests: 276 passed, zero skipped.
- Final Reader services: 305 tests total; 247 passed and 58 optional integration
  tests skipped. Compiler/source-history prerequisites, physical devices and live
  OAuth/inference are not verified by those skips. Existing install/static-asset
  checks pass with the new modules and versioned renderer components.
- Chromium paragraph chat: 40 checks passed, zero page errors, using fake local
  OAuth/provider only. Covers immutable question context, stale snapshots,
  reselection, duplicate send/lost acknowledgment, streaming/interruption,
  partial failure/retry, Markdown/TeX/code escaping, late math guards, shared
  settings/focus, mobile overflow, exact margin geometry and annotations.
- Chromium Homepage: 36 checks passed, zero page errors. Added a real 15-second
  polling-timer regression proving link identity/focus survive status changes;
  removal of a focused destination moves focus to the document section. The
  earlier detached-node target measurement is also measured against current DOM
  with the original 44px tolerance applied to both axes for all links.
- Focused storage boundary tests: 9 passed. Before the fix, the temporary Git
  checkout/worktree, alias and Homepage pre-sink cases reproduced the problem.
  Final checks reject before creation or chmod, including relative/dotdot paths,
  case and Unicode-equivalent non-Git source names, and canonical parent aliases
  into source. Ordinary external storage, private-file permissions and external
  parent aliases remain valid. Leaf symlinks remain rejected.
- A separate read-only storage review found the macOS identity bypass; the
  revised samefile ancestor check closes it. Its final review found no concrete
  remaining storage bypass or compatibility regression. This is separate from
  the final publication/history audit recorded below.
- Reader lint, changed-file Prettier, strict OpenSpec and canonical Typst checks
  pass. Known personal absolute paths and private Library references were removed
  before the fresh implementation commit; metadata prechecks report no matches
  in the outgoing changed files. Ignore patterns are defense in depth only.
- Desktop 1440px and mobile 390px previews were visually inspected with a
  fictional variational-calculus document/history at reading size 17px. They are
  production-source fixtures, not a live installed UI. The canonical inline SVG
  L is retained. Unsupported answer mathematics remains literal, with no raw
  HTML, remote image or dynamic TeX extension capability.

The repository workflow triggers on main pushes or explicit dispatch, not feature
branch pushes or pull requests. The implementation has since merged to main;
the earlier no-push publication state no longer applies. This record does not
verify deployment or installation from the normal main delivery pipeline.

## Independent content/history privacy clearance (2026-11-06)

Reviewer: Lagrangian (PM), independent of the original merge authors' unchecked claim.
Scope: content and conversation-history privacy on main at `eb22c529` (includes PR #13 S1–S5 and PR #14). Not a live deploy or TLS activation review.

### Code review findings
- `chat_storage.private_directory` rejects source-project containment (including `samefile` ancestors), Git worktrees other than a resolved `$HOME` root, symlinks, and non-owner UIDs; creates `0700` directories and `0600` files before use.
- `paragraph_chat.model_context` admits only `documentID`, `revision`, `selection`, and `paragraph` into model history — no private filesystem paths.
- `chat_auth.logout` clears tokens and notices only; it does not delete `history.sqlite3` or drafts. Durable history ownership stays with `ConversationStore`.
- Document `/api/chat/auth` mutations remain rejected (read-only document account); Homepage management retains session/CSRF/`no-store` isolation. Read-only ingress sessions cannot evict management sessions (PR #13 S1).

### Re-run evidence (this clearance)
- `python3 -m unittest discover -s tests -p 'test_chat_storage.py' -v` → 11 passed
- `python3 -m unittest discover -s tests -p 'test_homepage.py' -v` → 14 passed
- `python3 -m unittest discover -s tests -p 'test_paragraph_chat.py' -v` → 22 passed
  Notable cases: storage boundary rejections before mkdir/chmod; logout invalidation without remote-identity leakage; document account read-only; drafts/history survival; no exception-secret echo; no source edits via tools.

### Explicitly out of scope (unchanged)
- Live ChatGPT OAuth, paid inference, Tailnet/TLS provisioning, physical iOS/macOS browsers, and Mac auto-install from this clearance run.
- Those remain activation/ops verification, not blockers for checking this content/history privacy task.

Verdict: **cleared** for content/history privacy as specified by the refine-reader-paragraph-chat and add-reader-homepage contracts on the reviewed main tip.

