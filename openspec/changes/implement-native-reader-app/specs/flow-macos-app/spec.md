# Spec Delta

## MODIFIED Requirements

### Requirement: One action starts reading
The app SHALL offer Read to validate the selected profile, asynchronously start or reuse its managed preview, verify document availability, and open its native document once. It SHALL show progress and actionable failure causes in the same window. Command success, HTTP availability and accepted semantic content SHALL remain distinct from successful native paint. Configured external-reader URLs SHALL remain available through an explicit external-open action.

#### Scenario: Read a stopped project
- **WHEN** the user selects Read for a valid stopped project
- **THEN** the app displays validation, requested startup, observed running service, accepted document and native paint as distinct states
- **AND** opens the native document once after a matching accepted snapshot is available
- **AND** the window remains responsive throughout the operation

#### Scenario: Invalid or failed startup
- **WHEN** profile validation, launch, compilation, readiness or native presentation fails or exceeds its deadline
- **THEN** the app shows the known cause and a retry path without claiming native paint readiness
- **AND** validation failure does not stop an existing service

#### Scenario: An old request completes
- **WHEN** the user switches projects, stops the preview or closes the document before an earlier request completes
- **THEN** that request cannot open a native document or replace the current project's status

### Requirement: Native status follows asynchronous operations
The app SHALL execute blocking service and settings operations off the UI thread, serialize conflicting mutations, coalesce status checks, and reconcile immediately after actions. It SHALL distinguish requested commands, an observed process, an available document, accepted native content, painted frame, stopped state and failure. Concrete native presentation SHALL own its geometry and paint acknowledgment; existing external readers SHALL retain their rendering ownership.

#### Scenario: Slow service command
- **WHEN** a process command or settings operation is slow
- **THEN** the main run loop continues handling window events
- **AND** duplicate or conflicting controls cannot create overlapping mutations
- **AND** completing a command triggers a fresh status observation

### Requirement: Reader continuity survives interrupted transport
Paged, HTML and native readers SHALL retain accepted content, reading position, zoom and native selection across transient network loss, sleep/resume and engine restart. They SHALL reconnect with bounded requests and capped retries, react to online/resume signals and ignore obsolete callbacks. Reconnection SHALL NOT require a page reload or document reopen. Active selection SHALL continue to hold document replacement until explicitly released.

#### Scenario: Reconnect an unchanged document
- **WHEN** transport reconnects to the same document after an engine restart
- **THEN** the reader resumes delivery without resetting the viewport or losing selected text
- **AND** source actions continue enforcing current service/revision/source checks

#### Scenario: Content changes during interruption
- **WHEN** replacement content arrives while text is selected
- **THEN** the accepted DOM or native document and selection remain until the user releases selection
- **AND** pending replacement and reading-location restoration use the latest valid document state

#### Scenario: Old position or selection no longer matches
- **WHEN** a recovery snapshot belongs to another document, its text no longer matches, or the user has since navigated
- **THEN** the reader does not apply stale selection or position to unrelated content

#### Scenario: Hidden or disposed reader
- **WHEN** the page or native view is hidden, offline or disposed
- **THEN** retry work is reduced or suspended and disposed sessions cannot publish updates
- **AND** returning online or visible triggers recovery without duplicate connection loops


## ADDED Requirements

### Requirement: Home feedback describes available native actions
Loading feedback SHALL explain waiting, the step after completion and safe
close/reopen if it persists without instructing use of disabled controls.
Empty/error/busy feedback SHALL match the existing state; service lifecycle
labels SHALL distinguish service start/stop/restart from Read without changing
enabled policy, targets/actions, readiness probes, settings or Read intent.

#### Scenario: Loading and isolated preparation
- **WHEN** profile loading disables selection/Read, or isolated preparation disables service Stop
- **THEN** home SHALL provide a usable waiting/next-step explanation and SHALL NOT instruct that disabled action
- **AND** no extra retry, initialization, timer, inference or service restart is introduced

### Requirement: Minimal home layout and separated project settings sheet
Home SHALL show a compact header, project selector, primary `읽기` and a .ghost icon dock with a sage running dot. Service, reading and configuration actions SHALL remain available through the status-bar menu. Settings SHALL open separately with Save only in its sheet. NativeAppDesign SHALL own sage/.ghost and NativeBrandMark SHALL supply statusImage.

#### Scenario: Home surface when preview service is stopped or running
- **WHEN** the user views the home window
- **THEN** the header shows brand, `+` and `⚙` without subtitle or path caption, and the project card shows selector and `읽기`
- **AND** the icon dock offers start when stopped or stop with a sage running dot when running
- **AND** browser, address copy, offline and overflow actions follow existing enabled policy
- **AND** the status-bar menu includes home, Read, browser/offline, service control, editor connection, copy/logs, settings, login, guide/about and quit with a branded statusImage

#### Scenario: Opening separated project settings sheet
- **WHEN** the user opens `'프로젝트 설정…'` (or `⚙`)
- **THEN** project configuration opens in a separate project settings sheet/window
- **AND** the save button is located only inside the project settings sheet
