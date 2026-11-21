= Native editor actions (NA15)

This component implements F10's explicit source jump. The original F10 inventory
and MIGRATION requirements remain inputs. It does not complete NA16 account
work, final delivery, GUI acceptance, VoiceOver or actual macOS 13 verification.

= Mapping and effects

`NativeReaderActions.perform(.locate)` retains its existing read-only mapping
contract: verified means source correspondence and an opaque semantic anchor.
It never establishes that an editor moved. The native Locate Source control now
calls `NativeReaderActions.jump(_:query:)`. Its separate
`NativeReaderEditorReceipt` contains only correlation IDs and a bounded status.
Only the existing Neovim Lua owner's `jumped` response establishes movement.
No source path, hash, coordinates, editor address or registration token enters
product feedback, accessibility, clipboard or result DTOs.

`NativeReaderTransport` carries selection synchronization, prepare, explicit jump,
and receipt reads through `/api/native-editor`. The production HTTP owner retains
its Host, exact Origin, body-size, framing, proxy and registered-document guards;
this endpoint additionally requires the genuine IPv4 loopback socket peer and a
loopback Host. HTTP cannot register an executable, address, source path or cursor.

`services/native_editor_actions.py` coordinates these bounded requests over
`AcceptedSnapshot`, `SavedSourceNavigation`, `EditorAttachments` and
`NeovimEditor.jump`. The existing source mapping alone supplies the private saved
source span, SHA-256, line and zero-based UTF-8 byte column. The adapter never estimates
coordinates from native text, PDF, glyph geometry or semantic anchors. Preparation
captures the exact mapping; dispatch resolves it again and requires equality.
Final Lua delivery rechecks disk hash, target buffer bytes and modified state.
Source writes are zero; even another dirty buffer remains intact.

= Explicit local consent

FlowApp's Connect Editor menu action chooses an existing private local JSON
descriptor, validates it off the main thread, then asks for explicit Connect
consent. The four exact descriptor fields are `address`, `executable`, `ownerPID`
and `controlFile`. Descriptor and control must be regular, locally owned private
files; the executable must be absolute and executable and the owner must be live.
The descriptor is supplied by the existing editor owner, never discovered from
processes, ports or environment. There is no automatic default editor opt-in.
The native chooser/consent interaction itself still requires GUI acceptance.

The consented `NativeReaderManagedEditor` is consumed for one native client.
The local manager's additive `--native-editor-consent` flag validates private
control and an exact executable before using the existing private registration.
Its acknowledgment is `nativeEditorActions: 1`. Ordinary terminal registration
schema and behavior remain compatible. FlowApp passes the editor into the real
managed client; HTTP never receives registration authority. Closing/replacing
that client or restarting the service does not renew native consent. Reconnection
requires another explicit Connect. Disconnect revokes the native view; it never
stops Neovim, the shared service or another attachment, or deletes user files.
Existing registration cleanup and its 32-active-attachment limit stay with the
manager and attachment owner.

= Validation and lifetime

Before effect and before adoption, bind document, service incarnation, revision,
input ID, view, generation, document request UUID, full exact selection and ticket,
consent UUID, sequence, attachment and receipt UUID. Prepare and dispatch also
bind the private verified source span and exact local registration, control and
executable file identities. Failed newer selection validation revokes old pending
work. Same-view synchronization requires its original consent and attachment;
a foreign attachment cannot close that view. Monotonic sequences reject reordered
updates; close leaves a tombstone. Native cancellation revokes local authority
first and makes only a bounded best-effort revoke/close request.

The effect gate retains edit-lock then publication-lock ordering. A queued
cancellation can prevent dispatch. Cancellation after RPC starts cannot promise
rollback: an actual move may have occurred and an obsolete response cannot be
adopted or clear a newer selection. Restart, expired preparation, changed saved
input, dirty target, missing control, dead owner and revoked registration fail
closed. Offline and Original PDF acquire no source authority.

= Receipt and resource bounds

A prepare is valid for ten seconds. At most 128 views/tombstones and 128 pending
preparations are held per service. A private 0600 SQLite receipt file retains at
most 4096 consumed request identities; capacity exhaustion returns unavailable,
never evicts an identity to permit a replay. It stores only UUID, private binding
digest and bounded status, never source contents or coordinates. The service
incarnation in that binding prevents replay across restart.

The adapter commits `unknown` before the RPC and records its outcome afterward.
Duplicate UUIDs return the prior receipt or refuse a different binding; they
never redispatch. Lost response, timeout or interrupted receipt persistence has
unknown effect. Check Editor Result performs one bounded read, with no automatic
retry or polling loop. The native actor blocks new jumps while its previous
outcome is uncertain. Stale selection cannot recover an old effect into new UI
state; reconnect with fresh explicit consent is required when that binding is
unavailable. Neovim RPC is capped at 2.5 seconds; requests retain the transport's
existing finite size/time budgets and close notification is capped at 3 seconds.

= Verification and delivery

`test_native_editor_dispatch.py` uses an actual isolated prebuilt compiler,
production HTTP, private local registration and headless Neovim. The dedicated
`NativeEditorActionTests.swift` adds actual native Swift action/transport calls.
Its response gates and dropped acknowledgment are injected fault conditions;
the compiler, HTTP service and editor effect remain real. The independent oracle
uses raw `nvim_win_get_cursor`, `nvim_buf_get_name` and buffer reads, never the
jump response or `reader.cursor`. Evidence records before/after source and buffer
bytes, expected file/line/UTF-8 column, receipts, exact exits, skips and hashes.
Fixture source mutations belong to negative-test setup, not application writes.
Headless Swift and offscreen AppKit regressions do not establish real native UI
operation, visual quality, VoiceOver, focus or macOS 13 runtime support.

No new production Swift file is required: all new types are in existing listed
sources. The dedicated test is manually added to the sources.json-based test
compile. The new Python helper must enter the next tracked reader bundle,
portable backend and installed layout. The integration owner must append an exact
source correction inventory and rebind runtime/backend/application signatures
and hashes. Existing immutable bundles remain unchanged; this component must not
relax source pins or treat HEAD as a blanket delivery grant. NA16 takes the
verified shared-file component in sequence and preserves this editor API.

Native manager registrations add the optional `nativeJumpOnly: true` marker.
`EditorAttachments.resolve` continues to serve existing source-write consumers
and refuses these movement-only tokens; the new jump adapter uses the existing
private record validation instead. Attachment connection acknowledgment validates
record lifetime without granting write capability. The Swift source adapter also
rejects Highlight through this consent. Therefore Connect Editor does not enable
an implicit source writer; legacy terminal/write registrations remain unchanged.
Closing or disposing the native host revokes this consent even while attachment
resolution is pending, while ordinary document reopening remains available.

The host serializes move/receipt controls and preserves the original uncertain
receipt UUID on repeated clicks. `pendingEditorReceiptID()` exposes only that
bounded correlation ID from the action owner. No newer action may replace an
unresolved receipt or cause automatic dispatch; receipt feedback still validates
the current native request and selection before adoption.

= NA15 supervised receipt-lifetime correction

A request digest alone cannot confirm an editor effect after a private token's
registration changes. Consumed receipts now also persist the exact registration
fingerprint captured before the effect: record fields and registration/control/
executable device, inode, timestamps, size, ownership and mode. Replacing an
address, registration file or control-file lifetime makes receipt, duplicate
prepare and duplicate jump return unknown without redispatch. The old UUID stays
consumed. Existing database rows gain a nullable fingerprint column; rows without
that proof remain unknown even if their historical status was jumped. No private
fingerprint or record is returned to native feedback.

Native coordination requires the local record's `nativeJumpOnly` value to be
exactly boolean true. An HTTP-supplied consent UUID cannot promote a legacy
terminal token or a malformed marker. The legacy write resolver remains unchanged.

The supervised fixture uses NSApplication's prohibited activation policy and
explicitly hidden native windows. FlowApp's Read closure and the offscreen tests
share `readNative`; descriptor validation and adoption share
`connectEditor(descriptor:for:consent:)`. Only the explicit consent decision and
local manager inventory are injected. The test changes the actual TextView
selection and invokes the host Locate/Check Result selectors, exercising the
production callbacks and real HTTP/editor effect. Lost acknowledgment, repeated
Locate and Check Result query the original UUID. New selection, close, changed
source and replaced registration retain their failure boundaries. Independent
Python RPC observes file, line, UTF-8 column and every loaded buffer. This proves
offscreen AppKit control events; the chooser/alert and real GUI/foreground, visual,
VoiceOver and OS13 runtime acceptance remain unverified.

Private editor coordinates use a one-based line and zero-based UTF-8 byte column.
The existing source/Neovim owners check range and character boundaries, including
continuation-byte rejection; native feedback does not gain source coordinates.

= v4 selection independence and exact local lease cleanup

A valid body selection is checked and adopted independently of optional editor
synchronization. Every changed or invalid selection first revokes old pending
editor work. A dead owner, missing private control/registration or sync transport
failure leaves editor Locate unavailable; source excerpt, mapping-only locate
and Ask keep their accepted-document authority. Wrong document/input/context and
invalid/over32 source selections still fail. No error turns a mapping receipt
into an editor effect or resends an uncertain jump.

The current production native resolver creates an opaque operation and retained
lease before attach. It calls local `--attach` with `--native-editor-operation`
and `--native-editor-deadline`, in addition to explicit movement consent. Under
the existing manager lock, EditorAttachments stores a private bounded durable
operation intent before publication. Reserved requires token/profile/document and
deadline; prepared/issued also require complete record SHA-256 and inode. Only a
complete fsynced staging record becomes visible through exclusive hard-link
publication. A partial staging file is never an attachment. Cancellation first
persists the tombstone, then verifies that exact operation/digest/inode before
reusing the existing native-token retirement owner. Replacement/collision fails
closed without removing the other file.

`--release-native-editor-operation --root ROOT --entry ENTRY
--native-editor-operation OPERATION` withdraws only that exact locally known
operation, optionally scoped by `--reader-service ID`. It needs no live service,
current source file or current registration in config to withdraw old authority.
It cannot approve a new attachment/descriptor. The existing token release remains
compatible; no HTTP registration/delete/path authority is added. Terminal default
register is unchanged in call shape, private policy, source authority and32 quota.
Direct legacy native-consent attach without an operation is still compatible but
has only response-token cleanup, not the new pre-response crash guarantee.

=== Local operation interoperability

The existing local CLI remains the owner; these are not HTTP endpoints.
#table(columns:(1.2fr,3fr),inset:4pt,align:top,
 table.header([Field/operation],[Contract]),
 [`--native-editor-operation`],[Exactly64 lowercase hexadecimal characters, generated by the caller before registration; not a hyphenated UUID.],
 [`--native-editor-deadline`],[Finite Unix epoch seconds. New reservation requires0 < deadline - now <=7; cleanup has its own finite remaining deadline.],
 [`--native-editor-expected-scope`],[The new managed caller passes its queried64lowercasehex scope with the native operation. The manager rejects a different actual registered document/reader before reservation or registration, and rechecks issuance freshness before publication. Legacy local callers without this optional field retain their prior contract; response-only comparison is not the new guarantee.],
 [Attach response],[Echoes the exact `nativeEditorOperation`, plus manager-owned `nativeEditorScope`; the resolver checks both before adopting.],
 [Cleanup response],[Exactly one field `released` with JSON boolean type. `{"released":false}` confirms the exact registration is already absent; it is successful confirmation. Extra fields, nonboolean, parse or command failure remain pending.],
 [`--native-editor-scope`],[Read-only root/entry/optional registered reader ID query. Returns exactly `scope` (opaque64hex, or null when no unique valid document) and `requestBinding` (opaque64hex). It neither probes nor starts services or publishes a registration. Optional query deadline is finite future Unix epoch (not the reservation7second limit). The managed Swift caller's CommandRunner sets a 1-second execution timeout for the query, shortened to min(1, deadline-now-0.2). On timeout it requests termination, gives a 0.2-second grace window before forcing termination if needed, and waits for exit. The direct CLI checks the supplied finite-future deadline on entry. Nonpositive budget fails before execution. Command, parse or exact-shape failure rejects a new grant and preserves pending leases. Null scope denies a new grant but its original requestBinding can still retry exact withdrawal.],
)

The manager preserves the original absolute request expression (with NFC spelling), including dot components: lexical link/.. reduction can name a different real file. Equivalent spellings are correlated by manager scope, not by removing those components. Existing records with only a reduced spelling cannot reconstruct a discarded original expression; no fallback guesses that authority.

New operation records distinguish stable lexical caller request binding from the
actual document root/entry validated during issuance. Withdrawal validates the
original request/reader ID and private operation record plus registration
SHA-256/inode; it does not resolve current filesystem aliases. Removing, renaming
or retargeting an internal root/entry alias therefore cannot prevent exact
withdrawal or authorize a different target. Attach still requires existing
registered actual scope/type/Unicode identity and unchanged source/service.
The existing operation owner validates its private record; this document does
not define a parallel internal journal schema. Existing version1 records remain
readable under their prior resolved binding; an alias spelling never captured by
an old record cannot be reconstructed after disappearance. There is no migration
or scan to guess that missing authority.

Resolver copies and successive FlowApp clients share the caller-known leases.
Command/lock/invalid-result failure stays pending after resolve throws, instead
of losing the nonce in a stack local. A subsequent explicit connect, Read or close
may try one pending lease within its budget; confirmation alone removes it.
Concurrent attempts coalesce. Only a new consented editor grant is blocked by
unconfirmed cleanup. Manager-owned registered document/reader scope binds this
gate across `main.typ`, `./main.typ` and supported aliases. The original request
binding also finds a retained exact operation when its alias is gone/retargeted;
it confers no new attachment authority. A different actual document/reader scope
is independent. Swift consumes opaque bindings and does not reimplement path
matching. Plain body Read does not retry or confirm editor retirement,
and keeps accepted Source/Ask authority with zero editor movement permission.
No journal scan, resident cleanup timer, automatic retry/inference or service/editor/control
termination occurs.
Private journals/tombstones are retained; automatic pruning and automatic recovery
following an entire app-process restart are not provided. Tests separately cover
surviving-caller recovery and explicit exact-operation recovery after both test
processes die. They do not prove automatic restart recovery.

The ten-second native caller budget includes pending retry, prepare/ack, final
HTTP state verification and cleanup. Manager preparation is at most6.5 seconds,
its process ceiling7, cleanup process ceiling2.5, shortened by remaining deadline.
The final state request reserves2.75 seconds for cleanup/TERM grace. Its
per-operation absolute deadline cancels the owned URLSession task and awaits
`didCompleteWithError` before returning. A short idle interval between response
bytes cannot extend this deadline; late success is also rejected. Ordinary
network session timeouts are unchanged.
These are measured bounded fixture budgets, not OS real-time guarantees. Process
cancellation performs bounded TERM/KILL and waits only for its own manager child;
shared-service lifecycle rollback is not implied.

Historical299 used a response-bound lease: its retained `resume2-*` timeout and
SIGKILL witnesses leak two registrations and desired oracle exits1. The current
component's actual registration-before-plan gates, state-delay combination,
manager crash, pending-client retry, malformed journal and lock witnesses are in
DevSSD `test-output/native-reader-identity-ui-v5/resume5-handoff.md`. This is a
source-only correction, not a new App, actual GUI or overall F10 acceptance.

The local production descriptor export is
`--native-editor-descriptor --root ROOT --entry ENTRY --token EXISTING_TOKEN`.
It accepts an existing private service registration with a live owner and private
control file and returns `descriptorFile` under the manager-owned private
`native-editor-descriptors` directory. Its exact four fields are reused by the
native Connect Editor chooser/consent owner; HTTP never registers these fields.
The user explicitly selects that generated file in Connect Editor. It is not
editor discovery, automatic consent or a source-write grant. Missing/stale/private
storage failures preserve prior descriptors. The fixture verifies this actual
manager generator and the same FlowApp descriptor adoption API without opening
a chooser. Actual GUI selection/consent acceptance is still pending.

The retained v5 independent full-suite queued-cancel failure remains a failure;
its missing setup/queued/revoked signals cannot be replaced by later diagnostic
passes. The v6 fixture confirms setup, takes the actual effect lock, observes the
persisted unknown jump after transmission, then observes revocation before
unlocking. A failed gate precondition fails and revokes only the fixture token
before cleanup unlocks it. These tests hold the actual selection edit_lock after a jump is transmitted
and its durable unknown row is committed. A newer invalid selection or explicit
view cancellation revokes the old lease before that effect gate is released;
source bytes and the independent Neovim cursor/buffers remain unchanged. This is
separate from delaying a prepare response. Existing after-dispatch uncertainty
and exact original receipt lookup remain unchanged.

The immutable v4 quota regression used an ASCII registered entry. Its retained
Unicode manager reproduction failed when NFC/NFD spellings named the same macOS
file but resolved Path strings differed. That gap remains a limitation of the
frozen d7/v4 App and its historical acceptance packet. The v5 source component
below corrects matching; it has not been registered, packaged or GUI accepted.
Existing v4 reports and original design/case hashes remain unchanged.

= v5 managed document identity and source-only verification

ReaderManager owns this correction. A new attachment requires an existing actual
directory and regular entry, with the resolved entry inside the actual project
boundary. Registered and supplied resolved spellings must be Unicode canonical
equivalents (NFC comparison), and their device/inode identities must match for
both root and entry. Only then is the original registered profile, ID and entry
spelling returned. Normalized text alone and samefile/inode alone are insufficient;
different roots or hardlink names do not become the same document authority.
Compatibility normalization and case folding are not added. Existing exact
resolved aliases inside the approved document scope retain their contract;
symlink targets outside that root, missing paths and wrong types fail closed.
Multiple matching registrations remain ambiguous without the exact explicit
reader-service ID. Source mapping, accepted input/service checks and Lua's final
saved-source/modified-buffer checks remain with their unchanged owners.

Withdrawal is separate from new attachment or descriptor publication. If source
has been renamed/deleted, the registered spelling may select only the local
retirement path. It reads only that exact64-hex token's bounded private record
under the selected profile directory, then delegates native-only removal to
EditorAttachments.release_native. Its retained document ID is retirement data,
not a fresh source/input or editor grant. Other tokens, control files, source,
editor and service are preserved; no HTTP deletion API or new discovery exists.
A live entry still uses the existing document_identity owner and rejects a
mismatched record. Descriptor export always requires live validated paths.

The filesystem oracle uses actual NFC/NFD root+entry names with spaces, quotes
and Hangul, real stat/content and hardlinks; it does not mock samefile or aliases.
The manager-to-production-HTTP fixture moves the same isolated headless Neovim
cursor to independently specified line/UTF-8 column and compares source/buffer
bytes. Configured profile inventory and managed PID observation are explicit test
inputs; HTTP, compilation, registration and editor effect are real. APFS results
do not certify other filesystems, races after observation, native GUI/focus,
VoiceOver or actual macOS13. The source component's fixed SHA and exact delivery
delta go to PM for later sourcepin/packaging approval, not to the immutable v4 App.


== v6 source component and immutable evidence

SF2-B1 slow-drip, SF2-P1 six alias mutations and pending-caller recovery, and
V501 canonical-scope gate corrections are source-only. Actual v6 before/after,
input hashes, failed attempts and remaining gates are external DevSSD
`test-output/native-reader-lifetime-v6/REPORT.md` and `handoff.md`. Historical
H5 and `native-reader-identity-ui-v5/resume5-handoff.md` results are not rewritten.
The frozen d7/v4 App has not received these changes. Integration/source registry,
a new App and independent GUI/VO/actual macOS13/live-provider/125case acceptance
remain PM gates, along with F04 raw deltas and F13/NA16. No automatic entire-app
restart recovery or journal pruning is claimed.

= Fixture inspection boundary

With an explicit dev root and native fixture, editor connection is unavailable
both from controls and direct descriptor/consent methods. No manager is created
for this path. This development boundary does not change the normal live editor's
existing explicit consent, source/context validation, receipt or unknown-effect
owners. Offscreen injected operations establish this refusal; they do not complete
actual GUI, VoiceOver, platform isolation or independent F10 acceptance.
