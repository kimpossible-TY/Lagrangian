## ADDED Requirements

### Requirement: Parallel reading outputs
The system SHALL produce a reflowable HTML reading view from the same saved Typst source as the existing paged view. Existing PDF export and the running paged endpoint SHALL remain available.

#### Scenario: Mobile entry
- **WHEN** a phone opens the configured reading entry after rollout
- **THEN** it receives the responsive reader and can explicitly open the original paged view
- **AND** the user's explicit view preference is respected

### Requirement: Mathematical fidelity
The reader MUST retain mathematical symbols and decorations, equation and theorem numbers, cross references, footnotes, and annotation meaning. Unsupported constructs MUST use faithful alternative rendering or produce a visible diagnostic, never silently disappear.

#### Scenario: PDE annotations
- **WHEN** a document contains mannot or scoped mathematical annotations
- **THEN** marked terms remain associated with their annotation content after reflow

#### Scenario: Decoration after a mathematical line break
- **WHEN** a marked term occupies multiple visual fragments
- **THEN** its semantic mathematical content remains available independently of its decoration
- **AND** the original decoration is rendered against every fragment without painting the inter-line gap
- **AND** obsolete geometry cannot paint the new document or retain a misleading decoration after a font change

### Requirement: Responsive readable content
The reader SHALL lay out ordinary text, mathematical expressions, figures, and essential annotations at 320–768 CSS px and the user's selected font size in the continuous reading body. Reading this content MUST NOT require zooming, horizontal panning, a slide/carousel, opening a separate equation view, or clicking to reveal essential content. Shrinking a complete equation or canvas until its labels become unreadable MUST NOT count as responsive layout.

#### Scenario: A long equation or wide drawing
- **WHEN** an equation, matrix, or drawing exceeds the available width at readable text size
- **THEN** the layout stage uses mathematically valid line breaks, alignment changes, or an explicit faithful alternate composition
- **AND** figure panels, labels, and legends are recomposed rather than uniformly shrinking their text
- **AND** unresolved layout is a failed release requirement; clipping, scrolling, and expansion controls do not satisfy it

#### Scenario: Continuous reading
- **WHEN** a reader reaches a section boundary or a mathematical annotation
- **THEN** the next content is available through ordinary vertical reading without a required next-section button or reveal action
- **AND** storage or lazy loading boundaries are not presented as slides

#### Scenario: Font or orientation change
- **WHEN** a reader enlarges text or rotates the device
- **THEN** paragraphs reflow, labels remain readable, and the same logical passage stays in view

### Requirement: Revision-aware updates
The reader SHALL expose the compiled revision and compilation state, retain the last successful output on compilation failure, and preserve reading anchors and selections across updates.

#### Scenario: Failed source edit
- **WHEN** a saved edit fails to compile
- **THEN** the last valid document remains usable with an explicit stale/error status
- **AND** a successful subsequent compilation updates the reader without losing its logical reading position

### Requirement: Persistent local highlights
The reader SHALL save explicitly selected quotations in browser-local storage scoped to the current document, including context for relocation after edits. It SHALL preserve the original quotation when relocation is uncertain or impossible.

#### Scenario: Paragraph or section moves
- **WHEN** a saved quotation remains present after surrounding text or section boundaries change
- **THEN** the reader locates it in the accepted revision and can navigate to its current section
- **AND** rendering the highlight does not insert HTML elements into MathML

#### Scenario: Ambiguous or removed quotation
- **WHEN** no unique current location can be established
- **THEN** the saved quotation remains visible with its missing or ambiguous status
- **AND** the reader does not guess a location or silently remove the saved record

### Requirement: Independent serving boundary
Flow SHALL own reader compilation and project settings. Tail Hosting SHALL expose and monitor the reader endpoint without taking ownership of document rendering or duplicating the service lifecycle.

#### Scenario: Independent Reader lifecycle
- **WHEN** the Reader is started, stopped, restarted, or recovered after an unexpected exit
- **THEN** only its own managed process and LaunchAgent are affected
- **AND** the original paged service remains available
- **AND** a new Reader start resolves the current parent Flow project settings

#### Scenario: Compile monitoring
- **WHEN** Tail Hosting checks the Reader
- **THEN** it distinguishes HTTP reachability from the Reader's reported compile and content-validation result
- **AND** serving the last accepted revision after a failed save is reported as a compile failure
