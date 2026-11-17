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
- Keep ReaderManager authoritative for profiles, service startup and source/account policy. Bundling supplies executable paths, not a new service lifecycle. Missing configuration or a required manager injection API is an explicit handoff, never implicit installation.
- Write candidates beside the destination and exchange only after verification; failed candidates preserve accepted stages. Outer signing occurs after internal signatures and manifests.

## Risks / Trade-offs
- [Modified Python framework bytes] → preserve distribution provenance and verify all load paths, signatures and post-sign hashes.
- [Existing service configuration refers to old runtime paths] → fail closed and report the manager configuration handoff; do not migrate live data.
- [macOS 13 is unavailable] → inspect every arm64 Mach-O deployment target and report runtime certification as unverified.
- [Core/page integration is pending] → bind initial source and helper exactly, then resume this session for final rebinding.

## Migration Plan
No live migration is executed. Build and verify isolated candidates, review the source-bound manifest, and hand exact outputs to NA06/NA08. Keep the immutable NA11 stage untouched. A future approved pipeline installation uses the standard updater.
