# Reader contracts

## Read

Read [the architecture source map](../docs/tinymist/dev/reader-architecture.typ) and the matching OpenSpec contracts. Local reader instructions refine this file.

## Ownership and boundaries

- `reader-common/` owns matching selection submission/press state, bounded review persistence, change-location, session activity and browser scheduling policy. Native ESM and declaration files serve JavaScript and TypeScript consumers.
- Concrete readers own DOM/page geometry, transport and renderer-specific state. Shared modules must not import concrete readers; readers must not import each other's internals. Keep imports acyclic.
- Classify new work under an existing feature owner before adding one. Define supported capabilities, effects, failure/stale handling and disposal; expose only implemented capabilities.

## Contracts

- Preserve native page coordinates and semantic DOM offsets. Do not manufacture coordinates to satisfy another renderer's interface.
- Validate document/revision/service identity on asynchronous results. Old responses must not dismiss current selections or paint a newer document.
- Source Highlight writes verified source. Saved for Codex stores explicit context without sending messages or starting an assistant turn. Review Strike is browser-local paint with undo/clear and compatible storage keys.
- Retired quotation storage stays untouched. Do not introduce another quote library or automatic migration.
- Update the architecture source map when ownership changes. Cross-language reuse shares contracts and fixtures while retaining runtime boundaries.

## Verification

Commands run from the repository root:

- `yarn lint:readers` checks first-party browser and Node code.
- `yarn test:architecture` checks reader dependency boundaries and runtime import cycles.
- `yarn test:readers` runs shared/HTML policy tests, Python services/install tests, paged frontend and DOM tests. Run it when shared behavior changes.
- `node --test tools/reader-common/tests/*.mjs` is the focused shared-policy suite.
- Use concrete reader instructions for compiler, browser, build and installation coverage; report skipped fixtures accurately.
