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


## NA19 implementation and source-only status

The PM explicitly resumed the same S18–20 writer on H18
`567841a5d200f15904c9cc824b9d15103a38b992`; board ownership is PM-maintained.
The NA18 canonical Typst records that earlier component stage and remains
read-only in this task. This section records the newer actual source application.
No source registry, packaging, new App, installed state or GUI claim is made.

FlowApp.buildWindow now uses the exact vector and shared light rounded brand
title, shared semantic buttons and a solid paper root for home/settings. Existing
project picker, settings fields/tabs, selectors and schema remain intact.
NativeReaderHostWindow uses shared button paint in primary/disclosure/review/
recovery controls, original vector status, and preference-aware labels/search/
outline chrome. NativeReaderChatView uses a solid panel around the unchanged
composer/transcript text views, shared semantic buttons and wrapping command row.
The existing measured native command-row implementation has one shared owner in
NativeFloatingCapsule.swift (NativeChromeControlRow), used by host/chat/capsule.
No body, answer, object, math or Original PDF painter is traversed by the chrome
adapter. Theme and rendering authority remain with the existing display owners.

The capsule is an in-window native view, bound to the exact request context
(document/service/revision/view/generation/request) and selection ticket/mode.
The TextView change is a read-only method returning current renderer-owned,
viewport-clipped selection rectangles. PDF geometry comes from its existing store.
The host observes only its own clip bounds and existing layout notifications.
It fits the capsule above/below visible selected rectangles inside the viewport;
when no safe space exists, it allocates a separate layout row rather than
covering selected content, search hits or primary controls. The capsule scrolls
its own wrapping controls when enlarged labels need more height.

Session.authorize and Selection.validate remain authoritative. Over 32 fragments,
read-only/offline/restored/pending work and PDF modes project existing restrictions
into disabled reasons. Ordinary copy retains the full selection and uses the
existing injected copy callback. Editor consent and source-write restrictions
come from the existing attachment; the UI does not grant or persist permission.
Dismissal never acknowledges selection. Old dismissals and acknowledgments cannot
close a new binding. Explicit selection action entry supports keyboard focus;
Escape/close returns focus while leaving retained selection intact.

Every Ask entry opens the actual local composer with its exact current selection.
It does not resolve operations, open/create a remote conversation, read account
status, save a server draft or start inference. Explicit Send resolves the existing
actions owner, rechecks current authorization after awaits, reads existing account/
models, refuses unavailable permission/model, and opens the conversation only then.
The same explicit Send continues through the established message UUID/unknown-effect
owner. Existing accepted-conversation, history, pending-Send and math behavior stays
in that owner. Local draft editing has no remote draft operation because no
conversation exists before Send. No provider, model catalog, credential or
conversation database is invented by the new UI.

UI9-C1: pending recovery loading and failure now outrank generic recovery mode
restrictions. These flags are direct projections of Session.hasPendingRecovery,
state and failure, not a new lifecycle store or success boolean. The primary
status never recommends disabled live refresh. Explicit retry uses Session's
existing preparationChanged; explicit cancel uses existing storage cancellation
or Session.cancel. Successful recovery's bidirectional mode refusal (UI7-C1),
live held-selection/release/explicit retry and live refresh behavior remain gates.

Validation uses actual offscreen controls and actual Session recovery prepare,
with compiler-produced semantic/PDF fixtures. A gated prepare records pending
loading, failure, retained prior publication/context, source denial, mode/refresh
restriction and zero added live calls. The before copy is read-only H18 Git bytes
under external NA19/before, never a frozen-worktree edit. The identical expectation
fails before and passes after. Every attempt preserves its source/runner bytes,
actual argv, hashes, exits and logs. Untouched regression runners receive only
isolated output-path and explicit Swift-source adapters, with original runner
hashes and unchanged assertions recorded. Fake network/counters are identified
separately from real native controls, compiler/PDFKit and local editor fixtures.
Actual GUI/VO, real accounts/inference, macOS13 runtime, NA20 delivery, independent
NA21/22/23, F04/F13/NA16, original125 and PM receipt remain separate gates.


## R19 boundary corrections in the same NA19 writer

R19-1 seals the initial Send click's exact Unicode question, text-edit generation,
model-edit generation, selected model and bound selection before asynchronous
account/selection/conversation preparation. A changed draft/model stops automatic
continuation and requires another explicit Send. If conversation opening already
completed, the existing conversation is adopted with the current draft still
visible; neither old nor replacement question is sent implicitly. The normal Send
message UUID, receipt, cancellation and unknown-effect owner remains unchanged.

R19-2 retains the actual unsent composer when selection changes or an old selection
acknowledgment arrives. The Session authorization closure disables Send and explains
the mismatch. The original selection binding survives lazy conversation setup;
no new selection/effect authority or draft store is introduced. Only explicit
close/replacement or the established document/view lifetime disposes presentation.

R19-3 uses a read-only query of actual current TextKit used bounds, including
attachments, to establish occupied body content. A capsule overlay must avoid
both selection and all visible used content inside the document viewport.
Unavailable/stale geometry and the PDF viewport are conservatively occupied;
otherwise the existing separate dock row is used. No body paint, selection,
source or PDF geometry owner changes. The prior shared measured row layout now
has one chrome owner, NativeChromeControlRow in NativeFloatingCapsule.swift, used
by host, composer and capsule.

External round2 evidence freezes the current pre-fix dirty NA19 production bytes;
it is explicitly NOT the H18 commit. Independent actual-native/HTTP oracles fail
on those bytes for account-wait edits, open-wait edits, model-wait edits, vanished
unsent draft and body occlusion, then use the same expectations against the fix.
The earlier H18 UI9-C1 before evidence remains separate. Raw home settings JSON
and canonical JSON retain exact schema/types/values while allowing unspecified
object-key order. No old report/output is overwritten. Parent-interrupted run1
work is marked interrupted rather than accepted as final evidence.


The existing measured wrapping row is shared as NativeChromeControlRow in
NativeFloatingCapsule.swift by reader, conversation and capsule controls. This
moves the original layout implementation to one reusable presentation owner;
it creates no operation, state, credential or renderer authority. NativeChrome
bridges dynamic chrome colors only and stops traversal at document/PDF/text views.
