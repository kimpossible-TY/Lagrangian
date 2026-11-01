## Why

Reader web changes never reach the Mac. The engine-input hash excludes `tools/flow-reader`, so a web-only push is an engine cache hit that republishes the old `flow-engine-darwin-arm64` artifact. The Mac updater then runs `tools/flow-reader/install.py` from a local checkout that is not updated by that hit.

## What Changes

- Publish `reader-bundle-<headSha>` and `flow-reader-bundle` from `.github/workflows/flow-engine.yml` on both the engine cache hit and the cache miss.
- Leave `scripts/engine-input-hash.py` and the `flow-engine-darwin-arm64` artifact layout unchanged.
- Add `scripts/fetch-reader-bundle.py` to download the bundle with `gh`, verify `headSha` and checksums, and print a staging directory without installing the reader.
- Let `install.py` install that staging directory, with an external `--engine`, without a git checkout.

## Capabilities

### New Capabilities

- `reader-bundle`: the CI artifact, its manifest, the fetch helper, and installation from the staged tree.

### Modified Capabilities

## Impact

The Mac launchd updater is outside this repository and is pending. It still installs the reader from its local checkout. When it is wired, it can pass one `--run-id` to `fetch-engine` and the helper, then run `install.py` from the printed directory. Engine cache behavior and the installed reader layout stay the same. A web-only reader change still skips Cargo and still publishes a new reader bundle.
