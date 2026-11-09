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

### Requirement: One primary pointer owns the gesture
A gesture SHALL start only from a primary pointer pressing the primary button on the logo. Other buttons SHALL NOT start, extend or cancel it under the same pointer ID; a pointerdown from a different pointer ID SHALL cancel an uncommitted gesture whatever its button. Classification: [`logo-home-swipe.js`](../../../../../tools/flow-reader/web/features/navigation/logo-home-swipe.js); effects: [`status-logo.js`](../../../../../tools/flow-reader/web/features/session/status-logo.js).

#### Scenario: Gesture start input
- **WHEN** a non-primary pointer or a button other than the primary one presses the logo with no gesture in progress
- **THEN** no gesture starts from that input

#### Scenario: Same pointer ID keeps the gesture
- **WHEN** another button presses with the same pointer ID while a gesture is uncommitted
- **THEN** the press neither extends the gesture nor cancels it

#### Scenario: Different pointer ID cancels the gesture
- **WHEN** a pointerdown from a different pointer ID lands inside or outside the logo while a gesture is uncommitted
- **THEN** the uncommitted gesture is cancelled without navigation

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
A 500 ms hold SHALL commit only when its scheduled callback runs while the pointer is still in the valid pressing state, and commitment SHALL show confirmation feedback for 100 ms before the adapter navigates. A qualifying swipe SHALL be a separate contract that navigates at pointer release without the hold timer and without that confirmation. A leftward or predominantly vertical movement SHALL NOT complete a swipe.

#### Scenario: Hold home
- **WHEN** a reader holds the shared logo for 500 ms without moving more than 10 CSS pixels
- **THEN** the progress indicator and confirmation precede Homepage navigation, with vibration where supported

#### Scenario: Reduced motion
- **WHEN** the reader prefers reduced motion and holds the logo
- **THEN** a static held indicator replaces the ring animation and the press scale

### Requirement: Hold cancellation leaves swipe completion intact
Movement more than 10 CSS pixels from the press point SHALL cancel only the hold confirmation and hold-triggered navigation; the same gesture SHALL still navigate at pointer release when its swipe qualifies. An early release SHALL end that gesture without navigation, and a separate qualifying swipe SHALL still navigate at its own release.

#### Scenario: Slop cancels only the hold
- **WHEN** the pointer moves more than 10 CSS pixels and then completes a qualifying swipe before release
- **THEN** the Homepage navigation occurs at that release without hold confirmation

#### Scenario: Early release leaves a later swipe available
- **WHEN** the pointer releases before the hold commits
- **THEN** that gesture does not navigate and a later qualifying swipe still navigates at its own release

### Requirement: Gesture termination and committed navigation
A `pointercancel` or a pointerdown from a different pointer ID SHALL end an uncommitted gesture without navigation, and later gestures SHALL remain available. After commitment, release, cancellation, movement and later pointers SHALL NOT revoke the scheduled navigation; disposing the logo SHALL clear the scheduled navigation.

#### Scenario: Pointer cancellation ends the gesture
- **WHEN** `pointercancel` or a pointerdown from a different pointer ID occurs before commitment
- **THEN** the gesture ends without navigation

#### Scenario: Committed hold is not revoked
- **WHEN** the pointer releases, is cancelled, moves or is joined by another pointer after the hold committed
- **THEN** the scheduled Homepage navigation still occurs

#### Scenario: Disposal clears a committed navigation
- **WHEN** the status logo is disposed while a Homepage navigation is scheduled
- **THEN** the scheduled navigation does not occur
