# Responsive mobile reader alongside the paged preview

Show source highlights immediately in both paged and HTML readers, including
the terminal Reader's shared browser surface. Keep existing feedback text while
verification and compilation run in the background, then replace temporary
paint with the accepted document. Roll back rejected paint without changing
unselected text, source validation or review-strike persistence.

Place native CeTZ labels from their measured boxes and available drawing space,
including short formulae, multi-line names, edge labels and aligned SVG labels.
Use compact line spacing at the selected reading font, bounded nearby candidates,
collision-aware allocation and explicit leaders before numbered fallback. Verify
the complete current diagram corpus visually and across mobile widths/fonts.

Restore authored flowboxes as centered, continuously framed derivations with
compact internal spacing. Do not add separator rules outside the frame or
around the mathematical renderer's internal row groups. Retain existing source
calls, mathematical text, equation numbering, links and paged output.

Reduce dynamic decoration latency by retaining Typst's incremental compilation
cache across geometry requests, with unchanged authored output, revision gates,
bounded worker lifetime, and cold compilation recovery.

Place short plain and mathematical annotation names in nearby measured free space.
Prefer concept 3 for fitting short mannot names even on wide screens. Ordinary
footnotes use concept 12 whenever the side-space checks pass; longer mannot
explanations choose concept 1 or 12 from the available width.
Search around preceding equation lines and reserve additional label rows when
names compete; a local collision alone must not turn a fitting short name into
a popover. Keep longer explanations and physically oversized names accessible
through the existing popover controls.

Replace annotation-only braces and brackets with the same adaptive association
when a mannot target has a text note. Remove the grouping paint and its anchor
outset together, preserving independent grouping, other mathematical decorations
and graphical relationships.

Use the tablet's wider reading canvas instead of limiting the entire document
to a narrow book column. Side notes reserve their measured width and height only
within the equation or paragraph they annotate; ordinary passages regain the
full reading width immediately before and after that row.
Match concept 12 with a dot and connector from the annotated term to a local
column divider, with an equation reference and retained authored formatting.
Set concept 12 note text and mathematics to 80% of the body reading size.
Use the same local columns for eligible footnotes and concept 1 popovers at their
references in compact presentation. Original numbered links and endnotes remain
source and diagnostic fallbacks.

Match the paged preview's explicit selection actions: persist Highlight in the
Typst source after compiler verification, and keep red strikes browser-local
with undo and clear. Replace the mistaken browser quotation library with real Save for Codex context.
Resolve saved Codex text across readers of the same project and entry document,
without asking users to identify an internal service. Remove time-based expiry;
continue checking service identity, accepted revisions and source changes.
Present these selection actions in a compact floating capsule with visible
icons and labels; keep undo and clear in a separate review capsule.

The current saved-document preview fixes content to printed page geometry. A phone reader must zoom or rotate to read ordinary paragraphs, equations, and figure labels. Add a distinct HTML reading output and frontend to tinymist-flow, sharing the original Typst sources with the existing paged output.

The reader preserves headings, mathematical notation, numbering, references, footnotes, and annotations. Paragraphs reflow at the selected font size. Equations and figures are composed to the available reading width at readable text sizes. Essential body content is readable continuously without zoom, horizontal panning or slide navigation. Authored text annotations use short labels above their shaded targets and tap-to-open anchored popovers for longer explanations. A sufficiently wide landscape viewport presents longer notes and footnotes in an adjacent column. Annotation bodies and source language remain intact without copying the target equation into a second block. Reader updates preserve an active selection or annotation popover and follow accepted visual edits after it ends; recent reading gestures defer that navigation while retaining the reading position.

Implement the reader as independent modules within this repository. Flow owns compilation and project settings; Tail Hosting exposes the new endpoint. Keep the installed paged service and address available throughout development and rollout. Validate the full PDE document, not only a simplified demo, before making the mobile reader the default mobile entry.

Use the existing Tail Dashboard Hosting card as the configured document entry.
Keep a direct open action and browser-local automatic/Reader/original preference.
Keep original-page access in the Dashboard and existing addresses; the Reader
toolbar contains only an outline icon, a centered Flow identity, and a reading-settings icon.
Move font sizing and appearance into reading settings. A
two-finger pinch updates the actual text size during movement, coalesced to
animation frames, and persists the final size once on release;
the user explicitly chooses this over browser magnification. A horizontal swipe
from the inner left reading margin opens a reversible outline drawer.
Only a fresh, healthy, strictly published native Reader qualifies for automatic
touch-device selection; development and unknown runtime flags keep the original
entry. Existing paged bookmarks and both document lifecycles remain unchanged.

Use the semantic HTML/MathML output with a local, width-aware mathematical
renderer. Retain logical token identities across line breaks so selections,
decorations, and original CeTZ relationships follow the new composition. Publish
only validated results for the current document and geometry. Preserve authored
drawing coordinates through shared adapters.
Keep cancellation and overline bodies semantic as well. Original cancellation
properties draw paint around measured fragments; overlines span their full bodies.

Preserve exported source-language metadata separately from localized controls,
including moved mathematical annotations. Managed release switches wait for the
previous Reader job to finish stopping before activating another release.

Include every exported HTML heading level in the outline and indent each deeper
level consistently, so sections and their subsections remain visually distinct.
Present it in a floating frosted capsule with a bounded scrolling list and a
current-location pill, retaining swipe, keyboard and solid-material alternatives.
Opening or reopening centers and focuses the current entry, including when its
heading belongs to an earlier transport section that is no longer mounted.

Keep display equation numbers at the inline end and vertically centered beside
the complete expression. Reserve their width when composing mathematical lines.

Provide explicit automatic, light and dark appearances with browser-local persistence.
Present them in an anchored preview panel from a compact icon-only button,
with native radio keyboard behavior, clear selection and restrained material/motion.
Use coordinated reading and control palettes, and restrained theme-specific colors
for authored highlights instead of browser-default yellow. Original
drawings and mannot annotations blend into their surrounding reading background,
with readable theme-aware vector paint and label colors.
Preserve pale CeTZ cell fills as distinct surface shading rather than converting
them to foreground ink; keep text and stroke contrast correction separate.
Resolve the compiler's Oklab colors, inherited group paint and fixed
`currentColor` ink in either appearance. Authored SVG paint updates must replace
the prior source color and its presentation without accumulating theme drift.

Preserve the existing `highlighted` helper for plain text and mixed mathematical
passages. Its HTML adapter must retain native math and paint the complete
expression through reflow without replacing authored calls with `highlight`.

Retain authored `paragraph_tab` / `paragraph-tab` spacing at 1.5em in HTML,
including beside mathematics and within highlights, without adding quotation
text or changing the existing paged output.

Non-goals: replacing Typst's parser or evaluator, removing PDF export, changing mathematical meaning, or automatically inferring a responsive layout from every arbitrary drawing program.

Bring the paged reader's last-edit behavior to HTML: persist a project-scoped
visual change independently of viewers, restore it on entry/reload, and follow
accepted live changes after rendering. Recent reading gestures defer the jump
behind a compact change-location button. Explicit links and history navigation
retain their destination.

Bring the paged reader's single reference return action to HTML. After following
an internal body or outline link, offer “원래 위치로” at the bottom alongside the
independent change-location action. Restore the semantic reading anchor and its
URL after section loading and reflow; a later link replaces the return origin.
Both readers use one `reader-common` controller for origin state, action visibility,
completion consumption and disposal; native coordinates and navigation effects
remain with their adapters.

Preserve verified HTML block-to-source ranges for prose inside content wrappers
and complete mathematics. Saved for Codex and bidirectional editor navigation
share this accepted mapping, keeping source changes, unsupported output and
ambiguous cursors explicit.

Reuse the paged reader's activity policy, notice controller and styles from
`reader-common/session` for a compact fixed notice in both readers:
compiling, loading accepted content, displaying it, paused reading interactions,
and failures. Keep it visible while scrolled, preserve selections, and hide it
after the current accepted content is displayed.

## Local mathematical decoration rendering

Export a versioned drawing description for supported solid highlights, rectangles, underlines and cancellations in the initial HTML compilation. Regenerate their per-fragment SVG in the HTML rendering owner after font/viewport changes, eliminating those dynamic decoration requests. Preserve unsupported styles and arbitrary callbacks through the existing validated Typst path. Relationships, canvas conversion, persistent cache and workers remain subsequent work.

## Bounded canvas label sizing

Extend measured native-label allocation with automatic compact-label size candidates,
a readable lower bound, finer nearby position search and reserved source anchors.
Use full-size numbered fallback when no readable candidate fits; no per-label tuning.

## Browser computation and offline reading

Extend the existing HTML Reader with an installable web app and recoverable offline
reading of complete accepted snapshots. Move raw Typst compilation into an injected
execution boundary, with the local executable and an active browser WASM Worker
as interchangeable executors. Python retains normalization, content audit, source
mapping, final highlight validation and publication. All viewers consume the same
server-adopted revision. Expand supported local mathematical/figure composition,
measure the actual PDE corpus in a Worker, lease shared jobs to visible phones with
server fallback, and queue revision-bound offline highlight requests for guarded
reconnection. This work does not require a native iPhone app or deployment to the
user's running services.

The user-requested rollout packages the matching browser compiler, preserves explicit
Reader-only font inputs, updates the signed Flow app and bundled guide, and verifies
actual PDE delivery over the existing local and HTTPS routes with recovery snapshots.

Expose a two-position Low/High workload slider in reading settings. Low is the new
default and retains server compilation with existing browser-local math and figure
composition. High offers the local WASM compiler under the existing foreground leases.
Preserve explicit saved boolean preferences as Low/High, including older document choices.

## Verifiable device computation

Show device connections and bounded execution history in reading settings. Add explicit
small-document and current-document checks pinned to the requesting browser. Compare
its output with a native reference using the same captured bytes; fallback never counts
as device-test success. Provide Korean progress, recovery instructions and copyable
results for physical iPhone verification. Deploy through the existing Flow Reader service.

Record explicit browser termination signals and distinguish unreported heartbeat loss from deadlines.

After silent iPhone document-check loss and an observed automatic page reload, retain last execution phase, bounded WASM allocation and heartbeat timing, plus optional tab-local recovery correlation.

Provide an explicit waiting web-shell update action and reject diagnostic checks from legacy clients without current execution evidence.

## Layout iteration history memory

Retain shared introspectors instead of complete previous HTML and paged outputs
during layout convergence. Preserve the five-pass limit, all iteration diagnostics,
tracing, public Output implementations, and final exports. Maintain the exact pinned
Typst core as a small local patch; do not change installed services.
