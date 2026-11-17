# Design

## Context
See proposal.md. The delivery worktree starts at frozen 9b2dc876, preserving the 882 ancestor and NA10's eight-file delta. Shared native contracts, service policies and page consumers are read-only.

## Goals / Non-Goals
Produce a relocatable, hash-bound runtime and backend with a fresh native app independently of engine cache status. Preserve existing profile, manager and initializer contracts. Live service provisioning, final core/page integration, remote CI, macOS 13 execution and GUI acceptance are outside this initial production stage.

## Decisions
- Reuse the existing runtime producer's package SRI and 105-font preservation checks. Add portable Node distribution binding and sign its copied binary before inventory. A host dylib closure cannot establish portable delivery.
- Use the official Python.org framework payload without installing its package. Rewrite only copied Mach-O framework references to loader-relative paths, sign every copied Mach-O, and inventory the resulting bytes. Preserve original archives, signatures, licenses and input hashes separately.
- Supply official Typst prebuilt for backend compilation because the installed engine lacks the backend's CLI flags. Preserve the existing engine independently for preview and source history.
- Place backend, reader-common, interpreter, compiler and runtime in one app-relative delivery root. The copied verifier is also the backend launcher. Swift validates the outer seal and delivery inventory off the main thread before invoking existing manager operations.
- Keep ReaderManager authoritative for profiles, service startup and source/account policy. Bundling supplies executable paths, not a new service lifecycle. The owner accepts optional concrete ReaderExecutables; its original config file is never rewritten. Manager and shared child independently authenticate the app and inject those operations through an optional managed-server factory. Missing configuration still fails; no implicit installation occurs.
- Write candidates beside the destination and exchange only after verification; failed candidates preserve accepted stages. Outer signing occurs after internal signatures and manifests.

## Risks / Trade-offs
- [Modified Python framework bytes] → preserve distribution provenance and verify all load paths, signatures and post-sign hashes.
- [Existing config refers to old executables] → substitute only authenticated concrete executable operations in ReaderManager while preserving schema/profile/source validation and config bytes. Child reentry repeats seal/release/inventory verification; environment and HTTP cannot mint bindings.
- [macOS 13 is unavailable] → inspect every arm64 Mach-O deployment target and report runtime certification as unverified.
- [Core/page integration is pending] → bind initial source and helper exactly, then resume this session for final rebinding.

## Integrated owner sources and external PM decision
C 76f5ac13 (including core ec2c4af9) is integrated with a normal no-ff merge, preserving 9b/882 ancestry. Canonical sources.json registers the actual page view/transport; C implementation bytes remain immutable. The input and delivery manifests bind owner commit ancestry and actual merged files, current source revision and current reader inventory. Runtime dependency and engine build provenance remain separate from app source identity.

The verifier takes --acceptance plus --pm-acceptance-receipt. The receipt binds the exact app source revision and signed bundle checksum to seven named gate artifact digests/statuses: source, runtime, requiredtests, code-review, docs, nativeGUI and AX. Bounded relative JSON artifacts repeat gate/app/source/status and requiredSkips=0; requiredtests requires positive test count. Missing/stale/tampered/failed/required-skipped receipts return acceptance exit2, independently of integrity. A structurally valid receipt records an external PM decision and does not establish authority, review quality or user permission. Test passes use clearly synthetic mechanism fixtures only.

This is a pre-GUI candidate: actual formal final gate evidence remains absent. Integration is complete while review is pending. Original source anchors/jumps remain unsupported; PDF selection is page-local display only and rawdiff-v1 native consumption remains unverified. Current-host/minOS evidence does not certify actual OS13 runtime, live provider use or VoiceOver speech.

## Migration Plan
No live migration is executed. Build and verify isolated candidates, review the source-bound manifest, and hand exact outputs to NA06/NA08. Keep the immutable NA11 stage untouched. A future approved pipeline installation uses the standard updater.
