## ADDED Requirements

### Requirement: Locally delivered document components

The Homepage SHALL present a responsive document library using locally delivered component assets and retain all safe reader destinations.

#### Scenario: Document selection on a narrow screen

- **WHEN** a document has a safe preferred destination
- **THEN** its full name is a wrapping primary link, with its actual status and other safe destinations accessible nearby

#### Scenario: Local delivery

- **WHEN** the Homepage is served from an installed reader
- **THEN** its component assets and their dependencies are available from explicit local routes without external requests

#### Scenario: Multiple alternatives of the same kind

- **WHEN** the safe alternatives menu contains multiple entries of the same kind, excluding the primary title
- **THEN** those entries append one-based numbers in displayed order to their existing kind labels, and accessible labels match the visible distinction
- **AND** a unique kind keeps its unnumbered label, the primary remains the document name, and all safe occurrences retain their destinations and keyed identity
- **AND** numbers describe current menu positions rather than service aliases; labels expose neither URLs nor internal profile paths

### Requirement: Composed paper and green document library

The Homepage SHALL retain document selection as its primary purpose and follow the adopted 2026-11-16 measurements in design: aligned framing, solid independently bounded document surfaces, restrained elevation and deliberate typography. It SHALL reuse existing shared light/dark roles and the system font stack, with additional Home presentation tokens owned only by `home.css`.

#### Scenario: Narrow library with a long name

- **WHEN** the library is shown at 320 CSS pixels with a long Korean/Latin or unbroken document name and alternative destinations
- **THEN** the entire name wraps inside the available column beside a separate 44px alternatives target, with actual status visible below and no horizontal page overflow or overlapping hit areas
- **AND** heading text is 28px/650, document names are 17px/650 and the search occupies a full row

#### Scenario: Wide library and document depth

- **WHEN** the library is shown at 1280 CSS pixels
- **THEN** the centered frame remains at most 880px including gutters, the heading is 32px/650 and document names are 18px/650, with search beside the heading when space permits
- **AND** each document is separated from the paper background and adjacent documents by a solid surface, full perimeter, restrained shadow and 12px gap rather than only border-top rules

#### Scenario: Focused content rather than a dashboard

- **WHEN** the Homepage is displayed in either theme
- **THEN** the brand/settings header, title/count, search and initial documents are directly discoverable without explanatory copy, slogans, Tail Dashboard, fabricated formula previews or decorative dashboard tiles
- **AND** the title remains the primary link rather than introducing a whole-card navigation action

### Requirement: Truthful accessible visual states

The Homepage SHALL preserve the current full document names, inventory count and search semantics, actual status wording, loading/empty/error/no-results distinction, and independent no-safe-address explanation. State SHALL remain understandable without color. All interactive targets SHALL be at least 44x44 CSS pixels, with visible focus, immediate semantic press feedback and sufficient text/control contrast in light and dark modes.

#### Scenario: Incomplete or failed observation

- **WHEN** inventory is loading, unavailable or cannot refresh a previously observed list
- **THEN** the existing truthful status/error is visible, retained entries remain stale as appropriate, and no artificial progress, ready label, document or count is introduced
- **AND** an error is not replaced visually by an empty search result

#### Scenario: No safe opening address

- **WHEN** a document has no safe reader destination
- **THEN** its full plain title, actual state and separate public-address-unavailable text remain visible without a misleading navigation treatment

#### Scenario: Keyboard, pointer and accessibility preferences

- **WHEN** a control is focused, pressed, released, canceled or rapidly pressed again
- **THEN** it gives visible feedback without moving its hit geometry, delaying native activation, duplicating actions or retaining stale pressed state
- **AND** reduced motion removes Home decorative movement/transitions, forced colors retains system-color edges/focus, and solid surfaces remain usable without transparency support

#### Scenario: Contrast across effective themes

- **WHEN** explicit light, explicit dark or System mode is active
- **THEN** existing shared roles govern every Home surface, text and focus state without modifying shared theme sources
- **AND** ordinary text reaches 4.5:1, large text 3:1 and essential control boundaries/focus 3:1 against their actual adjacent fills, including hover and press

### Requirement: Presentation preserves interaction owners

Visual restoration SHALL retain the existing safe-link, keyed-DOM, polling, Web Awesome focus/lifecycle, appearance, native settings and account-authority contracts. It SHALL keep Basecoat 1.1.0 and Web Awesome 3.14.0 locally vendored and introduce no new library, external CDN or font.

#### Scenario: Polling changes a destination or an open menu

- **WHEN** inventory retains, removes, promotes or demotes a focused safe destination while a menu is opening, closing or queued to reopen
- **THEN** existing keyed link identity, all safe variants, HTML-first/Paged fallback, readerLink validation, roving active/tabindex and latest user focus intent remain intact
- **AND** existing show/hide/reopen ordering and outside-input/Escape/removal cancellation remain authoritative

#### Scenario: Settings and connection navigation

- **WHEN** settings opens normally or through initial/hashchange `#connection`, then closes by Escape or its close control
- **THEN** the named native dialog remains scrollable within the viewport, connection navigation reveals/focuses its section, and normal dismissal restores the invoking settings control
- **AND** theme choice preserves existing storage/System behavior, while account IDs, instance/version guards, CSRF, notice persistence, management permissions and hidden/disabled controls remain unchanged

#### Scenario: Long settings content and zoom

- **WHEN** settings displays long synthetic account/status content at narrow width, 200% text scaling or 200% browser zoom
- **THEN** the solid dialog retains 16px viewport clearance, readable wrapped content, an accessible close target and internal vertical scrolling without horizontal page overflow

### Requirement: Restoration acceptance remains evidence based

The restoration SHALL be evaluated against the responsive coverage matrix in design: basic/long-title documents at 320x800, 390x844 and 1280x800 in light/dark, plus representative empty/loading/error/no-results/settings, zoom and accessibility states spanning affected layout branches. Source checks and historical tasks SHALL NOT be represented as rendered visual acceptance.

#### Scenario: Representative states exercise layout risks

- **WHEN** responsive verification is performed
- **THEN** basic documents and long names are checked at all three viewport sizes in both themes, and additional state combinations document the narrow/wide layout and accessibility risks they exercise
- **AND** full titles, truthful states, safe alternatives, focus and reachable 44px targets remain available without horizontal page overflow

#### Scenario: Comparable implementation evidence

- **WHEN** implementation and visual evidence are reviewed
- **THEN** records identify the source revision, dirty state, tool versions, fixture, effective viewport/theme/state and actual command/observation results using the delivered Home assets and synthetic data
- **AND** missing rendered coverage remains explicitly unverified until observed; source checks or screenshots alone do not establish actual interaction quality
