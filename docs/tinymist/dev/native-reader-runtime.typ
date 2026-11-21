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
  --proof-input <provenance.json> --output <stage> --identity -
<stage>/node/bin/node <stage>/verify-runtime.mjs --verify <stage> \
  --node <stage>/node/bin/node
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

NA13 production policy is *portable-bundled*. `node-distribution.json` pins
Node `v22.23.5`, darwin arm64, the exact official archive/checksums/detached
signature, authorized release key fingerprint and full license digest. The
release line is supported through 2027-04-30 according to the acquired official
schedule. Preparation requires the original official executable hash, copies
Node to `node/bin/node`, signs it and records its post-sign hash. The copied
verifier binds that relative executable after relocation. No PATH/Homebrew
substitution is accepted. `--node-distribution` and `--identity` are explicit
preparation options; consumption uses the copied policy.

Actual arm64 load-command inspection observes minOS 11.0, only system dylibs
and no rpaths. Every delivered executable/library is additionally inspected by
the delivery producer. The app target remains macOS 13.0. Current-host execution
and a target at or below 13.0 do not certify execution on macOS 13.

The original NA11 stage remains immutable with its historical *host-required*
Node26/96-library closure and effective minOS 27.2. Its manifest hash is
`e2fbdb745477db56a4a6505503656cd64d27ad9e13c428c395ec46537c531eb7`.
It is prior evidence, not portable shipping proof. New production outputs use
`build/delivery-production`; evidence uses `test-output/delivery-production/NA13`.

== Historical NA11 proof and current integration boundary

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

Required prerequisites and skips fail. The current Python suite reads frozen
9b source blobs from this repository, never a live owner worktree. It preserves
the 108-case dynamic-range/native fraction matrix, independent font notices and
async worker failures, and uses the new portable stage and exact final NA10
helper. Its copied interpreter runs after source, dependency and cache reads and
network are actually denied. The existing production worker uses its own
sandbox, so it is tested separately to avoid unsupported nested sandboxing.

The JavaScript suite covers missing fonts/modules, package SRI, payload/helper
and lock tamper, path escape, partial-copy interruption and valid-stage
preservation. DeliveryRuntimeTests adds portable release/signature policy,
post-sign bytes and final TeX/base/AMS computation. The required installed-layout
suite exercises the actual signed app and bundle-relative Python/backend/compiler
and native paint. No scratch success substitutes for these proofs.

The preceding NA11/core-boundary discussion is historical. Fixed staged input
09c5186bff1850b17f6e85fe2f3115153520bc94 integrates core, original-page, G1
inspection and published provider inputs with portable runtime delivery. At that historical inspection, the subsequent
review-fix source was not yet restaged into that app; final inventory
and source/app evidence must be rebound by the delivery owner. GUI/VoiceOver, live provider/account,
general fidelity and macOS 13 execution remain separate acceptance. See
#link("native-reader-delivery.typ")[the production delivery contract] for staging
commands and manager configuration handoff. No live installation, service
restart, Rust build, remote CI dispatch or push is performed.


Historical09c inspection commands and source/app identities are in
`test-output/delivery-production/NA13/final-app-v1/inspection-commands.json` and
`final-binding.json`; see #link("native-reader-app-verification.typ")[inspection].
The host is macOS27.2.1; deployment target13 and closure minOS<=13 are not actual OS13 proof.
The later single partial GUI Read and AXPress error -25200 are interrupted,
incomplete observations, not GUI/AX success. For a current intermediate application, use the new external PM-bound packet
and build handoff, not the historical09c command arrays. Actual GUI acceptance
remains separate from offscreen tests and integrity verification.
