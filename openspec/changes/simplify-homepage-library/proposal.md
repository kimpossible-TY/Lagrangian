# Proposal

## Why

The Homepage obscures document selection with introductory and operational content. A compact library makes opening a document the primary task while retaining account management.

## What Changes

- Present searchable documents with one safe preferred reader link and optional alternatives.
- Move appearance, account and service information into accessible settings; preserve account links and authority.
- Remove the Homepage Tail Dashboard entry.

## Capabilities

### New Capabilities
- `homepage-library`: Document selection and settings on the shared Homepage.

### Modified Capabilities
- `chat-ui-dashboard-card`: Remove the Homepage dashboard entry proposed by the active change; its chat requirements remain intact.

## Impact

Homepage HTML, CSS, JavaScript, tests and Reader documentation change. Existing APIs, shared theme and authentication boundaries remain unchanged.
