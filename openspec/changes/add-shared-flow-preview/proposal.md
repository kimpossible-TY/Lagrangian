## Why

Windows VS Code over Code Tunnel recompiles the same book as the running Flow service. Editing produced 95-second compilations and discarded 159-second evaluations under critical memory pressure on an 8 GB Mac. Shared preview viewers and save-triggered automatic compilation reduce duplicate preview work and superseded evaluations.

## What Changes

- Add an opt-in shared Flow preview setting. Resolve the active document to a host-side Flow profile and display its existing saved-document service without starting an LSP preview task.
- Add an independent `compileOnSave` option that keeps editor source synchronization and language queries current while deferring automatic full compilation after typing until save or an explicit compilation trigger.
- Keep defaults unchanged, reject ambiguous profiles and unsupported shared preview modes, label the saved-document view, and reuse one viewer per profile.
- Add regression and workload checks for compilation admission and shared preview lifecycle; document configuration and measurement limits.

## Capabilities

### New Capabilities
- `shared-flow-preview`: Reuse managed saved-document preview services from VS Code without an additional LSP preview server.
- `save-triggered-compilation`: Defer automatic full compilation while editing without freezing source synchronization.

### Modified Capabilities

## Impact

VS Code preview routing and configuration, Tinymist LSP compilation admission, focused tests and canonical Typst documentation. No dependency pin changes. This stage shares the Flow preview compiler across viewers; it does not serialize Typst compiler objects between processes. LSP saved diagnostics and demand-driven queries can still perform independent evaluation.
