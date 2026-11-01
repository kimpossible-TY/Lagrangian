## MODIFIED Requirements
### Requirement: Logo refreshes the reader
The logo SHALL expose a deliberate keyboard-accessible refresh action. A pointer press held for approximately 500 ms or Shift+Enter SHALL show loading feedback and reload the page, applying a waiting service-worker update first. Movement beyond a small slop or releasing early SHALL cancel the long press. Errors and selection-held updates SHALL retain visible explanatory text and the existing explicit release action.

#### Scenario: Reader requests refresh
- **WHEN** the reader holds the logo for approximately 500 ms or presses Shift+Enter
- **THEN** the logo shows loading feedback and the page reloads

#### Scenario: Waiting update is applied
- **WHEN** the reader invokes the refresh action with a service-worker update waiting
- **THEN** the reader applies the update before reloading

#### Scenario: Selection holds an update
- **WHEN** the reader invokes the refresh action during a held update
- **THEN** selection is preserved and the existing explicit release action remains available without reloading

#### Scenario: Offline reading
- **WHEN** an accepted saved document is read offline
- **THEN** the logo identifies offline reading rather than claiming a live connection

## ADDED Requirements
### Requirement: Logo explains current status
A single logo activation SHALL toggle an accessible speech-bubble popover with a short localized explanation of the current state, including any waiting update. It SHALL dismiss on Escape or an outside pointer action. A single activation SHALL NOT reload, reconnect, or release a selection. The popover SHALL update when the status or language changes.

#### Scenario: Reader inspects status
- **WHEN** the reader taps or clicks the logo
- **THEN** the popover explains the current logo state without invoking the refresh action

#### Scenario: Reader dismisses status
- **WHEN** the reader presses Escape, taps outside, or activates the logo again
- **THEN** the popover closes

#### Scenario: Short or moved press
- **WHEN** a pointer is released before the long-press threshold or moves beyond the allowed slop
- **THEN** the long-press action does not run
