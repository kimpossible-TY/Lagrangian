# Tasks

## 1. Shared routing and authority

- [x] 1.1 Compose Homepage and prefixed document handlers; verify exact IDs, assets, worker scope, stale/cross-document requests and 307 compatibility with isolated HTTP tests.
- [x] 1.2 Share ChatAuth/provider ownership and require capability on management mutations and privileged status; verify non-loopback/proxy 403 and cookie/CSRF without proof denial for management. Homepage login without registration selection and logout now follow the superseding `homepage-account-auth` policy in `remove-homepage-host-proof`.
- [x] 1.3 Exercise delivered Homepage module events to verify proof transmission, restart recovery, logout clearing and no browser-storage writes.

## 2. Runtime and lifecycle

- [x] 2.1 Compose managed states/watchers and redirect listeners in one runtime; verify shared PID/provider, loaded inventory, startup/bind rollback and disposal in fake-state tests.
- [x] 2.2 Preserve direct document CLI and make home.py a managed Reader alias; verify alias arguments and existing source-history CLI fixture.
- [x] 2.3 Add shared ReaderManager plans, attachment URLs and one job identity; preserve a byte-exact manager.py.bak before plist-generator edits and verify manager tests.
- [x] 2.4 Update canonical architecture/operator documentation for migration, launchd impact, rollback and paged protocol limits; compile both Typst documents and check generated docs.

## 3. Integration verification

- [x] 3.1 Run focused Homepage/storage/chat/routing/runtime/manager Python and shared/HTML Node suites; record full-suite environment failures and browser-launch limits without changing live services.
- [x] 3.2 Validate this OpenSpec change strictly, review diff/backup/worktree scope and write verification.md plus /tmp/homepage-unify-report.txt.
