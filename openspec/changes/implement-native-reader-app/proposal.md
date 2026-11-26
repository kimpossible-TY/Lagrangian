# Proposal

## Why

Native reader workers need one executable, loss-aware document and interaction contract before they can implement an AppKit body without duplicating compiler, source or account authority.

## What Changes

- Add a typed Swift semantic document, narrow asynchronous operations and a Python accepted-section importer with independent compiler fixtures.
- Preserve mathematical, tabular and graphical content and reject unknown required semantics. Probe existing object computation and native paint separately.
- Add a disposable, owner-scoped 64 MiB LRU layout cache with one shared envelope/atomic-write helper and separate per-revision document storage; typed offline recovery retains its existing owner.
- Record the 64 MiB document cap, mathml-batch helper bounds, listItemNumber, percentage image units and mark: anchors introduced in 20ad89a5.
- Retain the simplified home icon dock, status-bar controls, sage running indicators, .ghost buttons and statusImage branding.
- Replace browser-only Read presentation with a native document destination while retaining external readers. Shell, transport, full object fidelity and GUI acceptance remain subsequent work.

## Capabilities

### New Capabilities

- `native-reader`: ordered semantic snapshots, explicit units, loss diagnostics and guarded native operations.

### Modified Capabilities

- `flow-macos-app`: native Read adoption and paint acknowledgment, preserving asynchronous lifecycle and external-reader compatibility.

## Impact

NA01 owns the shared Swift/Python contract and fixtures. NA02 text, NA03 objects, NA04 services and NA05 shell consume the same committed contract. No new dependency, HTTP implementation, source writer, authentication authority, installation or P0 source modification is included. Canonical detail: `docs/tinymist/dev/native-reader-app-contract.typ`.

## NA15 additive editor effect implementation

Connect explicit native Locate Source to the existing saved-source and private
editor owners with a distinct effect receipt; preserve read-only locate semantics.
FlowApp composes one consented local editor without discovery or default opt-in.
This adds a bounded loopback-only editor adapter and no-replay receipt store, not
a source writer or account authority. Canonical contract:
`docs/tinymist/dev/native-reader-editor-actions.typ`. NA16, exact delivery rebinding
and real native interaction/visual acceptance remain separate follow-ups.

## Current app and cache scope

NativeReaderRecoveryStore owns typed offline recovery; NativeReaderLayoutCache owns
only disposable viewed layouts in the profile-shared native-reader/layout-cache
directory, partitioned by ownerID. NativeReaderSnapshotStorage owns their shared
schema/SHA-256 envelope and atomic writes. NativeReaderViewedLayouts owns the
bounded in-memory working set. FlowApp, NativeAppDesign and NativeBrandMark are
in scope for the delivered simplified home and menu-bar presentation. These
source corrections do not install or restart the user's services.
