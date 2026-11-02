## Why
Reader behavior is spread across renderer entrypoints, flat Python modules and cross-reader imports. Compiler unit tests obscure production responsibilities, and native app configuration, service control and UI orchestration share compressed files. Make feature ownership explicit while preserving shipped behavior and protocols.

## What Changes
- Create a shared reader feature layer and renderer-specific feature adapters; organize selection actions, review marks, navigation, appearance and session integration by responsibility.
- Group HTML Reader compilation, document processing, rendering and HTTP/service implementations into an explicit Python package, retain supported CLI entrypoints, and share content validation policy.
- Split the Rust project compiler and native app by responsibility without changing crate boundaries or public protocols.
- Update AGENTS.md, scoped guidance and canonical development documentation with ownership, dependency and validation rules.
- Share browser render scheduling between the paged WASM renderer and HTML mathematical composition, retaining their distinct geometry, compilers and transports.
- Centralize design principles in the development guide, reduce agent instructions to scoped contracts, and run reader lint and architecture/behavior tests through shared local and CI commands.
- Apply those principles to shared selection press state, accepted-source freshness/input fingerprints, and native project creation/selection/LaunchAgent ownership policy, keeping native adapters and effects local.
- Validate source and installed-layout delivery, inspect the resulting patch, commit on a new branch and merge the verified result into main.

## Capabilities
### New Capabilities
- `reader-architecture`: feature ownership, dependency boundaries and delivery invariants.

### Modified Capabilities
None. Existing reading, source writes, saved Codex context and service behavior remain contractual inputs.

## Impact
Reader JavaScript/TypeScript, Python service and installation, project compiler internals, Swift app and packaging, tests and contributor guidance. Existing uncommitted terminal/Neovim work in the original checkout is preserved separately; only committed source belongs to this branch.
