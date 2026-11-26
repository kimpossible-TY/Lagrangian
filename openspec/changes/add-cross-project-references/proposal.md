## Why
Readers need to inspect a reference to another project without losing their current reading position. IDE users also need to register a project directory without guessing its entry file.

## What Changes
- Specify IDE directory registration with deterministic entry discovery, explicit selection for ambiguous entries and an optional stable projectRefKey.
- Add read-only schema-1 projects.json catalog resolution and a bounded cross-project back-navigation stack.
- Add a compact native preview component: first click previews; a second click on the body or the interactive icon jumps to the target project and anchor. The icon uses SF Symbol `arrow.up.right`, with no visible `열기` label.
- Specify HTML `data-project-ref-*` metadata and a projects.json URL/page/display-text fallback.

## Capabilities
### New Capabilities
- `native-reader`: cross-project preview and navigation contracts.
### Modified Capabilities
- `flow-macos-app`: directory registration and reference identity.

## Impact
This change delivers reusable Swift core/AppKit components and their FlowApp.swift integration: IDE directory chooser, reader preview, committed project/anchor navigation and Back restoration. HTML producers `tools/flow-reader/packages/local/flow-reader/0.1.0/lib.typ`, `document/content.py` and `document/native_document.py` export/preserve labels and native projectRef metadata. A first-click preview may attach through the existing ReaderManager and start the target project's reader service; it does not navigate. Existing session/service/source owners remain authoritative. PDE readers and external catalog producers remain outside this repository's implementation. The unused Python cross_project_refs service and its isolated test are removed; Swift owns catalog/snippet policy.
