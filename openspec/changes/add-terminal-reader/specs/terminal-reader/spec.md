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
The terminal Reader SHALL use persistent document storage and a stable origin, and SHALL report a requested owned service port being unavailable rather than silently changing origins.

#### Scenario: Restart preserves local marks
- **WHEN** the same document is reopened with the same configured profile and origin
- **THEN** review strikes remain available; Save for Codex context remains in its service record and is freshly validated

### Requirement: Native terminal panes have an owned lifecycle
The optional Neovim integration SHALL open the Reader beside the editor in a supported native terminal pane, SHALL provide explicit start and stop actions, and SHALL restore terminal modes and stop owned subprocesses on exit.

#### Scenario: Editor exits
- **WHEN** the editor owning a terminal Reader exits
- **THEN** its Reader host and any service it started stop without terminating an independently running Reader service

#### Scenario: Unsupported terminal
- **WHEN** no supported native pane launcher or graphics protocol is configured
- **THEN** startup explains the missing requirement without opening a broken Neovim terminal buffer

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
