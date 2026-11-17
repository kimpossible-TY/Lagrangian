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
