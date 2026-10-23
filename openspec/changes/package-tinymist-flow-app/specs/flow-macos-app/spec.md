## ADDED Requirements

### Requirement: One action starts reading
The app SHALL offer Read to validate the selected profile, asynchronously start or reuse its managed preview, verify document availability, and open the configured URL once. It SHALL show progress and actionable failure causes in the same window. A successful command or static HTTP response alone SHALL NOT imply document readiness.

#### Scenario: Read a stopped project
- **WHEN** the user selects Read for a valid stopped project
- **THEN** the app displays validation, requested startup, observed running service and document readiness as distinct states
- **AND** opens the browser once after a document is available
- **AND** the window remains responsive throughout the operation

#### Scenario: Invalid or failed startup
- **WHEN** profile validation, launch, compilation, readiness or browser opening fails or exceeds its deadline
- **THEN** the app shows the known cause and a retry path without claiming readiness
- **AND** validation failure does not stop an existing service

#### Scenario: An old request completes
- **WHEN** the user switches projects, stops the preview or closes the app before an earlier request completes
- **THEN** that request cannot open a browser or replace the current project's status

### Requirement: Native status follows asynchronous operations
The app SHALL execute blocking service and settings operations off the UI thread, serialize conflicting mutations, coalesce status checks, and reconcile immediately after actions. It SHALL distinguish requested commands, an observed process, an available document, stopped state and failure. Actual browser rendering remains reader-owned.

#### Scenario: Slow service command
- **WHEN** a process command or settings operation is slow
- **THEN** the main run loop continues handling window events
- **AND** duplicate or conflicting controls cannot create overlapping mutations
- **AND** completing a command triggers a fresh status observation

### Requirement: Laptop lifecycle and power preserve reading intent
The native app SHALL suspend probes while asleep, reconcile on wake and network changes, and reduce idle checks on battery, Low Power Mode or elevated thermal conditions. Explicit Read and retry actions SHALL remain immediate. It SHALL neither prevent sleep nor stop requested previews as an implicit power policy.

#### Scenario: Wake after a network transition
- **WHEN** the Mac wakes or its network path changes
- **THEN** stale observations are ignored and current service/document state is checked
- **AND** recovery does not open another browser tab or start an explicitly stopped project

#### Scenario: Low power operation
- **WHEN** battery or system power/thermal policy requests less background work
- **THEN** idle checks use a reduced cadence without accumulating concurrent requests
- **AND** an explicit reading action still starts promptly

### Requirement: Reader continuity survives interrupted transport
Paged and HTML readers SHALL retain accepted content, reading position, zoom and native selection across transient network loss, sleep/resume and engine restart. They SHALL reconnect with bounded requests and capped retries, react to online/resume signals and ignore obsolete callbacks. Reconnection SHALL NOT require a page reload. Active selection SHALL continue to hold document replacement until explicitly released.

#### Scenario: Reconnect an unchanged document
- **WHEN** transport reconnects to the same document after an engine restart
- **THEN** the reader resumes delivery without resetting the viewport or losing selected text
- **AND** source actions continue enforcing current service/revision/source checks

#### Scenario: Content changes during interruption
- **WHEN** replacement content arrives while text is selected
- **THEN** the accepted DOM and selection remain until the user releases selection
- **AND** pending replacement and reading-location restoration use the latest valid document state

#### Scenario: Old position or selection no longer matches
- **WHEN** a recovery snapshot belongs to another document, its text no longer matches, or the user has since navigated
- **THEN** the reader does not apply stale selection or position to unrelated content

#### Scenario: Hidden or disposed reader
- **WHEN** the page is hidden, offline or disposed
- **THEN** retry work is reduced or suspended and disposed sessions cannot publish updates
- **AND** returning online or visible triggers recovery without duplicate connection loops

### Requirement: Discoverable user documentation
The README SHALL describe Flow's reading and review features before development details, show a screenshot of a reproducible example document, and explain the first preview using the app's actual control labels. Installation instructions SHALL distinguish a fresh machine from rebuilding with an installed engine.

#### Scenario: Discover and try a feature
- **WHEN** a new user reads the README
- **THEN** they can find mobile reading, source highlights, browser-only review marks, saved Codex context, document themes, reference return and change navigation
- **AND** they can follow project addition, start and open-preview instructions and find the mobile access prerequisites

### Requirement: One canonical user guide for web and app
The documentation generator SHALL produce a GitHub-readable user guide from the same Typst source bundled as the app's PDF. Local image and documentation links SHALL work from each generated Markdown output. The guide SHALL explain feature purpose, actions, outcomes and relevant conditions, including that highlights modify source, red strikes stay in browser storage, and saving for Codex does not start an assistant turn.

#### Scenario: Read the guide on GitHub or in the app
- **WHEN** a user follows the README's user-guide link or opens the app's guide menu
- **THEN** they can read the corresponding guide without needing to interpret Typst source
- **AND** the web and app guides are generated from one maintained source

#### Scenario: Detect an outdated web guide
- **WHEN** the canonical guide changes without regenerating Markdown
- **THEN** the documentation consistency check rejects the outdated generated guide

### Requirement: Integrated Flow source repository
The repository SHALL maintain the native Flow app, packaging, branding, documentation, engine implementation, preview frontend, supporting editor integrations, tests and workflow contracts. Applicable license notices and prior source history SHALL be preserved.

#### Scenario: Package a compatible external engine
- **WHEN** a compatible external engine executable is supplied
- **THEN** the app can be built and tested without an engine source workspace
- **AND** the engine is copied into the app bundle independently of the Flow source revision
- **AND** current preview lifecycle and engine feature arguments are preserved

### Requirement: External engine input
Packaging SHALL accept an explicit engine path or FLOW_ENGINE_PATH and otherwise use the current installed Flow engine. The input SHALL be checked before an existing build output is replaced. The release manifest SHALL identify the external engine by version and hashes in addition to the Flow source revision.

#### Scenario: Reuse an installed engine
- **WHEN** Flow is rebuilt using the current installed engine
- **THEN** the engine sources are not needed
- **AND** the installed app, project settings, and running previews are unchanged by the build

#### Scenario: Reject an incompatible or missing engine
- **WHEN** the supplied engine is missing or lacks the required preview CLI support
- **THEN** packaging reports an actionable error
- **AND** an existing output bundle is preserved

### Requirement: Native engine build
Packaging SHALL support --build-engine using the locked flow-release profile and the native macOS target. The release manifest SHALL record engine build settings, version and hashes. Packaging SHALL build into a staged bundle and preserve an existing output when packaging fails.

#### Scenario: Build the maintained engine
- **WHEN** a native engine build is requested
- **THEN** the maintained workspace is built with the flow-release profile and copied into the staged app
- **AND** engine build metadata accompanies the app source revision and engine hashes
- **AND** development builds do not replace the installed app or its running engine

### Requirement: Product repository identity
The development repository SHALL be named tinymist-flow to match the product. Current documentation and local remote URLs SHALL use this name. The earlier independent repository SHALL be retained as tinymist-flow-archive.

#### Scenario: Align repository and product names
- **WHEN** the development repository is renamed to tinymist-flow
- **THEN** its existing history and upstream fork relationship are preserved
- **AND** the earlier independent repository remains accessible as tinymist-flow-archive
- **AND** README generation and development instructions use the current repository name

### Requirement: Branded installed app
The system SHALL install a macOS app named tinymist-flow with its own bundle identifier, icon, bundled engine, and release manifest.

#### Scenario: Build and install
- **WHEN** a local release is built and installed
- **THEN** development rebuilds do not overwrite the installed engine
- **AND** macOS can attribute the app and its preview service to tinymist-flow

### Requirement: Project and service controls
The app SHALL let the user select or add projects, edit preview settings, open previews and logs, start or stop services, and configure app login startup. Profiles SHALL be validated before persistence or launch.

#### Scenario: Start a configured project
- **WHEN** the user starts a project
- **THEN** its preview binds only to loopback using its configured port and original source paths
- **AND** the focus record PID matches its LaunchAgent PID

#### Scenario: Stop a project
- **WHEN** the user stops a project
- **THEN** its job is disabled until explicitly started again

### Requirement: Persistent signing identity
Packaging SHALL support explicitly saving a user's signing certificate identifier and SHALL reuse it for app and engine builds unless --identity or FLOW_SIGN_IDENTITY overrides it. A configured but unavailable identity SHALL stop the build rather than silently selecting ad-hoc signing. Private keys SHALL remain outside source files and signing configuration.

#### Scenario: Rebuild after configuring a certificate
- **WHEN** a user builds without an explicit signing override after configuring a certificate
- **THEN** the app and bundled engine use that same certificate
- **AND** changed builds retain mutually compatible designated requirements

#### Scenario: Configured certificate is unavailable
- **WHEN** the configured signing certificate or its private key cannot be found
- **THEN** the build reports the unavailable identity and preserves existing output
- **AND** it does not silently sign ad hoc

#### Scenario: Verify certificate provenance
- **WHEN** a certificate-signed bundle is built or verified
- **THEN** its manifest records the signing certificate SHA-256 fingerprint
- **AND** verification rejects an app or engine signed by a different certificate

#### Scenario: Migrate from ad-hoc signing
- **WHEN** the installed app first changes to a persistent certificate
- **THEN** normal macOS consent remains required where requested
- **AND** update permission continuity is reported only after actual document delivery is verified across an installed update

### Requirement: Recoverable updates
Installation SHALL validate the incoming bundle and preserve the previous installed version. A rollback command SHALL restore that bundle and restart previously running profiles. Failures SHALL be reported explicitly.

#### Scenario: Update or rollback
- **WHEN** a user installs a valid new local release or requests rollback
- **THEN** settings and project source files are preserved
- **AND** the installed version and source revision can be inspected

#### Scenario: Preview shutdown completes asynchronously
- **WHEN** a stop command returns before the previous preview process disappears
- **THEN** installation waits for its stopped status before replacing the bundle or restarting profiles
- **AND** a bounded shutdown failure is reported instead of treating the new preview as started

### Requirement: Tail Hosting integration
Migration SHALL import the configured project, keep its port and HTTPS URL, and leave ingress ownership with Tail Hosting. The adapter SHALL preserve a recoverable copy of the previous configuration.

#### Scenario: Migrate an existing preview
- **WHEN** migration is requested for a Tail Hosting registry
- **THEN** lifecycle commands use the installed Flow app and focus readers use the migrated profile's record
- **AND** unrelated hosted services retain their configuration
