# Design

## Context
See proposal.md. The delivery worktree starts at frozen 9b2dc876, preserving the 882 ancestor and NA10's eight-file delta. Shared native contracts, service policies and page consumers are read-only.

## Goals / Non-Goals
Produce a relocatable, hash-bound runtime and backend with a fresh native app independently of engine cache status. Preserve existing profile, manager and initializer contracts. Live service provisioning, final core/page integration, remote CI, macOS 13 execution and GUI acceptance are outside this initial production stage.

## Decisions
- Reuse the existing runtime producer's package SRI and 105-font preservation checks. Add portable Node distribution binding and sign its copied binary before inventory. A host dylib closure cannot establish portable delivery.
- Use the official Python.org framework payload without installing its package. Rewrite only copied Mach-O framework references to loader-relative paths, sign every copied Mach-O, and inventory the resulting bytes. Preserve original archives, signatures, licenses and input hashes separately.
- Supply official Typst prebuilt for backend compilation because the installed engine lacks the backend's CLI flags. Preserve the existing engine independently for preview and source history.
- Place backend, reader-common, interpreter, compiler and runtime in one app-relative delivery root. The copied verifier is also the backend launcher. At startup, Swift synchronously verifies the outer app seal, release/manifest binding and entrypoint paths before app.run(). Manager operations run in a detached task. The bundled Python launcher and shared child each verify the full delivery inventory before constructing trusted executable operations.
- Keep ReaderManager authoritative for profiles, service startup and source/account policy. Bundling supplies executable paths, not a new service lifecycle. The owner accepts optional concrete ReaderExecutables; its original config file is never rewritten. Manager and shared child independently authenticate the app and inject those operations through an optional managed-server factory. Missing configuration still fails; no implicit installation occurs.
- Write candidates beside the destination and exchange only after verification; failed candidates preserve accepted stages. Outer signing occurs after internal signatures and manifests.

## Risks / Trade-offs
- [Modified Python framework bytes] → preserve distribution provenance and verify all load paths, signatures and post-sign hashes.
- [Existing config refers to old executables] → substitute only authenticated concrete executable operations in ReaderManager while preserving schema/profile/source validation and config bytes. Child reentry repeats seal/release/inventory verification; environment and HTTP cannot mint bindings.
- [macOS 13 is unavailable] → inspect every arm64 Mach-O deployment target and report runtime certification as unverified.
- [Core/page integration is pending] → bind initial source and helper exactly, then resume this session for final rebinding.

## Integrated owner sources and external PM decision
C 76f5ac13 (including core ec2c4af9) is integrated with a normal no-ff merge, preserving 9b/882 ancestry. Canonical sources.json registers the actual page view/transport; C implementation bytes remain immutable. The input and delivery manifests bind owner commit ancestry and actual merged files, current source revision and current reader inventory. Runtime dependency and engine build provenance remain separate from app source identity.

That statement describes the historical C integration. Current source-provenance metadata in backend-delivery.json registers correction `338304a374bdd75ba76151a34bc8c284510ce725` relative to `09c5186bff1850b17f6e85fe2f3115153520bc94`: exactly 30 source/test/document paths with original and corrected SHA-256 values. integrated_sources retains historical core/page/G1/published revisions and digests separately, then checks each effective correction against its fixed Git objects and current regular-file bytes. Corrected files are not described as unchanged C/G1 bytes. Metadata and the binding owner are included by the existing sourceFiles and integratedSources manifest bindings.

The existing delivery owner has a finite exact file list, including its provenance metadata and binding test. Changes since the historical baseline must belong to that list or a registered correction; there is no directory-prefix or whole-HEAD exemption. Source must be clean. Correction bases/revisions must be full ancestor commits; path sets, original digests (or explicit verified absence for additions) and corrected digests must match immutable objects. No current-byte rehash repairs a mismatch. Production metadata registers338304 relative to09c (30 paths), followed by full8744c1b3db0b494f2e36529df281be993ccf11b4 relative to09e78630a6afb51436e45da140c3588c82c295f5 (15 paths). Both inventories use immutable Git-object original/corrected hashes; the older record is unchanged. Source-binding tests use the actual assembled checkout and current explicit delivery bytes, retaining an old338-only rejection of actual8744 code. This does not provide an engine profile/provenance, build an app or register pending NA15/16 source. Later native corrections or APIs require PM-transferred fixed commits/inventories and the canonical registry/packaging inputs for actual new files; no pending owner SHA is invented. This preparation does not build or certify an app.

The verifier takes --acceptance plus --pm-acceptance-receipt. The receipt binds the exact app source revision and signed bundle checksum to seven named gate artifact digests/statuses: source, runtime, requiredtests, code-review, docs, nativeGUI and AX. Bounded relative JSON artifacts repeat gate/app/source/status and requiredSkips=0; requiredtests requires positive test count. Missing/stale/tampered/failed/required-skipped receipts return acceptance exit2, independently of integrity. A structurally valid receipt records an external PM decision and does not establish authority, review quality or user permission. Test passes use clearly synthetic mechanism fixtures only.

This is a pre-GUI candidate: actual formal final gate evidence remains absent. Integration is complete while review is pending. Original source anchors/jumps remain unsupported; PDF selection is page-local display only and rawdiff-v1 native consumption remains unverified. Current-host/minOS evidence does not certify actual OS13 runtime, live provider use or VoiceOver speech.

## Migration Plan
No live migration is executed. Build and verify isolated candidates, review the source-bound manifest, and hand exact outputs to NA06/NA08. Keep the immutable NA11 stage untouched. A future approved pipeline installation uses the standard updater.

## Final inspection assembly
Normal no-ff merges add fixed GUI preparation G1 and published main487. G1 seven files and published services/homepage are exact; only the transferred C test collection/input roots are changed. Runtime is freshly prepared from pinned dependencies at the final clean HEAD so runtime/reader/delivery/app source identities agree. A later source change invalidates the final-build binding and requires rebuilding.

The D test launcher composes G1's evidence base/reentry script only; existing root, sandbox, source, HTTP, private-copy and bounded lifecycle policies remain with G1. Inspection is setup-only, separate smoke starts/stops an owned foreground fixture, and the actual user home is denied. The historical G1 smoke1/2 possible live-profile read is retained as an unverified early limitation. Composer clipboard and external actions are excluded. At that frozen NA13 stage, updater build-without-delivery was a separately reported consumer limitation; NA14 supplies the new-checkout consumer below.

## NA14 existing CLI consumer

The engine-local schema-2 context binds repository, R/H, canonical engine path/hash, validated run record, artifact inventory digest and named delivery/source/helper/runtime/reader/signing bindings at a fixed relative root. The current consumer accepts only context schema 2. Its transport binding keeps raw archive, manifest and raw-inventory digests separate from the normalized inventory digest after authenticated external-engine mode normalization; artifactInventorySHA256 names that normalized inventory. The producer's schema-1 JSON transport envelope is a separate format, not context schema 1. The context is not authority: build re-views exact R, downloads the exact artifact again and compares raw and normalized bindings through the existing owner. Current app seal/release/sidecar, sourceFiles/helper, runtime, reader and integrated owner checks precede fresh Swift packaging. The reader downloader/check_manifest verifies the separate same-R artifact. E can be older; app/delivery/runtime/reader and checkout must equal H. Missing payload is a bounded producer failure, never a management-only fallback. Explicit delivery cannot weaken those checks. Standalone engine builds require explicit verified delivery; management-only fixtures opt in and fail require-delivery.

Original artifact signing/hash provenance is preserved. Local signing requires an explicit identity or saved certificate; ad-hoc is explicit only. A different identity signs copied candidate images through the existing stager/runtime verifier and rebinds post-sign runtime/delivery inventories before the outer seal. Exact input is checked again before atomic app exchange. No global last-run state, installed/scratch/PATH dependency fallback, network acquisition or mutable producer pins are added. Offline gh and installer/service spies do not prove deployment. NA14 source requires final source rebinding and separate PM integration, delta review and exact-byte GUI/AX acceptance.

## Native artifact transport correction
The native directory is no longer uploaded directly. The stable artifact name carries a tar and a strict JSON R/H/repository/raw-SHA/inventory envelope. Ordinary file/directory modes, internal relative links and hidden signatures survive upload v4's documented permission loss. The new native_delivery_artifact orchestration reuses reader_bundle's shared bounded tar extraction, delivery inventory and atomic publication, and existing run/source/reader/signing owners. It introduces no global last-run database or parallel relaxed signing validator.

The shared extractor bounds raw/PAX headers before allocation, validates exact members/modes/hashes/bytes, rejects special files/modes, sparse data and unsafe paths/links, and creates links last. Native budgets are 2GiB archive/total, 256MiB entry, 30000 logical members, 64KiB PAX and 16MiB manifest. Extraction uses a private candidate; rehash and input-drift checks precede atomic publication. A prior valid stage survives interruption.

Fetch stores the raw transport separately in its engine-local cache and authenticates the archive before normalizing only external flow-engine to755. Schema2 context binds both raw transport and normalized inventory; same R/H is re-viewed and re-downloaded for each build. Archive failure has no flat/old-app/scratch fallback. Only engine-only cache reuse can read a verified legacy flat engine contract, discarding its app. Every current app/tar is rebuilt. Actual frozen09c has no retained engineBuild and remains an expected producer failure; offline positive R/H/E/profile metadata is synthetic, never actual GitHub provenance. No dependency pins, Swift/UI/backend/receipt policy or live updater services change.

## Review repair: development runtime exception

Production APP_ID build, validation and artifact publication require current-H
runtime provenance. A retained runtime is an inspection-only exception for an
explicitly validated development bundle namespace with ad-hoc identity. Generic
staging does not make a retained payload production-eligible. Before candidate
copy/compile, and again during signed app validation, the existing delivery owner
checks the runtime producer against application revision and validated namespace.
Retained certificate combinations remain refused before copying or signing.

The retained exception accepts only the fixed runtime manifest SHA-256
`aa824a56c4d310a9977cdcc1f7a65dd718b92fcba46605347cad20dd431623fc`
and exact registered clean producer record at
`d7cd069f2249a405061bf220cfd7e0184f75c7fe`, including its producer input digests.
The existing staging owner still verifies ancestry, Node distribution, helper,
runtime inventory and immutable payload hashes before ad-hoc staging. This
staging permission grants no production bundle eligibility: only a validated
development namespace with ad-hoc identity may consume the retained bytes.
Current-H production runtime and fresh-runtime certificate paths retain their
existing policy. No runtime guard, producer record or original payload changes.
Current-H production/certificate policy remains available; injected identity tests
are distinct from real certificate/Keychain acceptance. Original retained payload,
manifest, signature and producer records remain byte-preserved.
