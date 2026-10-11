## Context

Flow runs a saved-file preview on the Mac. The remote VS Code extension currently starts a separate LSP preview before resolving even custom previewer providers. LSP source edits trigger full document compilation despite preview refresh being onSave.

## Goals / Non-Goals

**Goals:** Reuse the managed Flow preview for desktop and phone viewers; reduce superseded automatic LSP evaluation; preserve current source snapshots and explicit language queries; retain defaults and failure visibility.

**Non-Goals:** IPC serialization of Typst/comemo objects, eliminating all demand-driven LSP evaluation, changing installed engines or live profiles automatically, or displaying unsaved buffers on the phone. LSP save-time diagnostics remain an independent compilation; shared preview alone does not remove that cost.

## Decisions

- `tinymist.preview.sharedFlow` opts a trusted workspace into host-side Flow profile discovery. Read the existing Flow settings location (respect FLOW_DATA_DIR), match canonical document/root paths, select the most specific root, and reject ambiguous matches. Require a valid profile entry inside that root and a healthy local HTTP endpoint.
- Route before ordinary preview creation. Shared previews create no LSP preview task, thumbnail socket or scroll-sync subscription. Use the existing HTTPS public URL directly when available; otherwise translate the loopback HTTP endpoint through asExternalUri. Show an explicitly saved-document webview, with a browser option, bounded CSP and one panel per profile/URL. Do not silently fall back to an expensive independent compiler when shared routing fails. Slides, development previews and browsing mode fail explicitly in shared mode.
- `tinymist.compileOnSave` independently defers automatic LSP compilation following didChange. Source memory/VFS and generation invalidation still update immediately, so queries see fresh buffers and superseded jobs cannot publish. Per-project admission flags survive discarded worker completion. Save, close, explicit compile/entry changes and real filesystem changes release deferral; upstream VFS synchronization caused by typing does not. Configuration changes rebuild the project consistently. Already running Typst evaluation cannot be forcibly cancelled.
- LSP full diagnostics update on save or external changes. Interactive queries remain available and may evaluate expressions. Saved Flow preview, LSP unsaved buffers and theme-specific outputs retain distinct identities.

## Risks / Trade-offs

- Full diagnostics are delayed during typing → Opt-in setting, clear documentation, save and manual compilation remain available.
- Service unavailable or ambiguous profile → Report actionable errors; never start another backend silently.
- Profile switching or repeated concurrent opens → Deduplicate viewers and resolve pending opens without duplicate panels.
- Same engine does not imply shared all-process caches → Measure automatic compile counts and saved preview backend identity; do not promise a memory halving or a fixed latency improvement.
- Source-to-preview jumps rely on LSP render state → Shared view initially exposes the Flow reader controls, without claiming editor cursor synchronization.

## Migration Plan

Build and test source changes in an isolated branch. Enable both options in a configured Flow workspace after installing a compatible engine and extension. Disable sharedFlow to return to ordinary preview; disable compileOnSave to restore automatic typing compilation. Installed services and user settings are not altered by implementation tests.
