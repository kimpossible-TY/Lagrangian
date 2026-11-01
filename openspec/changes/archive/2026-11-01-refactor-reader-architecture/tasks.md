## 1. Establish change
- [x] Inspect current source/remote state and preserve unrelated local work.
- [x] Create isolated worktree and refactor/reader-architecture branch.
- [x] Record architecture and behavior-preservation requirements.

## 2. Shared reader features
- [x] Extract shared feature policy/state and remove cross-reader internal imports.
- [x] Organize paged and HTML adapters, feature code and rendering assets by responsibility.
- [x] Preserve feature contracts and validate shared assets in installed layout.

## 3. HTML Reader service
- [x] Move implementation into responsibility-oriented flow_reader packages, preserve CLI entrypoints.
- [x] Unify isolated/incremental content normalization, audit and diagnostic policy.
- [x] Separate HTTP delivery from mutable document/service state and update tests/imports.

## 4. Engine and native app
- [x] Split project compiler implementation and tests while preserving crate APIs and lifecycle semantics.
- [x] Split native app models, storage, lifecycle, launch, CLI and UI responsibilities; update packaging/tests.

## 5. Guidance and validation
- [x] Update root/scoped AGENTS and canonical architecture/development documentation.
- [x] Run reader, frontend, Rust, Swift and packaging checks appropriate to all affected areas.
- [x] Independently review final patch and resolve findings.
- [x] Commit/push branch, merge verified branch into main and verify remote state while preserving unrelated work.

## 6. Shared browser rendering follow-up
- [x] Extract the matching browser render scheduling policy and adopt it in the paged WASM and HTML math adapters, preserving renderer-specific guards and ordered updates.
- [x] Cover coalescing, asynchronous serialization, selection holds, cancellation, failures and completion reentrancy in shared and concrete-reader tests.
- [x] Update ownership, asset delivery and architecture checks; validate both readers, types, frontend build and archived HTML installation on the current branch.

2026-10-19 follow-up validation: 128 shared/HTML Node tests, 129 Python tests
(41 compiler-dependent cases skipped; archived installation/delivery passed),
82 paged frontend tests and 36 DOM tests passed. Both TypeScript projects,
preview build, scoped formatting, generated-doc consistency and strict OpenSpec
validation passed. Since Yarn is unavailable on PATH, the reader gate's commands
were run directly. Chromium (installed Chrome) and WebKit passed actual local
MathJax reflow, selection hold/resume, stale-candidate rejection, direct-probe
serialization and disposal with zero rendering API requests. That checkpoint did
not include deployment, server-load/device latency benchmarking or a physical
iPhone check. The shared scheduler was subsequently installed in both readers in
the confirmed `flow-v0.1.27` release; see the deployment evidence in
`../add-responsive-reader/verification.md`. HTML now draws supported decoration
primitives locally; unsupported callbacks and relationships retain server rendering.

## 7. Contributor guidance and validation follow-up
- [x] Centralize design and validation policy in the canonical development guide; simplify root and scoped instructions.
- [x] Add reader ESLint scopes and shared architecture/reader commands; connect CI without duplicating policy.
- [x] Provide a required Python integration mode that rejects skipped tests, retaining the optional local suite.
- [x] Regenerate and compile documentation; run lint, architecture and reader suites; inspect the diff and validate OpenSpec.


2026-10-20 guidance/validation follow-up: reader lint (zero warnings), architecture
checks, 148 Node tests, 82 paged tests, 36 DOM tests, both TypeScript checks and
preview build passed. The Python suite reported 133 tests and 42 skips (41
compiler fixtures and one companion-source class); installed-layout and new strict
runner tests passed. Required integration was not run against real compiler or
Tail Hosting inputs. New runner tests verify missing prerequisites, skipped
coverage, failures and empty discovery cannot report required success.

Typst PDF/HTML validation, regenerated Markdown consistency, scoped Prettier,
workflow YAML parsing, diff whitespace checks and strict OpenSpec validation passed.
The package commands were also executed through Yarn 1.22.22 via npx because Yarn
is absent from PATH. VS Code lint retains 27 existing errors and 8 warnings:
comparison against HEAD's rules with only the plugin lookup path corrected produced
identical diagnostics. Its baseline is not silently weakened or claimed passing.
The new CI job was validated locally; remote GitHub Actions was not executed.

## 8. Feature policy ownership follow-up
- [x] Centralize shared selection press/click lifecycle and preserve both readers' event and cleanup contracts.
- [x] Centralize captured accepted-source freshness and compiler input fingerprints without changing per-action results or lock order.
- [x] Move native project creation/selection into ProjectService and unify LaunchAgent argument ownership policy.
- [x] Update source maps, scoped ownership and contract deltas; validate reader/native behavior, installed delivery and final patch independently.


2026-10-20 feature ownership follow-up: shared selection press state now has one
owner used by both reader adapters; accepted-source actions share a captured
snapshot guard, and compiler inputs own content fingerprints. Native project
creation, selection and updates delegate persistence to ProjectService;
LaunchAgent creation/ownership share one argument producer. Creation/selection
save failures intentionally retain the prior UI settings.

Validation: 154 Node, 84 paged and 36 DOM tests passed through the reader gate.
Python service suite reported 139 tests with 42 optional compiler/companion-source
skips; native suite reported 45 tests with 6 external-engine skips. Actual Neovim
RPC, archived installation/import/HTTP asset delivery, reader lint (zero warnings),
both TypeScript checks, preview build, scoped Prettier, Typst architecture PDF/HTML,
generated-doc consistency, strict OpenSpec and diff whitespace checks passed.

Independent review of selection/native changes and snapshot/fingerprint changes
found no introduced regressions. No real compiler/browser/device fixture or manual
AppKit interaction was claimed. Changes retain the current branch and unrelated
working files; no app/service installation, restart or release operation occurred.
