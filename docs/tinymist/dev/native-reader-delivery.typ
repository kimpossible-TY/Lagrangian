#set page(paper: "a4", margin: 16mm)
#set text(size: 9pt)

= Native reader delivery — NA13

Engine reuse and app production have independent lifetimes. Both cache paths
build current Swift, branding, backend, reader-common and computation payloads.
The retained artifact contributes only `flow-engine`, its checksum and engine
provenance. Its old app is discarded. The engine input hash and root locks are
unchanged by this change; the existing hash policy still includes packaging code.
Local cache fixtures model this boundary; they are not remote CI execution.

== Explicit preparation and staging

All paths below are explicit isolated build inputs. Preparation can fetch pinned
official distributions and SRI-authenticated registry archives; verification and
consumption have no acquisition fallback.

```sh
python3 scripts/stage-native-reader-delivery.py acquire \
  --backend . --output <isolated-dependencies>
node scripts/prepare-native-reader-runtime.mjs \
  --runtime-source <complete-packages> --helper <current-helper.mjs> \
  --node <official-node> --output <runtime> --identity -
python3 scripts/package-reader-bundle.py --head-sha <current-commit> \
  --worktree --output <reader-artifact>
python3 scripts/stage-native-reader-delivery.py unpack-reader \
  --bundle <reader-artifact> --output <current-reader>
python3 scripts/stage-native-reader-delivery.py binding \
  --backend . --engine <prebuilt-engine> --runtime-source <runtime> \
  --helper <current-helper.mjs> --reader-bundle <current-reader> \
  --output <input-binding.json>
python3 scripts/stage-native-reader-delivery.py stage \
  --manifest <input-binding.json> --backend . --engine <prebuilt-engine> \
  --runtime-source <runtime> --helper <current-helper.mjs> \
  --reader-bundle <current-reader> --python-archive <official-python.pkg> \
  --compiler <official-typst> --typst-packages <official-package-archives> \
  --certifi-wheel <official-certifi-wheel> --output <delivery> --identity -
python3 scripts/stage-native-reader-delivery.py verify \
  --output <delivery> --manifest <input-binding.json>
python3 scripts/flow-app.py build --engine <prebuilt-engine> \
  --delivery <delivery> --identity - --output <isolated>/Lagrangian.app
python3 scripts/verify-native-reader-app.py <isolated>/Lagrangian.app \
  --require-delivery --binding <input-binding.json> \
  --source-revision <current-commit>
```

Use `--help` and each subcommand's `--help` for the authoritative parser. Runtime
preparation signs its copied Node before computing the runtime inventory. Backend
staging rewrites only copied Python framework load references, signs internal
Mach-O images and nested bundles, then writes the delivery inventory. App
packaging signs its copied engine, binds delivery and post-sign engine hashes in
`release.json`, and seals the outer app last. Ad-hoc identity is not a persistent
certificate. No engine is compiled by these local commands.

The inventory binds file bytes, executable modes and internal symlinks. Input
binding includes current source revision and source hashes, engine input,
reader-bundle checksum, helper and runtime manifest. Stale sources, helper,
release/sidecar pairs, path escapes, missing dependencies and signed-byte drift
fail nonzero. Candidates are verified before atomic publication; a failed
candidate leaves a previously valid stage intact.

== Backend and default composition

The app-relative `Contents/Resources/native-reader` tree supplies the complete
reader and reader-common trees, manager/server entrypoints, console CPython with
its backend standard library, official Typst compiler, portable Node and MathJax. Hash-pinned official tiptoe and oxifmt archives
supply the bundled overlay packages' transitive Typst imports in an immutable
app-relative package cache. Missing delivered packages fail inventory checks.
Optional Tk/IDLE GUI modules and the x86-only Python launcher are explicitly
excluded alongside development headers/object files; they are not backend dependencies. Original Python/Typst licenses and
all delivered third-party notices remain in the payload. The official Python installer's original license/readme and pinned certifi
CA data/license are preserved. The private interpreter uses that verified
process-local CA file; system/user Keychains are not modified. Loading CA data
is tested offline and does not prove a live provider/account exchange.
The original signed
Python installer and acquisition evidence remain isolated build inputs.

The native composition verifies the outer app seal and exact delivery/release
binding before supplying existing runtime and manager initializer arguments.
The shell entrypoint uses bundled Python, clears development module/dyld
overrides, and the Python launcher checks the full payload inventory. ReaderManager receives the exact bundled interpreter, compiler, Flow manager
and engine through its optional concrete executable operations. Existing
schema-1 config files can retain their external executable paths unchanged. There is
no source checkout, Homebrew, global module, PATH or scratch fallback.

ReaderManager retains profile matching, managed lifecycle, configuration
validation and source/account authority. Staging does not install a service or
rewrite live configuration. The owner still validates config/profile/source/lifecycle policy. Both the
parent launcher and shared backend child authenticate their own outer app seal,
release/manifest pair and file inventory before constructing those operations.
The child reenters the same app-relative composition and the managed server
accepts its explicit manager factory. No remote field or environment value
creates trusted executable bindings. Missing configuration fails explicitly. A loopback fixture and a contract
fake provider can verify delivery without implying a live service or account.

== Integrated owner binding and acceptance

The original 882 contract and `9b2dc87651eb16a809bb48dbe4539614cfe30d6a`
remain ancestors. A normal no-ff merge integrates core correction
`ec2c4af91988f0db66d494cea97a551ffd7cf180` and original-page owner
`76f5ac13df10c2c16824323ab65fbf397ce4de7c`. Both new Swift files are
registered in canonical `sources.json`; the same owner backend HTTP and
`native_pages.py` are shipped in the current reader inventory. Staging checks
ancestry and exact owner-file bytes; the app/delivery source revision names the
current clean integration commit. Core integration does not imply final review.

Original mode uses `original-pdf-full-v1`, an immutable full-PDF/reset publication
with accepted HTML/PDF input fingerprints, publication identity, sequence and
PDF digest. It supplies page-local display selection. Original source anchors
and source jumps remain unsupported; raw engine diff-v1 native consumption is
unverified. Verified semantic reflow source actions retain their existing owner.
The actual final helper is
`dc100395fc2ea1299c99ec90c201faaed80a1ca5ad0fefaa5d2451278e4a5d76`.
Existing runtime component source provenance and its immutable dependency bytes
remain distinct from the new app source revision. Input engine hash, engine
build/version provenance, signed engine hash, signed runtime inventory and outer
app checksum are separate identities. Prior stages are preserved.

This build is a pre-GUI candidate. `--acceptance` requires an explicitly supplied
external PM receipt; absence or rejection returns exit 2 while valid delivery
integrity remains independently reportable. Normal app launch has no receipt
dependency. Receipt validation records a PM decision, and cannot authenticate
review quality, PM authority or user permission.

```sh
python3 scripts/verify-native-reader-app.py <app> --require-delivery   --source-revision <exact-app-commit> --acceptance   --pm-acceptance-receipt <external-evidence>/acceptance.json
```

The JSON receipt has `schemaVersion: 1`, `kind: external-pm-acceptance`,
`decision: accepted`, a nonempty `recordedBy`, exact `sourceRevision` and signed
`bundleChecksum`. Its `gates` object has exactly `source`, `runtime`,
`requiredtests`, `code-review`, `docs`, `nativeGUI`, `AX`. Each gate carries
`status: passed`, an artifact path relative to the receipt directory and the
artifact's `sha256`. Absolute paths, parent traversal and escaping symlinks fail.
Each bounded JSON artifact repeats its `gate`, `status: passed`, exact app/source
binding and integer `requiredSkips: 0`; requiredtests also records positive integer
`tests`. Missing, tampered, failed, stale or required-skipped evidence is rejected.
Synthetic passing receipts in tests verify only this mechanism and are never
published as actual PM acceptance.

Formal Review/Docs/Tester/native GUI/AX artifacts have not been supplied for this
candidate. Its actual acceptance result remains exit 2. Current-host local app
integrity, headless PDF/math paint, source-denied execution and local cache
fixtures are distinct evidence. A macOS 13 deployment target and inspected
closure do not certify macOS 13 execution. Live provider/account and VoiceOver
speech remain unverified; recording a gate does not relabel those coverage facts.
Required suite prerequisites/skips fail; the historical optional certificate
check is separate.

No command here authorizes live installation, launchd changes, activation, push,
manual CI, Cloud or Rust compilation. GUI preparation is deliberately excluded;
its future fixed commit requires a new source binding/build in this session.
