## ADDED Requirements

### Requirement: Shared saved-document preview
The extension SHALL support an opt-in shared Flow preview that reuses the existing managed service without starting an LSP preview task.

#### Scenario: Open and reopen a managed document
- **WHEN** a trusted workspace enables sharedFlow and the document matches one healthy managed profile
- **THEN** VS Code shows that profile's saved-document reader and reuses its panel on repeated opens
- **AND** no LSP preview server, thumbnail connection or editor scroll-sync subscription is created

#### Scenario: Multiple viewers
- **WHEN** a phone and VS Code view the same profile and theme
- **THEN** they consume the same Flow preview compiler output

### Requirement: Explicit profile and lifecycle boundaries
The extension MUST select the most specific containing canonical profile root, validate the entrypoint and URL, and fail clearly on ambiguity, untrusted workspaces, missing services or unsupported preview modes.

#### Scenario: Invalid or ambiguous profile
- **WHEN** no unique valid profile matches the document
- **THEN** the extension reports an error without starting an independent preview

#### Scenario: Reader disposal
- **WHEN** the user closes the shared preview
- **THEN** only its viewer is disposed and the Flow service remains running

#### Scenario: Unsaved edit
- **WHEN** the editor buffer differs from saved files
- **THEN** the shared reader remains labeled as a saved-document view and does not present unsaved content as compiled
