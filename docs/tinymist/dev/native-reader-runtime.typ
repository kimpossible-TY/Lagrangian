#set page(paper: "a4", margin: 16mm)
#set text(size: 9pt)

= Native Reader computation runtime — NA11

This private runtime supplies the complete pinned registry packages
`@mathjax/src@4.1.3` and `@mathjax/mathjax-newcm-font@4.1.3`, including all 18
locked packages (two direct and 16 transitive), SVG/MathML input, TeX extensions, liteAdaptor,
metrics, dynamic font ranges and original font bytes. It computes geometry;
the frozen native Swift renderer paints the resulting glyph paths.

== Preparation and offline consumption

Materialize only in the isolated DevSSD dependency root using the private
package manifest and lock. Run `npm ci --ignore-scripts --no-audit --no-fund`
with an explicit isolated npm cache; do not modify root locks or npm settings.
Preparation needs `archives/` containing each lock-resolved registry tarball
and `acquisition.json`: an array of `{package, url, file}` records. Package is
the lock key, URL is its exact resolved URL, and file is a relative archive path.
Provide the canonical manifests and THIRD-PARTY-NOTICES alongside node_modules.
The producer never invokes npm, fetches URLs, or installs anything.

```sh
node scripts/prepare-native-reader-runtime.mjs \
  --runtime-source <complete-materialized-root> \
  --helper <fixed-helper.mjs> --node <absolute-node> \
  --proof-input <provenance.json> --output <stage>
node <stage>/verify-runtime.mjs --verify <stage> --node <absolute-node>
```

The optional proof-input JSON binds helperSHA256 and records component,
model, painter and fixture file hashes. Acceptance runs supply it; the original
four-option preparation contract also works and records helper-only provenance.
Helpers are arbitrary but hash-bound;
NA08 can reuse this producer for the final NA10 helper and updated provenance.
The relative entrypoint is `helper.mjs`, invoked with `--runtime <stage>` and
one bounded JSON request on stdin. The current MathML request fields are mathML,
width, fontSize, font and context. Context binds revision, generation and theme.
The helper's own contract remains authoritative; the producer does not rewrite it.

Verify works from its copied script with the source checkout denied. It compares
exact inventory, lock, archive SHA-512 SRI and extracted file hashes without
network or npm. Internal bin symlinks must remain inside node_modules. External
symlinks, path traversal, unexpected package files and missing ranges fail.
The schema 2 manifest binds source HEAD/dirty state and all seven source file hashes separately
from frozen proof inputs. It records package licenses, resource inventory,
Node policy, exact prepare argv/exit and the deterministic verify report hash.
Integrity hashes bind provenance; they are not an external signature or authority.

Preparation validates into a sibling directory and verifies it before promotion.
Darwin renamex_np RENAME_SWAP atomically exchanges an existing verified stage;
failures preserve the previous stage. An exclusive sibling lock rejects concurrent
writers. SIGKILL can leave an unused temporary directory or lock; remove it only
after checking the original producer is no longer running. No partial candidate
is consumed as the output stage. A damaged existing output is rejected rather
than overwritten automatically.

== Licenses and runtime policy

All original package license files, headers and notices remain intact. The font
npm archive omits LICENSE, and its published GitHub repository/gitHead returned
404. The supplement instead preserves authoritative same-version WOFF2 name-table
copyright and GUST declarations, MathJax's original addCopyright, full GUST/LPPL
terms and the package's Apache declaration with standard Apache terms. These
font rights are not inferred solely from an SPDX string. Exact source URLs,
font hashes and original notice text are in THIRD-PARTY-NOTICES.md.
An independent development-only FreeType reader checks all 105 pinned WOFF2
name tables: 84 original GUST notices and 21 MathJax-added original notices,
with zero parse errors. Each original font hash, notice classification and
notice fingerprint is embedded in the supplement and is mandatory at stage
verification. Official terms were retrieved with URL, UTC time, HTTP status,
length and hash during materialization. FreeType is not a product dependency.
These are license preservation evidence; final DocsAudit and legal/policy review
remain separate. No current CTAN newcm license is inferred for these older bytes.

Policy is *host-required*, not standalone. The supported executable is the exact
`/opt/homebrew/Cellar/node/26.13.1/bin/node`, Node `v26.13.1`, darwin arm64, with
SHA-256 pinned in each manifest. The host must retain its recorded Homebrew
dylibs. The manifest captures otool dylib/rpath output, recursively resolved
non-system library hashes/minimum OS, and Node's full LICENSE. Verification
rejects missing, replaced, incompatible or unlaunchable Node before consumption.
Integration must perform this preflight and present the configured path with an
actionable runtime unavailable/incompatible error; PATH fallback is unsupported.
No Node executable or Homebrew library is bundled or signed by this task.

The Node executable has minimum macOS 13.5. The Swift painter is compiled with
Swift 5, warnings-as-errors and `arm64-apple-macosx13.0`. These are separate
contracts: compiling the app for 13.0 does not make this Node run on 13.0.
The 96 resolved non-system libraries include minimum OS 27.2, so this particular
Homebrew closure actually requires *macOS 27.2 or later*, as recorded by
`effectiveMinOS`. Preflight checks the running host against that maximum.
Current-host execution is not certification on macOS 13.0 or 13.5. Supporting
older systems requires a separately verified Node distribution and library policy.

== Initial proof and integration boundary

Source patch baseline: `cc790bc1778dd7560984eafca93f0d6c052805d4`.
Frozen proof core: `1eb9a44196aa34e47ab2088f3facc158f4627e0d`.
Helper and painter lineage: `d968f59fbf8d19c44ffb47cf316f36f86b70e9cf`.
Model/operations lineage: `312502ceb573f4791e61d01000df132d6da16323`.
Proof files are read from the committed frozen core, never NA09's changing tree.
The initial runtime stage is
`/Volumes/devSSD/Developer/lagrangian-native-20261117/build/runtime-producer/NA11/runtime`.
V1 evidence remains under `test-output/runtime-producer/NA11`; the original CLI
was interrupted by PM with SIGINT, exit 1. V2 continuation evidence is under
`test-output/runtime-producer/NA11/v2`; tmp/cache are isolated
under `tmp/runtime-producer` and `cache/runtime-producer` on the same DevSSD.

```sh
python3 -B -m unittest discover -s tests/flow-app/native-reader-app \
  -p test_runtime.py -v
node --test tests/flow-app/native-reader-app/RuntimeTests.mjs
```

Required prerequisites and skips fail. The Python runner first demonstrates
actual OS network denial and source-read denial, then verifies a relocated copy
with worktrees, dependency scratch roots, NODE_PATH and user caches unavailable.
It runs 320/640/960pt by 14/20/28pt by inline/display MathML across six formulas,
including five nondefault dynamic ranges. It compiles the frozen production
Swift painter/worker, checks native glyph paths and independent fraction
geometry/glyph identity/topology, paints PNGs, and tests stale/timeout/cancel/budget
failures. Range paint is a delivery smoke test, not a general fidelity oracle.
The frozen helper internally converts with display=false, even when MathML
carries display=block; display typography parity remains a later helper gate.
Bare Cyrillic with zero descent was observed to return unsupported-svg-style
from this frozen helper. The range matrix uses genuine subscript expressions;
it does not claim that the frozen helper accepts every bare glyph expression.
macOS rejects nested sandbox-exec with sandbox_apply exit 71. Source-denied
helper and native paint therefore form one proof; production NativeMathWorker
runs separately with its own deny-network/write sandbox for the async success,
stale, cancellation, timeout and output-budget checks. The worker proof itself
does not claim that an outer sandbox denied source reads.

The JavaScript suite exercises missing font/module, lock/payload/helper tamper,
external links, traversal, partial failures, existing-stage preservation and
invalid Node. It preserves raw commands, stdout/stderr, exits and TAP counts.
The canonical document is compiled using the prebuilt Typst under network denial.
A final evidence binding associates the clean commit, seven source hashes,
manifest, native paint and test reports. This binding is separate from the
manifest's pre-commit source identity, avoiding a self-referential commit hash.

NA11 completes only the initial frozen MathML producer and offline payload proof.
NA08 must rerun with NA10's final TeX helper and NA09's accepted exact model/API.
General mathematical fidelity, inline breaking, paged/print parity, selection,
AX/VoiceOver, GUI and the final packaged .app remain their own acceptance gates.
No live installation, service restart, Rust build, CI dispatch or push is needed.
