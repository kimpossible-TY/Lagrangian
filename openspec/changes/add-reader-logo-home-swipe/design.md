## Design

The HTML Reader recognizes shared mode from the server's `/d/<id>/` document route; its origin root `/` is the shared Homepage. The standalone Reader is served at `/` and has no Homepage, so it exposes neither navigation nor the link. The terminal presentation uses this same HTML Reader; terminal hosts can forward mouse pointer events instead of touch.

A single pointer state machine arbitrates the 500 ms hold and width-based swipe; movement beyond 10 CSS pixels cancels the hold, and a completed hold excludes a subsequent swipe. The adapter shows a filling ring, press scale and brief confirmation before navigation, with optional vibration. Reduced motion uses a static held indicator without animation or scaling. Cancellation resets feedback. Click opens the status popover, which contains a Homepage link and refresh button; Shift+Enter also refreshes. Standalone has no home gesture. Registered `/p/<id>/` previews use a different frontend with no logo and are unaffected.
