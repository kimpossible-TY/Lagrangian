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
- [x] Replace the former browser quotation library with explicit server-owned Save for Codex context (see Codex context tasks below).
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

- [x] Set concept 12 mannot and footnote text/mathematics to 80% of the body reading size; verify layout/transitions and install the clean Reader release.

- [x] Open compact footnotes in concept 1 popovers at their references, preserving reading position, history, mathematical markers and accessible dismissal.
- [x] Load distant compact bodies on activation with in-dialog loading/retry and stale-response protection; verify phone, portrait and side-column transitions.
- [x] Install the compact-footnote Reader from a clean commit and verify actual HTTPS document and asset delivery.

- [x] Prefer concept 3 for fitting short mannot names at every viewport width; keep footnotes on concept 12 whenever the existing side-space checks pass, and longer mannot notes on concepts 1/12.
- [x] Preserve label lanes, column bounds and clear connectors when short names share a host with longer notes or footnotes.
- [x] Use the host's available text width and current origin as the short-note math budget so font changes or asynchronous movement cannot collapse a label or strand its typesetting.
- [x] Verify mixed note kinds, actual PDE wide/compact transitions and canonical content; install and verify the clean Reader release.

- [x] Expand tablet reading width and reserve side-note width/height only on the annotated host, using the measured note size.
- [x] Verify the photographed iPad passage, ordinary paragraph widths, local rails, orientation/font changes and phone annotations; install and verify the Reader.
- [x] Match concept 12 with a target dot, connector, local column divider and authored title/equation reference hierarchy.
- [x] Present ordinary footnotes in the same local side columns, retaining original numbered links and endnotes in compact layouts.
- [x] Defer drawing/math resize observer writes to the next frame and verify side-column width changes produce no observer feedback warnings.
- [x] Verify both note types, remote footnote sections, orientation/font changes and canonical content; install the clean Reader release and verify HTTPS delivery.

- [x] Search the nearby free space for all short plain and mathematical names before using a popover, and reserve collision-free label lanes when necessary.
- [x] Verify the photographed kernel, indexed delta, competing labels, viewport/font changes and long-note controls; install and verify the clean Reader release.

- [x] Reuse a bounded persistent Typst compiler for dynamic paint, retaining source/revision/geometry gates and cold-compile fallback.
- [x] Compare authored output and actual PDE latency across cold/warm requests, source changes and worker recovery; install and verify the Reader.

- [x] Retain authored text bodies once, adapt native labeled braces/brackets, and remove cloned target previews.
- [x] Present short names as collision-free labels and longer notes as accessible anchored popovers, preserving selection and update behavior.
- [x] Switch to a nonoverlapping side column only when viewport ratio and available width permit it; refresh on font, section and math changes.
- [x] Verify real compiled annotations, keyboard/touch activation, dismissal, viewport/font transitions, canonical copy and graphical annotation compatibility; update Reader documentation.
- [x] Prepare a clean annotation-only commit and verify its isolated runtime against the actual configured PDE document.
- [x] Install the immutable Reader release and verify registered HTTPS delivery, adaptive annotations and unchanged original PDF service.
- [x] Keep colliding short-name popovers open through layout measurement, reproduce the reported phone tap failure, and verify keyboard/touch dismissal.
- [x] Install the short-name popover correction from a clean commit and verify the reported PDE tap flow over registered HTTPS.
- [x] Allow compact indexed mathematical names as short labels and inset the complete close control/focus ring within the popover; verify the photographed PDE delta and keyboard/touch controls.
- [x] Install the compact-math and close-control correction from a clean commit and verify registered HTTPS delivery.

## Return from internal references

- [x] Add the single semantic reference origin, successful-link capture and guarded section/URL return with disposal.
- [x] Present “원래 위치로” beside the independent change action without narrow-screen overlap.
- [x] Verify latest-reference, reflow, remote/failing/superseded navigation, keyboard focus and static/installed delivery.

2026-10-20 reference-return validation: all 130 HTML Node tests, the full reader
lint, two architecture checks and the isolated clean-release installation/HTTP
asset test passed. The real Reader shell passed Chromium and WebKit at 320/390px
with normal/reduced motion: local and remote references, one-use/latest origin,
font/viewport reflow, history isolation, failed-return retry, superseded fetches,
URL/focus restoration and simultaneous navigation-action layout. Screenshots
were inspected in `dist/reader-reference-checks`. Scoped formatting, diff and
strict OpenSpec checks passed. The additional existing outline browser fixture
failed its strict `<1px` scroll assertion on a 1px WebKit change; the identical
failure was reproduced with the unmodified HEAD assets. No installed service
was updated, and physical-device/VoiceOver checks were not performed.

## Shared reference-return ownership

- [x] Move the single-origin/action lifecycle to reader-common and compose both reader adapters with their native capture/restore effects.
- [x] Move policy tests to the shared owner, update asset/ownership contracts and verify both readers, types, preview bundle and installed asset delivery.

2026-10-20 shared ownership correction: `reader-common/navigation/reference-return.js`
now owns the origin and action lifetime for both readers. The HTML-only controller
was removed; policy tests moved beside the shared implementation. Native geometry,
section publication, URL changes and paged scroll-anchoring effects remain local.
The full reader gate's direct commands passed 158 shared/HTML Node, 85 paged and
36 DOM tests. Python reported 139 tests with 42 optional compiler/companion-source
skips; archived installation and HTTP/import delivery of the shared asset passed.
Both TypeScript checks, warning-free reader lint, preview bundle, Chromium/WebKit
reference flows, scoped formatting, architecture PDF, generated-doc consistency
and strict OpenSpec validation passed. No app/service installation or restart,
physical-device or VoiceOver validation was performed.

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
continuous flow, preserving cross-section references, reading keys and active selections while parking distant content. The former saved-quotation relocation checks used a synthetic
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
- [x] Add red strike, undo and clear controls with document-scoped persistence and layout-aware repainting; preserve Codex context and pending selections.
- [x] Verify source edit rejection/success and browser selection, reflow, reload and review controls; install and verify actual Reader delivery.
- [x] Replace the selection card with compact floating action/review capsules, retaining labels, native selection, pending feedback and accessible material fallbacks.
- [x] Verify capsule layout and actions in narrow light/dark browsers, install the clean Reader commit, and verify actual HTTPS delivery.

## Codex context instead of local quotations

- [x] Remove the local quotation library, list entry, relocation and paint without deleting or migrating legacy browser data.
- [x] Implement atomic per-service focus records, supported source excerpts and explicit unmapped text, with revision/service/input checks, informational age and no compilation or messages.
- [x] Expose distinct profile focusFile paths, a validated local selection reader and a portable Tail Hosting selection adapter.
- [x] Verify Python/Node, browser and terminal save, failed/pending selections and legacy-data behavior; align canonical docs and OpenSpec. Installation/deployment is excluded.

## Codex context service rollout

- [x] Commit the validated Reader changes and stage a clean immutable release while preserving unrelated worktree files.
- [x] Back up runtime configuration, install/restart only the Reader and apply the tested local selection adapter.
- [x] Verify registered HTTPS delivery, explicit save/read freshness and source isolation; record the deployed revision and recovery paths.

## Unified saved-context lookup without expiry

- [x] Resolve same-project/document saved text across reader adapters, preserving exact filters, document isolation and stale/error evidence.
- [x] Remove time-based expiry from HTML and paged context readers; cover old mapped/unmapped text, taps, changed source, service and revisions.
- [x] Align canonical docs, the portable companion patch and local Codex instructions with unified lookup.
- [x] Run targeted and reader integration checks, install the clean immutable Reader release, and verify the local PDE lookup without a reader argument.

## HTML block-to-source range mapping

- [x] Preserve compile-verified source ranges for wrapped prose and whole equations without changing delivered HTML or workspace sources.
- [x] Share accepted range resolution between Saved for Codex and bidirectional Sync Editor, preserving snapshot and ambiguity checks.
- [x] Verify real compiler/browser flows, Unicode, repeated/cross-file/unsupported and stale sources; update ownership and canonical documentation.
- [x] Install the clean immutable Reader release, restore the exact saved context and verify unified lookup, bidirectional navigation and registered HTTPS delivery.

## Visible HTML document activity

- [x] Add session-owned fixed activity for compilation, accepted-content loading/publication, held updates and failures, preserving native selection and stale-request guards.
- [x] Verify status precedence, live updates, selection release, recovery and narrow light/dark layout; check static/installed delivery and document the behavior.
- [x] Extract the existing paged activity policy, notice controller and styles into reader-common; replace the separate HTML notice with that implementation and retain concrete session signal adapters.
- [x] Verify both readers, shared lifetime/selection behavior, bundled preview output and installed HTML asset delivery after extraction; update ownership documentation.

## Deploy shared reader activity

- [x] Commit the validated shared activity change and build clean immutable HTML and signed native app candidates with recovery snapshots.
- [x] Install both candidates, preserve the previous running/stopped profiles and saved context, and verify registered delivery plus actual document rendering.

## Live pinch text sizing

- [x] Add anchor-preserving transient font previews, a once-only final preference write and cancellation rollback in the appearance owner.
- [x] Apply pinch movement through a coalesced animation frame, flush the final size on release and cancel stale frames on interruption/disposal.
- [x] Hold expensive mathematical/dynamic drawing work during live previews and resume the existing renderers for the final size.
- [x] Verify live growth/shrink, persistence, cancellation/extra fingers, stale frames, reading position and existing gesture guards in Node and Chromium/WebKit; update canonical documentation.

2026-10-19 live-pinch validation: 12 focused Node cases and the shared/HTML Node
gate passed. The real Reader shell with local MathJax passed Chromium (installed
Chrome) and WebKit: body and mathematical glyph sizes changed before touchend,
the reading paragraph remained within 2px of its starting position, browser
viewport scale stayed 1, preview wrote no font preference and release wrote once.
Each engine also passed all 36 reading-navigation checks, including live shrink,
touch cancellation, third-contact rollback, selection/scroll/swipe guards and
settings controls. Scoped formatting, generated-doc consistency and strict
OpenSpec validation passed. Touch sequences are synthetic; physical iPhone
acceptance and installed-service delivery were not performed at this implementation
checkpoint. Installed-service validation is recorded in the deployment section below.

## Local mathematical decoration rendering

- [x] Export versioned, conservative primitive descriptors with point/em paint geometry while preserving callbacks and paged rendering.
- [x] Generate fragment SVG locally in the HTML decoration owner, retaining server fallback, interaction holds and stale guards.
- [x] Verify compiler parity, request elimination, mixed fallback, reflow/theme and installed asset delivery; update canonical ownership/docs.

## Deploy shared rendering, live pinch and local decorations

- [x] Finish the coordinated source work, run the combined Reader gate, snapshot installed configuration/context and commit the verified implementation on the current branch.
- [x] Build a clean signed 0.1.27 app with the shared scheduler in its native engine and stage the matching immutable HTML Reader release.
- [x] Install both candidates with recovery backups and preserve the exact running/stopped profile state and saved context.
- [x] Verify installed signatures/provenance, HTTPS asset/document delivery, live pinch/local decoration behavior and isolated paged document rendering; record the confirmed release tag and recovery evidence.

## Authored flowbox presentation

- [x] Separate authored flowbox framing from internal mathematical derivation groups; restore centered content and compact spacing with no external separator rules.
- [x] Verify real compilation, unchanged paged output, narrow/wide light/dark reflow, numbering, cancellation, links and canonical text; record source and actual PDE evidence.

2026-10-20 flowbox validation: the real compiler fixture retains nested equations,
references and cancellations; original/overlay PDF bytes match. Chrome and WebKit
each pass 24 combinations of 320/390/430/768px widths, 13/18/30px fonts and both
themes, including frame-only presentation, compact rows, centered arrows/numbers,
bounded mathematical ink and canonical text. The full live PDE sources compile
with all 101 authored flowboxes, no lost links/annotation targets or compiler-loss
warnings, and the saved `Use Equation (P.1.3)` passage still maps to line 61.
An isolated service loading that export passes three photographed-flowbox cases
per engine (390px/18px light, 320px/30px dark, 768px/30px light).
Evidence and inspected screenshots are under `dist/reader-flowbox-checks`; the
full compile is under `dist/reader-flowbox-pde`. The Reader gate's equivalent
direct commands passed 144 Node tests, 147 Python tests (one optional companion
bridge class skipped) and 82 paged Vitest tests; Yarn is unavailable in this
shell. Generated-doc consistency, scoped formatting, diff checks and strict
OpenSpec validation pass. This checkpoint covers local implementation and
desktop browser checks; installed Reader delivery and physical-device checks
were not performed.

## Deploy authored flowbox presentation

- [x] Commit the verified flowbox implementation on the current branch and prepare a clean immutable Reader release with configuration/context recovery snapshots.
- [x] Install the Reader release, preserve other service states and saved context, and verify registered HTTPS assets plus the actual photographed flowbox in Chrome/WebKit.

## Deploy reference-return action

- [x] Commit the verified shared reference-return implementation on the current branch and stage a clean immutable HTML Reader candidate with configuration/context recovery snapshots.
- [x] Install the Reader candidate, preserve existing service states and saved context, and verify registered HTTPS assets and real internal-reference return in Chrome/WebKit.

2026-10-20 deployment completed from clean commit
`b01b5b4409f6920a0400afd84f4d9272f65bc868`. Installed-document verification
exposed unnecessary mounted-section reconstruction and late mathematical layout
movement; direct mounted restoration and a renderer-owned semantic anchor hold
were added before final acceptance. All 159 shared/HTML Node tests and all eight
reference-browser combinations passed. The installed HTTPS Reader passed Chrome
and WebKit at 13px/390px and after changing to 18px/430px: local/remote origin,
consumption, URL/focus and native semantic offsets, with maximum error 0.234375px.
All 514 immutable files and 48 public/local assets match; published document bytes,
configuration, three context files and other service states are preserved.
Receipts, inspected screenshots and recovery snapshots are indexed in
`dist/reader-reference-rollout/verified-rollout.json`. Native app replacement,
remote publication and physical-device/VoiceOver checks were not performed.

- [x] Try bounded nearby placements for compact CeTZ symbols at the reading size before numbered fallback; preserve exact placements, collisions and source anchors.

## Callout change destinations

- [x] Assign semantic navigation anchors to callouts and include titles/unwrapped prose in visual history without duplicating accepted selection passages or losing existing child targets.
- [x] Reproduce short-note insertion, body/title edits and upgrade relocation in Python, and verify actual compiler/WebKit automatic navigation with existing gesture/selection/history guards.
- [x] Reuse the semantic reading-position hold after local/remote change jumps so asynchronous mathematics cannot hide the changed callout title; verify the actual PDE note in Chrome and WebKit, including reload.
- [x] Apply the clean immutable Reader release, restore the missed Green-function note as the last accepted edit, and verify installed document delivery and saved-context preservation.


## Measured canvas label allocation

- [x] Replace symbol-only nearby placement with measured label candidates, edge projection, constrained allocation and stroke/leader collision checks.
- [x] Keep the reading font with compact label line spacing and index sampled strokes to bound repeated layout work.
- [x] Verify every current native PDE figure visually, compare retained labels, and exercise Chrome/WebKit at 320/390px and 13/18/30px.
- [x] Verify selection/text/geometry contracts and install the clean Reader release with preserved context and installed-asset checks.

## Bounded canvas label sizing

- [x] Combine generic compact-label size candidates with measured nearby placement and preserve natural dimensions across retries.
- [x] Verify effective font floors, stroke/label clearance, source anchors and font-reset stability, including the PDE fractions.
- [x] Coordinate and install the clean immutable release; verify HTTPS assets, saved context and change navigation.

## Adaptive annotation grouping

- [x] Omit mannot text-note grouping paint and anchor outsets in HTML while retaining independent grouping, graphical-only targets and paged output.
- [x] Verify native/grouped targets, multi-target notes and note order through real compiler and browser reflow fixtures.
- [ ] Install the clean grouping-annotation release and verify full PDE compilation, HTTPS delivery, browser reflow and preserved service/context state.

## Immediate source-highlight feedback

- [x] Share optimistic paint lifetime across paged and HTML/terminal readers, retaining concrete geometry and existing feedback wording.
- [x] Release native selection after immediate paint and retire it only on accepted replacement; roll back rejected/stale/disconnected actions with retry and newer-selection guards.
- [x] Verify lifecycle, real browser geometry/reflow and replacement, reader suites, type/lint checks and built/installed asset layout; record coverage limits in verification-optimistic-highlights.md.

## Install immediate source highlights

- [x] Build and verify signed Flow 0.1.30 with its new native engine and stage the matching immutable HTML Reader release from a clean commit.
- [x] Install both releases with recovery snapshots, preserve profile states/settings/history and verify actual local/HTTPS document and asset delivery.
- [x] Verify installed browser highlighting and real isolated source writes in Chromium/WebKit, complete compiled-document handoff, and confirm services and release integrity after the user's Mac reboot.

## Preserve CeTZ cell shading

- [x] Preserve pale geometric fills as tinted surface washes while keeping foreground glyph/stroke contrast and decoration-underlay rules.
- [x] Verify photographed blue/purple cell colors, alpha, masks/resources, repeated themes and late/cloned SVG paint in Node, Chromium and WebKit; record coverage in verification-cetz-shading.md.
