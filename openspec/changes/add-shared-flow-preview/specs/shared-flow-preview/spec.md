## ADDED Requirements

### Requirement: Shared saved-document preview
The extension SHALL support an opt-in shared Flow preview that reuses the existing managed service without starting an LSP preview task.

#### Scenario: Open and reopen a managed document
- **WHEN** a trusted workspace enables sharedFlow and the document matches one healthy managed profile
- **THEN** VS Code shows that profile's saved-document reader and reuses its panel on repeated opens
- **AND** no LSP preview server or thumbnail connection is created

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

### Requirement: Desktop bidirectional synchronization
Embedded and VS Code-opened external shared readers SHALL reuse Tinymist's existing editorScrollTo/panelScrollTo protocol, span-range resolver, source-to-document mapping and preview jump rendering without creating another compiler or observing mobile viewers' selections.

#### Scenario: Click a mapped source location
- **WHEN** a source hit from the embedded viewer matches the compiled revision
- **THEN** the existing Tinymist resolver reveals its source component range with Unicode-correct editor columns
- **AND** resolution uses the current compiled view and the requesting viewer socket

#### Scenario: Unrelated or invalid location
- **WHEN** a message comes from another origin or viewer channel, has invalid coordinates, or points outside the canonical project root
- **THEN** the editor does not navigate
- **AND** stale or unmapped hits and mobile-only selections do not move the editor

#### Scenario: Unsaved source
- **WHEN** the target editor buffer has unsaved changes
- **THEN** the extension asks the user to save before using saved-preview coordinates

#### Scenario: External browser opened from VS Code
- **WHEN** the user clicks a source location in a reader opened through Open in Browser
- **THEN** a temporary origin-checked control connection moves the cursor in the originating VS Code window
- **AND** ordinary phone URLs do not carry that connection and retain their current behavior
- **AND** extension reload disposes the connection and the reader asks to reopen from VS Code

#### Scenario: Click a saved source component in the editor
- **WHEN** a single editor selection changes by mouse in the matched saved source and scrollSync permits it
- **THEN** panelScrollTo resolves the source location against the reader's rendered revision and uses the existing jump renderer to reveal it
- **AND** keyboard changes follow the existing scrollSync setting and programmatic editor reveals do not create a feedback loop
- **AND** the manual preview sync command also works with shared readers

#### Scenario: Viewer and theme isolation
- **WHEN** a desktop reader navigates in either theme while another desktop or phone reader is connected
- **THEN** only readers explicitly connected to that originating editor receive its source navigation
- **AND** mobile viewers keep their current scroll position and Codex behavior
- **AND** navigation sends only small control messages and does not trigger compilation, memory-file synchronization or full document rendering
