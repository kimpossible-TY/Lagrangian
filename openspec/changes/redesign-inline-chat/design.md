## Design

The paragraph remains the visual anchor. A quiet header contains the connection and collapse controls, followed by the selected excerpt and a transcript with a clear question/answer hierarchy. The composer starts at one line, grows with text to a bounded height and puts model selection and send on one compact row. Streaming interruption remains close to the response. Styling uses existing Reader theme roles and supports narrow screens, dark mode and reduced transparency.

The shared connection dialog remains accessible from every conversation. Existing draft, model, focus, error and revision ownership remain with the controller. Coordinate integration with the concurrently active `refine-reader-paragraph-chat` work, which owns accepted-stream draft recovery and progress localization.

Verify isolated mobile and desktop browser interactions and review screenshots with synthetic data. Physical iPhone behavior and live model latency need separate verification.

The expanded conversation uses a single floating, opaque surface with a subtle
edge and shadow to distinguish it from the document. The transcript and
composer share that surface rather than stacking cards. A restrained edge
identifies a folded conversation; a divider identifies the composer. Native
buttons retain keyboard activation and visible focus, with immediate pressed
feedback and a forced-colors fallback. This is an editorial web treatment, not
an imitation of native Liquid Glass optics.
