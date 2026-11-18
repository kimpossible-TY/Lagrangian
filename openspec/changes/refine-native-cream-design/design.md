## Context

This change applies the user's cream paper, original rounded marker logo and
floating selection capsule to the Swift/AppKit macOS app. The SCSS request
informs reusable components and state tokens. AppKit owns their implementation.

NA18 began at v9 `00c28e9be4edb70c97b5a4a4d10e08c80c6c28ba` and produced the
[historical component contract](../../../docs/tinymist/dev/native-cream-design.typ).
NA19 applied it to the home, settings, Reader and conversation chrome.
NA20 registered the new sources and delivered an isolated development app at
`016734db869f8892bf2cd1e330be2fb4edda962f`.

## Goals / Non-Goals

Share native paint and vector components while preserving platform activation,
content rendering and the existing operation owners. The design adds no new
document renderer, service, account store or web UI runtime.

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
8/92 segment. Reduced motion hides the halo and beam and makes the base opaque.
Offline and reconnecting retain their 5/3 dashes. High contrast and reduced
transparency remove the halo and make the base opaque. Error/held use readable error/warning
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
permission, offline and explicit-Send owners stay authoritative. C06 covers narrow
windows, enlarged labels, hit targets, keyboard and accessibility. C07 covers
the preference matrix and UI7-C1 failure precedence. C08 binds source and app
identity to separate evidence for the build and the assigned acceptance checks.
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

The PM binds every required case to its unchanged expectation, assigned owner,
source revision and artifact. The independent reports record actual assignment
and result references separately. Use the following locators in the PM project
workspace under `native-reader-20261117/` and in the project test-output directory.

| Contract or evidence | Locator and fixed revision | Scope |
| --- | --- | --- |
| Original `lagrangian-native-app-actions-acceptance-20261118-v1` | `app-plan-native-actions-acceptance/acceptance-plan.json`, design source `09e78630a6afb51436e45da140c3588c82c295f5` | F01–F18, 125 original cases. See the [migration inventory](../../../docs/tinymist/dev/native-reader-20261117-inventory.typ). |
| Cream design `lagrangian-native-cream-acceptance-20261118-v1` | `app-plan-native-cream-20261118/acceptance-plan.json`, design source `cb31c504d21a16dd8fc4786537c7917a14970588` | All original cases plus 32 new cream cases. |
| Cream source `lagrangian-native-cream-source-acceptance-20261118-v1` | `app-plan-native-cream-20261118/source-bound-4bd6e0da/{acceptance-plan.json,contracts.json}`, fixed `4bd6e0da0d529dafa9993ff8467cac4652bfa2ac` | 15 source-only cases. Keep their assignment-time contract hashes and results separate from an app packet. |
| NA19 round 2 | `test-output/native-cream-na19/round2/{REPORT.md,tests.json,final-binding.json,before-after.json}`, bound to `4bd6e0da0d529dafa9993ff8467cac4652bfa2ac` | Producer recorded 15 focused offscreen tests and a separate one-test ChatMath rerun, each exit 0 with no skips. The records retain the initial ChatMath failure, the expected before failures and interrupted attempts. |
| NA20 round 4 | `test-output/native-cream-na20/{REPORT.md,final-binding.json}`, fixed `016734db869f8892bf2cd1e330be2fb4edda962f` | The isolated development app includes the three registered Swift sources. Its bound fixture checks recorded three passes with no skips. The fixture supplies no Original PDF, chat, account, editor or live service owner. |

NA16 is the separate F13 work to connect explicit native login, cancel and logout
to the existing account authority. Listing status or models and linking to
Homepage do not complete it. F04 raw delta, F13/NA16, the original 125 cases,
real macOS 13, same-app native interaction/visual/VoiceOver and PM acceptance
retain their own evidence requirements. NA18 contrast ratios and images are
component observations listed in the historical record. Same-build visual
contrast and the narrow-window layout still need separate observations.

## NA19 source adoption

NA19 resumed the design writer from H18
`567841a5d200f15904c9cc824b9d15103a38b992` and applied the shared components.
This section describes its fixed source. The NA20 record above covers source
registration and the later isolated development app. The NA20 checklist records only completed source registration and isolated app
production. Use each bound app packet to identify its actual source and remaining
independent GUI, original 125-case, NA16 and PM-receipt gates.


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

The capsule binds the active request context (document, service, revision,
view, generation and request), selection ticket and current mode. The host
rechecks the binding before dispatch. `Session.authorize` and
`Selection.validate` enforce live context and the 32-block action limit.
The display selection remains intact when that limit rejects source or Ask.

| Command | Existing owner and behavior | Availability |
| --- | --- | --- |
| 복사 | Body display copy uses `NativeReaderTextView.copyPlainText`. Original PDF delegates to `NativeReaderOriginalPageView.copyDisplay`. | Current visible selection, including longer selections or a read-only view. |
| 원문 보기 | `requestSource(.excerpt)` uses the source action owner and copies a verified excerpt after freshness and document checks. | Live eligible body selection. PDF, offline, restored or otherwise unauthorized contexts disable it. |
| 원문 강조 | `requestSource(.highlight)` uses the existing source write path. | Live eligible body selection and a source-write attachment with no managed-editor consent ID. While capability is unknown it stays disabled. The source owner still checks write authorization. |
| 질문하기 | `openChat` opens the local composer through the host. | Live eligible body selection. Sending has its own account, model and selection checks. |
| 편집기 위치로 | `locateSelected` delegates to the existing guarded editor jump. | Live eligible body selection and a current editor attachment with a managed-editor consent ID. While capability is unknown it stays disabled. The jump still checks the existing attachment and consent. |
| 닫기 / Escape | The host dismisses only the current binding and restores focus without releasing or acknowledging the selection. | The capsule is open. The explicit 선택 작업 command opens or refocuses it and moves focus to the first enabled action or Close. |

The placement input is the clip viewport, current visible selection rectangles
and the renderer's visible used content bounds, including attachments. The host
hides the capsule when no selection rectangles are visible. PDF and
unknown/stale used bounds treat the entire viewport as occupied. Overlay width
is `min(560, max(120, viewport.width - 16))` pt. The height is capped at 180 pt
and the internal scroll view accommodates wrapped commands. The host insets the
viewport by 8 pt. Placement tests a horizontally clamped frame above or below
the selection's union with an 8 pt gap and 4 pt clearance from the selection
and occupied bounds. If no frame fits, the host uses a layout dock outside
the document view, with its width pinned to the containing stack. The dock
remains until the capsule is hidden.
The host recomputes placement on its clip and layout updates.

Ask opens a local composer for the selected passage. Opening or editing that
composer sends no account, catalog, conversation, draft or inference request
for Ask. Selection registration and capability checks are independent.
Explicit Send resolves the existing actions owner, checks authorization after
awaits, reads account and models, and refuses unavailable permissions/models.
A first Send without a selected model can continue with the first returned
model. A question or model edit during preparation requires a new explicit Send.
The established message UUID, authorization and unknown-effect owner governs
dispatch. Existing draft and pending-state recovery remains a requirement.

The chat repair at `8e57062ea768320c3fe64f266eb50f40f53d16c1` reuses
current/recovered draft adoption and persistence for actual host Ask reentry.
Within the same living Reader context and exact selected range, reopening an
already created conversation restores its latest Unicode draft/model and original
unknown Send UUID/question/model without retyping. Up to32 presentation
associations distinguish known passages; they do not authorize Send or persist
across Reader lifetime. The current selection ticket is checked on explicit Send.
An uncreated initial draft and app restart have no immediate restoration guarantee. A newer local
edit wins. Successful explicit Refresh must precede unknown-Send resolution:
matching original history permits a new question, absent confirmation permits only
the original question/model/UUID retry, and failed Refresh retains uncertainty.
Closing and reopening an unconfirmed pending Send requires a fresh successful
Refresh before retry. Refresh is available for an open conversation when no
other conversation action is in flight, using existing context authorization.
New Send still requires current selection authority, while Stop/history use the
existing conversation/context authority. Stop requires an accepted streaming
conversation; local account/open preparation alone supplies no Stop target. Initial Ask
and editing add no account/model/conversation/draft/inference effects; selection
registration remains a distinct operation. The recorded 26 offscreen checks,
including unchanged passive ChatMath, are not same-app GUI/VO acceptance.

The current three-argument fixture integration composes local fixture/bundled math
without default or explicit manager/editor connections. External targets are
disabled and guarded, child verification gets dedicated root-bound environment,
and home/body copy share a private board. Normal nonfixture composition remains
in its existing owners. Virtual-home/injected-operation and actual Swift math
checks must be distinguished from GUI launch and full platform IO isolation.


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
These are NA19 checks. NA20 delivery and the independent source, native GUI,
VoiceOver, actual macOS 13, live account/inference and PM results each have their
own evidence requirements as listed above.


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
it is explicitly NOT the H18 commit. The offscreen native and injected HTTP oracles failed
on those bytes for account-wait edits, open-wait edits, model-wait edits, vanished
unsent draft and body occlusion, then passed with the same expectations against the fix.
The earlier H18 UI9-C1 before evidence remains separate. Raw home settings JSON
and canonical JSON retain exact schema/types/values while allowing unspecified
object-key order. No old report/output is overwritten. Parent-interrupted run1
work is marked interrupted rather than accepted as final evidence.


The existing measured wrapping row is shared as NativeChromeControlRow in
NativeFloatingCapsule.swift by reader, conversation and capsule controls. This
moves the original layout implementation to one reusable presentation owner;
it creates no operation, state, credential or renderer authority. NativeChrome
bridges dynamic chrome colors only and stops traversal at document/PDF/text views.

The fixture keeps the existing local offline recovery library under its dev-profile
root, including saved drafts. Offscreen construction respects the existing
showNativeWindow input; it does not grant manager, editor or external effects.

## NA24 review repair boundaries

Fixture field editors and multiline input views enforce the same clipboard restrictions. Standard
Cut/Copy/Paste is refused at the responder, including keyboard and direct action
entry; normal AppKit editing is unchanged. Existing private home/body/PDF Copy
remains separate. Offline Original PDF rendering stays available, while fixture
Export UI, forced callback, destination selection and staging refuse effects.
Normal export still validates and publishes exact accepted bytes.

Known exact-range associations reference a conversation UUID; one bounded latest
display snapshot per UUID supplies draft adoption across ranges in the same
paragraph. Separate paragraphs remain separate, and this cache never authorizes
Send. While Stop is in flight, both its button and handler refuse duplicate Stop
entry without cancelling the genuine first completion. Disposal/context/epoch
and monotonic accepted-record checks still reject stale replies.

Stop uses existing conversation/context authorization. After its owner await,
cancellation, lifetime, operation epoch, context and conversation identity are
rechecked; the latest accepted nonolder record is presented immediately without
clearing pending Send through a new reconciliation path. Late/disposed results
cannot update presentation. Fixture settings read a no-follow regular descriptor.

Optional startup diagnostics enqueue only owned path/data and descriptor state.
Neither init nor deinit performs or waits for filesystem I/O. Existing no-follow,
regular-owner/private-file checks remain, with bounded records and file growth.
The old main-thread open sample is evidence of waiting, not a root-cause finding.
The new app's first window still requires PM-assigned same-computer background
launch by Dogfood; offscreen checks do not complete GUI/VO/macOS13 gates.
