## ADDED Requirements

### Requirement: Reader chrome presentation

The HTML Reader SHALL use shared design roles and system fonts for its toolbar, outline, reading settings and status chrome while preserving existing interaction, positioning and document layout contracts.

#### Scenario: Chrome material

- **WHEN** backdrop filtering is supported
- **THEN** the toolbar, outline drawer and reading settings panel MAY use frosted material over a solid baseline

#### Scenario: Reduced transparency

- **WHEN** reduced transparency or increased contrast is requested, or backdrop filtering is unavailable
- **THEN** those surfaces use solid theme colors

#### Scenario: Accessible controls

- **WHEN** chrome controls are focused, hovered or used at a narrow viewport
- **THEN** focus and hover feedback remain visible, text remains legible in light and dark themes, and touch targets are at least 44 CSS pixels

#### Scenario: Reduced motion

- **WHEN** reduced motion is requested
- **THEN** chrome transitions and activity animation use stable equivalents
