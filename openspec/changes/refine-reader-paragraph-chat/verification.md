# Verification

The publication branch starts at the existing remote Homepage proposal and merges
only current public main before applying the sanitized final implementation as a
fresh commit. Earlier local implementation commits remain intact outside this
publication ancestry. Final independent content/history privacy clearance is
required before any push. No application install/restart, remote write, live
sign-in or model inference was performed.

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
  the still-required final publication/history audit.
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
branch pushes or pull requests. No dispatch, main merge or auto-merge is enabled.
The normal main delivery pipeline remains outside this publication authorization.
