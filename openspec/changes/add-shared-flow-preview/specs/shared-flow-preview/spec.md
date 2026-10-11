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

#### Scenario: Remote reader and external browser
- **WHEN** the extension runs in a remote extension host
- **THEN** the reader uses VS Code port forwarding even if the profile provides a private HTTPS address
- **AND** a visible Open in Browser button opens that same resolved reader URL without starting another compiler

### Requirement: Desktop click-to-source navigation
The embedded shared reader SHALL reveal the clicked saved source position in VS Code without creating another compiler or observing mobile viewers' selections.

#### Scenario: Click a mapped source location
- **WHEN** a source hit from the embedded viewer matches the compiled revision
- **THEN** its source file, line and Unicode-correct cursor column are revealed in the editor
- **AND** the existing Flow hit-test response is reused without another connection or polling

#### Scenario: Unrelated or invalid location
- **WHEN** a message comes from another frame, origin or viewer channel, has invalid coordinates, or points outside the canonical project root
- **THEN** the editor does not navigate
- **AND** stale or unmapped hits and mobile-only selections do not move the editor

#### Scenario: Unsaved source
- **WHEN** the target editor buffer has unsaved changes
- **THEN** the extension asks the user to save before using saved-preview coordinates
