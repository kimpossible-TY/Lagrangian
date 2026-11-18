## ADDED Requirements

### Requirement: Reusable cream native chrome
The macOS app SHALL provide reusable AppKit chrome components for cream paper,
readable ink, solid panels, indigo actions, spacing, restrained rounded strokes,
chrome typography and focus/hover/pressed/disabled feedback on macOS 13 and later.
Components SHALL preserve NSButton semantic activation, native keyboard/focus and
accessibility contracts. Paint SHALL NOT dispatch actions or change target/action.

#### Scenario: Native activation and interrupted feedback
- **WHEN** a common control is clicked, activated by keyboard, disabled, canceled or rapidly activated again
- **THEN** AppKit retains command delivery and feedback returns without duplicate commands or stuck press state
- **AND** a native focus indicator remains available independently of hover

#### Scenario: Preference and multilingual presentation
- **WHEN** chrome uses light/dark, increased contrast, reduced transparency or reduced motion
- **THEN** text, selection, boundaries, focus and state feedback remain readable on an opaque baseline
- **AND** native fallback supports Korean, decomposed Unicode and symbols without changing document typography

### Requirement: Exact native brand vector
Native branding SHALL reuse the original three logo paths and 240 by 220 viewBox
from svg.reader-logo-mark, preserve round caps/joins and base/halo/beam hierarchy,
and scale uniformly without substituting a newly drawn mark or raster app icon.
Native status alternatives SHALL remain low-motion and SHALL NOT imply readiness.

#### Scenario: Idle, busy and accessible logo states
- **WHEN** the native mark renders an idle, busy, offline, error or held state
- **THEN** its exact original cubic path and source stroke hierarchy are preserved
- **AND** reduced motion removes decorative moving-layer equivalents, with solid high-contrast alternatives and separate status semantics

### Requirement: Staged native design evidence
Design implementation SHALL distinguish source-component tests, screen adoption,
source registration, packaged delivery and actual GUI acceptance. New Swift sources
SHALL be explicitly compiled by component tests until the packaging owner registers
them. Existing product and accepted operation contracts SHALL remain authoritative.

#### Scenario: NA18 source-only handoff
- **WHEN** common components pass their focused offscreen tests
- **THEN** evidence binds actual compiler inputs and exact committed source
- **AND** home/settings/reader/chat adoption, capsule behavior, packaging and GUI remain pending their separate stages
