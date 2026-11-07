## ADDED Requirements

### Requirement: Paragraph chat summary converts math delimiters to plain text
The collapsed paragraph conversation summary SHALL convert raw LaTeX math delimiters to plain text and render content safely using textContent or safe DOM nodes without injecting raw HTML.

#### Scenario: Collapsed summary with LaTeX math
- **WHEN** a paragraph conversation contains inline or block math delimiters
- **THEN** the collapsed summary button displays the expression in plain text without raw delimiters or HTML injection.

### Requirement: Chosen model is preserved per conversation
The paragraph conversation composer SHALL retain the user's chosen model across message transmissions and conversation switches. If the available model list refreshes and the chosen model is no longer present, the selection SHALL fall back to empty and disable sending until a valid model is chosen.

#### Scenario: Follow-up question keeps model
- **WHEN** a user completes sending a question with a chosen model
- **THEN** the composer retains that chosen model for follow-up questions.

#### Scenario: Model list removes chosen model
- **WHEN** the available model list refreshes and excludes the previously chosen model
- **THEN** the selection falls back to empty and the send button is disabled.

### Requirement: Homepage provides Tail Dashboard entry panel
The Homepage aside SHALL provide an entry card linking directly to the Tail Dashboard URL with `rel="noopener"`.

#### Scenario: Navigating to Tail Dashboard
- **WHEN** a user views the Homepage aside panels
- **THEN** the Tail Dashboard entry card is presented with a standard hyperlink to the configured dashboard URL.
