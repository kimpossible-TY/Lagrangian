## ADDED Requirements

### Requirement: Lagrangian web viewer identity
Lagrangian SHALL be the canonical native macOS product and feature contract. Lagrangian Web Viewer SHALL be its web-optimized projection in `tools/flow-reader/web/`, using the shared `flow_reader` backend and `tools/reader-common` policy. User-facing viewer titles and HTML variant labels SHALL use Lagrangian Web Viewer, the manifest short name SHALL be Lagrangian, and the ready label SHALL be `웹 뷰어 준비됨`.

#### Scenario: Open the viewer or homepage
- **WHEN** a user opens the viewer or views an HTML document variant on the homepage
- **THEN** the visible viewer identity is Lagrangian Web Viewer and the homepage retains Lagrangian branding
- **AND** a titled document uses its title followed by ` · Lagrangian Web Viewer`

### Requirement: Web cross-project preview and return
The web viewer SHALL show a preview popover on first activation of a uniquely resolved cross-project reference without navigating. A second activation SHALL commit navigation to the target and make Back available to restore the origin through shared return policy.

#### Scenario: Preview, jump and return
- **WHEN** a user first activates a uniquely resolved reference
- **THEN** a preview appears and the original document and location remain current
- **WHEN** the user activates the preview to jump and then chooses Back
- **THEN** the target opens and Back restores the saved origin and location
- **AND** failed or cancelled navigation leaves the current document and return history unchanged

#### Scenario: Target cannot be uniquely resolved
- **WHEN** a reference is ambiguous or unavailable
- **THEN** no guessed target is opened and existing safe external URL behavior is preserved
