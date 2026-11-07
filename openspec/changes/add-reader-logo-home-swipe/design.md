## Design

The HTML Reader recognizes shared mode from the server's `/d/<id>/` document route; its origin root `/` is the shared Homepage. The standalone Reader is served at `/` and has no Homepage, so it exposes neither navigation nor the link. The terminal presentation uses this same HTML Reader; terminal hosts can forward mouse pointer events instead of touch.

A pure single-pointer classifier applies the width-based distance and horizontal direction thresholds. The status logo adapter captures pointer input, cancels the existing refresh timer on movement, suppresses the subsequent click, and navigates on completion. Reduced motion removes the visual follow and spring. The existing click continues to toggle the status popover; a real link in that popover provides keyboard access. The existing 500 ms long press and Shift+Enter continue to invoke refresh. Registered `/p/<id>/` previews use a different frontend with no logo and are unaffected.
