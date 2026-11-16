# Developer worktree recovery, 2026-11-16

The nine development worktrees below were preserved before any cleanup. Each
`archive/developer-20261116/<worktree>` branch is published in this repository.
The original directories, worktree heads and pending changes were left in place.
These branches are recovery snapshots, not claims that their old implementations
should replace current `main`.

The integration baseline is `7dc507a4d1d354cec8e99f6126170f8f23237f33`.

| Worktree | Published snapshot | Integration decision |
| --- | --- | --- |
| `lagrangian-chat-redesign` | `22f4d0d3c51a866413591c3e617aa67322d2a218` | Already an ancestor of the baseline; retain current inline-chat implementation. |
| `lg-homepage-library-followup` | `9bec593e2d33b6002c7c2494d2499d67a23fd995` | Already an ancestor; no source replay. |
| `lg-homepage-library-redesign` | `fff0a8d75cc99289d5989f68653615269dd51a4c` | Already an ancestor; no source replay. |
| `lg-homepage-spec` | `498b149141ddc617946f3c33983fb010157ea1d9` | Preserve the original commits. Homepage behavior has evolved on main; do not overwrite the current implementation with this earlier version. |
| `lg-homepage-unify` | `7e2f35d9bcacfbbcddeaab35adf5070172789414` | Preserve the exact untracked `manager.py.bak` in its snapshot. The implementation tree of its parent `9800297a` matches the merge result of PR #16; do not install the backup file. |
| `lg-logo-home-doc-review` | `9438b9b4bb6c99fdcfbdf7b196024e1c64fcc5c5` | Already an ancestor; no source replay. |
| `lg-paragraph-chat-redesign` | `be299ac15021b050d8b333e01196ae31558e300d` | Preserve the local history. Retain the later inline-chat, draft recovery and settings integration on main. |
| `lg-preview-unify` | `18524eeeedbeff9dea023026a8b4676ca8cdc789` | Preserve five modified and twelve previously untracked files. Main already has the proxy plus newer CSP, bounded WebSocket drain and EOF teardown fixes and tests; replaying the old files would remove those fixes. |
| `lg-reader-review-ci` | `7a8eadfdecbef7f456145ab1e529583b06b0659c` | Integrate the final local-only duplication pilot: `.jscpd.json`, `report:duplicates`, and canonical development documentation. Do not revive the intermediate `reader-quality.yml` workflow removed by this branch's second commit. |

Snapshots retain the original commits as ancestors. The two new snapshot commits
add pending source files to their respective old heads; they do not amend or
rewrite those original commits. Recovery uses a normal clone or checkout of the
corresponding published branch. The nine branches were also exported to a
self-contained local Git bundle, fetched into a separate bare repository and
checked with `git fsck --full`. Snapshot trees and all eighteen newly captured
file blobs were verified after that independent restore.

Ignored screenshots, duplication reports, generated PDFs and an empty editor log
(77 non-cache files) are retained in a local evidence archive with a SHA-256
manifest. They were not published to this public repository. Python bytecode,
dependency trees and dependency symlink targets were excluded from source
snapshots. No original worktree or evidence file was deleted. The separate
Revmux prototype directories were not imported into this repository.

The local archive and the Git bundle are additional recovery copies; no claim is
made that Google Drive has uploaded them or that a production app was tested.

The local-review utility deliberately imports the final result of `f1fd8b91` and
`7a8eadfd` for the configuration, package command and canonical Typst development
guide. The Markdown development guide was regenerated with `link-docs.mjs`.
Validation passed: duplication reporting scanned 165 files and reported two
advisory clones without enforcing a threshold; both existing architecture tests
passed; generated documentation matched; and the development guide compiled to
PDF without warnings. The initial architecture run lacked TypeScript in the
isolated checkout; the final run used the existing dependency tree without
installing packages. No Rust build or production installation was performed.
