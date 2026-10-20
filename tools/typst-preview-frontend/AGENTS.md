# Paged Reader

## Read

Read [the architecture source map](../../docs/tinymist/dev/reader-architecture.typ), `src/features/` and the affected engine protocol implementation.

## Ownership

- `src/features/` owns paged selection, review marks, navigation, appearance, editor synchronization and connection/session adapters.
- `../typst-dom/` owns document deltas, WASM composition, page geometry and touch-selection operations.
- Reuse `../reader-common/` for matching policy; keep WebSocket transport and engine-generated theme variants with their concrete owners.

## Contracts

- Preserve page coordinates, ordered deltas, originating-editor channels and document/revision guards. Rendering completion belongs to its original request.
- Keep initialization focused on composing controllers and disposing owned listeners/resources.
- Update the existing asset build when source delivery changes and verify the resulting preview bundle.

## Verification

Commands run from the repository root:

- Feature tests: `yarn workspace typst-preview-frontend test run`.
- DOM rendering tests: `yarn workspace typst-dom test run`.
- Type checks: `yarn tsc --noEmit -p tools/typst-preview-frontend/tsconfig.json` and `yarn tsc --noEmit -p tools/typst-dom/tsconfig.json`.
- Frontend edits: `yarn lint:readers`; build/delivery edits: `yarn build:preview`.
- Shared contracts: `yarn test:readers`; engine protocol changes also require the affected Rust crate tests.
