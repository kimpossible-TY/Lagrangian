## Tasks

- [x] Package `reader-bundle-<headSha>` and `flow-reader-bundle` from the flow-engine workflow on both cache paths without editing `scripts/engine-input-hash.py`.
- [x] Verify `headSha`, `bundleChecksum`, `archiveSHA256`, and every file in `scripts/fetch-reader-bundle.py`, and refuse without writing the installed reader.
- [x] Install from the staged bundle with `install.py --engine` without a git checkout.
- [x] Cover packaging and mocked-`gh` verification with Python unit tests.
- [x] Document the bundle in `AGENTS.md` and the development guide.
- [x] Wire the Mac launchd updater (`dev.lagrangian.engine-autoupdate`) to `scripts/fetch-reader-bundle.py`. That integration is outside this repository. It passes one run id to `fetch-engine` and the helper and installs the reader from the verified bundle of the same successful `main` run (see `87e233c`).
