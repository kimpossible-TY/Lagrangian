## Design

The paragraph remains the visual anchor. A quiet header contains the connection and collapse controls, followed by the selected excerpt and a transcript with a clear question/answer hierarchy. The composer starts at one line, grows with text to a bounded height and puts model selection and send on one compact row. Streaming interruption remains close to the response. Styling uses existing Reader theme roles and supports narrow screens, dark mode and reduced transparency.

The shared connection dialog remains accessible from every conversation. Existing draft, model, focus, error and revision ownership remain with the controller. Reuse the accepted-stream draft recovery and progress localization integrated from `refine-reader-paragraph-chat`.

Verify isolated mobile and desktop browser interactions and review screenshots with synthetic data. Physical iPhone behavior and live model latency need separate verification.

The expanded conversation uses a single floating, opaque surface with a subtle
edge and shadow to distinguish it from the document. The transcript and
composer share that surface rather than stacking cards. Every attached conversation
has the same ChatGPT-logo annotation appended to its paragraph at every viewport
size, including while open. It is a native toggle button with a 28x24 visual body
inside a reserved 44x44 inline target. The target reserves inline space rather
than overlapping source text and never becomes a summary row. Known reader
exclusions (`.reader-chat` and selection-ignore metadata) keep it outside canonical
text and model context. Unresolved history retains its accessible text entry
outside the canonical article. Unmount and disposal remove both controls.

The existing HTML geometry owner places expanded panels. A side capsule starts
24px beyond the reading edge, is 360–420 CSS pixels wide and leaves at least 12px
to the viewport edge. Entering side presentation requires another 24px of spare
width; an existing side panel can shrink to 360px before returning below the
paragraph. These are local design choices, not native Apple constants. A source
ink/annotation collision or collision with an earlier open panel falls back below
the paragraph. The reading column is not narrowed to manufacture margin space.

Layout temporarily removes side candidates from document flow together before
measuring source ink, so a panel's own inline row cannot create its side vacancy.
The same paragraph-local panel DOM is positioned absolutely for side placement
and returns to normal flow otherwise. The annotation remains in place during
open/close and resize, preserving its paragraph's wrapping. Panel size changes,
article mutations, resize and font completion coalesce into the controller's
existing frame scheduler; collapsed/mobile layouts avoid document ink scans.
Bounded transcript scrolling keeps the composer reachable; reflow retains its
scroll offset, draft, selection/caret, model and focused composer control. Native controls
retain keyboard activation, Escape and focus return to the annotation. Reposition
immediately without spatial animation, including under reduced motion, so input
remains interruptible throughout. A divider identifies the composer. Buttons
retain visible focus, pressed feedback and a forced-colors fallback. This is an
editorial web treatment, not an imitation of native Liquid Glass optics.
