## MODIFIED Requirements

### Requirement: Logo refreshes the reader
The logo SHALL provide keyboard-accessible refresh via Shift+Enter and a popover refresh button, and show loading feedback before reloading. Status details, offline information and highlight state SHALL remain available in advanced settings. Errors and selection-held updates SHALL retain visible explanatory text and the existing explicit release action.

#### Scenario: Reader requests refresh
- **WHEN** the reader uses Shift+Enter or the popover refresh button
- **THEN** the logo shows loading feedback and the page reloads

#### Scenario: Selection holds an update
- **WHEN** the reader requests refresh during a held update
- **THEN** selection is preserved until explicit release and queued publication resumes through the existing guarded action

#### Scenario: Offline reading
- **WHEN** an accepted saved document is read offline
- **THEN** the logo identifies offline reading rather than claiming a live connection
