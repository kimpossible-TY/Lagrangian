#set page(paper: "a4", margin: 16mm)
#set text(size: 9pt)

= Native reader delivery — NA13 and NA14

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

`<delivery>` must be outside the backend checkout, `<runtime>`, and `<current-reader>` (stage rejects overlap).

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

At startup, Swift synchronously verifies the outer app seal, release/manifest
digest binding and entrypoint paths before app.run(). Manager operations run
in a detached task. The bundled Python launcher and shared child each verify
the full delivery inventory before constructing trusted executable operations.
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
`82f5d948ce927f47d9ab04380f2e895ffed98c06b418565f6ff5338174a813c0`.
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
manual CI, Cloud or Rust compilation. Fixed GUI preparation `1e32419dd2cb448fb183ce563e39736cf64a1fca` and
published reader/homepage `4871104deef949d437deccef8b39ddd48ed07bef` are
historical integration inputs from normal no-ff merges. Their original bytes and
C source proof are retained separately from registered owner corrections below;
the transferred C test collects each actual Swift file once while retaining the
standalone pre-registry path. The published unlimited tool-round/document-read
policy is preserved with existing per-request and freshness/cancellation guards.

The final source is frozen before runtime preparation, reader packaging, staging
and app build. For production, runtime sourceSHA, reader headSha, delivery
sourceRevision and app release.sourceRevision must all equal that final HEAD.
The existing delivery owner permits byte-preserving ad-hoc staging of one
registered retained runtime: manifest SHA-256
`aa824a56c4d310a9977cdcc1f7a65dd718b92fcba46605347cad20dd431623fc`
and the exact clean producer record at
`d7cd069f2249a405061bf220cfd7e0184f75c7fe` must match its fixed registration.
Staging still checks producer ancestry and inputs, Node distribution, helper,
manifest and payload hashes. An app may consume this retained runtime only with
an explicitly validated development bundle namespace and ad-hoc identity; generic
staging does not make it production-eligible. Production apps still require a
current-H runtime, and retained certificate combinations are refused. The app,
reader and delivery always bind the final HEAD independently of the retained
runtime producer. Test/doc changes after a
build require a fresh build from the new HEAD. Previous app/stage/evidence are
immutable. Dependency/package/license/notice bytes stay unchanged.

The canonical D `test_page_delivery_bundle.py gui-fixture` entry composes only the
new inspection storage base and reentry script with G1
`test_app_integration.py` owner functions. It does not replace test collection,
classes, source/security validation, sandbox or lifecycle policy. Setup creates a
new root; serve is explicit foreground with a bounded lifetime; stop cleans only
that owned fixture. Inspection remains running=false. A separate smoke root
checks real HTTP/fake provider/private board and is stopped and reaped. G1
smoke1/2 may have discovered live profiles; their contents were not logged and
no mutation was recorded. Those historical failures are not successes and are
not relabeled as zero user-data access. Final serving uses an owned change_file
and OS denial of the real user home. Body/verified Source copy uses the named
private board. Composer/answer Cut/Copy/Paste and external links/editor actions
are excluded from inspection; no user clipboard is inspected or changed.

== Fixed source owner corrections

The common integrated_sources owner reads tracked sourceProvenance in
backend-delivery.json, already included in sourceFiles and the delivery
distribution manifest. The first registered production correction is full revision
`338304a374bdd75ba76151a34bc8c284510ce725`, relative to
`09c5186bff1850b17f6e85fe2f3115153520bc94`. Its exact 30 source/test/document
paths bind both original and corrected SHA-256 values. Historical core ec2,
pages76, G1, published reader and baseline9b revisions/digests remain historical
proof; effective corrected files are not claimed to retain their old bytes.

Binding requires a clean checkout, full ancestor commits, exact changed path
sets and regular-file bytes matching the immutable correction. Missing files,
dirty or later committed drift, mixed original/corrected digests, extra paths
and nonancestor corrections fail closed. Only a finite exact list of existing
delivery-owned files uses current HEAD; no native directory prefix or whole HEAD
is exempt. A future added file must explicitly bind verified original absence
and its actual corrected digest. Rehashing changed current bytes cannot repair a
fixed correction mismatch.

The second registered production correction is `8744c1b3db0b494f2e36529df281be993ccf11b4`,
relative to `09e78630a6afb51436e45da140c3588c82c295f5`, with exactly15 paths and
Git-object original/corrected SHA-256 values. It is applied after338; the old
338 inventory and historical C/G1/P0/published records are not rewritten using
current bytes. It contains the completed C1–C3/F15/F16 source changes only,
not a new app/runtime/reader artifact or actual engine provenance proof. Later corrections and new
API owners must first supply PM-transferred exact fixed commits and inventories.
Their registration must include actual Swift source-list or backend packaging
changes where needed; nonexistent files and pending owner SHAs are not registered.
This binding preparation is not app/runtime/reader production, GUI, remote CI or
PM acceptance. A later integrated app still needs fresh final-source assembly and
verification; old app/evidence remain immutable.

== Existing updater consumer — NA14

The golden old CLI remains fetch-engine --run-id R, fetch-reader-bundle --run-id R,
then build --engine with the printed engine path. Checkout HEAD must be run head H.
Fetch writes schema-2 native-delivery-context.json beside the engine; the current
consumer accepts only context schema 2. It binds the
repository, validated run record/ID/head, canonical engine path/hash and artifact
inventory digest. The transport binding separately records raw archive,
manifest and raw-inventory digests, plus the normalized inventory digest after
authenticated external-engine mode normalization. The top-level
artifactInventorySHA256 is that normalized inventory digest; it does not replace
the raw archive SHA-256. The producer's schema-1 JSON transport envelope is a
different format from this schema-2 context. The context's delivery binding
explicitly records sourceFiles, manifest,
payload, helper, runtime and reader digests, signing and the fixed relative root. Fixed artifact-relative paths and the existing inventory owner reject
escaping symlinks. The context is a locator, not server authority: build re-views
exact R and re-downloads that artifact, comparing the full inventory before using
its payload. It verifies the artifact app seal, application release/sidecar,
current sourceFiles (including the new consumer), helper, runtime and reader.
The separate reader artifact is checked with the existing same-R manifest/archive
owner. No latest lookup, mtime, global last-run database or installed-app inference
is used. Download success alone does not mean app production success.

The current payload must exist in the artifact app. Old engine build provenance
E is permitted, while app/delivery/runtime/reader and run H agree. Build compiles
current Swift/resources, never copies an old signed app as its final result.
Explicit --delivery follows the same source/engine checks and cannot override a
run-bound payload. A standalone engine needs explicit delivery; --management-only
is a labelled nonshipping fixture that fails require-delivery. Missing identity
cannot silently select ad-hoc signing. An explicit identity or saved certificate
is required; explicit '-' is isolated ad-hoc evidence only.

A different local certificate signs only a copied temporary candidate. The existing
runtime inventory/verifier rebinds post-sign Node bytes, the stager signs internal
images/nested bundles, and delivery/runtime hashes are updated before the outer
app seal. Original artifact digests, runtime hash, signing identity and run/source
context are preserved in nativeDeliveryInput; output hashes remain separate.
Failure, interruption or input drift leaves a valid previous app/cache stage
unchanged. There is no local dependency acquisition fallback. A run lacking the
current portable payload fails before install and requires a producer repair.

Offline transport and service spies are simulations. Actual current Swift build,
codesign and require-delivery verification are separately recorded in the NA14
handoff. No live updater file, installer, restart, launchctl, remote CI or push is
part of this validation. The installed old updater is not assumed updated by a
repo script edit. Current integration is staged; GUI inspection remains partial,
official final review needs fixes and PM acceptance is incomplete. Exact new
source/executable GUI/AX, delta review and final integration remain PM gates.
Actual final PM receipt remains absent; acceptance stays 2.

== Permission-preserving producer/consumer transport

`upload-artifact@v4` documents directory mode 755 and regular-file mode 644.
Uploading the signed app directory directly loses required executable/resource
modes and may omit hidden payload. The producer now uploads only
`native-delivery-artifact.tar` and `native-delivery-artifact.json` under the stable
artifact name. The tar preserves the extracted legacy engine/app layout,
normal directory/file modes, internal relative links and hidden files. Cache hits
reuse only engine bytes/checksum/provenance E; both paths build the current H app
and produce a new R/H-bound transport. Current GitHub run/repository environment
or explicit stage arguments supply R/repository; source H comes from the verified
clean application and checkout. Genuine engineBuild provenance remains required.
The retained 09c app lacks that field and still fails official artifact staging.
Synthetic offline profile/R/H metadata is a test input, never actual CI evidence.

The JSON schema binds repository, numeric R, exact H, raw tar SHA-256 and the
complete inventory (kind, ordinary permission mode, byte count/hash or link).
Consumer run selection still belongs to flow_engine_runs. Before any extraction,
the shared reader archive owner hashes the raw tar and bounds raw/PAX headers.
Limits: 2 GiB archive/total bytes, 256 MiB per entry, 30000 logical entries,
64 KiB PAX metadata per header and 16 MiB transport manifest. It rejects absolute,
root/traversal/duplicate paths, hardlinks/devices/FIFOs, sparse/special modes,
escaping/missing/cyclic links and links used as parents. It verifies exact modes,
member sizes/hashes and creates files/directories before symlinks. Parent tar
structure and trailing bytes are checked, and archive bytes are hashed again
following extraction. All work is in an owned temporary candidate. Existing
atomic publication exchanges only verified stages; failure or interruption keeps
the prior valid output.

Fetch rejects legacy flat portable artifacts. There is no fallback when either
transport file is missing or invalid. The engine cache-reuse owner alone can read
older flat artifacts for their three authenticated engine files; it discards the
old app. A fetched cache stores the raw envelope separately from extracted files.
Only the external `flow-engine` gets the historical 755 normalization, after hash
authentication; its before/after mode and unchanged binary digest are bound apart
from raw archive/manifest/inventory digests. Signed payload modes are never
repaired from a corrupted flat tree or rehashed as if valid. Build re-downloads
the exact R/H envelope and same-run reader, compares raw and normalized bindings,
and then uses the existing full inventory/signing/source owners. Current Swift
and resources are rebuilt, internal images are re-signed only in the owned
candidate if required, manifests bind post-sign bytes, and the outer seal is last.
New transport/helper and shared archive-owner source hashes are part of delivery
sourceBinding. The old CLI stdout/process sequence remains unchanged.

Local tests use explicit offline GHA/gh/run/ZIP fixtures and genuine prebuilt
engine/Swift/codesign/runtime verification. The positive fixture does not confer
GitHub authority on its synthetic engineBuild metadata. Archive tamper, budgets,
links, mixed R/H/reader, raw digest replay, signed modes, stale sources, identity
failure and after-hash/interrupt preservation remain separate negatives. No actual
CI, Rust build, install, service restart, GUI or live account/provider is implied.
This transport component remains separate from the concurrent UI correction and
formal final integration/review/GUI/Docs acceptance.


= v4 current native correction binding

The immutable338/8744 correction records remain unchanged. Source provenance
appends the exact cc557788→f510fe32 component (19paths) and f510fe32→
`d98f6e98cd282450a47cf8ceea9d8fea59145cda` correction (28paths), with Git-derived
before/after hashes, ancestry and exact path sets. The current delivery-owned
allowlist remains25 exact paths; no native prefix/blanket HEAD exemption is added.
Current source/app identity comes from the external v4 build handoff, independently
of retained raw387 engine E/build provenance. This is an intermediate diagnostic
app, with GUI/startup cause, F13/NA16 and full125-case acceptance still incomplete.


The subsequent current F10 explanation is pinned separately: exact one-path
`7c98e620ea1480764ac536c578894bf2d12e6cd6` →
`72bd0b385d8d71ef4ad7f30d5067e9171493bc05` changes only
`docs/tinymist/dev/native-reader-app-contract.typ`. It distinguishes the delivered
consented editor operation from mapping-only locate, without claiming GUI or
Unicode manager matching acceptance. Native code correction remains d98f6e98;
this docs record adds no native path or delivery allowlist exception.

The footnote-merge owner correction registers the four main paths from
`fdd6f613f5451ecb2ac38660001c16833ee0c5ad` →
`316417a79562efb6b6162a5802606b98ed4a35da`:
`tools/flow-reader/web/rendering/annotations.js`,
`tools/flow-reader/tests/footnotes-browser.mjs`,
`tools/flow-reader/tests/test_annotations.mjs`, and
`tools/flow-reader/tests/fixtures/side-footnotes.typ`.
Hashes are Git-derived. That inventory contains no delivery-owned paths.
The current delivery-owned allowlist is 27 exact paths.

The release-retention owner correction registers the six gated paths from
`87ebbae84e676233acbacedf6402e5f046222773` →
`36b05a6a8d6f0febba038e204eabad601a229ca4`:
`scripts/mac/README.md`,
`scripts/mac/refresh-reader-engine.sh`,
`scripts/mac/test-reader-refresh.py`,
`tests/flow-app/test_app.py`,
`tools/flow-reader/install.py`, and
`tools/flow-reader/tests/test_install.py`.
Hashes are Git-derived. That inventory contains no delivery-owned paths.

The flow-reader selection owner correction registers the sixteen gated paths from
`36b05a6a8d6f0febba038e204eabad601a229ca4` →
`86c8d12de6076dd1989d7981fad1b28a0870caf6`:
`tools/flow-reader/flow_reader/compiler/source_map.py`,
`tools/flow-reader/flow_reader/document/passages.py`,
`tools/flow-reader/flow_reader/services/paragraph_chat.py`,
`tools/flow-reader/flow_reader/services/selection.py`,
`tools/flow-reader/flow_reader/services/source_highlight.py`,
`tools/flow-reader/flow_reader/services/source_mapping.py`,
`tools/flow-reader/tests/selection-browser.mjs`,
`tools/flow-reader/tests/selection_fixture.py`,
`tools/flow-reader/tests/test_focus.py`,
`tools/flow-reader/tests/test_paragraph_chat.py`,
`tools/flow-reader/tests/test_selection_actions.mjs`,
`tools/flow-reader/tests/test_selection_copy.mjs`,
`tools/flow-reader/tests/test_source_edits.py`,
`tools/flow-reader/tests/test_source_mapping.py`,
`tools/flow-reader/web/features/selection/controller.js`, and
`tools/flow-reader/web/features/selection/source-segments.js`.
Hashes are Git-derived. That inventory contains no delivery-owned paths.

The scripts/mac owner correction registers the four scripts/mac paths from
`99583ad8d4576a513b6cd8b6d676700773ffde54` →
`edee107b243630d920d7efa8653bd22b7f6d10ea`:
`scripts/mac/README.md`,
`scripts/mac/auto-update-engine.sh`,
`scripts/mac/test-auto-update-engine.sh`, and
`scripts/mac/test-reader-refresh.py`.
Hashes are Git-derived. That inventory contains no delivery-owned paths.

The flow-reader follow-up owner correction registers the eight paths from
`7b089be34903e6712b26550b99eba5175e404042` →
`ccb31c9b63741409d078ef0963ede12347dc63b2`:
`docs/tinymist/dev/reader-architecture.typ`,
`tools/flow-reader/AGENTS.md`,
`tools/flow-reader/flow_reader/compiler/source_map.py`,
`tools/flow-reader/flow_reader/document/passages.py`,
`tools/flow-reader/flow_reader/server/native_reader.py`,
`tools/flow-reader/flow_reader/services/source_highlight.py`,
`tools/flow-reader/tests/test_native_editor_dispatch.py`, and
`tools/flow-reader/tests/test_passages.py`.
Hashes are Git-derived. That inventory contains no delivery-owned paths.

The Home/PDE integration owner correction registers the twenty-six paths from
`ff66cdb89c9e68b17196a99c76e26d352b399e78` →
`40df486581d1b3d71cb7b421e2b85284e3cf9bf1`:
`apps/macos/FlowApp.swift`,
`apps/macos/NativeAppDesign.swift`,
`apps/macos/NativeBrandMark.swift`,
`apps/macos/NativeReaderDocument.swift`,
`apps/macos/NativeReaderObjectRenderer.swift`,
`apps/macos/NativeReaderPagedLayout.swift`,
`apps/macos/NativeReaderRecoveryStore.swift`,
`apps/macos/NativeReaderSession.swift`,
`apps/macos/NativeReaderTextView.swift`,
`apps/macos/NativeReaderTransport.swift`,
`apps/macos/NativeReaderWindowController.swift`,
`tests/flow-app/FlowAppTests.swift`,
`tests/flow-app/ReadingSessionTests.swift`,
`tests/flow-app/native-reader-app/ContractTests.swift`,
`tests/flow-app/native-reader-app/DeliveryRuntimeTests.mjs`,
`tests/flow-app/native-reader-app/ObjectsTests.swift`,
`tests/flow-app/native-reader-app/ServiceTests.swift`,
`tests/flow-app/native-reader-app/TextInteractionTests.swift`,
`tests/flow-app/native-reader-app/test_app_integration.py`,
`tests/flow-app/native-reader-app/test_contract.py`,
`tests/flow-app/native-reader-app/test_objects.py`,
`tests/flow-app/native-reader-app/test_services.py`,
`tests/flow-app/native-reader-app/test_text_interaction.py`,
`tools/flow-reader/flow_reader/document/native_document.py`,
`tools/flow-reader/flow_reader/server/native_reader.py`, and
`tools/flow-reader/native/math_layout.mjs`.
Hashes are Git-derived. That inventory contains no delivery-owned paths.

The cross-project integration owner correction registers the twenty-eight paths from
`d7c9d93366257f7130692a97c66aac105c9ed0d1` →
`c033eac8fcbf349cd7c711647e154c52c5bbbdad`:
`apps/macos/CrossProjectReference.swift`,
`apps/macos/FlowApp.swift`,
`apps/macos/NativeCrossProjectPreviewPopover.swift`,
`apps/macos/NativeReaderDocument.swift`,
`apps/macos/NativeReaderTextView.swift`,
`apps/macos/NativeReaderWindowController.swift`,
`apps/macos/Profiles.swift`,
`apps/macos/ProjectService.swift`,
`openspec/changes/add-cross-project-references/.openspec.yaml`,
`openspec/changes/add-cross-project-references/design.md`,
`openspec/changes/add-cross-project-references/proposal.md`,
`openspec/changes/add-cross-project-references/specs/flow-macos-app/spec.md`,
`openspec/changes/add-cross-project-references/specs/native-reader/spec.md`,
`openspec/changes/add-cross-project-references/tasks.md`,
`tests/flow-app/FlowAppTests.swift`,
`tests/flow-app/ProjectServiceTests.swift`,
`tests/flow-app/native-reader-app/CrossProjectPreviewTests.swift`,
`tests/flow-app/native-reader-app/test_contract.py`,
`tests/flow-app/native-reader-app/test_cross_project_preview.py`,
`tests/flow-app/test_flow_ui.py`,
`tests/flow-app/test_project_service.py`,
`tools/flow-reader/flow_reader/document/content.py`,
`tools/flow-reader/flow_reader/document/native_document.py`,
`tools/flow-reader/flow_reader/document/sections.py`,
`tools/flow-reader/flow_reader/services/cross_project_refs.py`,
`tools/flow-reader/packages/local/flow-reader/0.1.0/lib.typ`,
`tools/flow-reader/tests/test_cross_project_refs.py`, and
`tools/flow-reader/tests/test_sections.py`.
Hashes are Git-derived. That inventory contains no delivery-owned paths.


= Post-review source registration

Registered owner corrections may retire a regular source with a null `sha256`
and its exact prior `baseSHA256`. The binder validates absence at the correction
revision and current HEAD, and rejects a reappearing file unless a later owner
correction registers it with a null `baseSHA256`. Delivery-owned paths can never
be deleted through a correction. Historical correction records remain immutable.
Missing files without an explicit deletion correction still fail source binding.

The post-review owner correction registers the following paths from
`705f48b30e74887d00acb871806fd9f62ef9aa7e` → `44e0aa6f7efd3d08e4390bdc63924b5d60b268c3`:
`apps/macos/CrossProjectReference.swift`,
`apps/macos/FlowApp.swift`,
`apps/macos/NativeReaderObjectRenderer.swift`,
`apps/macos/NativeReaderRecoveryStore.swift`,
`apps/macos/NativeReaderWindowController.swift`,
`docs/tinymist/dev/reader-architecture.typ`,
`openspec/changes/add-cross-project-references/design.md`,
`openspec/changes/add-cross-project-references/proposal.md`,
`openspec/changes/add-cross-project-references/specs/native-reader/spec.md`,
`openspec/changes/add-cross-project-references/tasks.md`,
`openspec/changes/implement-native-reader-app/design.md`,
`openspec/changes/implement-native-reader-app/proposal.md`,
`openspec/changes/implement-native-reader-app/specs/flow-macos-app/spec.md`,
`openspec/changes/implement-native-reader-app/specs/native-original-pages/spec.md`,
`openspec/changes/implement-native-reader-app/specs/native-reader/spec.md`,
`openspec/changes/implement-native-reader-app/tasks.md`,
`tests/flow-app/FlowAppTests.swift`,
`tests/flow-app/native-reader-app/LayoutCacheTests.swift`,
`tests/flow-app/native-reader-app/MathBatchTests.swift`,
`tests/flow-app/native-reader-app/ServiceTests.swift`,
`tests/flow-app/native-reader-app/test_cross_project_preview.py`,
`tests/flow-app/native-reader-app/test_layout_cache.py`,
`tests/flow-app/native-reader-app/test_math_batch.py`,
`tests/flow-app/test_flow_ui.py`,
`tools/flow-reader/flow_reader/services/cross_project_refs.py`,
`tools/flow-reader/tests/test_cross_project_refs.py`,
`tools/flow-reader/tests/test_passages.py`.
Hashes are Git-derived; deleted sources bind null sha256.

The post-review math chunk follow-up registers the following paths from
`78f89ae202b1d87081e0fac6f705dbd8ae64d12d` → `9942afbcf8d3860a3bb1ac5f5cffe4924fb78f88`:
`apps/macos/NativeReaderObjectRenderer.swift`,
`tests/flow-app/native-reader-app/MathBatchTests.swift`.
Hashes are Git-derived.
