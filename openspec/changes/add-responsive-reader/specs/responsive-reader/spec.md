## ADDED Requirements

### Requirement: Visible saved-document activity
The HTML Reader SHALL reuse the paged reader's shared activity priority, localized notice controller and styles. Concrete adapters SHALL own transport and rendering signals. The notice SHALL show compilation, loading and publication, hide only after current accepted content is displayed, and preserve local mathematical and figure feedback.

#### Scenario: Mobile reading during an update
- **WHEN** the reader scrolls, changes theme or changes the visual viewport during an update
- **THEN** the notice remains readable within the visible safe area
- **AND** it respects reduced motion and allows document gestures except on its explicit selection-release button

#### Scenario: Saved edit and successful publication
- **WHEN** a saved edit is compiling or its accepted content is being fetched and mounted
- **THEN** the notice identifies the known activity with a loading ring
- **AND** it hides after that content is displayed, without adding healthy-document spacing

#### Scenario: Reading interaction holds an update
- **WHEN** accepted content is waiting for a native selection, annotation, dialog or reading gesture to end
- **THEN** a static notice explains why the update is paused without a loading ring
- **AND** an article text selection offers an explicit keyboard-accessible clear-selection action that preserves selection until activation
- **AND** publication resumes through the normal refresh path after the interaction ends

#### Scenario: Failed or stale work
- **WHEN** connection, compilation or section loading fails
- **THEN** its notice remains visible while the last accepted document stays readable
- **AND** cached content and obsolete request completions cannot clear a newer failure or pending update
- **AND** successful retry resumes normal activity and disposes no replacement session's state

### Requirement: Return to the origin of an internal document link
The HTML Reader SHALL offer “원래 위치로” after successfully following a valid internal body or outline link. It SHALL capture the semantic reading position and URL immediately before following the link, retain only the latest origin, and consume it after returning. The action SHALL remain independent of visual-change navigation.

#### Scenario: Follow and return across sections and reflow
- **WHEN** the reader follows an internal reference to another mounted or unmounted section
- **THEN** the action restores the originating passage and viewport offset using current semantic geometry, including after font or viewport changes
- **AND** the original URL is restored, the article receives focus without scrolling, and the button disappears
- **AND** a mounted origin retains its existing section and composed mathematics instead of triggering a new section publication

#### Scenario: Latest successful reference and independent actions
- **WHEN** another internal reference succeeds before returning
- **THEN** it replaces the single return origin without retaining a stack
- **WHEN** an external link, footnote popover, browser history, editor or automatic change navigation occurs
- **THEN** it does not create or replace the return origin
- **AND** both return and deferred-change actions can appear without overlap on a narrow viewport

#### Scenario: Failed, obsolete and disposed navigation
- **WHEN** destination loading fails or a navigation is superseded
- **THEN** it cannot replace or consume the current return origin
- **AND** a failed return remains available for retry, while a completed return to a removed passage consumes the action without guessing another passage
- **WHEN** the reader is disposed
- **THEN** its origin and button listener are discarded

### Requirement: Shared reference-return policy
Both readers SHALL use one renderer-independent owner for the single origin, replacement/consumption, button visibility and click/disposal lifecycle. Their adapters SHALL retain native capture/restore, asynchronous validity checks, section loading, scroll anchoring and URL/history effects.

#### Scenario: Shared policy with native positions
- **WHEN** the paged or HTML reader captures a reference origin
- **THEN** the same shared controller manages its temporary lifetime without converting page coordinates to semantic anchors or vice versa
- **AND** obsolete return completion cannot consume a newer origin, and disposal prevents later callbacks from reviving the action

### Requirement: Last visual edit navigation
The HTML Reader SHALL use the paged preview's persistent visual-change and render-before-jump behavior with reflowable body targets. The server SHALL retain the last accepted visual edit per document independently of connected viewers. A new entry or reload SHALL restore that edit; a live viewer SHALL follow each newly accepted edit once. A direct named link and browser history navigation SHALL retain their destination.

#### Scenario: Distant saved edit and reload
- **WHEN** a saved edit changes a distant body passage, mathematical expression or native figure
- **THEN** the Reader navigates directly to its matching accepted target after mounting the destination section
- **AND** a refreshed or newly opened Reader restores that edit even when another reading position was saved
- **AND** an edit accepted with no connected viewer is available on the next entry

#### Scenario: Reading gesture or selected passage
- **WHEN** an edit arrives during a recent direct reading gesture
- **THEN** the visible reading position is retained and a change-location button offers the latest edit
- **AND** a gesture during destination loading also defers navigation
- **WHEN** a selection or Reader dialog is active
- **THEN** publication waits until it ends

#### Scenario: Stable history and explicit navigation
- **WHEN** the Reader reconnects, changes appearance or recomposes at a different font size
- **THEN** an already observed edit does not replay or create a stale change button
- **WHEN** a named link opens or browser history restores an entry
- **THEN** that explicit destination takes priority over last-edit restoration

#### Scenario: Restart, failed save and nonvisual inputs
- **WHEN** the service restarts with matching inputs or an unchanged visible output
- **THEN** its valid last-edit target is retained and relocated in the current document
- **AND** metadata-only changes or runtime-only rendering changes do not replace it
- **WHEN** a compilation fails or a saved record is corrupt or belongs to another document
- **THEN** no false visual edit is published from that result
- **AND** a deleted target uses a surviving adjacent body location when available

### Requirement: Parallel reading outputs
The system SHALL produce a reflowable HTML reading view from the same saved Typst source as the existing paged view. Existing PDF export and the running paged endpoint SHALL remain available.

#### Scenario: Mobile entry
- **WHEN** a phone opens the configured reading entry after rollout
- **THEN** it receives the responsive reader and the original paged view remains available through the Dashboard and existing URLs
- **AND** the user's explicit view preference is respected
- **AND** the Reader toolbar does not expose a page-view link

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

#### Scenario: Authored paragraph tabs
- **WHEN** a source uses `paragraph_tab` or `paragraph-tab` in a paragraph, beside math or inside a highlight
- **THEN** HTML retains the authored 1.5em gap at the current reading font without indenting wrapped continuation lines
- **AND** the spacer adds no private marker or synthetic characters to copied quotations
- **AND** the existing paged output and ordinary paragraphs remain unchanged

### Requirement: Hierarchical heading outline
The Reader SHALL include exported h1 through h6 headings and deeper ARIA headings in its outline and indent each additional heading level consistently relative to the shallowest exported level.

#### Scenario: Nested headings in a narrow outline
- **WHEN** a document contains sections and deeper headings, including skipped levels
- **THEN** every heading appears in source order with a distinct inset for its depth
- **AND** long titles wrap within the outline panel
- **AND** each entry navigates to its heading even across transport-section boundaries

### Requirement: Mathematical fidelity
The reader MUST retain mathematical symbols and decorations, equation and theorem numbers, cross references, footnotes, and annotation meaning. Unsupported constructs MUST use faithful alternative rendering or produce a visible diagnostic, never silently disappear.

#### Scenario: Authored flowbox derivations
- **WHEN** an existing `flowbox` contains equations, downward arrows and explanatory prose
- **THEN** the Reader presents one continuous theme-aware frame with centered prose/arrows and compact internal spacing
- **AND** no additional separator rules appear before or after the frame or around internal mathematical row groups
- **AND** equations reflow within the padded inner width at the selected reading font with their numbers vertically centered in a separate inline-end column
- **AND** cancellation strokes, references, canonical selectable text, Saved for Codex mapping and original paged output remain intact

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
The reader SHALL lay out ordinary text, mathematical expressions, figures, and graphical relationships at 320–768 CSS px and the user's selected font size in the continuous reading body. Reading this body content MUST NOT require zooming, horizontal panning, a slide/carousel or opening a separate equation view. Authored text annotations SHALL use the adaptive presentation below. Shrinking a complete equation or canvas until its labels become unreadable MUST NOT count as responsive layout.

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
- **WHEN** a reader reaches a section boundary or a graphical relationship
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
- **AND** active selections and reading positions are preserved
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

#### Scenario: Numbered display equations reflow
- **WHEN** a numbered display equation is composed at a different viewport width or reading font size
- **THEN** its number stays at the inline end, vertically centered beside the complete expression
- **AND** the expression fits the remaining width without overlapping its number
- **AND** unnumbered equations retain the full available width

### Requirement: Adaptive authored text annotations
The Reader SHALL shade annotated terms without cloning their equations. Short mannot names SHALL prefer nearby labels (concept 3), including on wide screens. Longer mannot explanations SHALL use popovers (concept 1) or eligible side columns (concept 12). Footnotes SHALL use eligible side columns. Eligibility SHALL retain the viewport and host-space checks. Original content, language, IDs and associations MUST survive presentation changes.

#### Scenario: Short and long annotations on a phone
- **WHEN** a reader views an annotated equation in a compact viewport
- **THEN** a plain name of at most 24 graphemes and three words appears above its target without covering mathematical ink
- **AND** both plain and mathematical names search nearby free space and the space above preceding equation lines before using a popover
- **AND** competing names gain bounded extra label rows while preserving the reading anchor
- **AND** a longer or rich annotation, or a label physically wider than the readable host, is reachable by tapping the shaded target or activating it with Enter or Space
- **AND** a selection gesture does not open an explanation
- **AND** the popover is bounded by the visible viewport and dismisses through its close button, Escape or outside activation, with predictable keyboard focus return

#### Scenario: Compact indexed mathematical names
- **WHEN** a short annotation consists of a mathematical name with subscripts or superscripts, such as an indexed delta
- **THEN** it appears as a label when it fits without obscuring mathematical ink
- **AND** its complete mathematical notation and canonical text remain intact
- **AND** its mathematical line budget comes from the host's available text width, so changing the reading font cannot collapse the intrinsic label or leave it uncomposed
- **AND** movement during asynchronous typesetting uses the current cell origin for overflow checks instead of incorrectly promoting a fitting name to a block

#### Scenario: A focused close control near the popover corner
- **WHEN** a popover is open on a phone at a small or enlarged reading font
- **THEN** its complete 44px close target and visible focus indicator remain inside the rounded card

#### Scenario: A short label has room elsewhere in the equation
- **WHEN** the position directly above a short name's target collides with an earlier mathematical line
- **THEN** a name such as kernel or indexed delta uses a nearby free gap or a reserved row above the equation
- **AND** all competing short names remain visible without overlapping each other or mathematical ink
- **AND** inline names also avoid the surrounding prose line fragments
- **AND** viewport/font changes and scrolling recompute stable, bounded placement
- **AND** a note whose mathematical typesetting is pending can reserve a bounded native label row once its host is ready, so it remains measurable

#### Scenario: A short label is physically too wide
- **WHEN** a short name exceeds the readable host width and the reader opens its fallback popover
- **THEN** subsequent layout measurements keep that popover open and retain focus
- **AND** repeated touch activation and explicit dismissal remain usable

#### Scenario: Viewport and text-size changes
- **WHEN** a viewport is at least 960px wide with aspect ratio at least 1.15 and an annotated host can fit a readable body and side note separated by 20px
- **THEN** longer mannot explanations and ordinary footnotes occupy a side column inside that host and stack without overlap
- **AND** fitting short names remain labels above their targets, without reserving a side gutter of their own
- **AND** a portrait viewport, narrower width or larger reading font restores labels and popovers automatically
- **AND** the source equation and its copied/selected text remain unchanged by the presentation switch

#### Scenario: Tablet passages without annotations
- **WHEN** a tablet reader uses a viewport of at least 768px
- **THEN** the reading canvas expands up to 1200px instead of retaining a document-wide 76ch limit
- **AND** side-note width and height are reserved only in the annotated equation or paragraph
- **AND** a short indexed delta remains a nearby label without reserving a side gutter
- **AND** ordinary passages before and after that row use the full reading width
- **AND** rotation, text-size changes and section replacement remove obsolete local reservations

#### Scenario: Side-column width changes update drawings
- **WHEN** a side-column reservation changes the available width of mathematics or drawings
- **THEN** resize observer callbacks defer paint invalidation and geometry preparation to the next frame
- **AND** the layout settles without observer feedback warnings or growing row reservations

#### Scenario: Mixed labels and side notes in the same host
- **WHEN** short mannot names share an equation or paragraph with longer explanations or footnotes on a wide screen
- **THEN** the short names keep concept 3 and the eligible longer notes and footnotes use concept 12
- **AND** label rows remain available above the text/math cell and do not extend into the note column
- **AND** connecting leaders avoid both mathematical ink and visible short labels

#### Scenario: Native labeled braces and brackets
- **WHEN** a source uses an underbrace, overbrace, underbracket or overbracket with an annotation
- **THEN** HTML exposes its body as the shaded target and its annotation through the same adaptive presentation
- **AND** an unlabeled grouping decoration and the paged output remain intact

#### Scenario: Grouping decorations associated with mannot text notes
- **WHEN** a mannot text annotation targets a bottom-bracket mark or a mark whose complete body is wrapped in an unlabeled underbrace, overbrace, underbracket or overbracket
- **THEN** HTML retains the complete mathematical body and adaptive text-note association without the associated brace/bracket paint, reserved decoration space or decoration anchor outset
- **AND** this holds for notes before or after their marks and notes associated with multiple targets
- **AND** independent grouping, graphical-only targets, nested grouping within a larger expression and other mathematical decorations retain their authored behavior
- **AND** viewport/font changes retain the association without reintroducing the omitted decoration
- **AND** paged output retains its original rendering

#### Scenario: Connected local side columns
- **WHEN** an authored annotation uses the wide-screen side presentation
- **THEN** a visible local divider and accent leader with a target dot connect its marked term to the note column without covering intervening ink
- **AND** both mannot and footnote side-column text, including mathematics, use 80% of the body reading font size
- **AND** the actual equation number and retained authored formatting provide a clear hierarchy without invented explanation text
- **AND** leaders and generated reference UI do not enter canonical copy text or persist in compact mode

#### Scenario: Footnotes beside their references
- **WHEN** a footnote reference is in a host eligible for side presentation
- **THEN** its complete body appears in the same connected local column, including when its endnote section is not mounted
- **AND** its number reveals the side note while original numbering, document links, language and canonical body content remain intact
- **AND** narrow, portrait or large-text layouts use concept 1 popovers at their references instead of navigating to the endnote list
- **AND** stale or failed loads cannot publish a wrong-revision body or break the original link
- **AND** repeated references, section parking and resize do not duplicate IDs or grow row reservations indefinitely

#### Scenario: Footnotes without side-column space
- **WHEN** the aspect ratio, host width or reading font prevents concept 12
- **THEN** activating the numbered reference opens a concept 1 dialog at that reference without changing the URL, history or reading position
- **AND** native mathematical references and prose references support touch, Enter and Space; Escape and close return focus to the current trigger, while outside activation dismisses the dialog
- **AND** distant bodies load on activation with visible loading and retryable failure states, without mounting or navigating to the endnote section
- **AND** loaded notation, authored formatting, language and document links remain intact, and obsolete asynchronous results cannot populate replacement notes
- **AND** returning to eligible side space closes the dialog and restores connected concept 12 presentation

#### Scenario: Updates while reading a popover
- **WHEN** an annotation is open during a source update or nearby section parking
- **THEN** the active note and target remain available until it closes
- **AND** obsolete or disconnected targets cannot retain an open popover

### Requirement: Revision-aware updates
The reader SHALL expose the compiled revision and compilation state, retain the last successful output on compilation failure, and preserve active selections across updates. Reading anchors SHALL be preserved during composition and while visual-edit navigation is deferred; an accepted change target SHALL otherwise take priority.

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

#### Scenario: Relationship paint follows the surrounding appearance
- **WHEN** a mathematical relationship is displayed in light or dark reading mode
- **THEN** its frame and SVG background remain transparent
- **AND** mathematical text, equation numbers, references and vector ink retain readable contrast against the actual surrounding surface

#### Scenario: Visible relationships are requested in a different batch
- **WHEN** an already rendered relationship is requested with the same accepted revision and geometry
- **THEN** its original result is reused independently of other requested components
- **AND** only missing or changed component layouts require compilation
- **AND** a failed source save cannot mix a new uncached layout with the previous accepted revision

#### Scenario: Failed source edit
- **WHEN** a saved edit fails to compile
- **THEN** the last valid document remains usable with an explicit stale/error status
- **AND** a successful subsequent compilation updates the reader without losing its logical reading position

### Requirement: Minimal reading navigation and touch reflow
The Reader SHALL show only outline and reading-settings action icons in its
toolbar. Font controls and appearance SHALL remain available
in reading settings through semantic keyboard-accessible controls.

#### Scenario: Pinch changes text size
- **WHEN** two fingers pinch on article content without an active selection or dialog
- **THEN** the actual body font changes between 13px and 30px during movement without browser magnification, using at most one update per animation frame
- **AND** preview uses the original reading anchor without writing font preferences
- **AND** lifting one finger applies the latest candidate even before its queued frame and persists the final font once
- **AND** cancellation, a third finger, a selection, a width change or lost visibility restores the starting font without persisting preview values or applying stale frames
- **AND** remaining touches cannot restart the gesture
- **AND** costly math composition and dynamic drawing requests wait until completion or rollback, then resume for the final geometry
- **AND** ordinary one-finger vertical scrolling and reference taps remain available

#### Scenario: Swipe the outline
- **WHEN** a horizontal rightward swipe starts in the article outside the outer 24px browser edges
- **THEN** the outline drawer follows it and settles based on distance and recent velocity
- **AND** vertical intent, browser-edge gestures, active selections and interactive starts do not open it
- **AND** reverse swipes close it, cancellation restores its prior state, and stale velocity after a pause cannot cause a fling
- **AND** native dialog focus, Escape, outside dismissal and button alternatives remain available
- **AND** rapid reversals and reduced-motion changes cannot leave stale motion or block input

#### Scenario: Floating outline capsule
- **WHEN** the outline opens on a phone or larger viewport
- **THEN** it appears as a rounded floating surface with visible space around its edges and a bounded scrolling list
- **AND** all heading levels remain navigable with readable wrapping and 44px targets
- **AND** the current reading heading is marked and revealed within the outline without moving the article
- **AND** solid material fallbacks retain contrast, and dismissal clears the capsule and its shadow from the viewport

#### Scenario: Reopen the outline from a long section
- **GIVEN** the reader is in body content whose preceding heading is in an earlier unmounted transport section
- **WHEN** the reader opens or reopens the outline using the button or swipe
- **THEN** that preceding heading is marked as the current location, centered within the outline's scrollport where its edges permit, and receives keyboard focus
- **AND** a following heading below the reading threshold does not become current early
- **AND** previous manual outline scrolling is replaced by the current location without moving the article, including with reduced motion

### Requirement: Explicit reading appearance
The Reader SHALL expose Automatic, Light and Dark appearances and persist the
choice in browser-local storage. Automatic SHALL follow device appearance changes.
Explicit choices SHALL override the device before the first styled paint and
remain usable if storage is unavailable. Theme changes SHALL preserve document
content, quotations, mathematical structure and reading position.

#### Scenario: Choose an appearance and reload
- **WHEN** a reader selects Light or Dark and reloads or opens another document on the same origin
- **THEN** the saved appearance is applied before the document is styled
- **AND** choosing Automatic follows the current device appearance and subsequent changes

#### Scenario: Read highlighted mathematics in either appearance
- **WHEN** authored highlights appear in light or dark reading mode
- **THEN** each uses the matching muted highlight palette with readable foreground ink
- **AND** original drawing frames and native canvas labels use the surrounding theme's ink, paper, selection and highlight colors
- **AND** the toolbar controls fit a 320px viewport with their labels on one line

#### Scenario: Export the existing highlighted helper
- **WHEN** an authored `highlighted` call contains plain text, a string, nested formatting, links or mathematical expressions
- **THEN** HTML retains semantic highlights around that original content, respects paragraph/display boundaries and keeps its mathematics native and selectable
- **AND** tall and reflowed mathematical expressions retain the highlight across font, width and appearance changes
- **AND** the existing paged output and authored calls remain unchanged

#### Scenario: Choose appearance from the preview panel
- **WHEN** a reader opens the toolbar's appearance button
- **THEN** an icon-only trigger opens an anchored panel showing Automatic, Light and Dark previews and the current choice
- **AND** choice names and the live appearance description remain accessible to assistive technology without visible mode text in the enhanced controls
- **AND** native radio keyboard input changes the appearance immediately without closing the panel
- **AND** Escape or outside interaction dismisses it, with keyboard dismissal returning focus to the trigger
- **AND** rapid reopen/selection remains usable, reduced motion removes spatial transitions, and solid high-contrast treatments remain readable
- **AND** the panel fits the viewport and browsers without popover support retain the native select

#### Scenario: Transparent drawings update or change appearance
- **WHEN** CeTZ or mannot paint is mounted, cloned, or changes between reading appearances
- **THEN** SVGs remain transparent and label backplates match their enclosing paper or callout surface
- **AND** opaque colored text has at least 4.5:1 contrast, opaque solid vector ink at least 3:1, and filled underlays preserve at least 4.5:1 contrast with their marked term
- **AND** original source colors, vector geometry, SVG resource references, masks, clipping and raster pixel payloads remain intact
- **AND** repeated theme changes restore the same presentation colors without replacing semantic mathematics

### Requirement: Explicit Save for Codex context
The HTML Reader SHALL replace the former local quotation library with Save for Codex. An explicit action SHALL atomically save the service's latest bounded selection on the preview host, with document identity, rendered and accepted revisions, viewer and process identity, logical HTML endpoints, exact text and verified source context where available. Saving SHALL neither compile nor edit source nor send a Codex message.

#### Scenario: Save a supported passage
- **WHEN** a reader chooses Save for Codex for at most 8000 characters in the accepted snapshot
- **THEN** the service records that exact text and its uniquely verified source excerpt in a private project-specific focusFile
- **AND** the Reader confirms success only after the service acknowledges the write
- **AND** the latest explicit selection replaces the previous record rather than adding a quotation library entry

#### Scenario: Wrapped prose and mathematics have compiler-verified source ranges
- **WHEN** accepted HTML carries verified source ranges for a selection inside a content wrapper or containing complete mathematics
- **THEN** Saved for Codex and Sync Editor resolve the same original file and range without compiling during the action
- **AND** editor cursor navigation uses those accepted ranges in the reverse direction
- **AND** source columns preserve UTF-8 byte boundaries while saved excerpts use their existing Unicode column convention

#### Scenario: Preserve rendered output when building source correspondence
- **WHEN** compile-only carriers cannot match an accepted block's identity and full canonical text, fail compilation, or have unhandled diagnostics
- **THEN** their unsupported mappings are discarded and the original accepted HTML remains available
- **AND** no carrier is written into workspace source or served document content
- **AND** repeated block signatures require agreement of the full ordered block sequence before occurrence numbers authorize a mapping

#### Scenario: Unsupported or generated content has no unique source
- **WHEN** the selected accepted text has no supported unique source mapping
- **THEN** its text and logical block endpoints are still saved with an explicit unmapped status and no invented source position or PDF page coordinates

#### Scenario: Ambiguous reverse mapping and source boundaries
- **WHEN** one saved source range maps to multiple accepted HTML blocks
- **THEN** cursor navigation reports ambiguity rather than selecting a rendered occurrence
- **WHEN** selected ranges cross files, include unsupported output or no longer match saved source hashes
- **THEN** they do not produce a usable source range

#### Scenario: Stale document or service
- **WHEN** the rendered revision, source inputs or service identity changed before saving
- **THEN** the record is marked stale without retaining a usable selection and the Reader requests a fresh selection
- **WHEN** a local selection reader reads a record
- **THEN** it freshly checks the live service, current accepted revision and source hash/excerpt
- **AND** a restarted or unavailable service cannot make an old record current

#### Scenario: Saved context has no time limit
- **WHEN** a saved selection is read more than five minutes or days after saving
- **THEN** elapsed time alone does not invalidate it
- **AND** age remains informational while service, revision and source validation still apply

#### Scenario: Resolve saved text across readers of one document
- **WHEN** the requested project and entry document have both paged and HTML readers
- **THEN** the local reader selects the latest explicit saved text from their validated records without asking the user to choose an internal service
- **AND** a newer tap-only location does not hide saved text
- **AND** the response identifies the originating reader and preserves source or revision failure flags without substituting older saved text

#### Scenario: Keep documents and exact reader targets separate
- **WHEN** resolution contains different projects or entry documents, or equally recent saved records
- **THEN** the local reader reports ambiguity instead of choosing by global recency
- **WHEN** the user provides an exact reader ID or URL
- **THEN** only that reader is read, even if another has newer saved text
- **WHEN** all readers of the resolved document have no saved context
- **THEN** the response requests a save rather than an internal reader choice
- **AND** unavailable readers are reported without concealing available saved context

#### Scenario: Preserve selections while awaiting acknowledgment
- **WHEN** a save fails
- **THEN** its submitted selection remains available for retry unless it was dismissed or replaced
- **AND** an older response cannot clear a newer selection

#### Scenario: Retire the former browser quotation library
- **WHEN** a browser with legacy saved quotations opens the updated Reader
- **THEN** no quotation library, stored-quotation paint or relocation UI is exposed
- **AND** existing localStorage quotations remain untouched and are never automatically sent to Codex
- **AND** source Highlight and browser-local Red strike remain separate explicit actions

### Requirement: Source highlights and temporary review strikes
The Reader SHALL provide Highlight and Red strike alongside Save for Codex, with keyboard-accessible controls that preserve native text
selection and fit the visible safe area.

#### Scenario: Floating selection actions
- **WHEN** a passage is selected on a narrow reading screen
- **THEN** Highlight, Save for Codex and Red strike appear with visible icons and labels in a floating capsule with at least 44px action targets and a named close control
- **AND** undo and clear occupy a separate review capsule while red strikes exist, including after selection ends
- **AND** controls remain inside the visual viewport with safe-area spacing after wrapping or resizing
- **AND** dark appearance, reduced motion/transparency, increased contrast and forced colors retain readable controls and keyboard focus

#### Scenario: Save a source highlight
- **WHEN** a current selection resolves to one compiler-verified source slice in a writable accepted workspace dependency
- **THEN** Highlight saves the real Typst `highlighted` helper, or standard `highlight` for ordinary text, and the watcher publishes it
- **AND** the complete body text and exact selected occurrence are verified in an isolated compilation before any source write
- **AND** the final source compiles for HTML and with the original PDF packages before it is saved
- **AND** complete mathematics uses the math-aware helper; partial formulas, reused macro output, code/string lookalikes, ambiguous and stale selections do not change source
- **AND** a concurrent source save is never overwritten and file permissions are preserved

#### Scenario: Pending source action and native selection collapse
- **WHEN** a source highlight is pending or its toolbar tap collapses native selection
- **THEN** duplicate submissions are disabled and the submitted quotation remains available if rejected
- **AND** success or staleness releases only that submitted selection so document updates can resume
- **AND** a newer selection survives an older response

#### Scenario: Temporary red strikes
- **WHEN** the reader applies Red strike to selected prose or mathematical fragments
- **THEN** noninteractive red lines paint those fragments without changing source or compiling
- **AND** document-scoped browser persistence survives reload, reflow and transport-section remounting
- **AND** changed block text is never given an old mark, unavailable storage retains in-memory review, and undo/clear remove marks without compiling

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


#### Scenario: Playful outside dismissal
- **WHEN** the resting outline capsule is dismissed by tapping outside
- **THEN** it briefly anticipates before sliding left, while focus and dismissal commit immediately
- **AND** the exit remains visible without closed-dialog display/overlay transition support
- **AND** reopening continues from its current motion and reduced motion omits the flourish while retaining swipe-to-open
### Requirement: Incremental dynamic paint

The Reader SHALL reuse a bounded incremental compiler for uncached dynamic
decoration, canvas and relationship geometry while preserving authored paint,
strict content validation, and accepted-source revision checks.

#### Scenario: Consecutive geometry requests
- **WHEN** reading width, font size, theme or fragment geometry changes
- **THEN** the service reuses the compiler's evaluated source cache
- **AND** only complete output carrying the current request identity is accepted
- **AND** the returned paint matches isolated compilation of the same request

#### Scenario: Worker failure or changed sources
- **WHEN** the incremental compiler exits or cannot validate its output
- **THEN** the service closes it and attempts isolated compilation
- **AND** changed sources and obsolete revisions remain ineligible for uncached paint
- **AND** service shutdown terminates the worker and removes temporary files

### Requirement: Local supported mathematical decoration paint
The HTML Reader SHALL render explicitly supported decoration primitives locally from a versioned compiler-carried description and current fragment geometry. It SHALL preserve authored paint, length units and annotation anchors, semantic copy and assistive mathematics. Unsupported descriptions and callbacks SHALL retain the validated server path.

#### Scenario: Font or viewport change
- **WHEN** a supported highlight, rectangle, underline or cancellation changes size or splits across lines
- **THEN** each visible fragment receives matching local SVG without a decoration API request or dynamic compilation
- **AND** paint does not cross line gaps or retain obsolete geometry

#### Scenario: Mixed capabilities and held interactions
- **WHEN** supported and unsupported decorations coexist or the description is invalid
- **THEN** only unsupported decorations request server paint and failures retain existing retry feedback
- **AND** selection or a live pinch holds paint publication and server requests until release
- **AND** an older asynchronous response cannot paint a newer revision or measured layout


### Requirement: Readable native canvas labels
The HTML Reader SHALL allocate native figure labels using measured free space, preferring the selected reading size and allowing bounded reduction for compact labels while preserving geometry and complete semantic fallback.

#### Scenario: A native canvas label needs nearby readable space
- **WHEN** a native label cannot occupy its original box at the selected reading font
- **THEN** the Reader evaluates its measured dimensions and nearby free space, including multi-line names, edge positions and explicit SVG alignment/baselines
- **AND** figure labels use compact line spacing and try their full measured size first; compact labels may retry at 95%, 90%, 85% and the readable minimum of max(80% of the selected font, 11 CSS px), keeping the largest fitting size
- **AND** nearby travel is bounded to two to four reading em according to label extent and at most one quarter of stage width
- **AND** safe exact placements within the current priority group, stage bounds, painted stroke thickness and already placed text/leader relationships remain reserved; displaced text does not cover another source anchor
- **AND** a displaced label retains its source anchor and an explicit leader when separated from it
- **AND** nested, oversized or obstructed labels retain complete numbered fallback
- **AND** font/width changes remeasure the same semantic labels without compiler requests, author-coordinate edits or paged-output changes

#### Scenario: Many diagram labels compete for free space
- **WHEN** multiple measured native labels need nearby placements
- **THEN** the Reader reserves compact coordinate labels before larger descriptions and prefers fewer available candidates within each group, including candidates along actual obstacle and stage boundaries
- **AND** a local spatial index bounds repeated stroke-collision work
- **AND** the rendered result preserves logical text, label-to-number associations and the page width

#### Scenario: Reduced labels are recomposed
- **WHEN** a compact native label uses a reduced presentation size and the Reader measures it again
- **THEN** the owner recovers its natural dimensions, preventing compounded reduction or repeated layout drift
- **AND** width/font changes reset the reduction before measuring, while nested labels and numbered fallback retain full reading size
- **AND** the same rules apply to every label without source-text or label-number exceptions
