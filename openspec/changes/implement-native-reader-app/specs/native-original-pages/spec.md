## ADDED Requirements

### Requirement: Accepted immutable PDF publication
The server SHALL reuse AcceptedSnapshot and Project.execute for PDF compilation, bind accepted HTML and stable additional PDF dependencies to service/document/revision/input/incarnation/sequence and PDF bytes, and compile outside the publication lock. Failed or stale candidates SHALL retain the previous publication. Byte echoes SHALL NOT establish publication authority.

#### Scenario: Saved input changes without visual changes
- **WHEN** stable saved input changes while generated HTML/PDF bytes remain identical
- **THEN** a new input binding and monotonic publication sequence are accepted
- **AND** resources from stale inputs and obsolete service incarnations are rejected

### Requirement: Scoped full-PDF native transport
Manifest/resource routes SHALL retain existing Host/Origin/registered-prefix validation, exact native identities, capabilities and budgets. Swift SHALL validate the publication envelope and exact immutable resource before native preparation. This implementation SHALL identify immutable PDF full reset separately from the unverified engine raw diff-v1 native consumer.

#### Scenario: Tampered or replayed result
- **WHEN** resource bytes, target identity, input, incarnation or ordered sequence differ from the current request
- **THEN** transport rejects the result and leaves the accepted view intact

### Requirement: Separate native display modes and receipts
Native reflow and original PDF pages SHALL use the canonical semantic store and PreparedAdoption while retaining separate geometry, selection and copy meaning. Only actual paint in the visible mode SHALL acknowledge Read. Held page selection SHALL defer replacement until explicit release; cancellation/disposal SHALL reject late callbacks.

#### Scenario: Hidden reflow or failed candidate
- **WHEN** reflow draws while original pages are visible or candidate preparation fails
- **THEN** hidden paint cannot acknowledge the original-page Read
- **AND** the previously accepted page, selection and viewport remain

### Requirement: Bounded lazy original pages
The implementation SHALL prepare geometry without eagerly rasterizing all pages, bound raster/text/search caches and results, evict unused entries and support cancellation. Verification SHALL use at least 256 actual compiler pages and record render count, cache bytes and RSS. Bounds exceeded SHALL be explicit unsupported/budget failures.

#### Scenario: Navigate and recover a far page
- **WHEN** an accepted 256-page document navigates, searches, zooms and recovers near its final page
- **THEN** only requested page rasters are prepared and bounded caches evict earlier entries
- **AND** recovery is tied to the same accepted identity/input/PDF digest and remains read-only offline

### Requirement: Explicit safe actions and source limits
PDF URI/GoTo actions SHALL become inert validated data activated only by explicit native callbacks. JavaScript/forms/launch/embedded/remote/unknown actions SHALL NOT execute. PDF text/bounds SHALL NOT authorize Typst source ranges. Source actions SHALL be unsupported without an actually verified same-artifact owner anchor; page mode SHALL NOT submit hidden reflow selections.

#### Scenario: Link or source command
- **WHEN** a safe credential-free URI or same-artifact finite in-range GoTo is explicitly activated
- **THEN** only the corresponding native callback runs
- **WHEN** a page source action lacks verified compiler-owner anchors
- **THEN** it reports unsupported without estimating source from text, coordinates or Rust API existence
