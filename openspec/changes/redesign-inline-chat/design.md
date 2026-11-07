## Design

The paragraph remains the visual anchor. A quiet header contains the connection and collapse controls, followed by the selected excerpt and a transcript with a clear question/answer hierarchy. The composer starts at one line, grows with text to a bounded height and puts model selection and send on one compact row. Streaming interruption remains close to the response. Styling uses existing Reader theme roles and supports narrow screens, dark mode and reduced transparency.

The shared connection dialog remains accessible from every conversation. Existing draft, model, focus, error and revision ownership remain with the controller. Coordinate integration with the concurrently active `refine-reader-paragraph-chat` work, which owns accepted-stream draft recovery and progress localization.

Verify isolated mobile and desktop browser interactions and review screenshots with synthetic data. Physical iPhone behavior and live model latency need separate verification.

The expanded conversation uses a single floating, opaque surface with a subtle
edge and shadow to distinguish it from the document. The transcript and
composer share that surface rather than stacking cards. A small rounded summary
bubble identifies a folded conversation; its boundary, opaque surface and shadow
match the expanded capsule. It retains the original one-third/two-thirds margin
placement. When no margin candidate fits, the controller appends one excluded
inline annotation to the associated paragraph; the expanded panel stays after
that paragraph. The annotation contains a decorative ChatGPT mark and a native
button, with a 28x24 visual body inside a reserved 44x44 inline target. The
target reserves inline space rather than overlapping source text. There is no
separate block row. Known reader exclusions (`.reader-chat` and selection-ignore
metadata) keep it outside canonical text and model context. Resize restores the
wide summary when space returns; unmount, unresolved anchors and disposal remove
the annotation. The original same-control panel and focus-return contract applies
to whichever entry is visible. A divider identifies the composer. Native
buttons retain keyboard activation and visible focus, with immediate pressed
feedback and a forced-colors fallback. This is an editorial web treatment, not
an imitation of native Liquid Glass optics.
