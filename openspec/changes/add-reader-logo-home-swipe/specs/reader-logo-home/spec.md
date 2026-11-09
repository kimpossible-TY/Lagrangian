## ADDED Requirements

### Requirement: Shared Reader logo navigates home
On a `/d/<id>/` document route the shared HTML Reader SHALL navigate to the Homepage at the origin root `/` when a single primary pointer pressing the primary button holds for 500 ms or swipes the logo right by at least the smaller of 60 CSS pixels and 40 percent of the logo width, with horizontal displacement greater than twice the vertical displacement.

#### Scenario: Swipe home
- **WHEN** a reader releases a qualifying rightward swipe on a shared Reader logo
- **THEN** the browser navigates to the shared Homepage without opening the status popover or refreshing

#### Scenario: Existing status and refresh controls
- **WHEN** a reader clicks the logo or invokes Shift+Enter or the popover refresh button
- **THEN** click toggles the status popover and the refresh controls preserve their existing behavior

#### Scenario: Exclusive gestures
- **WHEN** a completed hold is followed by a swipe before release
- **THEN** only one home navigation occurs
- **WHEN** movement exceeds the hold slop before completion
- **THEN** the hold timer is cancelled and only a qualifying swipe can navigate

### Requirement: One primary pointer owns the gesture
A gesture SHALL require a single primary pointer pressing the primary button; other buttons SHALL NOT start or extend it and a competing pointer SHALL cancel a gesture that has not committed. Classification lives in [`logo-home-swipe.js`](../../../../../tools/flow-reader/web/features/navigation/logo-home-swipe.js) and the effects in [`status-logo.js`](../../../../../tools/flow-reader/web/features/session/status-logo.js).

#### Scenario: Competing input
- **WHEN** a non-primary or right-button press arrives, or a second pointer joins an uncommitted gesture
- **THEN** no gesture starts from that input and the uncommitted gesture is cancelled without navigation

### Requirement: Home navigation follows the shared route
The Homepage gesture and link SHALL be available only under `/d/<id>/`. The standalone Reader served at `/` SHALL NOT expose Homepage navigation, a hold, a swipe or the Homepage link. The terminal presentation runs this same HTML Reader, so it follows the route and the input the host forwards. The paged preview frontend SHALL remain unchanged.

#### Scenario: Accessible home link
- **WHEN** a keyboard user opens the shared Reader logo's status popover
- **THEN** a focusable Homepage link is available and Enter follows it

#### Scenario: Standalone Reader
- **WHEN** a reader uses the logo on a standalone Reader
- **THEN** no Homepage link, hold or swipe navigation is available

#### Scenario: Terminal presentation
- **WHEN** a terminal host forwards a hold or swipe to a shared Reader logo
- **THEN** the Homepage navigation matches the browser document's behavior

### Requirement: Hold commits before release and swipe at release
A 500 ms hold SHALL commit only while the pointer is still in the valid pressing state, and commitment SHALL show confirmation feedback for 100 ms before the adapter navigates. A qualifying swipe SHALL be a separate contract that navigates at pointer release without the hold timer and without that confirmation. A leftward or predominantly vertical movement SHALL NOT complete a swipe.

#### Scenario: Hold home
- **WHEN** a reader holds the shared logo for 500 ms without moving more than 10 CSS pixels
- **THEN** the progress indicator and confirmation precede Homepage navigation, with vibration where supported

#### Scenario: Reduced motion
- **WHEN** the reader prefers reduced motion and holds the logo
- **THEN** a static held indicator replaces the ring animation and the press scale

### Requirement: Cancellation has pre-commit and post-commit boundaries
Before commitment, an early release, pointer cancellation, movement more than 10 CSS pixels from the press point or a competing pointer SHALL cancel the hold without confirmation or navigation. After commitment, release, cancellation, movement and later pointers SHALL NOT revoke the scheduled navigation; disposing the logo SHALL clear the scheduled navigation.

#### Scenario: Cancelled before commitment
- **WHEN** the pointer releases early, is cancelled, moves more than 10 CSS pixels or loses to a competing pointer before the hold commits
- **THEN** no confirmation shows and no Homepage navigation occurs

#### Scenario: Committed hold is not revoked
- **WHEN** the pointer releases, is cancelled, moves or is joined by another pointer after the hold committed
- **THEN** the scheduled Homepage navigation still occurs

#### Scenario: Disposal clears a committed navigation
- **WHEN** the status logo is disposed while a Homepage navigation is scheduled
- **THEN** the scheduled navigation does not occur
