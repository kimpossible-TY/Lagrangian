## 1. Implementation

- [x] 1.1 Add compileOnSave admission with fresh snapshots and stale-worker handling.
- [x] 1.2 Add shared Flow profile resolution, viewer reuse and early preview routing.
- [x] 1.3 Add localized configuration and canonical documentation.

## 2. Validation

- [x] 2.1 Add and run LSP admission, save, close, query freshness and stale-worker regressions.
- [x] 2.2 Add and run shared preview profile, routing and lifecycle regressions.
- [x] 2.3 Run targeted builds, formatting, lint and OpenSpec validation.
- [x] 2.4 Record reproducible workload results and remaining performance limits.

Host-watcher timing limitations and the unmeasured production latency are recorded in `verification.md`.

## 3. Authorized deployment and workload measurement

- [x] 3.1 Build and sign Flow 0.1.15 and package the matching native VS Code extension from the clean implementation commit.
- [x] 3.2 Back up and install the app/extension, enable both options for managed projects, and reload the active remote extension host.
- [x] 3.3 Verify installed engine identity, live document delivery and shared preview routing.
- [x] 3.4 Compare the real PDE workload before/after and record latency, memory and measurement boundaries.

## 4. Desktop source navigation

- [x] 4.1 Bridge viewer-local source hits to the embedded VS Code reader, preserving mobile selection behavior and rejecting stale or unrelated events.
- [x] 4.2 Reveal the saved source position in VS Code with canonical project boundaries and Unicode column conversion.
- [x] 4.3 Validate frontend, protocol and actual editor navigation; build and install the updated app and extension.

- [ ] 4.4 Support the user's external-browser workflow with a session-scoped callback, then validate and deploy both viewer modes.

## 5. Reuse Tinymist bidirectional synchronization

- [x] 5.1 Reuse upstream span-range resolution, source-to-document mapping, editor reveal and selection-change policy for shared readers.
- [x] 5.2 Adapt the existing editorScrollTo/panelScrollTo protocol to viewer-local desktop connections, including embedded and external readers and both themes.
- [ ] 5.3 Verify both directions, Unicode coordinates, revision/dirty guards, mobile isolation and absence of additional compilation.
- [ ] 5.4 Build and install the matching engine and extension; record deployment evidence and Windows confirmation limits.
