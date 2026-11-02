## Context
Work starts at origin/main 262d7554 in an isolated managed worktree on refactor/reader-architecture. The original checkout contains uncommitted terminal/Neovim work. Preserve it without importing or deleting it. Read add-responsive-reader, add-shared-flow-preview, package-tinymist-flow-app and compiler lifecycle specs as behavior contracts.

## Decisions
- Shared frontend code lives in tools/reader-common. It owns reusable feature policy/state and accepts renderer-specific operations; it never imports a reader. Renderer-specific coordinate and transport implementations stay local. No speculative universal coordinate representation.
- Keep each feature's state with its controller. Share actual matching policy (selection action submission, bounded review persistence, last-change queues) while retaining distinct DOM and page invalidation/geometry.
- HTML Reader Python implementation moves under flow_reader with compiler, document, rendering, server and services packages. Root CLI launchers remain supported. One content pipeline owns HTML normalization, auditing and accepted warning policy for isolated and incremental compilation.
- Rust compiler splits preserve scheduling tickets, revision ordering, cancellation and private unit-test access. Keep crate/public API boundaries. Native app separates profile storage, service lifecycle, engine launch, CLI and AppKit composition; packaging and tests discover the same explicit source set.
- Installation must carry shared assets and nested package files. Server static delivery remains an explicit allow-list. Existing storage keys, protocol field names, service identities and validation stay compatible.
- AGENTS guidance defines current ownership and dependency direction; a maintained source map describes concrete files. Do not demand pre-approval for routine implementation within authorized scope.

## Shared browser rendering follow-up

The paged preview renders its document model with WASM in the browser. The HTML
Reader composes semantic mathematics with browser-local MathJax and places native
figure labels locally. These are distinct renderers, not interchangeable compiler
backends. HTML graphical relationships and custom decorations still use the
server's validated dynamic renderer; this refactor does not move arbitrary Typst
programs to the browser or change those HTTP contracts.

`tools/reader-common/rendering/scheduler.js` owns coalesced animation-frame
scheduling, serialized asynchronous execution, adapter-supplied selection holds,
debounce delays and cancellation/disposal. Both `typst-dom` document rendering and
HTML mathematical composition use it. A held task waits for an adapter signal,
without polling or reporting completion. Cancellation invalidates completion of
in-flight work but cannot interrupt synchronous WASM/DOM work; adapters retain
their document/geometry guards. Completion runs after the scheduler releases its
running state so navigation may enqueue the next frame safely. The paged adapter
retains ordered deltas and viewport replacement, and the HTML adapter retains
nearby-expression batches, retry policy and mathematical identity checks.

Serve the shared module through the HTML asset allow-list and verify archived
installation. Include `typst-dom` in the shared dependency-boundary checks. No
installed app/service update is part of this follow-up.

## Validation
Run existing Node and Python reader suites, preview Vitest/build/type checks, Rust project crate tests/format/lints, Swift/app packaging tests and generated-doc checks where affected. Add meaningful cross-reader and packaged-delivery coverage. Inspect diff and get independent review before merge. No app installation or release tagging is required.

## Contributor guidance and validation follow-up

The canonical development guide owns OOP/SOLID interpretation, reuse criteria,
and validation selection. Root AGENTS provides a short entrypoint; scoped files
record only local ownership, contracts and commands. Existing source maps retain
file-level ownership. Continue on the current branch.

Reuse the reader dependency-graph and feature contract tests. Add an explicit
architecture command and include typst-dom tests in the reader gate. Add scoped
ESLint checks for browser JS/TS and Node test/terminal code, excluding vendor and
generated files. Preserve VS Code lint configuration and expose both scopes in
the aggregate lint command. CI uses the same commands on macOS so installed-layout
tests run. Compiler/browser fixtures retain explicit prerequisites and are not
claimed by the base gate. Required integration runs must fail on skipped tests.

Do not add a universal SOLID checker, class/line-count limits, duplicate contract
fixtures, or a new Python/Swift lint dependency in this change. Python lint
adoption remains a separate baseline assessment; Swift retains warning-denying
compilation. Documentation and lint configuration changes need focused validation,
not an unrelated engine rebuild.

## Feature policy ownership follow-up

Apply the canonical OOP/SOLID rules to three observed responsibility leaks:

- `reader-common/selection/press.js` owns the repeated press/click selection
  lifecycle shared by HTML and paged toolbars. Native DOM event bindings, selected
  positions, toolbar presentation and action effects remain with the concrete
  reader. Preserve deferred release after pointerup/cancel and dispose its timer.
- `flow_reader/services/accepted_snapshot.py` owns captured accepted document/input
  freshness for verified source operations. Capture under the existing publication
  lock, keep highlight's edit-lock order, and retain caller-specific stale/error
  mappings. `compiler/inputs.py` owns both stat signatures and content fingerprints;
  source-navigation and selection services share those definitions. Read-only
  geometry's accepted-output policy and locate's revision-only checks remain local.
- Existing native `ProjectService` owns project creation defaults, selected-profile
  changes and persistence in addition to profile updates. AppKit gathers inputs and adopts
  successfully saved settings. `LaunchAgentService` uses one argument producer for
  plist creation and ownership checks. Keep profile schema, IDs, label/port/path
  defaults and CLI behavior compatible; adding a profile does not control services.
  Creation and selection failures preserve the previously published UI settings.

Use focused lifecycle/contract tests, the shared reader gate, archived delivery,
TypeScript checks, preview build and native warning-denying tests. Update the
architecture source map and local ownership descriptions. No universal service
manager, cross-language runtime, renderer-coordinate unification, dependency pin,
branch switch, release installation or service restart is needed.
