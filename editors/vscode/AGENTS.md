# VS Code extension

## Read

Read `package.json`, nearby source/tests and the Rust implementation backing the affected command or setting. Shared activation and capabilities must work in both system and web modes.

## Ownership and sources

- `src/extension*.ts` owns activation/composition; `src/lsp*.ts` owns client wiring and platform launch; `src/features/` and `src/tools/` own user features and webviews.
- Reuse `tinymist`, `IContext`, the tool registry and e2e `Context` harness. Command/UI handlers gather inputs and delegate reusable policy.
- `package.json` owns shipped contributions; `package.other.json` supplies additional config documentation. Server-backed settings also involve `crates/tinymist/src/config.rs`.
- Localization sources are `locales/tinymist-vscode.toml` and `locales/tinymist-vscode-rt.toml` at the root; run `yarn build:l10n` there to extract strings before translation and regenerate afterward.
- Documentation sources are `docs/tinymist/frontend/vscode.typ` and `docs/tinymist/config/vscode.typ`. Grammar sources are `syntaxes/textmate/`; generated `out/*.tmLanguage.json` files come from `yarn build:syntax`.

## Contracts

- Keep command/setting identifiers consistent across manifests, localization, docs and backend handlers.
- Preserve web/system capability differences. Shared code must not assume a desktop binary or Node runtime.
- Keep source, tests and fixtures authoritative; generated bundles and localized JSON are build outputs.

## Verification

Commands below run from `editors/vscode/` unless marked root:

- Pure logic: `yarn type-check` and `yarn test:unit`; use `src/*.test.ts` for focused behavior tests.
- Commands/workspace/LSP behavior: `yarn test:vsc`; use `src/test/e2e/` and minimal fixtures under `e2e-workspaces/`.
- Formatting: `yarn format-check`; lint: root `yarn lint:vscode`.
- Activation/platform changes: `yarn compile:system` and `yarn compile:web`.
- Localization, grammar and docs: root `yarn build:l10n`, `yarn build:syntax` plus `yarn test:grammar`, or `yarn docs:check`, as affected.
- Backend contracts: run the affected Rust crate tests as well. Review snapshot differences before accepting them.
