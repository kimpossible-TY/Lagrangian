## Why
Readers need to understand the current status without accidentally refreshing or losing their place.

## What Changes
- Show the current localized status in a dismissible popover on logo activation.
- Label a waiting-update action as applying an update, and otherwise label it refresh.
- Move refresh or waiting-update application to a long press or Shift+Enter, preserving the selection-held guard.

## Capabilities
### Modified Capabilities
- `reader-status-logo`: Status explanation and deliberate refresh interaction.

## Impact
HTML reader logo presentation, interaction and browser tests. Activity state ownership remains unchanged.
