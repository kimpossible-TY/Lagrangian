## Context

`flow-engine.yml` republishes `flow-engine-darwin-arm64` when `scripts/engine-input-hash.py` matches a retained artifact. That hash covers Rust, Cargo, the build scripts, and embedded preview sources. It does not cover `tools/flow-reader/web`. `install.py` archives `tools/flow-reader` and `tools/reader-common` from a git checkout and records `git rev-parse HEAD` as the release id.

## Goals / Non-Goals

**Goals:**

- Ship the reader files for the run's commit on every successful engine run, including a cache hit.
- Verify `headSha`, a bundle checksum, and every file hash before anything is unpacked for install.
- Keep a failed fetch from writing the installed reader.
- Keep the engine artifact name, layout, and input hash.

**Non-Goals:**

- Changing `scripts/engine-input-hash.py` or rebuilding the engine for a web-only change.
- Running `install.py` or launchd from the helper.
- Replacing `fetch-engine`.

## Decisions

1. **Sibling artifacts, not extra engine files.** Upload `reader-bundle-<headSha>` and `flow-reader-bundle` from `dist/reader-bundle`. `fetch-engine` still downloads only `flow-engine-darwin-arm64`.
2. **Tar plus manifest.** `reader-bundle.tar` preserves the `web/reader-common` symlink and git file modes. `reader-bundle.json` records `headSha`, per-file SHA-256 and mode, `archiveSHA256`, and `bundleChecksum`. `bundleChecksum` is the SHA-256 of the canonical `headSha` and file records, so it does not depend on tar framing. The bytes are read from `git cat-file`, not from a dirty worktree.
3. **One verifier.** `scripts/reader_bundle.py` owns packaging and checks. The thin CLIs are `scripts/package-reader-bundle.py` and `scripts/fetch-reader-bundle.py`. The tar includes the verifier so `install.py` can recheck the staged tree. The fetch helper checks with the checkout copy before it prints a path.
4. **Install without git when the manifest is present.** `reader_revision` uses `headSha` after the checksums match and copies the two reader trees. A directory without `reader-bundle.json` still requires a clean git commit and `git archive`.
5. **Failure stays outside the installed reader.** Verification finishes in a temporary directory. The staging path is replaced only after that succeeds. Destinations under `~/Library/Application Support/Lagrangian`, the legacy app support directory, or `~/Applications` are refused. The helper never calls `install.py`.

## Risks / Trade-offs

- The helper and `install.py` must be new enough to understand the manifest. The launchd script needs one checkout update, then later reader web changes come from the bundle.
- Two artifact names store the same bytes for 30 days. The sha-named artifact identifies the commit; the stable name is what `--run-id` downloads if the sha name is missing.
- A hit still republishes the older engine. `release.json` inside that engine artifact can name an older commit than the reader bundle's `headSha`. Callers pass the fetched engine as `--engine` and take the reader from the same run.

## Migration Plan

Wire the Mac updater to `fetch-reader-bundle.py` and run `install.py` from the printed directory with the engine from `fetch-engine`. No reader data migration is required. Rollback is the previous immutable release already stored by `install.py`.

## Open Questions

None.
