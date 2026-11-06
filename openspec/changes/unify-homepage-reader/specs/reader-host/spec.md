# Reader host

## Purpose
Provide one Reader entry point for Homepage and configured HTML documents while
retaining local account authority, document identities and old URL compatibility.

## ADDED Requirements

### Requirement: Shared Homepage and document origin
The Reader host SHALL serve Homepage at `/` and each configured HTML document at `/d/<reader-id>/` from one process and origin, with separate accepted document state. Homepage requests SHALL NOT trigger compilation or inference.

#### Scenario: Open Homepage and two documents
- **WHEN** a configured shared Reader is running
- **THEN** `/` serves Homepage and each `/d/<reader-id>/` serves its Reader shell, state and assets on that listener
- **AND** unknown identifiers return 404 without selecting another document

### Requirement: Scoped document delivery
Document APIs, assets and offline workers SHALL remain under their document prefix. Document account endpoints SHALL remain read-only and cannot mutate credentials. The paged entry SHALL preserve the configured existing paged destination.

#### Scenario: Read and navigate a document
- **WHEN** a visitor opens `/d/<reader-id>/` or `/d/<reader-id>/paged/`
- **THEN** HTML requests resolve within that document prefix and paged entry redirects to its configured existing view
- **AND** document workers cannot control Homepage or cache its account responses

#### Scenario: Attempt document account management
- **WHEN** a document request invokes login, cancel or logout through its auth API, or uses a document-prefixed admin route
- **THEN** it receives 403 or 404 and no credential operation occurs

### Requirement: Local capability authority on a shared origin
Account sign-in, cancel and sign-out MUST require genuine admin loopback, exact Host and Origin, no forwarding headers, a current per-start private capability, and a valid management session with CSRF. Remote ingress MUST remain read-only even with copied proofs.

#### Scenario: Remote credential mutation
- **WHEN** a non-loopback peer or read-only proxy submits login, cancel or logout with valid capability, cookie and CSRF
- **THEN** the server returns 403 and does not invoke ChatAuth mutation

#### Scenario: Shared-origin document borrows a browser session
- **WHEN** a same-origin caller has a management cookie and CSRF but lacks the current private capability
- **THEN** account mutations return 403
- **AND** account identity details are not disclosed without that capability

### Requirement: Existing document URL compatibility
Configured old HTML origins SHALL redirect root and document resource URLs to the matching prefixed shared URL, preserving query strings and browser fragments. Compatibility listeners SHALL belong to the shared process and SHALL NOT serve account management.

#### Scenario: Existing bookmark or API URL
- **WHEN** a visitor opens an old document root or resource URL
- **THEN** a method-preserving redirect points to the same document on the canonical shared origin
- **AND** compatibility ingress cannot mint or use an admin session

### Requirement: Existing owners and shared lifecycle
ChatAuth SHALL remain the sole credential owner. ReaderManager SHALL retain inventory, launch settings and lifecycle ownership. Shared mode SHALL use one Reader launchd job for Homepage and all HTML documents, without requiring a second Homepage job.

#### Scenario: Attach a managed presentation
- **WHEN** a terminal or manager resolves an exact document in shared mode
- **THEN** it uses the common Reader job and prefixed URL with the existing document/service identity checks
- **AND** disposing one document conversation cannot cancel the shared account login

#### Scenario: Migrate or roll back
- **WHEN** an operator selects shared mode or restores prior configuration and immutable release
- **THEN** documented plist changes use existing manager ownership rules and preserve credentials, conversation history and per-document output
- **AND** tests do not install jobs or restart live services
