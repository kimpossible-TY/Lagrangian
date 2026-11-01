## ADDED Requirements
### Requirement: Toolbar mark presents actual reader activity
The HTML reader SHALL show the approved custom B mark at 85% prototype size and derive its activity from existing publication/connection state. Busy work SHALL follow the mark's stroke with slow departure, acceleration and a gentle repeated return. Reduced motion SHALL use stable visual indicators.

#### Scenario: Compilation finishes before display
- **WHEN** compilation succeeds while current content is still pending
- **THEN** the logo remains busy until the accepted current content renders

#### Scenario: Reconnect or error persists
- **WHEN** an obsolete render completes during reconnection or a compile error
- **THEN** the existing state precedence continues to govern the logo and errors remain visible

### Requirement: Logo exposes compact accessible details
The logo SHALL open keyboard-accessible status details including offline and highlight state. Errors and selection-held updates SHALL retain visible explanatory text and the existing explicit release action. The right panel SHALL retain appearance and compute controls with technical details collapsed.

#### Scenario: Selection holds an update
- **WHEN** the reader opens logo details during a held update
- **THEN** selection is preserved until explicit release and queued publication resumes through the existing guarded action

#### Scenario: Offline reading
- **WHEN** an accepted saved document is read offline
- **THEN** the logo identifies offline reading rather than claiming a live connection
