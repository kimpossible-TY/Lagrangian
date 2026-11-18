## Context

NA18 starts at v9 `00c28e9be4edb70c97b5a4a4d10e08c80c6c28ba` in
`feat/native-cream-20261118`. The PM's current exclusive-writer assignment takes
precedence over historical selector notes saying the worktree was not created.
The user's target is the native AppKit macOS application. Plan-93acf163de035059b497
and the PM's app-plan-native-cream-20261118 retain task and acceptance ownership.

## Goals / Non-Goals

Create usable common native paint and vector components while preserving platform
activation, content and existing operations. NA18 does not apply them to app
screens. NA19 owns screen/capsule adoption; NA20 alone owns sources.json and
packaging. No new runtime, account, service, policy or document renderer.

## Decisions

`NativeAppDesign` owns opaque sRGB palettes, measured control spacing/radii,
chrome-only font roles and state paint. Light starts at paper #F7F2E8, ink
#292722, panel #FFFCF5 and accent #514A83. Dark uses independently chosen solid
paper #24231F, panel #302E29, ink #F7F2E8 and accent #C6BEFF. Dark boundaries and
secondary text are brighter; selection has an opaque tint with normal ink.
High contrast strengthens boundaries. Reduced transparency requires no material
substitution because the baseline is already opaque. Reduced motion has no
queued animation to cancel. No treatment is claimed to be Liquid Glass.

`NativeDesignSurface` supplies paper/panel/floating containers; it paints a solid
paper backing around rounded panels. `NativeDesignButton` and its NSButtonCell
change paint only. AppKit retains tracking, target/action, keyboard equivalents,
responder focus, AX and command delivery. Hover/press never dispatch. Disabled,
cancel and window removal clear feedback. The platform exterior focus ring uses
a rounded mask. Minimum intrinsic height is 32pt and measured native title/font
size determines width and increased height. Layout/wrapping remains NA19's owner.
Chrome uses system fonts and a light rounded system brand title, with native
CoreText fallback. No brand font enters document, answer, math or PDF content.

`NativeBrandMark` copies all original cubic coordinates from
`tools/flow-reader/web/index.html`, viewBox 0 0 240 220. Source CSS at the current
base specifies base 11/.9 (busy .62), halo 15/.3 and beam 8/1, round caps/joins;
halo/beam are hidden except during busy work. Offline/reconnecting use 5/3 dashes
in pathLength=100 units. Native drawing preserves layer order and normalized
dash lengths, uses uniform centered fit and no blur/timer. Busy uses a static
8/92 segment; reduced motion hides halo/beam. High contrast/reduced transparency
remove the halo and make the base opaque. Error/held use readable error/warning
ink. Status labels remain required at adoption; a decorative mark cannot prove
readiness or replace textual diagnostics. This intentionally does not copy web
infinite animations, hold gestures, dragging or update authority.

## Surface and requirement mapping

C01: new shared components and original logo. C02: FlowApp buildWindow,
showSettings/settingsTabs (F01/F02/F15). C03: NativeReaderHostWindow loadWindow,
refreshStatus/requestMode/sourceControls and NativeReaderChatView composer,
send/history/account controls (F02–04/F06/F09–16 as mapped by PM). C04:
NativeReaderTextView selection callbacks/plainSelectedText/openChat provide the
selection anchor only; renderer remains unchanged. C05: existing conversation,
permission, offline and explicit-Send owners stay authoritative. C06: narrow
windows, enlarged labels, hit targets, keyboard and AX require screen adoption
and later actual input. C07: preference/state matrix and UI7-C1 retained failure
precedence; NA18 does not modify host status policy. C08: isolated build and exact
source/app/evidence binding remain NA20 and independent acceptance responsibilities.
NativeReaderOriginalPageView retains original PDF font/color/geometry.

## Verification and risks

The opt-in Python runner explicitly compiles the two new production files and
Swift harness under one shared Swift lock with arm64-apple-macosx13.0, Swift 5,
warnings as errors. Independent untouched SVG/CSS supplies geometry/width oracle;
CoreGraphics pixel equivalence covers round strokes, native NSColor resolution
covers contrast, CoreText glyph runs cover Korean/NFD/symbol fallback, and actual
offscreen AppKit controls cover command delivery, focus and cancellation. These
checks establish neither foreground AX/VoiceOver nor GUI feel. Build targeting
macOS 13 establishes SDK availability, not an actual macOS 13 runtime result.
Original failures and exact commands remain in external NA18 evidence.

## Follow-up and acceptance ownership

NA19 and NA20 require explicit PM resumption of this design session. NA21/22/23
perform independent source review/regression/docs work. PM binds the unchanged
source acceptance design (15 cases), design acceptance plan (32 cases total across
modes) and original 125-case expectations to the appropriate exact revision/app.
Assignments are not results. No NA18 result passes F04/F13/NA16, actual GUI,
whole-product acceptance or PM receipt. See canonical Typst for stage details.
