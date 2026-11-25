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
This change delivers reusable Swift core and AppKit components plus isolated tests. FlowApp.swift, PDE readers, HTML producers and live application/service state remain outside this implementation. IDE chooser wiring, document navigation and metadata emission are specified integration work, not delivered runtime behavior in this component change.
