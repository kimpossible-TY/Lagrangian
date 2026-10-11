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
