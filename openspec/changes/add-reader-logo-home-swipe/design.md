## Design

The HTML Reader recognizes shared mode from the server's `/d/<id>/` document route; its origin root `/` is the shared Homepage. The standalone Reader is served at `/` and has no Homepage, so it exposes neither navigation nor the link. The terminal presentation runs this same HTML Reader document, so the gesture follows the route and the pointer events the host forwards. Registered `/p/<id>/` previews use a different frontend with no logo and are unaffected. Only a single primary pointer with the primary (left) button starts a gesture; other buttons are ignored and a competing pointer cancels an uncommitted gesture.

`logoGesture` and `logoHomeURL` in [`logo-home-swipe.js`](../../../tools/flow-reader/web/features/navigation/logo-home-swipe.js) own classification only: hold and swipe phases, the swipe thresholds, and the mutually exclusive transitions between them. `StatusLogo` in [`status-logo.js`](../../../tools/flow-reader/web/features/session/status-logo.js) owns every effect: the element and popover, the `pressTimer`, `navigationTimer` and `reloadTimer` timers, pointer capture, the pressing/confirmed/dragging classes and `--logo-swipe-x`, vibration, navigation and refresh.

Hold and swipe commit on separate contracts:

- **Hold.** On the shared route the adapter starts a 500 ms timer on an accepted pointerdown and sends `hold` to the classifier, which accepts it only from the unmoved `pressing` phase. Commitment yields `longpress-fired` with `action: "home"`: the adapter shows the confirmed feedback, vibrates where supported, and schedules navigation after the 100 ms confirmation.
- **Swipe.** The classifier enters `swiping` once movement exceeds 10 CSS pixels and `pointerup` completes it when `dx >= min(60, 0.4 * width)` and `|dx| > 2 * |dy|` without a cancel. The adapter navigates at that release, with no hold timer and no confirmation delay.

Cancellation has two boundaries, and only the first one cancels a hold:

- **Before commitment** an early `pointerup`, `pointercancel`, movement more than 10 CSS pixels from the press point (the adapter clears `pressTimer` when the phase becomes `swiping`) and a competing pointer cancel the hold and its feedback.
- **After commitment** the classifier reports `longpress-fired` or `done` and returns no further action, while the adapter keeps the pending `navigationTimer`. Release, cancellation, movement and later pointers therefore do not revoke the scheduled navigation. `dispose()` is the lifecycle boundary that clears `navigationTimer` and `reloadTimer`; no other path releases a committed navigation.

Reduced motion keeps a static held indicator: the press scale and ring animation are removed and the ring shows its completed progress.

Click still toggles the status popover, which carries the keyboard Homepage link and the refresh button, and Shift+Enter refreshes. Related contracts: [`reader-logo-home`](specs/reader-logo-home/spec.md), [`reader-status-logo`](specs/reader-status-logo/spec.md), [`terminal-reader`](../../specs/terminal-reader/spec.md).

### Alternatives evaluated

- **Separate hold and swipe trackers.** Considered and not adopted: two trackers would have to agree on which commit wins when the timer fires during movement, and that agreement would live outside either tracker. One classifier with the explicit `pressing → swiping | longpress-fired → done` transitions keeps exclusivity in one place; the cost is that the adapter must route every pointer event through it.
- **Logo click navigates home, with a separate status entry.** Considered and not adopted: it would displace the existing click-to-popover affordance and add a second control. The current split — click for the status popover, hold or swipe for home, the popover's keyboard Homepage link, Shift+Enter and the popover button for refresh — keeps one trigger per action and keeps refresh keyboard-reachable.
