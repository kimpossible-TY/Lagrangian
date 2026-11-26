#set document(title: "Native cream design — NA18 component contract")
#set page(paper: "a4", margin: 20mm)
#set text(font: "New Computer Modern", size: 10pt)
#set heading(numbering: "1.")

= Native cream design

Lagrangian is a native AppKit macOS research notebook: cream paper, readable
ink, fine round marker strokes and the user's exact original logo. This is the
canonical record of the NA18 component contract for `refine-native-cream-design`. The SCSS request's
reusable component and state-token intent is implemented in Swift/AppKit.
The target is the native app, with a macOS 13 deployment baseline.

*Historical stage.* At NA18 the components had standalone offscreen coverage.
NA19 subsequently applied them to the app and added the selection capsule.
NA20 registered the sources and assembled an isolated development app. See
#link("../../../openspec/changes/refine-native-cream-design/design.md")[the active OpenSpec design]
(`openspec/changes/refine-native-cream-design/design.md`) for the current source,
packaging evidence and remaining native acceptance gates.

== Later chat and fixture integration

Fixed chat source `8e57062ea768320c3fe64f266eb50f40f53d16c1` added actual
offscreen host Ask reentry coverage: latest Unicode draft/model and original
unknown Send identity recover without retyping. Its 26 checks include the original
passive ChatMath regression. They are not actual GUI acceptance. Selection
registration is independent of initial Ask: opening/editing its local composer
adds no account, model, conversation, draft or inference effect. A stale selection
blocks new Send while the same conversation/context still permits Stop/history;
Stop requires an accepted streaming conversation; local preparation alone supplies no Stop target.

Within one living Reader context, immediate Ask restoration applies to an already
created conversation and the exact passage range. The bounded presentation
associations retain separate known passages, while current/recovered draft owners
retain text, model and pending identity. Ranges belonging to one conversation UUID
share its latest accepted display snapshot rather than older range-local copies.
A fresh selection ticket never authorizes
Send through this cache; the existing owner checks it on explicit Send. An initial
uncreated draft and app restart are outside this immediate restoration guarantee.
For unknown Send, successful explicit Refresh comes first: confirmed original
history permits a new explicit question, otherwise only the original question,
model and UUID may be retried. Closing and reopening an unconfirmed pending Send
requires another successful Refresh before retry. Refresh requires an open
conversation with no other conversation action in flight. Failed Refresh retains uncertainty. A successful
Stop adopts the accepted record immediately after context/epoch checks, without
changing pending-Send reconciliation.
An in-flight Stop disables repeated Stop entry while preserving the genuine first
completion and the existing disposal/context rejection of late responses.

Fixture standard edit responders refuse system clipboard operations, while the
existing home/body/PDF Copy remains private. A valid offline PDF remains readable
but fixture Export refuses its UI, forced callback, chooser and write entry.
Normal editing and verified export keep their existing owners. Optional startup
open/write/close work is queued with owned values; callers do not wait during
initialization or teardown. The observed old open sample is not a confirmed root
cause, and the new app's first native window remains a PM/Dogfood acceptance gate.

Packaging source `7307be92baf13d289038596d09e15341064d616c` recorded a new
isolated app and 64 final focused checks, retaining its original failures and
timeout evidence. The current integration consumes the six-file documentation
input `a689e38c6f984e4b8d11ab767bd5d1959e1003b9` as source bytes in new descendant
commits, not as an ancestor or merge. It also restricts the existing three-argument
fixture mode to local content/bundled math and private copy. See the current
source/app-bound packet for child environments and remaining platform/GUI gates.

== NA18 requirements and source mapping

The PM's `app-plan-native-cream-20261118` owns the C01–08 requirements,
`source-surface-map.json`, `logo-source.json` and acceptance assignments.
Its historical reference revision is `cb31c504d21a16dd8fc4786537c7917a14970588`;
NA18 starts on v9 `00c28e9be4edb70c97b5a4a4d10e08c80c6c28ba` in
`feat/native-cream-20261118`. Historical selector readiness notes are not current
writer reservations or test results. The separate existing 125-case contract,
NA16, F04 raw-delta and F13 remain unchanged.

#table(columns: (0.6fr, 2.4fr, 2.6fr), inset: 5pt, align: top,
 table.header([Scope], [Component or adoption owner], [Adoption / preservation contract]),
 [C01], [`NativeAppDesign.swift`, `NativeBrandMark.swift`],
 [NA18 reusable palette, surfaces, semantic button paint, chrome fonts and exact vector.],
 [C02], [`FlowApp.swift`: `buildWindow`, `showSettings`, `settingsTabs`],
 [NA19 home/settings chrome; existing F01/F02/F15 commands and state owners.],
 [C03], [`NativeReaderWindowController.swift`: `NativeReaderHostWindow.loadWindow`, `refreshStatus`, `requestMode`, `sourceControls`],
 [NA19 chrome only. Keep current/requested/failed status, retained content and UI7-C1 failure precedence.],
 [C03/C05], [`NativeReaderChatView.swift`: composer, send/history/account buttons],
 [NA19 conversation chrome. Existing history, account, permission, offline and explicit-Send policy stays authoritative.],
 [C04], [`NativeReaderTextView.swift`: callbacks, `plainSelectedText`, `openChat`],
 [Selection anchor only. NA19 owns floating capsule placement, lifetime and focus; no renderer change.],
 [C03/C07], [`NativeReaderOriginalPageView.swift` and existing object/math owners],
 [Read-only PDF/content boundary. Preserve body, answer, math and PDF font/color/geometry.],
 [C06/C07], [Shared controls plus future screen layout],
 [32pt minimum intrinsic control height; enlarged native labels; light/dark, contrast, transparency/motion preferences, keyboard and AX. Screen fit and actual input still pending.],
 [C08], [NA20 delivery owner; NA21–24 independent acceptance],
 [Register sources, build isolated app, bind exact source/app evidence. An assignment is not a result.],
)

== Shared native interface

`NativeAppDesign.Preferences.current(appearance:)` reads effective AppKit
appearance and the workspace accessibility display preferences without changing
OS settings. `preferencesOverride` permits window-specific composition and
isolated matrix tests. Consumers invalidate paint on effective-appearance and
accessibility-preference changes. There is no global appearance store.

`NativeDesignSurface` supplies opaque paper, panel and floating contexts.
NRD01B retains these for Home and Aa; floating overlays instead use the
transparent outer shell and rounded inner clip of `NativeFloatingGlassView`.
`NativeDesignButton` remains an NSButton with an NSButtonCell paint adapter.
Existing targets/actions and platform activation, tracking, key equivalents,
focus and AX remain in AppKit. Paint cannot dispatch. Hover, highlighted press,
disabled and cancel feedback are immediate, with no timer or completion queue.
The native exterior focus ring uses a rounded mask and the platform focus color.

Spacing is 4/8/12/20/28pt. Controls use 6pt corners, panels 10pt, floating chrome
16pt; this does not turn every view into a pill. Boundaries are 1pt, increased
contrast uses 2pt. The declared 3pt focus metric is available to future custom
focus consumers; NSButton itself uses the platform exterior focus ring. Solid
surfaces provide the baseline in every preference combination. No unverified
material is described as Liquid Glass, and there is no stacked glass treatment.

Typography uses a 23pt light rounded system brand title, 17pt semibold heading,
13pt medium controls and 12pt captions. Native intrinsic measurement expands
controls for longer labels and enlarged fonts. These roles are for chrome only;
body and answer typography remain with their renderers. The native mark's fine
stroke and light brand title should remain visually balanced at adoption.

== Color and native observations

The four light starting colors are preserved. Dark colors are chosen separately
for legibility; light colors are not blindly inverted. Secondary ink, boundaries,
selection, hover, press, disabled, warning and error have explicit opaque tokens.
Disabled feedback changes ink and fill while retaining a readable label.

#table(columns: (1.2fr, 1fr, 1fr), inset: 5pt,
 table.header([Token], [Light], [Dark]),
 [Paper], [`#F7F2E8`], [`#24231F`],
 [Ink], [`#292722`], [`#F7F2E8`],
 [Panel], [`#FFFCF5`], [`#302E29`],
 [Accent], [`#514A83`], [`#C6BEFF`],
 [Boundary], [`#81786A`], [`#A59D90`],
 [Selection], [`#E6DEF4`], [`#49405E`],
)

Actual NSColor sRGB resolution gives the following contrast ratios on the NA18
host. Tests independently compute WCAG relative luminance from resolved color
components; they require 4.5 for text and 3 for boundaries across both themes and
all 16 theme/preference combinations, including disabled and pressed labels.

#table(columns: (1.7fr, 1fr, 1fr), inset: 5pt,
 table.header([Foreground / background], [Light ratio], [Dark ratio]),
 [Ink / paper], [13.37], [14.10],
 [Ink / panel], [14.56], [12.15],
 [Secondary ink / panel], [6.38], [8.24],
 [Accent / paper], [7.08], [9.15],
 [Ink / selection], [11.45], [8.64],
 [Boundary / paper], [3.90], [5.86],
)

Actual offscreen PNGs in external NA18 evidence show both themes' vector and
button paint. They are component observations, not app screenshots or visual
review approval. CoreText shapes Latin, Korean, decomposed Hangul, Latin combining
marks and mathematical symbols for all four roles, rejecting missing glyphs.
The host resolves rounded Latin to AppleSystemUIFontRounded-Light, Hangul to
AppleSDGothicNeo variants, and supplementary math to STIXTwoMath-Regular.
Font availability on other systems and foreground VoiceOver still need their
own verification; a deployment target is not a runtime test of macOS 13.

== Original logo adapter

The read-only source is `tools/flow-reader/web/index.html`,
`svg.reader-logo-mark`, with `viewBox="0 0 240 220"`. All three paths have the
same exact original cubic coordinates. The d-string SHA-256 in the PM's logo
reference is
`b4d1dbfb513c47994dd54017b03e8f66da0ae1364f1d9bb92816f0ef50c2ce84`.
`NativeBrandMark.path` adapts these curves directly into CGPath.
It is not a redrawn logo, app-icon substitution or raster asset.

The reference CSS uses base width 11, opacity .9; busy base opacity .62;
halo width 15, opacity .3; beam width 8, opacity 1. All caps and joins are round.
Layer order is base, halo, beam. Halo and beam are hidden outside busy work.
Busy beam/halo use normalized 8/92 dash lengths; offline and reconnecting use
5/3 base dashes. The adapter converts pathLength=100 dash units using a bounded
arc-length estimate while preserving the exact curves for drawing.

Native rendering is deliberately static: no looping flow, pulse, blur, long-press
update gesture or drag behavior. Busy work uses a fixed segment and accent;
offline/reconnecting retain a dashed base; error and held use readable status
ink; completed uses accent without a timed pulse. Reduced motion hides halo and
beam and makes the static base opaque. Offline and reconnecting retain their
5/3 dashes. Increased contrast or reduced transparency removes
the halo and makes the base opaque. A separate existing status label must explain
work, failure or offline state at adoption; the mark cannot establish readiness.
The brand view exposes image semantics and a phase value, not a button action.

Scaling uniformly fits and centers the 240 by 220 viewBox, with letterboxing and
no crop/stretch. Intrinsic size is 44 by 41pt; give at least 24pt when adopting.
The final relationship to home/reader titles requires later visual review.

== Historical NA18 validation and handoff

At NA18, the opt-in `test_native_cream_design.py` compiled the two production
files and `NativeCreamDesignTests.swift` from an explicit source list before
NA20 registered them. The recorded command takes one outer shared lock:

```sh
D=/Volumes/devSSD/Developer/lagrangian-native-20261117
TMPDIR="$D/tmp/native-cream-na18" \
SWIFT_MODULECACHE_PATH="$D/cache/native-cream-na18/swift" \
CLANG_MODULE_CACHE_PATH="$D/cache/native-cream-na18/clang" \
NATIVE_CREAM_OUTPUT="$D/test-output/native-cream-na18" \
python3 "$D/tmp/with-native-swift-lock.py" -- python3 -B -m unittest discover \
  -s tests/flow-app/native-reader-app -p test_native_cream_design.py -v
```

Compiler flags are `-parse-as-library -swift-version 5 -warnings-as-errors
-target arm64-apple-macosx13.0`, with the explicit module-cache path. Tests use
an activation-prohibited NSApplication and hidden windows only. No general
clipboard, visible app, login, inference, user service or permanent setting is
used. The actual SVG/CSS supplies an independent coordinate/width oracle;
CoreGraphics compares original-path round-stroke pixels. NSColor, CoreText,
platform keyboard/target-action, mouse cancel and rapid activation are checked.
Hidden AX calls are compared with a plain NSButton; that is not real AX input.

External evidence belongs under `test-output/native-cream-na18`: REPORT.md,
handoff.json, tests.json, final-binding.json, exactdelta.json and raw command logs.
The final binding supplies exact committed source, actual compiler input hashes,
commands/exits/skips, and the current session's explicit resume reference.
Earlier failed test attempts remain separately preserved.

NA18 completed the shared components and focused offscreen validation. Its
contrast measurements describe the component host and preference matrix. Final
screen fit, focus, VoiceOver and actual macOS 13 behavior require separate
checks on the bound app. For NA19 screen adoption and NA20 delivery, use
the active OpenSpec design linked above. The original 125 cases and F04, F13
and NA16 remain separate acceptance obligations.


== NRD01B floating reader composition

The reader uses cream paper edge-to-edge, with 16pt padding inside its one-row
toolbar and a 1pt rule fading in beyond 4pt scroll. Ghost search and overflow use
SF Symbols. `NativeBrandMarkControl` adds status, refresh and injected Home while
preserving the original vector mark. `NativeModeMorphSwitch` uses a 32pt concave
track with sliding accepted-mode thumb: 140pt labeled in wide Reflow, 80pt icons
in compact Reflow or wide online PDF, overflow in narrow online PDF, and exact
`오프라인 PDF` badge for offline originals.

`NativeOutlineDrawerView` places a 24pt-radius glass panel on a content scrim.
It tracks the active heading with wash, accent text and a short accent bar;
keyboard navigation restores focus without clearing selection. Its toggle keeps
only the list icon at 680pt or below. Drawer, Aa and logo popovers are exclusive.

Notification and selection overlays use `NativeFloatingGlassView(.capsule)`.
Its clear outer layer carries two shadows; a continuous rounded inner clip holds
popover material, tint, edge and specular. Reduce Transparency or Increased
Contrast uses solid panel only inside the clip, 2pt boundary and attenuated
shadows, preserving transparent exterior corners. Aa remains opaque.
Notifications size to content between 160pt and min(520pt, content width minus
48pt), centered 10pt below the toolbar. `NativeOverlayPassThroughStack` passes
empty margins through. Persistent states offer 24pt inline pills, suppress lower
notices, never auto-dismiss and never take first responder.
Explicit notice tones select info, progress, offline warning, error and success
symbols with accent, warning, error and sage colors. Ghost cells retain their
native target/action and key equivalents; alignment insets are accounted for
so actual toolbar button bounds stay 32×30pt.

Selection tools use a 64pt surface with 28pt corners, centered 16pt above the
viewport bottom, capped at min(560pt, viewport width minus 32pt). Tiles have 17pt
symbols, 11pt medium labels, 62pt minimum width, 54pt height and 22pt corners.
Copy and Highlight use accent icons; Ask uses ink; red Strike uses reviewInk.
Source and Editor collapse to overflow at 640pt. A 1pt rule separates the 36pt
circular wash close button. A 40pt review capsule offers Undo and Clear above
tools in writable Reflow. A 26pt mini pill carries exact PDF capability footnotes
or the 32-block limit. Reflow reserves 104pt below content; PDF adds a temporary
scroll inset and uses selected page geometry to reveal ink. Selection never
changes the window frame, and printed PDF ink remains immutable.

The host routes mode, outline, refresh, review, Ask, zoom and tool-focus shortcuts
to existing owners. Cmd+0 remains Home; Opt+Cmd+0 resets zoom. Escape dismisses
Find, drawer, Aa/logo, tools retaining selection, then PDF selection. Tab and
horizontal arrows cycle visible tools. PDF search-field Escape follows that
order without invoking the explicit cancel button's selection release. Actual
offscreen key events verify Find-before-drawer and Aa-before-tools ordering.
A window-scoped keyDown monitor routes
Shift+Return before text inputs consume it. Offscreen automated tests cover these
source contracts, including a held Refresh that focuses a visible selection
release action without implicitly refreshing after release. Tests use generated
temporary fixtures; interactive GUI acceptance
and live installation are outside NRD01B verification.
