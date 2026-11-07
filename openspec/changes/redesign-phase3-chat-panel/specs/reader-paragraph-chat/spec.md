## ADDED Requirements

### Requirement: Chat panel presentation

The HTML paragraph-chat panel SHALL use shared design roles and system fonts, with solid readable message surfaces and frosted material limited to panel chrome over a solid baseline, while preserving existing placement and interaction contracts.

#### Scenario: Accessible material and controls

- **WHEN** chat is displayed in light or dark appearance, or transparency is reduced or unsupported
- **THEN** text remains legible, focus and hover feedback remain visible, and mobile controls have at least 44 CSS pixel touch targets

#### Scenario: Reduced motion

- **WHEN** reduced motion is requested
- **THEN** interaction feedback remains usable without motion

### Requirement: Plain folded summaries

Folded summaries SHALL strip paired unescaped Markdown bold markers outside inline code and math regions, then strip math delimiters before truncation. Bold delimiters must have non-whitespace content at both edges, and double underscores must have word boundaries. Summaries SHALL preserve inline code, unmatched and escaped bold markers and currency ranges, and render as text rather than HTML.

#### Scenario: Bold mathematical answer

- **WHEN** a question or answer contains paired bold markers around inline mathematics
- **THEN** the folded summary shows the plain content without those markers or math delimiters
