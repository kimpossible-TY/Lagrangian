## ADDED Requirements

### Requirement: Additive theme roles

The shared theme SHALL provide color, spacing, radius, typography, elevation, glass, and motion tokens for light and dark appearances without changing the computed values of existing Reader palette tokens.

#### Scenario: Existing Reader palette

- **WHEN** the Reader or chat uses an existing palette token in any supported theme
- **THEN** the token retains its previous computed value

#### Scenario: Reduced motion

- **WHEN** reduced motion is requested
- **THEN** motion duration tokens resolve to zero

### Requirement: Homepage presentation

The Homepage SHALL use the design roles with the system font stack, legible solid content surfaces, visible keyboard focus, and controls sized for touch at narrow and wide viewports while retaining its existing DOM and interaction contracts.

#### Scenario: Narrow viewport

- **WHEN** the Homepage is displayed at 390 CSS pixels wide
- **THEN** document and account controls remain accessible in a responsive layout

#### Scenario: Glass unavailable or reduced

- **WHEN** backdrop filtering is unsupported or reduced transparency is requested
- **THEN** Homepage card chrome uses a solid surface

#### Scenario: Dark appearance

- **WHEN** explicit dark or system dark appearance is active
- **THEN** Homepage color and material roles use the dark theme
