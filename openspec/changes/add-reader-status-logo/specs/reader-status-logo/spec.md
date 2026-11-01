## ADDED Requirements
### Requirement: Browser favicon follows the color scheme
The HTML Reader favicon SHALL present the approved L mark on an ivory tile in a light browser color scheme and on a charcoal tile in a dark browser color scheme.

#### Scenario: Browser color scheme changes
- **WHEN** a browser supporting SVG favicons displays the Reader in a light or dark color scheme
- **THEN** the favicon uses the corresponding contrasting tile and mark colors

### Requirement: Toolbar mark presents actual reader activity
The HTML reader SHALL show the approved custom B mark at 85% prototype size and derive its activity from existing publication/connection state. Busy work SHALL follow the mark's stroke with slow departure, acceleration and a gentle repeated return. Reduced motion SHALL use stable visual indicators.

#### Scenario: Compilation finishes before display
- **WHEN** compilation succeeds while current content is still pending
- **THEN** the logo remains busy until the accepted current content renders

#### Scenario: Reconnect or error persists
- **WHEN** an obsolete render completes during reconnection or a compile error
- **THEN** the existing state precedence continues to govern the logo and errors remain visible

### Requirement: Logo refreshes the reader
The logo SHALL act as a keyboard-accessible refresh button and show loading feedback before reloading the page. Status details, offline information and highlight state SHALL remain available in advanced settings. Errors and selection-held updates SHALL retain visible explanatory text and the existing explicit release action.

#### Scenario: Reader requests refresh
- **WHEN** the reader activates the logo
- **THEN** the logo shows loading feedback and the page reloads

#### Scenario: Offline reading
- **WHEN** an accepted saved document is read offline
- **THEN** the logo identifies offline reading rather than claiming a live connection
