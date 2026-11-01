## Tasks

- [x] Package `reader-bundle-<headSha>` and `flow-reader-bundle` from the flow-engine workflow on both cache paths without editing `scripts/engine-input-hash.py`.
- [x] Verify `headSha`, `bundleChecksum`, `archiveSHA256`, and every file in `scripts/fetch-reader-bundle.py`, and refuse without writing the installed reader.
- [x] Install from the staged bundle with `install.py --engine` without a git checkout.
- [x] Cover packaging and mocked-`gh` verification with Python unit tests.
- [x] Document the bundle in `AGENTS.md` and the development guide.
- [ ] Wire the Mac launchd updater (`dev.lagrangian.engine-autoupdate`) to `scripts/fetch-reader-bundle.py`. That integration is outside this repository and is pending. The job still installs the reader from its local checkout.
