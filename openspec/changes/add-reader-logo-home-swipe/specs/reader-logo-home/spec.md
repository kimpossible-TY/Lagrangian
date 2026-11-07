## ADDED Requirements

### Requirement: Shared Reader logo navigates home
The shared HTML Reader SHALL navigate to the Homepage at the origin root when a single primary pointer swipes the logo right by at least the smaller of 60 CSS pixels and 40 percent of the logo width, with horizontal displacement greater than twice the vertical displacement. Cancelled, leftward and vertical gestures SHALL NOT navigate. The standalone Reader SHALL NOT expose Homepage navigation. The paged preview frontend SHALL remain unchanged.

#### Scenario: Swipe home
- **WHEN** a reader completes the qualifying rightward swipe on a shared Reader logo
- **THEN** the browser navigates to the shared Homepage without opening the status popover or refreshing

#### Scenario: Accessible home link
- **WHEN** a keyboard user opens the shared Reader logo's status popover
- **THEN** a focusable Homepage link is available and Enter follows it

#### Scenario: Standalone Reader
- **WHEN** a reader uses the logo on a standalone Reader
- **THEN** no Homepage link or swipe navigation is available

#### Scenario: Existing status and refresh controls
- **WHEN** a reader clicks the logo or invokes its existing long press or Shift+Enter
- **THEN** click toggles the status popover and the refresh controls retain their existing behavior
