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
source span, SHA-256, line and UTF-8 byte column. The adapter never estimates
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
