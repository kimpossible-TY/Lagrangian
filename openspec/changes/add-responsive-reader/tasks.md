User clarification, 2026-10-17: the mobile solution must make all essential content
readable directly in the body. Slides, horizontal movement, zoom, and extra clicks
to enlarge equations are not acceptable substitutes for responsive composition.
The strict native Reader now supplies the configured mobile document entry for
the PDE project. Current acceptance and older experimental failures are separated
in `verification.md`; VoiceOver speech is explicitly deferred to follow-up.

- [x] Inspect current engine, preview, Flow profiles, Tail Hosting ownership, and PDE HTML failures.
- [x] Add isolated target-aware package adapters and a reproducible reader build command.
- [x] Compile the full PDE document with math, references, footnotes, and annotation adapters; verify graphical programs separately.
- [x] Evaluate automatic math line breaking against all 1,411 PDE display equations; record remaining overflow and fragment-identity issues.
- [x] Separate mathematical content from mark/decoration SVGs and distinguish derivation alignment from matrix structure.
- [x] Preserve mannot bodies as semantic MathML and render original decoration callbacks for each measured fragment; validate all PDE decoration IDs.
- [x] Preserve native cancellation and overline bodies as semantic mathematics, with original per-fragment cancellation paint and assistive enclosure notation.
- [x] Paint visible original terms independently from uncomposed offscreen explanatory copies, and verify both occurrences through ordinary scrolling.
- [x] Keep empty composed line-break carriers from retaining a false loading notice while preserving pending notices for real content.
- [x] Add an isolated, opt-in derivation-row composition probe and compare it with the prior adapter against a frozen source snapshot.
- [x] Implement width-aware mathematical line breaking/alignment at the selected font size, preserving every term and reference.
- [x] Bind canonical mathematical text to all rendered token occurrences and preserve selected quotations/highlights when script DOM order changes.
- [x] Carry every logical target fragment into graphical annotation requests and resolve CeTZ anchors on actual fragment surfaces without source edits.
- [x] Expose named CeTZ connector endpoints and reroute supported colliding connections around measured text while preserving their original styling and arrowheads.
- [x] Reuse accepted relationship components across differently grouped requests and compile only changed layouts, retaining source/revision checks.
- [x] Verify all 15 frozen PDE relationships at 320px with 18px/30px fonts, original vector paint, complete math and zero collision/overflow failures.
- [x] Connect the width-aware math renderer to the Reader with logical fragment geometry, local assets, update handling, and accessibility checks.
- [x] Integrate local MathJax/CHTML composition, validated publication, selection-aware updates, and per-fragment decoration/relationship refresh in the Reader.
- [x] Automatically recompose wide inline expressions in the body while retaining their original math style, text order, fragment paint, and narrower/wider container behavior.
- [x] Resolve actual-line accent overhang at the selected font size without leaving a notice-induced false overflow warning.
- [x] Compose wide fraction/radical children, spanning decorations, scripted bases and current PDE matrices with measured internal budgets while preserving canonical text, readable entry fonts, and full operator paint.
- [x] Verify local asset integrity, canonical copy, font changes, obsolete results, and automatic failure recovery in the actual Reader browser fixture.
- [x] Verify the refreshed physical iPhone Reader's text, mathematics and figures without zoom/horizontal movement, reference navigation/back and pinch behavior; browser version was not supplied.
- [ ] Follow up actual VoiceOver speech validation (explicitly deferred by the user on 2026-10-18; not a gate for this rollout).
- [x] Add coordinate-unit fitting, an automatic viewport/font request path, and per-canvas caching without editing authored CeTZ coordinates.
- [x] Bound pending canvas delivery, preserve reading anchors through drawing/font/viewport changes, and verify actual PDE page width and position in both viewport directions.
- [x] Implement a shared width-aware CeTZ canvas adapter that preserves source coordinates, separates geometry scale from readable labels, and detects collisions before introducing necessary panel/legend layout rules.
- [x] Export original native label bodies, geometry and anchor bounds behind an independent Reader option, preserving source order, typography and readable automatic legends.
- [x] Preserve source-derived native label passages and geometry reading points through font/width changes, including long offscreen legends and loading-notice removal.
- [x] Cover the five CeTZ 0.3.4/Fletcher PDE figures without changing their version-specific geometry, and verify stable accent math and optical ink bounds.
- [x] Export the four Maquette surface plots with native axis text, unchanged source pixels, coordinates and complete PDF output.
- [x] Preserve native label selections, quotations and source geometry reading points after preceding figure insertions in an isolated actual PDE copy.
- [x] Compose all six actual PDE tables vertically while retaining their 94 original cells, mathematical ink and header associations.
- [x] Verify all 67 native figures and all six tables at 320px, 390px, 430px and 768px with 18px/30px font settings.
- [x] Traverse every actual Reader body section at 320px/30px, checking all 7,006 body-math occurrences against their real nested container budgets.
- [x] Repeat all 56 actual body sections at 390px/18px with complete expression coverage, canonical text and horizontal-ink checks.
- [x] Set the 13px default, migrate legacy font choices once, and verify viewport-width handling without automatic whole-page shrinking.
- [x] Complete native figure checks for geometry, arrowheads, leaders, palette readability, source updates and device behavior before default rollout.
- [x] Show essential annotations and graphical relationships inline without reveal/expand actions.
- [x] Load transport sections automatically in continuous vertical reading, without slide or next-section navigation.
- [x] Enforce per-component layout checks: no required zoom, horizontal pan, expansion, clipping, or unreadable labels.
- [x] Add saved quotations with context-based relocation, cross-section navigation, and explicit ambiguous/missing states.
- [x] Complete broader reading-position and selection update checks on actual PDE content.
- [x] Integrate saved-source recompilation, revision diagnostics, and Flow lifecycle.
- [x] Verify reader at mobile widths and large font sizes against actual PDE content.
- [x] Expose an independent development Reader through Tail Hosting and Tailnet HTTPS.
- [x] Connect the mobile entry and explicit view preference after fidelity validation, retaining the original view.
- [x] Implement and test a guarded Dashboard document entry, exact profile pairing, explicit browser preference and independently observed Reader mode flags.
- [x] Publish and verify the companion status/Dashboard integration against the actual managed Reader and original service.
- [x] Promote automatic mobile reading after the remaining fidelity and device acceptance gates.
- [x] Verify existing paged service and reader delivery, document operation and rollback.
- [x] Add persistent Automatic / Light / Dark choices before first paint, with live device changes and storage-failure recovery.
- [x] Coordinate reading/control palettes and authored/saved highlight colors while retaining local drawing contrast.
- [x] Adapt the existing `highlighted` helper for HTML text and native mathematics while retaining its paged implementation and recording package provenance.
- [x] Verify plain/string/mixed/nested/tall/reflowed highlights, canonical copy, theme changes and unchanged paged output; compile the actual PDE document.
- [x] Install the verified highlight fix from a clean commit and check the managed PDE Reader's HTTPS delivery.
- [x] Preserve both paragraph-tab aliases as font-relative HTML spacing while retaining their original paged output and quotation text.
- [x] Verify paragraph, inline, mathematical and highlighted tabs through font/width changes and compile the actual PDE document.
- [x] Install the verified paragraph-tab fix from a clean commit and check the managed PDE Reader's HTTPS delivery.
- [x] Verify appearance persistence, contrast and compact controls against actual PDE content at phone and tablet widths.
- [x] Replace the basic appearance select with a compact icon/label trigger and an anchored, accessible three-choice preview panel; preserve persistence and verify keyboard, interruption and narrow layouts.
- [x] Install the appearance controls from a clean commit and verify registered HTTPS delivery, saved-highlight toolbar fit, preference persistence and the original paged service.
- [x] Remove visible mode names from the appearance controls, retain assistive names, and verify the installed icon-only UI.
- [x] Remove the toolbar's page-view link and its polling/style code, keep reading controls aligned right, and verify the installed Reader.
- [x] Reduce navigation to two icons, consolidate reading settings, and add a semantic, interruptible outline drawer.
- [x] Implement article pinch-to-font reflow and directional outline swipes with cancellation, selection/scroll guards and reduced-motion handling.
- [x] Verify gesture classification, real browser wiring, keyboard/focus and narrow layouts; install and verify managed HTTPS delivery.
- [x] Remove the healthy-document status caption and its spacing; retain diagnostics and verify the installed Reader.
- [x] Match the reading-settings icon to the plain outline icon, retaining its touch target; install and verify the result.
- [x] Replace the edge-to-edge outline sheet with a floating capsule, preserving hierarchy, scrolling, gesture travel and accessible dismissal; verify and install it.
- [x] Remove instructional prose from reading panels and verify the installed layout and controls.
- [x] Remove fixed light drawing backgrounds and adapt CeTZ/mannot paint, label backplates and marked term ink to the actual surrounding surface.
- [x] Verify drawing transparency, contrast, source geometry/resources and repeat/late/cloned paint through theme changes and actual PDE reading.
- [x] Include all exported heading levels in the outline with consistent depth-based indentation, wrapping titles and cross-section navigation.
- [x] Center equation numbers vertically beside their expressions and reserve their width during responsive composition; verify short, tall, multiline and unnumbered equations.

## Adaptive text annotations (selected concepts 1, 3 and 12)

- [x] Retain authored text bodies once, adapt native labeled braces/brackets, and remove cloned target previews.
- [x] Present short names as collision-free labels and longer notes as accessible anchored popovers, preserving selection and update behavior.
- [x] Switch to a nonoverlapping side column only when viewport ratio and available width permit it; refresh on font, section and math changes.
- [x] Verify real compiled annotations, keyboard/touch activation, dismissal, viewport/font transitions, canonical copy and graphical annotation compatibility; update Reader documentation.
- [ ] Prepare a clean annotation-only commit and verify its isolated runtime against the actual configured PDE document.
- [ ] Install the immutable Reader release and verify registered HTTPS delivery, adaptive annotations and unchanged original PDF service.

## Last visual edit navigation

- [x] Persist accepted HTML visual changes per project, including disconnected edits, restart restoration, deletion targets and invalid-record recovery.
- [x] Follow each revision-bound change after rendering, defer during recent gestures, and retain explicit-link/history and selection behavior.
- [x] Verify server history and actual browser update/reload/button/reconnect flows; document the feature.
- [x] Install the verified last-edit Reader commit and check its managed lifecycle and registered HTTPS document delivery.

Historical implementation checkpoint: the complete PDE document compiles to HTML with no
missing anchor targets, duplicate SVG IDs, unresolved annotation targets, or
unhandled compiler-loss warnings. All 15 graphical annotation programs render
against supplied term geometry; the browser verifies an actual PDE relationship
at normal and large font sizes. The reader now loads transport sections into a
continuous flow, preserving cross-section references, reading keys, selections,
and saved quotations while parking distant content. Saved highlights pass automated relocation tests and browser checks on a synthetic
fixture. Managed lifecycle and compiler-dependency watching are implemented and
tested. The separate managed PDE Reader completed its first accepted compilation after
the macOS Documents access wait resolved. The installed Reader update and Tail Hosting restart succeeded. Its separate
Tailnet HTTPS route is available. An intentional Reader-only exit recovered in
14.65 seconds while all original PDF checks stayed HTTP 200. Figure layouts,
offline delivery, and deployment validation remain unfinished. The Reader has its own HTTPS endpoint on port 23627. The original PDF route,
other services, and the mobile default are preserved.


- [x] Add a restrained playful anticipation to outside-tap capsule dismissal, with continuous interruption and reduced-motion fallback.

- [x] Keep exit motion visible independently of closed-dialog display support and support passage-center swipes without preview autofocus.
- [x] Verify reduced-motion swipe functionality, visible anticipation, rapid reopening and actual managed delivery after the gesture repair.

## Outline reading location

- [x] Resolve the current outline heading across heading-free transport sections and reveal/focus it whenever the drawer opens, preserving article position.
- [x] Verify long-outline reopening, nested headings, cross-section reading, keyboard navigation and reduced motion in real browsers.
- [x] Install the verified Reader from a clean commit and verify managed document and asset delivery.

## Selection review actions

- [x] Add compiler-verified, revision-bound source highlights for selected prose and complete mathematics without changing ambiguous or stale sources.
- [x] Add red strike, undo and clear controls with document-scoped persistence and layout-aware repainting; preserve saved quotations and pending selections.
- [x] Verify source edit rejection/success and browser selection, reflow, reload and review controls; install and verify actual Reader delivery.
- [x] Replace the selection card with compact floating action/review capsules, retaining labels, native selection, pending feedback and accessible material fallbacks.
- [x] Verify capsule layout and actions in narrow light/dark browsers, install the clean Reader commit, and verify actual HTTPS delivery.
