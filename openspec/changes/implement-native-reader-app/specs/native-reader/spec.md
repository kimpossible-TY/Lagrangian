# Spec Delta

## Purpose

Provide a loss-aware native reading document and guarded interaction contract while retaining existing compiler, source, conversation and authentication authority.

## ADDED Requirements

### Requirement: Ordered semantic snapshots
The reader SHALL retain accepted section order, exact Unicode scalars, headings, styles, links, mathematical structure and numbering, table cells and spans, figure assets and labels, and annotation anchors. Unsupported meaning SHALL reject the candidate with a bounded diagnostic instead of silently replacing content.

#### Scenario: Import an accepted compiler document
- **WHEN** an accepted document crosses transport section boundaries
- **THEN** native nodes retain logical order and distinct repeated-paragraph identities
- **AND** mathematical, tabular and graphical semantics remain available independently of paint support

#### Scenario: Preserve Unicode and mapping uncertainty
- **WHEN** composed, decomposed, supplementary or joined characters are imported
- **THEN** exact scalar sequences and explicit UTF8/codepoint/UTF16 maps are preserved
- **AND** selection uses extended grapheme boundaries and source correspondence remains explicitly unmapped until the source owner verifies it

#### Scenario: Unknown semantics or capability
- **WHEN** a candidate contains an unknown required capability, unsupported element, duplicate anchor or invalid offset
- **THEN** the whole candidate is rejected without replacing accepted content

### Requirement: Guarded native operations
Native operations SHALL bind document, service, revision, view, generation and selection ticket. Local correlation SHALL NOT replace server freshness, authorization or durable receipts. Source, chat, authentication and service lifecycle SHALL retain their existing owners.

#### Scenario: Late result or selected content
- **WHEN** a cancelled generation completes, another view responds, or replacement arrives during a held selection
- **THEN** the accepted native document remains unchanged
- **AND** acknowledgment for an old ticket cannot release a newer selection

#### Scenario: Uncertain mutation
- **WHEN** a source highlight or explicit chat Send loses its response after dispatch
- **THEN** its effect remains unknown and recovery queries the existing owner without automatically repeating the mutation

### Requirement: Native object evidence remains bounded
The reader SHALL distinguish object calculation, native paint, semantic fidelity, inline breaking, accessibility and GUI verification. Missing local helper dependencies SHALL remain blocked. Placeholder or PDF-only output SHALL NOT establish complete native reading support.

#### Scenario: Existing compiler object probe
- **WHEN** actual compiler SVG or PDF is decoded and painted on the host
- **THEN** evidence records compiler inputs, widths, primitives, native paint outcome and command exits
- **AND** untested formula fidelity, runtime compatibility, selection and accessibility remain explicit gates

### Requirement: Loss-aware image layout negotiation
Schema-1 snapshots SHALL preserve effective compiler image dimensions and units,
intrinsic aspect behavior, inline/block placement and validated loading/decoding
hints in typed image metadata. Snapshots using this meaning SHALL dynamically
require image-layout-v1. Unsupported CSS, units, values or incomplete metadata
SHALL reject atomically through import, transport and generic recovery decoding.

#### Scenario: Actual raw compiler image and labeled vector
- **WHEN** accepted compiler HTML includes sized PNG/JPEG images or symbol overflow
- **THEN** original attributes and digest-bound assets remain preserved
- **AND** native paint uses effective authored dimensions and inline/block order
- **AND** SVG visible/hidden symbol overflow retains the existing painter's clip semantics
- **AND** glyph paths do not acquire invented label-level source or accessibility text

#### Scenario: Old client and cached supplemented snapshot
- **WHEN** a semantic-tree-v1-only client requests a supplemented document, asset or action
- **THEN** the server explicitly rejects unsupported required capability even on a cache hit
- **AND** an old document without new meaning remains available to old and new clients

#### Scenario: Restore and rebind an image document
- **WHEN** a complete snapshot passes through HTTP, Codable disk recovery, session candidate or host fixture generation rebinding
- **THEN** every image supplement and required capability remains identical
- **AND** unknown fields, missing required metadata or invalid combinations fail without replacing accepted content

#### Scenario: A hidden symbol has distinct native instances
- **WHEN** hidden symbols use different viewports, viewBox origins, aspect alignment, transforms or nested clip references
- **THEN** the sole native SVG owner preserves each viewport clip with exact native pixel-mask evidence
- **AND** generated safe serialization retains reference identity without duplicate content IDs
- **AND** it revalidates generated nodes, depth, work and composed transforms before native decode
- **AND** unresolvable symbol viewport sizes are explicitly unsupported

#### Scenario: Compiler emits a base64 SVG image
- **WHEN** newly compiled accepted HTML carries a supported SVG base64 data image
- **THEN** the importer validates strict encoding, size, SVG references and content before publication
- **AND** original SVG asset bytes and authored image layout survive HTTP, recovery and native paint


### Requirement: Retained native presentation survives rejected work
The native reader SHALL separate retained layout authority from current request generation, preserve accepted body/selection/accessibility during held reflow, and reject stale geometry/source operations. Fallible candidate composition SHALL preserve the previously painted publication. Explicit close SHALL permit safe same-profile reopening without stale callbacks.

#### Scenario: Reflow while a newer candidate is held
- **WHEN** a new request completes while the accepted document is selected and layout inputs change
- **THEN** current-key preparation restores the retained document's native layout without adopting the pending candidate
- **AND** source operations continue rejecting stale/pending contexts until explicit release and fresh adoption

#### Scenario: Rejected candidate or closed selected window
- **WHEN** candidate B has missing/invalid object preparation after A was painted
- **THEN** A remains the published native body and accessibility document
- **WHEN** the user explicitly closes a selected window and reads the same profile again
- **THEN** the new request can complete and old close/cancel callbacks cannot cancel it

### Requirement: Local display selection and remote submission have distinct bounds
Ordinary native selection, hold, plain copy and accessibility selection SHALL support all accepted document blocks. Source/chat submission SHALL retain the existing 32-fragment and payload limits. Over-limit submission SHALL reject explicitly without copying or submitting an earlier short selection.

#### Scenario: Select a long document
- **WHEN** a user selects 32, 33 or 100 blocks through native range, Select All, drag, Shift or accessibility operations
- **THEN** plain copy and accessibility retain the exact full selected text
- **AND** more than 32 source/chat fragments are rejected before dispatch without releasing the display selection

### Requirement: Lost Send recovery uses identical actor and UI evidence
Authoritative history SHALL confirm a pending Send only when UUID, user role and exact stored content match. Confirmation SHALL permit a new message UUID/question. Missing/mismatched content SHALL permit only an explicit original UUID/question/model retry. Recovery SHALL never automatically send, and acknowledgment SHALL preserve newer private drafts.

#### Scenario: Confirm or retain an uncertain Send
- **WHEN** history contains the exact pending user message
- **THEN** adapter and UI clear the unknown state and allow a fresh explicit question
- **WHEN** history omits it or its role/content differs
- **THEN** a new UUID/question remains blocked and only the original explicit retry is permitted

#### Scenario: Recover through an explicit native control
- **WHEN** a pending Send blocks Send or a stream disconnects
- **THEN** the native Refresh conversation control permits an explicit read without inference or retransmission
- **AND** busy, cancelled, disposed, superseded, unauthorized or older history cannot clear pending state
- **AND** an absent conversation is reported as unavailable rather than completed
- **AND** recovery preserves the original bounded pending question/model separately from a newer local draft, with optional defaults for old snapshots

### Requirement: Block image placement reaches final native text layout
A supported block image SHALL have presentation line boundaries before and after its final TextKit attachment. These added boundaries SHALL NOT enter canonical/source text, plain copy or logical accessibility offsets. Inline images SHALL preserve inline placement when space permits.

#### Scenario: Prose surrounds a block or inline image
- **WHEN** an accepted paragraph contains before, image and after content
- **THEN** final native glyph line fragments place block image content on three ordered lines
- **AND** the inline control remains on one line while both preserve exact logical selections/copy/AX text

### Requirement: Original pages preserve reflow authority boundaries
Original PDF display SHALL compose the existing canonical store and prepared adoption. Display-only PDF text/bounds and offline PDF recovery SHALL NOT grant semantic source/chat authority. Hidden mode preparation or paint SHALL NOT acknowledge visible-mode Read success. Native reflow's retained layout and fresh source-operation guards SHALL remain intact.

#### Scenario: Enter original mode and return to reflow
- **WHEN** the reader switches between original pages and native reflow
- **THEN** each mode owns its geometry/selection and only its visible actual draw acknowledges paint
- **AND** source actions in original mode are explicitly unsupported while validated reflow actions keep their original path
