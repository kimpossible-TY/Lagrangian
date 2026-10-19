## Context
Work starts at origin/main 262d7554 in an isolated managed worktree on refactor/reader-architecture. The original checkout contains uncommitted terminal/Neovim work. Preserve it without importing or deleting it. Read add-responsive-reader, add-shared-flow-preview, package-tinymist-flow-app and compiler lifecycle specs as behavior contracts.

## Decisions
- Shared frontend code lives in tools/reader-common. It owns reusable feature policy/state and accepts renderer-specific operations; it never imports a reader. Renderer-specific coordinate and transport implementations stay local. No speculative universal coordinate representation.
- Keep each feature's state with its controller. Share actual matching policy (selection action submission, bounded review persistence, last-change queues) while retaining distinct DOM and page invalidation/geometry.
- HTML Reader Python implementation moves under flow_reader with compiler, document, rendering, server and services packages. Root CLI launchers remain supported. One content pipeline owns HTML normalization, auditing and accepted warning policy for isolated and incremental compilation.
- Rust compiler splits preserve scheduling tickets, revision ordering, cancellation and private unit-test access. Keep crate/public API boundaries. Native app separates profile storage, service lifecycle, engine launch, CLI and AppKit composition; packaging and tests discover the same explicit source set.
- Installation must carry shared assets and nested package files. Server static delivery remains an explicit allow-list. Existing storage keys, protocol field names, service identities and validation stay compatible.
- AGENTS guidance defines current ownership and dependency direction; a maintained source map describes concrete files. Do not demand pre-approval for routine implementation within authorized scope.

## Validation
Run existing Node and Python reader suites, preview Vitest/build/type checks, Rust project crate tests/format/lints, Swift/app packaging tests and generated-doc checks where affected. Add meaningful cross-reader and packaged-delivery coverage. Inspect diff and get independent review before merge. No app installation or release tagging is required.
