## ADDED Requirements

### Requirement: Parallel reading outputs
The system SHALL produce a reflowable HTML reading view from the same saved Typst source as the existing paged view. Existing PDF export and the running paged endpoint SHALL remain available.

#### Scenario: Mobile entry
- **WHEN** a phone opens the configured reading entry after rollout
- **THEN** it receives the responsive reader and can explicitly open the original paged view
- **AND** the user's explicit view preference is respected

#### Scenario: Guarded Dashboard document entry
- **WHEN** the Hosting card contains exactly one original/Reader pair with the same project and entrypoint and the exact derived service ID
- **THEN** its document link honors the browser-local automatic, Reader or original-page preference without opening address details
- **AND** automatic touch-device selection uses only fresh, healthy Reader delivery with explicit strict/native flags and an accepted revision
- **AND** development, missing flags, stale observations, unhealthy delivery and ambiguous pairs do not silently change the original default
- **AND** existing paged URLs and service lifecycles remain unchanged

#### Scenario: Accepted document during a failed save
- **WHEN** a strict Reader still serves its accepted revision during a new or failed compilation
- **THEN** fresh healthy delivery can retain the automatic Reader entry
- **AND** the failed compilation remains visible as a separate status

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

#### Scenario: Native cancellation and overline
- **WHEN** a source equation contains a cancellation or overline
- **THEN** its mathematical body remains semantic, selectable text
- **AND** cancellation paint retains the resolved source stroke, angle, length, inversion, and cross settings on every measured fragment
- **AND** assistive mathematics retains the cancellation notation after visual line breaking
- **AND** an overline visibly spans its complete mathematical body
- **AND** the paged output is unchanged

#### Scenario: An explanation repeats an offscreen decorated term
- **WHEN** a visible marked term also appears in an explanation outside the composition margin
- **THEN** its original decoration paints without waiting for the offscreen mathematical copy
- **AND** the copied occurrence receives its own current paint during ordinary scrolling
- **AND** equal geometry cannot cause paint for one occurrence to be mistaken for another

#### Scenario: A mathematical line break leaves an empty mark carrier
- **WHEN** a composed marked expression retains a zero-area wrapper before its real fragments
- **THEN** its nonempty fragments keep their original paint
- **AND** the empty carrier cannot retain a false loading notice
- **AND** native or pending mathematical placeholders still report pending composition

#### Scenario: A graphical relationship targets a wrapped term
- **WHEN** one logical marked term occupies several visual fragments
- **THEN** the relationship request retains every fragment rectangle and the original logical target identity
- **AND** named and angular anchors resolve to actual fragment surfaces, not an empty inter-line bounding rectangle
- **AND** the original CeTZ callback and its literal coordinate origin are preserved without editing authored figure positions

#### Scenario: A supported connection crosses readable text
- **WHEN** an open line or Bezier connection between named marked terms crosses the measured mathematical text
- **THEN** the reader may recompose its path around text without changing its target anchors, styling, or arrowhead definitions
- **AND** the route is validated for the current revision and geometry, with vertical space reserved for any outsets
- **AND** an unsupported or unsuccessful route remains an explicit layout failure

### Requirement: Responsive readable content
The reader SHALL lay out ordinary text, mathematical expressions, figures, and essential annotations at 320–768 CSS px and the user's selected font size in the continuous reading body. Reading this content MUST NOT require zooming, horizontal panning, a slide/carousel, opening a separate equation view, or clicking to reveal essential content. Shrinking a complete equation or canvas until its labels become unreadable MUST NOT count as responsive layout.

#### Scenario: Asynchronous mathematical composition
- **WHEN** a mathematical expression is recomposed for a new width or reading font
- **THEN** the reader validates its logical tokens before replacing the current expression
- **AND** results from an obsolete document, removed section, or obsolete measurement cannot publish
- **AND** publication waits for an active text selection or reader dialog to end
- **AND** a failed composition preserves the current expression, reports the failure, and retries automatically

#### Scenario: Directory metadata changes without a saved-source edit
- **WHEN** known input directory timestamps or Finder metadata change while the compiler inputs and entry names remain the same
- **THEN** the accepted snapshot remains valid for dynamic rendering
- **AND** creation of a previously missing import is still detected

#### Scenario: Local mathematical assets and semantic reading
- **WHEN** the reader composes mathematical content
- **THEN** its renderer and fonts load from the Reader origin without a third-party CDN
- **AND** copied text retains canonical source order without assistive-content duplicates
- **AND** semantic math and keyboard-accessible references remain available to assistive technology

#### Scenario: Original content inside a localized Reader shell
- **WHEN** the exported document language differs from the Reader interface language
- **THEN** the article, moved notes, copied target terms and mathematical views retain their exported source language
- **AND** interface names and status messages retain the interface language
- **AND** local language attributes survive while an unknown source language remains explicitly unknown

#### Scenario: Reader release switch after stop
- **WHEN** a managed Reader is stopped before activating another installed release
- **THEN** stop waits for the terminating launchd job to disappear
- **AND** a timed-out stop reports failure without restarting or signalling unrelated services

#### Scenario: A long equation or wide drawing
- **WHEN** an equation, matrix, or drawing exceeds the available width at readable text size
- **THEN** the layout stage uses mathematically valid line breaks, alignment changes, or an explicit faithful alternate composition
- **AND** figure panels, labels, and legends are recomposed rather than uniformly shrinking their text
- **AND** unresolved layout is a failed release requirement; clipping, scrolling, and expansion controls do not satisfy it

#### Scenario: A wide inline expression
- **WHEN** an inline expression cannot fit its reading container at the chosen font size
- **THEN** it may recompose into a block within the continuous body without a user action
- **AND** its inline mathematical style, fraction sizing, limits, and logical text remain unchanged

#### Scenario: An inline accent crosses the actual paragraph edge
- **WHEN** an inline expression fits in isolation but its glyph overhang crosses the edge of its actual line
- **THEN** the reader places it on an ordinary body line at the same font size
- **AND** publication measures after retiring any previous status notice
- **AND** fitting content does not retain an obsolete overflow warning

#### Scenario: Original CeTZ labels become responsive native content
- **WHEN** native figure composition is enabled for a saved Typst source
- **THEN** original label bodies are exported once as semantic HTML/MathML before SVG flattening
- **AND** the geometry retains the original coordinate system and aspect ratio while native text retains a reading-size floor and larger authored typography
- **AND** labels that cannot occupy their original anchors safely remain completely visible below the figure with matching readable markers and explicit associations
- **AND** low-contrast label ink is adapted for its reading background while retaining the source color in the export
- **AND** generated markers and loading messages do not enter copied logical source text
- **AND** width/font changes require no per-canvas compiler request and an obsolete offscreen placement cannot widen the reading page
- **AND** the original paged source and output are preserved
- **AND** short inline expressions keep their original presentation when their complete ink fits the actual line

#### Scenario: Reading a native diagram during recomposition
- **WHEN** the viewport or selected font changes while reading a diagram label or geometry
- **THEN** the same source passage or geometry point stays at the reading reference
- **AND** generated diagram numbering does not determine a label passage's reading key
- **AND** long mathematical labels retain the full available width and compose even when the diagram geometry is offscreen
- **AND** loading-notice changes cannot move a following reading target

#### Scenario: A wide structured mathematical body
- **WHEN** a fraction, radical, spanning decoration, scripted base, or matrix exceeds the reading width
- **THEN** the reader may compose its children at a measured inner width while retaining their mathematical grouping, script levels, labels, and canonical text
- **AND** matrix rows and columns remain intact and entry fonts retain the selected reading size
- **AND** short norms and intervals remain on one line when they fit
- **AND** a stretched operator remains completely visible, without scroll area from its masked stencil pieces

#### Scenario: Continuous reading
- **WHEN** a reader reaches a section boundary or a mathematical annotation
- **THEN** the next content is available through ordinary vertical reading without a required next-section button or reveal action
- **AND** storage or lazy loading boundaries are not presented as slides

#### Scenario: Font or orientation change
- **WHEN** a reader enlarges text or rotates the device
- **THEN** paragraphs reflow, labels remain readable, and the same logical passage stays in view

#### Scenario: Default text size and visual zoom
- **WHEN** a new reader opens or a legacy font preference is first migrated
- **THEN** the body uses 13 CSS pixels, including before JavaScript initialization
- **AND** subsequent explicit font choices persist in 1px steps from 13px through 30px
- **AND** content fits the device layout width without whole-page scaling
- **AND** automatic shrink-to-fit is disabled while user enlargement remains available
- **AND** a pinch-related visual resize does not restore an obsolete reading anchor when the layout width has not changed
- **AND** saved quotations and reading positions are preserved
- **AND** obsolete decoration and relationship SVGs cannot widen the page while mathematical layout or compilation is pending

#### Scenario: Direct target navigation during initial composition
- **WHEN** the reader opens a named target while mathematical or drawing layout is still completing
- **THEN** that target crosses the same reference line used for reading restoration
- **AND** automatic composition keeps the intended target visible
- **AND** a newly opened named link takes precedence over an older saved position at the same URL
- **AND** a reload or history restoration resumes its reading entry

#### Scenario: An offscreen drawing awaits responsive compilation
- **WHEN** a source canvas has not yet been adapted to the reading width
- **THEN** a bounded inline placeholder reserves space and the original drawing does not widen the whole page
- **AND** fitting and publication happen automatically without an expansion action
- **AND** replacing the placeholder or a previous fitted drawing preserves the reading anchor
- **AND** a failed width fit retains its complete drawing and explicit diagnostic

### Requirement: Revision-aware updates
The reader SHALL expose the compiled revision and compilation state, retain the last successful output on compilation failure, and preserve reading anchors and selections across updates.

#### Scenario: A preceding figure changes generated numbering
- **WHEN** a saved edit inserts a figure before the native figure being read
- **THEN** its label quotation and geometry reading point retain their source figure identity
- **AND** a reused canvas counter or repeated axis label cannot select another figure
- **AND** an active text selection remains intact until the reader releases it

#### Scenario: Reading a mathematical table on a narrow screen
- **WHEN** a source table exceeds the available reading width
- **THEN** its original rows and cells compose vertically at the selected font size
- **AND** all original math, source order and header associations remain available
- **AND** repeated column hints do not duplicate logical source text or equations
- **AND** no horizontal movement or reveal action is required

#### Scenario: A surface plot includes SVG axis text
- **WHEN** the supported Maquette source is exported for native figure reading
- **THEN** its original pixels and vector geometry retain their source data
- **AND** original axis text becomes native content at a readable font size with its original anchor and baseline
- **AND** the original paged output remains identical

#### Scenario: A literal-coordinate arrow conflicts with reflowed mathematics
- **WHEN** a pure vector annotation without named endpoint connections overlaps text or exceeds the reading width
- **THEN** its complete original vector paths remain visible in an automatic band below their source scene
- **AND** geometry fitting retains the original transforms, arrowheads and physical stroke thickness
- **AND** no destination term is inferred from unrelated numeric coordinates
- **AND** named endpoint connections continue to use the measured term geometry

#### Scenario: One end of an annotation is a free coordinate
- **WHEN** an open line or Bezier names a source term at only one endpoint
- **THEN** that named endpoint remains exact during responsive routing
- **AND** its explicitly free endpoint may move into clear space within the reading width
- **AND** unmarked mathematical ink remains a routing obstacle
- **AND** the original CeTZ renderer retains the path's styling and arrowheads

#### Scenario: A relationship needs an automatic replacement
- **WHEN** a measured candidate overlaps readable mathematical ink
- **THEN** its paint remains withheld while routing is pending
- **AND** a free endpoint reserves room for its complete original arrowhead
- **AND** the terminal result publishes automatically without a user action

#### Scenario: SVG geometry begins with an unpainted move
- **WHEN** a path contains an isolated initial move before its painted subpath
- **THEN** relationship and native label collision measurements ignore that unpainted point
- **AND** painted zero-length round or square caps remain obstacles

#### Scenario: A mathematical font line box extends into a clear channel
- **WHEN** a relationship lies in the empty ascent/descent space around a mathematical glyph
- **THEN** collision measurements use the glyph's actual surface and complete stretched-operator surfaces
- **AND** every visible mathematical surface retains its original marked-term identity
- **AND** assistive and staging copies cannot introduce duplicate obstacles

#### Scenario: A dark reader includes a light relationship panel
- **WHEN** original mathematical drawing paint requires light paper
- **THEN** its mathematical text, equation numbers and references use a readable local light palette
- **AND** the surrounding reader retains its selected appearance

#### Scenario: Visible relationships are requested in a different batch
- **WHEN** an already rendered relationship is requested with the same accepted revision and geometry
- **THEN** its original result is reused independently of other requested components
- **AND** only missing or changed component layouts require compilation
- **AND** a failed source save cannot mix a new uncached layout with the previous accepted revision

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

#### Scenario: Mathematical presentation order changes
- **WHEN** line breaking or script layout changes the presentation DOM order
- **THEN** saved quotations retain the source's logical character order
- **AND** highlighting a base and its subscript does not also highlight an unselected superscript
- **AND** repeated visual occurrences retain their association with the same logical token

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
- **AND** the time of observing the running Reader is distinct from the time of its last compilation
- **AND** the report preserves the actual development/native-figure settings, service kind and entrypoint for view selection
