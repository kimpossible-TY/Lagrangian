#set text(size: 11pt)
= Isolated native Reader inspection preparation

This procedure prepares Lagrangian-owned input for an independent GUI examiner.
It does not launch the app, install a service, establish GUI/VoiceOver success,
or accept the complete native application. Use only an explicitly approved final
app after the page-service component and delivery owner have completed staging.
The current delivery component app is not that integrated app.

== Owned fixture lifecycle

Run from the fixed final-integration checkout. All fixture roots must be new,
absolute directories under the following DevSSD directory. Existing roots are
preserved. The compiler and package cache are explicit, pre-existing local inputs;
there is no dependency download. Do not substitute personal or PDE documents.

```sh
D=/Volumes/devSSD/Developer/lagrangian-native-20261117
ROOT="$D/test-output/integration/gui-prep-v1/fixtures/inspection-001"
SCRIPT=tests/flow-app/native-reader-app/test_app_integration.py
python3 -B "$SCRIPT" gui-fixture setup --root "$ROOT" \
  --compiler /opt/homebrew/bin/typst \
  --package-cache "$D/test-output/core-review-fixes/v2-ui/cache/services/typst-packages"
python3 -B "$SCRIPT" gui-fixture serve --root "$ROOT" --seconds 900
```

Serve is a foreground, bounded process. Use another terminal for status and stop.
The fixture manifest records actual PID, incarnation, ports, root, source hashes,
compiler commands, profile settings and exact app arguments. Stop writes only this
owned fixture's stop request; it never signals another PID, invokes launchctl,
or stops a shared Reader. The foreground process closes both listeners and its
own compiler/chat resources. Keep all failed and successful roots for review.

```sh
python3 -B "$SCRIPT" gui-fixture status --root "$ROOT"
python3 -B "$SCRIPT" gui-fixture stop --root "$ROOT"
```

The serving process denies user-home file access, external network and writes
outside its owned root and explicit temporary directory. The compiler inherits
this confinement. A concrete fake auth/catalog/provider and fake manager
attachment observation are marked as test inputs; no credentials or real
inference are used. The ReaderState, accepted compiler publication, root and
registered `/d/gui/` HTTP handlers, native document/assets, guarded source actions
and ParagraphChat remain production owners. The fixture does not reproduce their
HTTP/parser/security/source rules. Response loss is injected only after an
explicit successful mutation, without changing acceptance or retry policy.

== Exact future app invocation

Read `fixture.json` only after `running` becomes true. Its `appArguments` uses the
existing parser: `--dev-root`, `--dev-no-activate`, and
`--native-reader-manager`. It supplies an owned schema-1 profile. There is no
`--native-reader-fixture` JSON provider, preview-port assumption or default-manager
launch. The explicit manager wrapper supports only exact attachment to this root
and entry, then checks the real HTTP document/service incarnation. PID observation
is fake; HTTP is real. Use the approved final executable and append the manifest
arguments verbatim. Preparation does not run this command. Runtime defaults must
come from the final verified bundle; no scratch/PATH/source-runtime fallback is
part of this procedure.

No-activate avoids forced activation; it does not prove visibility, focus,
selection, window ordering, AX, VoiceOver or actual native paint. Those remain
independent examiner observations.

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
  window restoration. Original PDF/page-host delivery through this same backend
  is unverified until the accepted C component and final staging are available.

A `gui-fixture smoke` command combines setup, owned serve, native HTTP/source/chat,
private-board/parser/typed-recovery checks and cleanup. Wrap it once in the same
Swift lock. Record actual exits, skips, source/binary hashes, compiler argv and
closed ports. Never reinterpret this headless smoke as a GUI, F01–18, final review,
standalone bundle or complete NA06 acceptance.
