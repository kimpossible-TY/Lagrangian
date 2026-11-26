## ADDED Requirements

### Requirement: First-click compact cross-project preview
The first click on a uniquely resolved cross-project reference SHALL show a compact preview without navigating. The preview SHALL use NativeAppDesign floating styling, header `projectTitle · referenceText` and a snippet. Its interactive icon-only NativeDesignButton SHALL use identifier `crossProjectPreview.open`, empty visible title, SF Symbol `arrow.up.right`, tooltip and accessibility label `해당 문서로 이동`, and SHALL NOT display `열기` text.

#### Scenario: Inspect and activate the preview
- **WHEN** the user first clicks a cross-project reference
- **THEN** the preview appears without replacing the current document
- **WHEN** the user next clicks the preview body or its arrow.up.right icon
- **THEN** onOpenTarget emits the same preview content for navigation to the target project and anchor

#### Scenario: Compose the shared floating surface
- **WHEN** the native preview is created
- **THEN** NativeCrossProjectPreviewView is an NSView embedding an exposed NativeDesignSurface child with role .floating
- **AND** NativeAppDesign supplies palette, typography, spacing and shape using the current shared NativeAppDesign implementation

### Requirement: Cross-project back-navigation stack
Committed jumps SHALL preserve complete origin locations on a bounded stack, default depth 64 with oldest-first eviction. Back SHALL restore through existing reader operations with fixed action label `돌아가기`. New Read/profile selection SHALL reset history; empty profileID origins SHALL NOT enter it. Peek/pop/canGoBack/backLabel SHALL reflect retained origins.

#### Scenario: Jump, return and overflow
- **WHEN** a second-click jump commits from project A to project B
- **THEN** A's complete location is retained and the reader offers `돌아가기`
- **WHEN** Back succeeds
- **THEN** A and its saved location are restored and the entry is popped
- **AND** failed navigation leaves the previous document and stack unchanged
- **WHEN** pushes exceed capacity
- **THEN** the oldest entries are discarded while the most recent return locations remain available

#### Scenario: New session or deleted origin
- **WHEN** the user starts a new explicit Read or selects a profile
- **THEN** canGoBack is false for the new session
- **WHEN** the top Back profile was deleted or no longer uniquely matches
- **THEN** Back discards it and tries the next available origin

#### Scenario: Inspect empty and retained history
- **WHEN** history is empty
- **THEN** pop returns nil and canGoBack is false
- **WHEN** an origin is retained
- **THEN** peek and backLabel expose it without removal, while pop removes it

### Requirement: Explicit HTML metadata and projects.json fallback
HTML references SHALL prefer `data-project-ref-project` and `data-project-ref-label` identity, with `data-project-ref-text` and `data-project-ref-title` display metadata. Links lacking identity SHALL use schema-1 projects.json fallback for `pdf_url#page=N`, filtered by page and display text. Resolution SHALL distinguish unique, ambiguous and unresolved targets without guessing duplicate labels. Unsupported schemas and oversized catalogs SHALL fail before adoption.

#### Scenario: Metadata or legacy PDF link
- **WHEN** a link supplies data-project-ref-* identity
- **THEN** the explicit key and label are resolved before any PDF fallback
- **WHEN** explicit identity is absent and a PDF URL/page/display text matches exactly one catalog reference
- **THEN** that reference is offered for preview
- **AND** display text matches entry.text or `entry.text + ' of ' + title`
- **WHEN** multiple targets remain, or the explicit label is declared ambiguous
- **THEN** navigation remains unavailable until ambiguity is resolved

### Requirement: Preview may start the target reader service
First-click snippet loading MAY start the target project's managed reader service through the existing manager. It SHALL preserve the origin document and position, and failure SHALL retain the catalog snippet. Closing the preview client SHALL NOT stop the shared reader service.

#### Scenario: Preview a stopped target project
- **WHEN** the user clicks a uniquely resolved reference whose target reader service is stopped
- **THEN** snippet loading may start that service and fetch its accepted native document
- **AND** the origin reader stays current until a second-click navigation commits

### Requirement: Provisional editor consent during project navigation
Candidate creation SHALL reserve only the target editor descriptor. Reader consent tracking SHALL commit at windowInitialized, preserving the origin's tracking before that point. Failed or cancelled candidates SHALL return the descriptor to consentedEditors.

#### Scenario: Candidate fails or is cancelled
- **WHEN** a target with existing editor consent fails to initialize or its navigation is cancelled
- **THEN** the target's consent remains available for a later attempt
- **AND** the origin reader and its editor consent tracking remain intact

### Requirement: Native explicit-reference wire and failure policy
Native link nodes MAY carry projectRef with non-empty project/label and optional title/page/text. Invalid metadata SHALL raise invalid-project-ref and duplicate anchors SHALL raise duplicate-anchor atomically. There is no separate projectRef capability; app and backend SHALL be delivered together for strict decoders. Explicit ambiguous identities SHALL suppress navigation; unresolved identities SHALL only open their original safe external URL, without guessing a catalog target from it.

#### Scenario: Explicit identity cannot resolve
- **WHEN** an explicit identity is ambiguous
- **THEN** activation is suppressed
- **WHEN** it is unresolved or the catalog cannot load
- **THEN** only the original URL may open under the existing external safety policy
- **AND** fragment-only or unsafe URLs have no external effect

### Requirement: Preserve user labels in HTML export
The HTML producer SHALL export labels on headings, figures and equations as data-flow-label wrappers, excluding private annotation/scope prefixes. Normalization SHALL transfer missing id/label attributes from a label-only single-child wrapper while retaining existing child attributes. Section/native export SHALL retain user label anchors independently of DOM ids and preserve the first exported label anchor on id collision.

#### Scenario: Export and normalize labeled content
- **WHEN** a heading, figure or equation has a user label
- **THEN** HTML export carries that label through data-flow-label and the normalized section/native anchor set
- **AND** private flow-native-annotation-, local-scope-, mannot-scope- and _mannot- labels are excluded
- **AND** an eligible wrapper transfers only attributes absent from its child
