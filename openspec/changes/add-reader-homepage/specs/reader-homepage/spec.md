# Spec Delta

## Purpose

Provide a reader host Homepage for configured document discovery, truthful availability, and secure host-owned ChatGPT account management.

## ADDED Requirements

### Requirement: Prerequisite merge gate
Homepage implementation MUST wait until `feat/reader-paragraph-chat` merges into `main` and its account-management contract is reconciled.

#### Scenario: Dependency remains unmerged
- **WHEN** implementation readiness is assessed before that merge
- **THEN** implementation remains blocked even if proposal validation passes

### Requirement: Host root entry
The reader host SHALL serve the Homepage at `/` independently of document compilation.

#### Scenario: No accepted document
- **WHEN** the host is reachable before any document compiles
- **THEN** `/` shows document availability and account controls

### Requirement: Configured document inventory
The Homepage SHALL list configured documents with names and available reader variants without enumerating arbitrary filesystem content.

#### Scenario: Empty inventory
- **WHEN** no documents are configured
- **THEN** the page shows an empty state without fabricated entries

### Requirement: Safe reader entry
Document entries SHALL link only to validated configured HTML or paged reader destinations without revealing private source paths.

#### Scenario: Invalid destination
- **WHEN** a configured entry has an unsafe URL
- **THEN** its navigation is disabled with an explanation

### Requirement: Document route compatibility
Existing document origins SHALL retain their `/` reading entry, API contracts, revision checks, and offline reading.

#### Scenario: Existing bookmark
- **WHEN** a reader opens a saved document-origin root URL
- **THEN** the document reader opens rather than the host Homepage

### Requirement: Truthful availability
The Homepage SHALL distinguish host availability from each document's ready, unavailable, stale, or unknown status.

#### Scenario: Status probe fails
- **WHEN** a document status cannot be refreshed
- **THEN** it is labeled unknown or stale rather than ready

### Requirement: Read-only overview
Loading or refreshing the Homepage SHALL NOT start services, compile documents, modify sources, or invoke model inference.

#### Scenario: Stopped document
- **WHEN** its entry appears on the Homepage
- **THEN** observation leaves the service stopped

### Requirement: Reader visual continuity
The Homepage SHALL reuse warm paper colors, green accent, approved L branding, and light/dark Reader themes.

#### Scenario: Dark appearance
- **WHEN** the selected Reader theme is dark
- **THEN** Homepage surfaces and controls use the corresponding dark palette

### Requirement: Accessible overview
Homepage navigation, status, and account controls SHALL support keyboard and touch use with readable labels at mobile widths.

#### Scenario: Keyboard navigation
- **WHEN** a user tabs through the page
- **THEN** actionable controls have visible focus and status is understandable without color

### Requirement: Homepage account ownership
The Homepage SHALL own sign-in, cancel, sign-out, and plan/model status presentation; document readers SHALL link there for account management.

#### Scenario: Manage from a document
- **WHEN** the user chooses account management
- **THEN** the host Homepage opens without losing the document's chat history or draft

### Requirement: Mac-only credential mutations
Sign-in, cancel, and sign-out MUST require explicit user action on the Mac's genuine loopback Homepage.

#### Scenario: Remote management request
- **WHEN** a Tailscale visitor attempts a credential mutation
- **THEN** it is denied and the page directs the user to manage access on the Mac

### Requirement: Sanitized remote account status
Remote visitors SHALL receive only sanitized sign-in, plan-grant, and model status without account identifiers or email addresses.

#### Scenario: Remote status view
- **WHEN** a remote visitor opens the account area
- **THEN** it shows permitted status without registration identities or host credentials

### Requirement: Credential isolation
Provider tokens MUST remain host-owned and MUST NOT enter browser responses, URLs, storage, logs, source files, or conversation records.

#### Scenario: Account response
- **WHEN** the page reads status or completes a management action
- **THEN** no provider token is disclosed

### Requirement: Independent host validation
Homepage account endpoints MUST reject a Host outside an exact trusted configured authority allow-list.

#### Scenario: Spoofed authority
- **WHEN** a request supplies an unconfigured Host with a matching Origin
- **THEN** it is rejected without account effects

### Requirement: Exact mutation origin
Account mutations MUST require an Origin matching the trusted configured scheme, host, and port; absent, null, or foreign Origins MUST fail.

#### Scenario: Missing Origin
- **WHEN** an account POST omits Origin
- **THEN** it is rejected without changing authentication

### Requirement: Proxy locality protection
Proxy connections and untrusted forwarding headers MUST NOT grant loopback management authority.

#### Scenario: Remote request via local proxy
- **WHEN** a proxy forwards a remote mutation over a loopback socket
- **THEN** the request remains ineligible for Mac-only management

### Requirement: CSRF-protected mutations
Account mutations MUST use POST and a valid browser-session-bound CSRF token in addition to Origin and Host validation.

#### Scenario: Invalid CSRF token
- **WHEN** an otherwise eligible POST has a missing or mismatched token
- **THEN** it is rejected without account effects

### Requirement: Browser session separation
Browser sessions MUST carry no provider credentials and MUST NOT convert remote read-only access into management authority.

#### Scenario: Copied remote session
- **WHEN** a remote session handle is used for a management request
- **THEN** management remains denied

### Requirement: Session lifetime
Management sessions MUST expire, rotate after sign-in, and become invalid after sign-out or host restart.

#### Scenario: Stale browser tab
- **WHEN** a tab submits an expired or invalidated session
- **THEN** the action fails and requires a fresh eligible session

### Requirement: Session transport protection
HTTPS session cookies MUST be host-only, Secure, HttpOnly, and SameSite=Strict. Any HTTP exception MUST be isolated to genuine Mac loopback.

#### Scenario: Plain remote HTTP
- **WHEN** a remote client requests a management session over HTTP
- **THEN** no management session is issued

### Requirement: Local OAuth completion
OAuth completion MUST retain the Mac callback, one-use state, nonce, and PKCE validation without accepting callback codes on the Homepage origin.

#### Scenario: Callback sent to host page
- **WHEN** an OAuth code is submitted to the reader host origin
- **THEN** it cannot complete sign-in

### Requirement: Honest plan and model status
The Homepage MUST distinguish a plan grant and model catalog from verified live access, and show unknown, unavailable, or reauthentication states honestly.

#### Scenario: Catalog is available
- **WHEN** a model appears in the account catalog
- **THEN** the page does not claim proven entitlement, quota, or successful inference

### Requirement: Account failure recovery
Account failures SHALL preserve document history and drafts and expose a retryable or reauthentication status without fabricated success.

#### Scenario: Credential refresh fails
- **WHEN** account status cannot be refreshed
- **THEN** the page reports the failure and existing conversations remain intact

### Requirement: Honest sign-out
Sign-out MUST stop local credential use, cancel pending login, and invalidate management sessions while reporting unconfirmed remote revocation honestly.

#### Scenario: Revocation network failure
- **WHEN** remote revocation cannot be confirmed
- **THEN** local sign-out still takes effect with that limitation displayed

### Requirement: Account cache isolation
Account, session, CSRF, and OAuth responses MUST use no-store and MUST NOT enter Service Worker or offline caches.

#### Scenario: Cached shell opens offline
- **WHEN** a saved page opens without host connectivity
- **THEN** it cannot replay cached account state as current or execute account mutations
