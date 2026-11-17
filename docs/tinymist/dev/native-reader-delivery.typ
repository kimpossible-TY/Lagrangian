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
overrides, and the Python launcher checks the full payload inventory. Manager
configuration must select the exact bundled interpreter and compiler. There is
no source checkout, Homebrew, global module, PATH or scratch fallback.

ReaderManager retains profile matching, managed lifecycle, configuration
validation and source/account authority. Staging does not install a service or
rewrite live configuration. Provisioning or relocating an existing managed
service requires the owning configuration writer to rebind those executable
paths. Missing configuration fails explicitly. A loopback fixture and a contract
fake provider can verify delivery without implying a live service or account.

== Acceptance and owner handoff

Initial source is frozen `9b2dc87651eb16a809bb48dbe4539614cfe30d6a`, preserving
the original 882 ancestor. The actual final NA10 helper is
`dc100395fc2ea1299c99ec90c201faaed80a1ca5ad0fefaa5d2451278e4a5d76`;
the old NA11 staged helper is historical and remains untouched. MathML, TeX and
base/AMS already belong to the verified packages; no package lock delta is needed.

`verify-native-reader-app.py --acceptance` remains nonzero while final NA06 core
and NA12 original-page rebinding, GUI/VoiceOver, live chat/account and macOS 13
execution remain open. Current-host local app integrity, headless native paint,
source-denied offline execution and local cache fixtures are distinct evidence.
A macOS 13 deployment target and inspected dependency closure do not certify
execution on macOS 13. A required installed-layout prerequisite or skip fails the
required suite; the existing optional certificate check is reported separately.

No command here authorizes live installation, launchd changes, application
activation, push, manual CI, Cloud execution or a Rust source build. The final
core/page commits must be rebound in the same delivery session before complete
application acceptance and NA08's final inventory review.
