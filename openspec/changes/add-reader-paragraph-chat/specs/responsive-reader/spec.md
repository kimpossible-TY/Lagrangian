## MODIFIED Requirements

### Requirement: Adaptive authored text annotations
The Reader SHALL shade annotated terms without cloning their equations. Short mannot names SHALL prefer nearby labels (concept 3), including on wide screens. Longer mannot explanations SHALL use popovers (concept 1) or eligible side columns (concept 12). Footnotes SHALL use eligible side columns. Eligibility SHALL retain the viewport and host-space checks. Original content, language, IDs and associations MUST survive presentation changes. While the HTML/terminal paragraph-chat layout is active, long annotations and footnotes SHALL use available local left whitespace and a narrow left margin without a divider; meaningful leaders and short nearby labels SHALL remain. Paged presentation SHALL remain unchanged.

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
- **THEN** longer mannot explanations and ordinary footnotes occupy a side column inside that host and stack without overlap, except that active HTML/terminal paragraph-chat uses local left whitespace and a narrow left margin without a divider
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
- **THEN** an accent leader with a target dot connects its marked term to the note column without covering intervening ink
- **AND** a visible local divider remains except while HTML/terminal paragraph-chat is active, when the divider is removed and long notes use local left whitespace and a narrow left margin
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
