# Terminal Reader

## Purpose

Deliver the existing interactive HTML Reader alongside Neovim in a graphics terminal while retaining document annotations and protecting editor contents.

## ADDED Requirements

### Requirement: Terminal presentation retains browser document behavior
The terminal Reader SHALL execute the existing HTML Reader in a real browser document and deliver terminal input to that document, preserving its mathematical layout, selections, source highlights and review strikes.

#### Scenario: Reader selection and review action
- **WHEN** a reader selects document text and invokes Red strike from the terminal
- **THEN** the existing Reader marks that exact DOM selection and offers undo without changing source

#### Scenario: Highlight reaches the existing verification path
- **WHEN** a reader invokes Highlight on a supported selection
- **THEN** the existing compiler verification determines whether source can be changed

### Requirement: Review state survives terminal restarts
The terminal Reader SHALL use persistent document storage and the HTML service's stable origin, and SHALL report an unavailable or mismatched managed service rather than silently changing origins.

#### Scenario: Restart preserves local marks
- **WHEN** the same document is reopened with the same configured profile and origin
- **THEN** review strikes remain available; Save for Codex context remains in its service record and is freshly validated

### Requirement: Editor Reader views have an owned lifecycle
The optional Neovim integration SHALL open the Reader in an internal right-hand view in the same terminal connection by default, SHALL retain explicit native pane and manual attachment modes, and SHALL provide start and stop actions that dispose owned presentation resources and editor attachments and restore the editor display without stopping the shared HTML service.

#### Scenario: Editor exits
- **WHEN** the editor owning a terminal Reader exits
- **THEN** its Reader host and private editor attachment are disposed without stopping the HTML Reader service or other views

### Requirement: Terminal presentation uses the managed HTML service
Project-based terminal launches SHALL resolve the existing HTML service manager by exact canonical project and entry identity and SHALL reuse its service and launch settings. A stopped service SHALL start only through its normal managed lifecycle. Terminal presentation SHALL NOT construct its own compiler launch plan or silently create a separate service.

#### Scenario: Existing document is already available
- **WHEN** a terminal view opens a document whose managed HTML Reader is running
- **THEN** it connects to that service's current accepted document without starting another compiler or replacing compiler, font, package, semantic-canvas or browser-computation settings
- **AND** closing and reopening the view preserves the service identity

#### Scenario: Missing, ambiguous or incompatible service
- **WHEN** no exact service matches, multiple services match without an explicit service ID, or the service cannot support the requested editor attachment
- **THEN** startup explains the configuration or upgrade required without starting a terminal-specific fallback

#### Scenario: Separate editor views share one Reader
- **WHEN** two Neovim views attach to the same HTML service
- **THEN** each has a private, service-bound editor attachment and verified writes reach only its own fixed editor
- **AND** closing one view revokes only that attachment
- **AND** revoked, dead-owner and prior-service tokens cannot authorize source writes, including at final write time
- **AND** browser requests cannot register an editor or choose its executable or address

#### Scenario: Unsupported terminal
- **WHEN** the default view has no attached supported TUI, image protocol or supported protocol-specific cell geometry
- **THEN** startup explains the missing requirement without painting an image over source or leaving owned processes running

#### Scenario: Reader startup takes time
- **WHEN** the internal Reader window is open while its browser or first image is still being prepared
- **THEN** its statusline shows animated loading feedback and elapsed time until the first image for the current visible layout is accepted
- **AND** the host handshake, status-only frames and obsolete frames do not dismiss loading
- **AND** closing the view stops the loading updates with its existing owned lifecycle

### Requirement: Windows Terminal uses its native image protocol
The terminal Reader SHALL support SIXEL output for Windows Terminal, while retaining the existing browser input, storage and source-action contracts. A protocol override SHALL work when remote sessions do not forward terminal environment markers.

#### Scenario: PowerShell in Windows Terminal
- **WHEN** a user selects SIXEL output in a Windows Terminal version with SIXEL support
- **THEN** the host emits native SIXEL frames and forwards terminal input to the same HTML Reader without requiring an iTerm2-compatible terminal

#### Scenario: Authored highlight colors survive SIXEL encoding
- **WHEN** a Chromium screenshot contains the existing HTML Reader's light or dark highlight backgrounds
- **THEN** the bounded SIXEL palette preserves those dominant colors without shifting gold highlights to red
- **AND** color selection uses screenshot pixels without changing the existing Typst/HTML highlight implementation or theme definitions

### Requirement: A second remote connection can attach to an editor-owned Reader
The Neovim integration SHALL prepare an editor-owned terminal session when manual opening is explicitly configured. It SHALL show a command for a second connection to the same host and preserve the existing editor and service lifetime checks.

#### Scenario: Start from a remote editor
- **WHEN** an editor invokes prepare or starts with manual opening configured
- **THEN** it creates a private argument manifest and shows a command to run in a separate native terminal connection instead of invoking the Mac's GUI pane launcher
- **AND** the attached host uses that editor's existing source-navigation and verified-highlight channel

#### Scenario: Stop before or after attachment
- **WHEN** the editor stops its prepared session or exits
- **THEN** its manifest is removed and an attached host disposes only its presentation resources and private editor attachment
- **AND** a command for that expired session cannot start a new Reader

### Requirement: Source navigation refuses uncertain positions
The Reader SHALL support editor-to-document and document-to-editor navigation for uniquely located saved literal passages and SHALL report stale, ambiguous or unsupported positions without jumping elsewhere.

#### Scenario: Unique literal passage
- **WHEN** a selected passage has one supported source location in the accepted snapshot
- **THEN** source navigation opens its file at the corresponding line and UTF-8 byte column

#### Scenario: Source position cannot be established
- **WHEN** a selection is ambiguous or generated, or its snapshot changed
- **THEN** navigation reports that state and preserves the current editor and reading position

### Requirement: Verified source highlights protect editor buffers
When connected to Neovim, the Reader SHALL route its final verified source edit through the editor and SHALL refuse to replace modified buffers or changed source contents.

#### Scenario: Unsaved target buffer
- **WHEN** a source highlight finishes verification while its target buffer has unsaved edits
- **THEN** neither the buffer nor the saved file is overwritten and the Reader reports the conflict

#### Scenario: Accepted edit
- **WHEN** the verified original still matches an unmodified editor buffer and saved file
- **THEN** the editor applies and saves the highlight and the Reader refreshes from the saved result

### Requirement: Terminal Save for Codex uses the HTML context contract
The terminal host SHALL invoke the HTML Reader's explicit Save for Codex action, saving the same bounded service-owned context without a separate terminal quotation store or source mutation.

#### Scenario: Save selected terminal content
- **WHEN** a terminal reader chooses Save for Codex
- **THEN** the HTML service records its exact logical selection and available source context and confirms acknowledgment
- **AND** the local selection reader checks service identity, revision and source freshness before using it

#### Scenario: Legacy terminal profile
- **WHEN** an existing terminal browser profile contains stored quotations
- **THEN** the updated Reader leaves them untouched without exposing a quotation library or sending them automatically

### Requirement: Same-connection frames remain inside the current Reader view
The default Neovim view SHALL position image frames inside its current window, forward Unicode keyboard, paste and mouse input to the existing browser, and discard frames from obsolete layouts. It SHALL provide source-window navigation without replacing the Reader buffer or losing modified source buffers.

#### Scenario: Remote Windows start
- **WHEN** a Neovim 0.12 or newer TUI in a SIXEL-capable Windows Terminal invokes start over one terminal connection
- **THEN** source remains on the left and the interactive Reader appears on the right without another connection or native pane launch
- **AND** the recognized Windows SIXEL virtual grid determines the browser viewport and mouse coordinates, even when SSH ioctl pixels are placeholders

#### Scenario: Resize or hide while capturing
- **WHEN** the Reader window is resized, hidden, replaced or closed while a screenshot is pending
- **THEN** the old frame is not presented and obsolete images are cleared before the editor is redrawn
- **AND** closing stops only that view's owned browser and service

#### Scenario: Statusline plugin refreshes while Reader is focused
- **WHEN** a statusline plugin replaces Reader feedback and periodically refreshes its statusline while the Reader message remains unchanged
- **THEN** periodic frames do not replace the plugin's statusline again or change the user's plugin configuration
- **AND** statusline-only refreshes do not retransmit the Reader image, while an actual Reader-buffer redraw restores it
- **AND** loading progress and new Reader feedback still update when their content changes

#### Scenario: Focus switches between Reader and source with lualine loaded
- **WHEN** focus enters the owned Reader window and lualine is already loaded
- **THEN** its statusline refresh is paused and the Reader statusline remains visible through loading and normal reading
- **AND** returning to source or another window/tab restores and refreshes lualine
- **AND** closing or replacing the Reader and failing its launch restore any lualine statusline paused by that view
- **AND** the current global/per-window status layout, lualine configuration, tabline and winbar are preserved
- **AND** starting the Reader without lualine does not load or require that plugin

#### Scenario: User drags the source and Reader divider
- **WHEN** a mouse-enabled Neovim user presses the divider and drags it left or right, with either source or Reader focused
- **THEN** Neovim adjusts both window widths and the Reader renders at its new measured position and size
- **AND** the gesture is not sent to the browser, even when it crosses into the Reader

#### Scenario: Mouse gestures retain their starting owner
- **WHEN** a drag begins in the source or Reader document and crosses the divider
- **THEN** the source gesture remains with Neovim or the Reader gesture remains with the browser through release
- **AND** a Reader selection does not resize the editor windows

#### Scenario: Reader keyboard width controls
- **WHEN** a user types `Ctrl-W <`, `Ctrl-W >` or `Ctrl-W =` in Reader input mode
- **THEN** Neovim decreases or increases the Reader width, or equalizes the windows, without forwarding those keys to the browser
- **AND** existing global mouse settings and unrelated window mappings are preserved

#### Scenario: Probe failure or interrupted startup
- **WHEN** terminal capability queries time out, fail or the editor cancels startup
- **THEN** the temporary response handler is removed, the editor remains running with input and foreground ownership intact, and startup reports failure

#### Scenario: Remote terminal replies late or varies optional capabilities
- **WHEN** the first capability query is lost or delayed, or Windows DA1 reports reordered/additional features
- **THEN** startup retries within a bounded time budget and recognizes the required Windows feature set without requiring an exact response string
- **AND** positive Kitty graphics or explicit iTerm cell reports do not depend on an unrelated DA1 response
- **AND** failed detection reports the received capability information or absence of replies without stopping the editor

#### Scenario: Same TUI starts the Windows Reader again
- **WHEN** the current attached TUI previously confirmed the Windows SIXEL grid and starts or resizes its Reader again
- **THEN** the integration reuses that fixed virtual grid without another capability round trip
- **AND** a different attached UI must establish its capabilities separately

#### Scenario: Interactive shell retains the editor in the foreground
- **WHEN** a user starts Neovim from an interactive remote shell and types `:FlowReader start`
- **THEN** the Reader opens without stopping any editor process or changing its terminal foreground process group
- **AND** browser input and stop/restart work in that same connection

#### Scenario: Kitty terminal has no cell-size report
- **WHEN** the terminal confirms Kitty graphics but does not report logical cell dimensions
- **THEN** the view uses a bounded logical viewport scaled to its row/column placement, with browser input using those same logical coordinates

#### Scenario: Browser-to-source navigation from Reader focus
- **WHEN** the focused Reader requests a verified source jump
- **THEN** the source window receives the location and focus, and the Reader remains in its own window

### Requirement: Readers and Neovim share the saved source edit
Readers and Neovim SHALL share one project/entry source edit owned by the common Rust project service. Saved-source observation and serialized persistence SHALL work independently of renderer lifetime. Managed, explicit and standalone lookup SHALL resolve the same project record. Each consumer SHALL validate current saved source and map positions through its own accepted document.

#### Scenario: Reopen the project in Neovim
- **WHEN** the configured entry opens with shared restoration enabled and a verified common edit exists in an included source file
- **THEN** Neovim opens that source file at the shared edit
- **AND** the command is available without opening a terminal Reader
- **AND** unsaved buffers and cursor movement during asynchronous lookup are preserved

#### Scenario: The common edit arrives after HTML publication
- **WHEN** the engine records the common edit after the HTML document has been accepted
- **THEN** HTML navigation metadata updates without compiling or replacing the accepted document
- **AND** active selections, recent gestures and explicit named destinations retain their existing navigation priority

#### Scenario: Import and distant body changes in the same save
- **WHEN** a saved source edit adds an import and changes a distant body passage or figure
- **THEN** common history retains the separate changed hunks and both readers exclude unchanged content between them from source-edit mapping
- **AND** HTML skips the unmapped import and navigates to the mapped body change instead of its unchanged section heading
- **AND** legacy records with only one range remain readable, while trivia-only saves rebase precise ranges without advancing the edit sequence

#### Scenario: Wrong, ambiguous or stale history
- **WHEN** a record belongs to another project, profiles are ambiguous, source bytes differ, or the saved range is invalid
- **THEN** no guessed shared position is opened
- **AND** a common but unusable edit is not replaced by an unrelated local visual edit

#### Scenario: Terminal startup retains restoration
- **WHEN** a terminal Reader starts with an unchanged source cursor
- **THEN** its first cursor poll establishes a baseline without replacing the restored reading destination
- **AND** later cursor movement or explicit sync can navigate normally

#### Scenario: HTML-only saved edits
- **WHEN** only the HTML service is running and a registered source dependency is saved, including while no viewers are connected
- **THEN** the common project service records its source range before HTML compilation
- **AND** failed compilation retains the accepted document without discarding the new source edit
- **AND** a later source-matching successful document can map that edit

#### Scenario: Concurrent reader services
- **WHEN** HTML and paged services alternately or concurrently observe and publish the same project
- **THEN** locked transactions reload current state and preserve the latest source sequence and all valid palette snapshots
- **AND** stale compilation results do not roll back or consume a newer edit

#### Scenario: Source-only changes and engine compatibility
- **WHEN** a comment-only save shifts the last edit or a deletion removes its original text
- **THEN** shared policy preserves UTF-8 boundaries, rebases comment shifts and chooses a surviving deletion anchor
- **WHEN** the configured engine lacks the common source-history capability
- **THEN** HTML startup reports the required capability without starting another visual edit chronology

#### Scenario: Stop during common history observation
- **WHEN** the Reader closes or startup is interrupted while an owned source-history helper is running
- **THEN** it terminates and reaps that helper within a bounded shutdown period
- **AND** a disposed client cannot start another observation or mutate the record later

### Requirement: Frame capture follows browser changes
The terminal host SHALL capture frames when the browser document changes instead of polling a fixed interval, SHALL coalesce changes that arrive while a frame is pending, and SHALL still capture the first frame and changes caused by resize, layout, visibility or statusline updates.

#### Scenario: Idle Reader
- **WHEN** the browser document does not change
- **THEN** the host takes no screenshots after the initial frame
- **AND** an interactive terminal receives no periodic image traffic

#### Scenario: Changes during a pending frame
- **WHEN** several browser changes occur while a screenshot, encoding or presentation is still in progress
- **THEN** the host acknowledges every browser signal and captures the latest state once the pending frame completes
- **AND** `--fps` bounds the minimum interval between captures instead of adding a polling timer

#### Scenario: Forced capture
- **WHEN** the Reader window is resized, its layout generation changes, it becomes visible, or its statusline message changes
- **THEN** a capture is requested even if browser pixels did not change
- **AND** a frame from an obsolete layout generation is not presented

### Requirement: Frame timing is opt-in and isolated
The terminal host SHALL record per-frame screenshot, encoding and presentation timings, transmitted bytes and skipped unchanged frames only when metrics are enabled, and SHALL never write metrics into the native image stream.

#### Scenario: Metrics enabled
- **WHEN** `--metrics PATH` or `FLOW_READER_METRICS` names a file
- **THEN** each capture appends one JSON Lines record with its timings, byte count and unchanged count
- **AND** capture scheduling and image output are unchanged

#### Scenario: Interactive stderr
- **WHEN** metrics are configured for `stderr` while stderr is an interactive terminal
- **THEN** startup rejects the destination instead of corrupting the Reader display

### Requirement: Image frames are synchronized
Kitty and iTerm2 image frames SHALL be wrapped in terminal synchronized-update mode by one protocol owner used by both the native and Neovim editor transports, while SIXEL output SHALL remain unwrapped until its synchronized behavior is verified.

#### Scenario: Native Kitty frame
- **WHEN** the native transport presents a Kitty or iTerm2 frame
- **THEN** the image sequence is surrounded by `CSI ?2026h` and `CSI ?2026l`
- **AND** the statusline write remains outside the image update

#### Scenario: Neovim frame
- **WHEN** the editor transport presents a frame with synchronized output enabled
- **THEN** the editor receives the wrapped image and the internal view paints it without nesting another synchronized-update sequence around the editor redraw

#### Scenario: SIXEL verification pending
- **WHEN** the host presents SIXEL output
- **THEN** the frame is not wrapped until a physical Windows Terminal check confirms the behavior
