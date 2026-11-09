## Design

The HTML Reader recognizes shared mode from the server's `/d/<id>/` document route; its origin root `/` is the shared Homepage. The standalone Reader is served at `/` and has no Homepage, so it exposes neither navigation nor the link. The terminal presentation runs this same HTML Reader document, so the gesture follows the route and the pointer events the host forwards. Registered `/p/<id>/` previews use a different frontend with no logo and are unaffected. Only a primary pointer pressing the primary (left) button on the logo starts a gesture: other buttons start and extend nothing, a further button press with the same pointer ID leaves that gesture alone, and a pointerdown from a different pointer ID cancels an uncommitted gesture whatever its button.

`logoGesture` and `logoHomeURL` in [`logo-home-swipe.js`](../../../tools/flow-reader/web/features/navigation/logo-home-swipe.js) own classification only: hold and swipe phases, the swipe thresholds, and the mutually exclusive transitions between them. `StatusLogo` in [`status-logo.js`](../../../tools/flow-reader/web/features/session/status-logo.js) owns every effect: the element and popover, the `pressTimer`, `navigationTimer` and `reloadTimer` timers, pointer capture, the pressing/confirmed/dragging classes and `--logo-swipe-x`, vibration, navigation and refresh.

Hold and swipe commit on separate contracts:

- **Hold.** On the shared route the adapter starts a 500 ms timer on an accepted pointerdown and sends `hold` to the classifier, which accepts it only from the unmoved `pressing` phase. Commitment happens when that scheduled callback runs and the classifier accepts it; 500 ms is the timer delay, not a wall-clock precision guarantee. Commitment yields `longpress-fired` with `action: "home"`: the adapter shows the confirmed feedback, vibrates where supported, and schedules navigation after the 100 ms confirmation.
- **Swipe.** The classifier enters `swiping` once movement exceeds 10 CSS pixels and `pointerup` completes it when `dx >= min(60, 0.4 * width)` and `|dx| > 2 * |dy|` without a cancel. The adapter navigates at that release, with no hold timer and no confirmation delay.

Cancelling a hold is not the same as ending a gesture, and none of the outcomes below touches a committed navigation:

- **Movement more than 10 CSS pixels** from the press point clears `pressTimer` as the phase becomes `swiping`. That loses only the hold confirmation and hold-triggered navigation; the same gesture still navigates at `pointerup` when its swipe qualifies.
- **An early `pointerup`** ends that gesture as `done` without navigation, and a later pointerdown starts a new gesture that can still swipe home and navigate at its own release.
- **`pointercancel` or a pointerdown from a different pointer ID** ends the uncommitted gesture as `done` without navigation, leaving later gestures free in the same way.
- **After commitment** the classifier reports `longpress-fired` or `done` and returns no further action, while the adapter keeps the pending `navigationTimer`. Release, cancellation, movement and later pointers therefore do not revoke the scheduled navigation. `dispose()` is the lifecycle boundary that clears `navigationTimer` and `reloadTimer`; no other path releases a committed navigation.

Reduced motion keeps a static held indicator: the press scale and ring animation are removed and the ring shows its completed progress.

Click still toggles the status popover, which carries the keyboard Homepage link and the refresh button, and Shift+Enter refreshes. Related contracts: [`reader-logo-home`](specs/reader-logo-home/spec.md), [`reader-status-logo`](specs/reader-status-logo/spec.md), [`terminal-reader`](../../specs/terminal-reader/spec.md).

### Alternatives evaluated

- **Separate hold and swipe trackers.** Considered and not adopted: two trackers would have to agree on which commit wins when the timer fires during movement, and that agreement would live outside either tracker. One classifier with the explicit `pressing → swiping | longpress-fired → done` transitions keeps exclusivity in one place; the cost is that the adapter must route every pointer event through it.
- **Logo click navigates home, with a separate status entry.** Considered and not adopted: it would displace the existing click-to-popover affordance and add a second control. The current split — click for the status popover, hold or swipe for home, the popover's keyboard Homepage link, Shift+Enter and the popover button for refresh — preserves click-to-popover behavior while keeping Homepage navigation and refresh keyboard-reachable.
