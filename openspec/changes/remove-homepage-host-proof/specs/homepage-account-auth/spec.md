# Homepage Account Authentication Spec Delta

## ADDED Requirements

### Requirement: Loopback login and logout without host proof
Homepage login without registration selection and logout MUST accept scoped OAuth or management CSRF without host proof after every local request guard passes. This capability owns that policy, superseding only the blanket proof gate in `unify-homepage-reader`'s reader-host “Local capability authority on a shared origin” requirement and borrowed-session scenario. All other authority gates remain.

#### Scenario: Local login without host proof
- **WHEN** a genuine admin-loopback visitor clicks Continue with ChatGPT without unlocking management and all independent request guards pass
- **THEN** an OAuth-only session supplies CSRF and login start returns an OpenAI authorization URL with PKCE challenge, state and nonce
- **AND** the browser proceeds directly to that validated OpenAI URL without another login-link click
- **AND** the rotated session retains no management authority and credentials remain server-side

#### Scenario: Local logout without host proof
- **WHEN** a genuine admin-loopback visitor submits logout with an OAuth-only session and matching CSRF and all independent request guards pass
- **THEN** local sign-out proceeds without host proof and invalidates all browser sessions
- **AND** history and drafts are preserved and remote revocation uncertainty remains visible

#### Scenario: OAuth response validation remains mandatory
- **WHEN** an OAuth callback has invalid state or nonce, or the token exchange fails PKCE verification
- **THEN** authentication fails without establishing an authenticated account
- **AND** omitting host proof for login start does not bypass these protocol checks

### Requirement: Single consent navigation owner
Homepage MUST suppress the server-side browser opener and navigate its current browser exactly once to the validated OpenAI authorization URL. Default terminal ChatAuth callers MUST retain their configured opener. ChatAuth MUST remain the sole credential owner and retain PKCE, state and nonce validation.

#### Scenario: Production Homepage starts consent
- **WHEN** Homepage starts login with production ChatAuth and a configured system opener
- **THEN** the server returns the authorization URL without invoking the opener and home.js navigates once
- **AND** a terminal caller using ChatAuth.login defaults still invokes that opener once

### Requirement: Independent local request guards
OAuth session creation, login start and logout MUST enforce the exact admin Host allowlist, exact Origin and actual admin-loopback socket peer, rejecting proxy ingress and Forwarded or X-Forwarded-* headers. Login start and logout MUST also require an unexpired browser session and matching session-bound CSRF. All guards MUST apply independently of host proof and fail before authentication effects.

#### Scenario: Host allowlist remains enforced
- **WHEN** an actual admin-loopback caller requests an OAuth session, login start or logout with a Host outside the exact admin allowlist, even with otherwise valid proofs
- **THEN** the server returns 421 without issuing an OAuth session or invoking a ChatAuth mutation

#### Scenario: Origin remains mandatory
- **WHEN** an OAuth session request, login start or logout has an absent or forged Origin even though its Host and socket peer are valid
- **THEN** the server returns 403 without issuing an OAuth session or invoking a ChatAuth mutation

#### Scenario: Forwarding and proxy ingress are rejected
- **WHEN** an OAuth session request, login start or logout arrives through proxy ingress or includes Forwarded or X-Forwarded-* headers, even with a loopback socket peer and valid Host, Origin and proofs
- **THEN** the server returns 403 without issuing an OAuth session or invoking a ChatAuth mutation

#### Scenario: Claimed loopback does not replace the socket peer
- **WHEN** a non-loopback socket peer submits an OAuth session request, login start or logout with a loopback Host and otherwise valid proofs
- **THEN** the server returns 403 without issuing an OAuth session or invoking a ChatAuth mutation

#### Scenario: Session and CSRF guards remain enforced
- **WHEN** login start or logout has a missing or expired session, or missing or mismatched CSRF, even though all local request guards and host proof are valid
- **THEN** the operation fails without authentication effects

### Requirement: Explicit OAuth-only browser session scope
An eligible local caller MUST explicitly request an OAuth-only session to obtain scoped CSRF without host proof, authorizing only login without registration selection and logout. Read-only and remote session requests MUST NOT gain OAuth or management authority. OAuth requests MUST NOT rotate or evict management sessions. OAuth sessions MUST retain ingress/origin binding, expiry, protected cookies and restart invalidation; rotation MUST preserve the initiating token's scope.

#### Scenario: Explicit session scope
- **WHEN** an eligible local caller explicitly requests an OAuth session without host proof
- **THEN** it receives session-bound CSRF for login without registration selection and logout only
- **AND** the session cannot authorize cancel, account selection or privileged account status

#### Scenario: Read-only session requests preserve management sessions
- **WHEN** an ordinary read-only or remote visitor requests a browser session
- **THEN** the request grants no OAuth or management authority
- **AND** existing management sessions are neither rotated nor evicted

#### Scenario: Reload retains a management cookie without module-memory proof
- **WHEN** an eligible local page retains a management cookie but has lost host proof and CSRF and explicitly requests an OAuth session
- **THEN** it receives a separate OAuth-only CSRF token bound to that cookie without rotating or evicting the management handle or revealing or changing its management CSRF
- **AND** the first login without registration selection or logout succeeds with that OAuth token after all request guards pass
- **AND** the token cannot authorize cancel or registration selection even with host proof; login rotation remains OAuth-only and normal credential invalidation remains in force

#### Scenario: OAuth session lifetime and binding
- **WHEN** an OAuth-only session is reused after expiry or server restart, or from a different ingress or origin
- **THEN** it cannot authorize login start or logout
- **AND** legitimate session rotation retains OAuth-only authority and cookie protections

### Requirement: Management operations retain host proof
Cancel, account selection (login with a nonempty registration) and other management operations MUST require current host proof, a management session and every local request guard. Management mutations MUST require management-scoped CSRF and reject unauthorized selection before ChatAuth.login. OAuth CSRF MUST NOT grant management authority. GET account without both valid proof and management session MUST return 200 sanitized public fallback without identity details.

#### Scenario: Shared-origin caller borrows a management session
- **WHEN** a same-origin caller has a management cookie and matching CSRF but lacks the current host proof
- **THEN** cancel, account selection and other privileged management operations return 403
- **AND** GET account returns 200 sanitized public fallback without disclosing account identity details
- **AND** only login start without registration selection and logout are permitted when all independent local request and CSRF checks pass

#### Scenario: Host proof does not promote an OAuth-only session
- **WHEN** a local caller attempts cancel, account selection or privileged account status with host proof but only an OAuth-only session
- **THEN** cancel and account selection return 403 before any ChatAuth mutation
- **AND** GET account returns 200 sanitized public fallback without disclosing account identity details

#### Scenario: Local management retains its existing authorization
- **WHEN** a genuine admin-loopback caller submits cancel or another management mutation with the current host proof, a valid management session and matching CSRF and passes all request guards
- **THEN** the operation is authorized through the management path

### Requirement: Remote and tailnet Homepage remains status-only
Remote, tailnet and proxied Homepage visitors MUST retain only read-only public account status, with no login, logout or management unlock controls and no privileged account identity details. Their OAuth session creation, login start, logout, cancel and other privileged management requests MUST return 403 even with copied host proof, browser cookies and CSRF. A loopback proxy socket MUST NOT grant local authority to a remote or tailnet visitor.

#### Scenario: Remote or tailnet Homepage
- **WHEN** a remote, tailnet or proxied visitor loads the Homepage
- **THEN** the account area remains status-only with no login, logout or unlock controls
- **AND** public status exposes no privileged account identity details

#### Scenario: Remote credential mutation with copied proofs
- **WHEN** a remote, tailnet or read-only proxy caller submits OAuth session creation, login start, logout, cancel or another privileged management request with valid copied host proof, cookie and CSRF
- **THEN** the server returns 403 without granting mutation authority, invoking a ChatAuth mutation or disclosing privileged account status
