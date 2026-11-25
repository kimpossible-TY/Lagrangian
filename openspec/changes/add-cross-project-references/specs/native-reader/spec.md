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
- **AND** NativeAppDesign supplies palette, typography, spacing and shape without changes to NativeAppDesign.swift

### Requirement: Cross-project back-navigation stack
A successful cross-project jump SHALL preserve profileID, documentTitle, anchor, blockID and scrollOffset on a bounded back stack. Back SHALL restore the origin project and location through existing reader operations. The default depth SHALL be 64; overflow SHALL evict oldest entries. peek SHALL NOT remove entries and pop SHALL return nil for an empty stack. canGoBack and backLabel SHALL reflect the current origin entry.

#### Scenario: Jump, return and overflow
- **WHEN** a second-click jump commits from project A to project B
- **THEN** A's complete location is retained and the back label names A's document
- **WHEN** Back succeeds
- **THEN** A and its saved location are restored and the entry is popped
- **AND** failed navigation leaves the previous document and stack unchanged
- **WHEN** pushes exceed capacity
- **THEN** the oldest entries are discarded while the most recent return locations remain available

### Requirement: Explicit HTML metadata and projects.json fallback
HTML references SHALL prefer `data-project-ref-key` and `data-project-ref-label` identity, with `data-project-ref-text` and `data-project-ref-title` display metadata. Links lacking identity SHALL use schema-1 projects.json fallback for `pdf_url#page=N`, filtered by page and display text. Resolution SHALL distinguish unique, ambiguous and unresolved targets without guessing duplicate labels. Unsupported schemas and oversized catalogs SHALL fail before adoption.

#### Scenario: Metadata or legacy PDF link
- **WHEN** a link supplies data-project-ref-* identity
- **THEN** the explicit key and label are resolved before any PDF fallback
- **WHEN** explicit identity is absent and a PDF URL/page/display text matches exactly one catalog reference
- **THEN** that reference is offered for preview
- **AND** display text matches entry.text or `entry.text + ' of ' + title`
- **WHEN** multiple targets remain, or the explicit label is declared ambiguous
- **THEN** navigation remains unavailable until ambiguity is resolved
