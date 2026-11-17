#set text(size: 11pt)
= Isolated native Reader inspection preparation

Current staged baseline `09c5186bff1850b17f6e85fe2f3115153520bc94` combines
core, original-page service/view, G1 inspection and published provider inputs.
Its app staging/integrity exists; official final review, independent GUI/AX and
PM acceptance remain incomplete. New review-fix source is not automatically
included in that app and must be restaged/rebound separately.

== Current final inspection entrypoint

Use `tests/flow-app/native-reader-app/test_page_delivery_bundle.py` as SCRIPT.
The original `test_app_integration.py` is the G1 fixture owner with a different
root contract, not the final root entrypoint. G1 denotes historical isolated GUI
preparation at1e32419d; C/NA12 denotes original pages and D/NA13 portable delivery.

```sh
D=/Volumes/devSSD/Developer/lagrangian-native-20261117
EVIDENCE="$D/test-output/delivery-production/NA13/final-app-v1"
SCRIPT=tests/flow-app/native-reader-app/test_page_delivery_bundle.py
```

The fixed final09c preparation record supplies `$EVIDENCE/gui-inspection-001`
as setup-only, not a running-service receipt. Do not rerun setup over it. Read
`$EVIDENCE/inspection-commands.json`; use its exact serve/status/appCommand/stop
arrays for the bound staged app and source, and inspect status before serving. Do not
launch a stale app against new source under an old acceptance binding. No command
in this document is executed by a docs check or authorizes an installation,
service restart, actual inference or credential/account change.

For a new inspection, select a new root below EVIDENCE and explicitly supply the
same pinned compiler and existing package cache from the fixed command record:

```sh
ROOT="$EVIDENCE/gui-inspection-new"
python3 -B "$SCRIPT" gui-fixture setup --root "$ROOT" \
  --compiler "$D/dependencies/portable-typst/v0.15.1/typst-aarch64-apple-darwin/typst" \
  --package-cache "$D/build/delivery-production/c-merge-v1/Lagrangian.app/Contents/Resources/native-reader/typst-packages"
```

Those are prebuilt/local inputs, not download or global-install instructions.
Serve is a bounded foreground process; stop requests only its owned fixture,
never a shared process, launchctl domain or user's data. Manifest PID/incarnation,
root, port, hashes and exact existing --dev-root/--dev-no-activate/manager arguments
are recorded. Real production compiler/accepted document, scoped native HTTP,
source and conversation APIs are reused. Auth/catalog/inference and manager PID
observation are explicitly fake; actual HTTP is separate evidence. Source bytes
remain immutable while serving. Do not replace the backend with fixture JSON.

The current synthetic original-PDF and semantic modes share the production backend;
256 pages are synthetic compiler input and37 Unicode paragraphs are the separate
G1 document. This does not prove original-PDF GUI fidelity or application recovery.
The host is macOS27.2.1; target13/closure minOS<=13 do not prove OS13 execution.
A single later partial Read/window observation and AXPress -25200 interruption
are incomplete, never GUI/AX/VoiceOver passes. The source/binary-bound headless
helper, actual GUI actions and VoiceOver speech remain separate evidence.

== Clipboard inspection

An isolated FlowApp composes Reader body Copy and verified Source copy with a
private named pasteboard derived from its isolated home. Ordinary production
composition continues to use the general pasteboard. The manifest records the
exact owned board name. Never read, snapshot, log, clear or write the user's
general clipboard. Do not use system Cut/Copy/Paste in the composer or answer
view during this fixture inspection; those independent responder paths are not
part of this document-copy seam. Do not open external links or Homepage accounts.

Build and probe the bounded offscreen helper before opening the approved app.
After copying in the app, use only its read mode so the probe cannot replace the
owned board contents. Use the shared Swift lock exactly once:

```sh
python3 "$D/tmp/with-native-swift-lock.py" python3 -B "$SCRIPT" \
  gui-fixture clipboard-helper --root "$ROOT"
```

The manifest then supplies `privateBoardReadCommand`. Its read mode reads only the
owned board, creates no visible window and performs no inference. Its probe mode
checks the actual parser/dev-root guards, isolated copy composition and production
HTTP-to-typed-recovery round-trip. A substituted general getter verifies ordinary
composition without accessing the actual user clipboard. This is component proof,
not GUI acceptance or complete app recovery wiring.

== Examiner checklist and limits

- Select more than 32 of the 37 Unicode paragraphs: ordinary native selection,
  plain body copy and AX must retain exact text; source/chat submission keeps its
  32-fragment limit and must explicitly reject oversized submission.
- Inspect inline/display fractions, table, raster/vector image and internal link.
  Native text/object calculation and pixels are separate from visual fidelity.
- Use the authored Source and chat probe paragraph for verified locate/chat.
  The existing source-excerpt owner copies complete math expressions only; select
  the displayed equation for that action. Do not infer prose source-copy support.
- Send explicitly to receive the fake provider's authored TeX answer. Prefix a
  question with `[lost-ack]` to lose its first successful response, then use the
  native Refresh conversation control. History alone must never send again.
- Compare the fixture's `effects.json` before/after history, copy and appearance
  changes; only new explicit Send may add an inference record. These are fake
  provider observations, not live inference or an account test.
- Exercise close/reopen and recovery as separate app-level gates. The helper's
  typed recovery round-trip does not prove the application's persisted draft or
  window restoration. The staged09c baseline includes original-page/backend delivery; its GUI page
  fidelity, actual app recovery and the current review-fix restaging remain
  independent and incomplete gates.

A `gui-fixture smoke` command combines setup, owned serve, native HTTP/source/chat,
private-board/parser/typed-recovery checks and cleanup. Wrap it once in the same
Swift lock. Record actual exits, skips, source/binary hashes, compiler argv and
closed ports. Never reinterpret this headless smoke as a GUI, F01–18, final review,
standalone bundle or complete NA06 acceptance.


Historical G1 smoke1/2 may have performed default SharedEditLocation live-profile
discovery; this remains unconfirmed, with no contents logged or mutation. Do not
rewrite that history as access0. The final owned-change-file/home-deny smoke is
separate. Body/verified complete-math Source copy uses the private named board;
answer/composer system Cut/Copy/Paste is outside that seam. Runtime, source,
receipt, recovery and resource limits are specified in
#link("native-reader-app-contract.typ")[the current contract], not waived by
fixture success. Final GUI/AX/official/PM gates remain open.


== Feature wiring inspection after the review-fix baseline

The source-level local wiring follow-up starts at24666ce2. It does not rebuild or
replace the older09c application or the frozen111-test evidence. Its separate
records live under `test-output/feature-wiring-v1`: reachability.json maps all
F01–18 entrypoints to existing owners and observable effects; final-binding.json
binds fresh compiler inputs/tests to the new source commit. Helper-only, missing
API, unsupported fidelity and actual GUI status are recorded separately.

Inspect the native document's Mark for review/Undo review/Clear review, Contents/
Back, Theme/Text size and Zoom/Fit controls. Strikes must preserve exact logical
copy and AX selection through resize/reflow and disappear on undo/clear or a new
accepted snapshot. Heading/reference navigation must use only typed mappings.
Last Edit/Locate Source remain bound to the current existing source/history owner;
a missing editor attachment or anchor is a failure/unavailable state, not a jump.

Save Offline, Refresh Saved and Open Saved must use the current profile's typed
store. The home Offline action must work without starting a service. Reopen into
a fresh managed view while target/network/assets operations fail if invoked;
expect native body/object paint, retained held selection/marks, disabled source/
chat/account and no inference. A newer private draft and its separate pending
question/model/UUID must survive. Verify Cancel/close against delayed owned disk
operations and reject stale completions. Reject selection33+ or display0.25 save
without replacing the previous file; ordinary local copy/AX still permits the
full selection. Do not infer complete application autosave or all saved display
states from this bounded explicit-save path.

Internal AppKit target/action, private-board, renderer pixel and typed-storage
checks run with activation prohibited and zero visible windows. No app staging,
real GUI/AX/VoiceOver, live account, external inference, service installation or
actual OS13 execution is performed by this task. The delivery owner must rebind
and stage the final exact commit before independent GUI inspection.
