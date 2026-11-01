# Proposal

## Why

Readers need one place to find their documents, understand service availability, and manage ChatGPT access without opening a compiled document. Account management currently belongs to the unmerged paragraph-chat Reader UI and must acquire an explicit host-level security boundary before appearing on a Tailscale-reachable Homepage.

## Prerequisite and implementation gate

**Proposal only. Implementation is forbidden until `feat/reader-paragraph-chat` merges into `main`.** That branch owns `tools/flow-reader/flow_reader/services/chat_auth.py`, direct SIWC OAuth PKCE, protected host credentials, and loopback-only sign-in/cancel/sign-out. This change reuses that owner; it must not copy, replace, or implement it ahead of the merge.

Prerequisite proposal, design, and `specs/reader-paragraph-chat/spec.md` were read using `git show origin/feat/reader-paragraph-chat:<path>` under `openspec/changes/add-reader-paragraph-chat/`, at `b0b5ffed346d38a5060b5714166477d9042f35b5`. Recheck the merged implementation and reconcile its loopback-only management requirement before implementing this proposal. Artifact completeness or validation success does not lift this gate.

## What Changes

- Add a Lagrangian Homepage at `/` on a dedicated reader host origin, with a configured document list, links into existing HTML/paged readers, and truthful host/document status, including empty and unavailable states.
- Move ChatGPT sign-in, cancel, sign-out, and plan/model status presentation from document Reader settings to the Homepage. Document readers link to that page and retain their chat/draft behavior.
- Keep credential mutations on the Mac's actual loopback Homepage by default. Remote HTTPS visitors see sanitized account/catalog status and instructions to manage access on the Mac. Whether remote management should ever be allowed remains an explicit open question.
- Separate browser management sessions from provider credentials; specify CSRF protection, independent Origin/Host validation, proxy handling, expiry, and cache isolation before expanding exposure.
- Reuse the Reader's warm paper colors, green accent, approved L branding, theme behavior, and accessible activity feedback.
- Preserve each document service's `/` reading entry, existing APIs, revision checks, and offline reading. The host Homepage is a separate origin, not a replacement for all document roots.

## Capabilities

### New Capabilities

- `reader-homepage`: Host-level document discovery, status, and secure ChatGPT account-management presentation.

### Modified Capabilities

None in the current accepted `openspec/specs/` inventory. `reader-paragraph-chat`, `reader-status-logo`, and `reader-favicon` are active changes, not accepted capabilities here. Reconcile paragraph-chat's management UI and loopback contract after its merge; add an exact accepted-spec delta if the merged contract requires one.

## Impact

Future implementation affects HTML Reader host HTTP composition, configured profile/status adapters, browser assets and static allow-lists, offline boundaries, and account UI entry points. `ChatAuth` remains the sole credential owner. `ReaderManager` and parent app profiles remain the inventory/lifecycle owners; this page does not start services, scan arbitrary files, or initiate model inference.

Host routing/proxy deployment, shared account authority, and remote-management policy require decisions recorded in `design.md`. This proposal changes no code, live services, credentials, or release artifacts. Implementation checks will use isolated fixtures; Rust compilation is not required for this proposal.
