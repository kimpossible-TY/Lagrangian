= Browser computation with server-owned publication

The HTML Reader can offer an open browser as a compiler worker. Python retains
normalization, loss-warning checks, source correspondence and final verified source
writes. All online viewers receive one server-adopted revision. Screen geometry
may differ with the viewport; an offline viewer retains its last accepted snapshot.

`Project.execute` is used by base HTML, source-carrier HTML and source-highlight
HTML/PDF candidates. The server captures immutable source/package/font bytes before
leasing a task. Files not in the bundle cannot be fetched from a newer workspace by
that task. Native discovery/fallback and the existing before/after source guards
preserve the last accepted document when inputs change. This does not make external
filesystem writers part of an atomic transaction.

= Build and enable

Build with the workspace Rust toolchain, the `wasm32-unknown-unknown` target, and
the exact `wasm-bindgen-cli` version in Cargo.lock. The build script checks that
version and emits `compiler.js`, `compiler_bg.wasm` and a hash manifest:

```sh
python3 tools/flow-reader/build-browser-compiler.py
```

Pass `--browser-compiler /absolute/path/to/dist/reader-compiler` to `serve.py`
to enable the protocol. The Reader settings control whether this browser offers
capacity through *이 기기 계산 부하*, a two-position Low/High slider. New viewers
start at Low: raw document compilation stays on the server while existing local
math, decorations and figure composition remain active. High offers the local WASM
compiler. Saved true/false choices map to High/Low, including legacy document choices
when no newer viewer choice exists. An untouched default is not saved as a choice.
The slider supports swiping, tapping and keyboard operation. Selecting Low terminates
an active compiler and releases its lease without changing the accepted document.
A visible, online High page registers only after its WASM Worker initializes.
Hiding, leaving or disabling it terminates computation and releases its lease;
lost heartbeats also expire. Late results cannot satisfy a reassigned lease.

Browser mode uses explicitly configured fonts plus the bundled fallback fonts
for both browser execution and native fallback. Include every required font via
`--font-path`, including fonts previously found implicitly in the system library.
Individual font files and directories are supported. Missing fonts remain subject
to the existing warning/content gate. Browser compilation needs the normal secure
browser environment (HTTPS or localhost), with same-origin assets and requests.

For a clean-commit installation, `install.py --browser-compiler PATH` packages
verified generated assets into a separate immutable release identified by source
revision and compiler hash. Omission preserves the installed compiler setting;
`--no-browser-compiler` disables it. Installation is separate from development
validation. Tests use isolated directories and never restart user services.

Managed Readers inherit their parent profile's fonts. Add Reader-only files or folders
with repeated `install.py --font-path PATH` options when portable compilation also needs
fonts previously discovered from the system. Omission preserves installed supplementary
paths; explicitly supplying paths replaces that supplementary set. Parent paged profile
settings remain unchanged. All configured paths are validated before installation.

Dynamic geometry uses available browser capacity, retains native incremental
compilation when no browser is available, and keeps the existing output and
revision checks. The browser is a temporary compute resource; the server owns the
task, acceptance decision and shared document.

= Reproduce the PDE measurements

`tests/prepare-wasm-benchmark.py` accepts an existing dependency report, package
root, explicit fonts, generated compiler directory and a new output directory.
It copies only the corpus inputs into isolation, compiles a native baseline, and
records file/font hashes, compiler identity and the fixed timestamp. It never
edits the original PDE sources. Supply all fonts, including Arial variants when
the project uses the maquette package.

Run `tests/compiler-browser.mjs` with `FLOW_COMPILER_CORPUS`,
`FLOW_COMPILER_ASSETS`, `FLOW_READER_PLAYWRIGHT_MODULE` and
`FLOW_READER_BROWSER_ENGINES=chromium,webkit`. `FLOW_COMPILER_ROUNDS` controls
the sequence length. Each run is journaled immediately, and an external deadline
bounds an unresponsive browser. `tests/verify-wasm-benchmark.py CORPUS` recreates
every edit in a separate native workspace and compares the complete normalized
HTML, not merely an output hash count or selected passages.

The 2026-10-24 desktop run used the actual PDE corpus: 188 files and 10,494,755
input bytes including 20 explicit fonts. Each browser compiled a fresh Worker
baseline plus 11 edits to the main source. Both browsers matched native normalized
HTML for all 12 versions and passed the content gate.

#table(
  columns: (2fr, 1fr, 1fr),
  [Metric], [Chrome], [Desktop WebKit],
  [Worker initialization], [87 ms], [122 ms],
  [First full compilation], [15.04 s], [15.43 s],
  [Incremental median], [1.69 s], [1.86 s],
  [Incremental range], [1.51–3.28 s], [1.74–3.10 s],
  [WASM linear-memory high-water mark], [3.23 GiB], [3.23 GiB],
  [Loopback result upload median], [235 ms], [60 ms],
)

The native preparation baseline took 10.41 s; Python normalization and audit took
2.03 s. The result-upload measurements use loopback HTTP and do not describe
phone-network latency. Benchmark inputs are fetched once; production currently
transmits complete snapshots for each leased task. Initial asset/network caches
and other host workloads are not controlled laboratory conditions.

Retaining ten obsolete evaluator generations exhausted wasm32 memory on the sixth
full-book edit: the last successful WebKit run had grown to 4.05 GB. Keeping the
latest used generation instead completed 12 iterations, with linear memory stable
from the second run. The measured high-water mark is allocated WASM linear memory,
not total browser RAM or physical-device peak RSS. The footprint is still large.
These results prove browser execution and output agreement on this Mac; they do
not establish iPhone memory viability, sustained thermal performance or background
execution. Physical iPhone testing remains separate.

= Local screen computation

Version 2 decoration descriptions support dashed/dotted strokes, phases, caps, joins
and miter limits. Typst resolves named patterns; the browser resolves their point/em
lengths at the current reading font. Unsupported rounded corners, sided strokes,
gradients and callbacks retain server rendering. Older clients reject the new version
and use that same fallback. The compiler fixture also confirms unchanged paged PDF.

`tests/local-decoration-browser.mjs` compares SVG geometry, paint, stroke width,
dash arrays/phases and line styles against actual Typst output in Chrome and WebKit.
Eleven eligible decorations at two fonts and two fragment shapes agree; viewport/theme
changes preserve semantic text with zero eligible decoration requests. The four
unsupported examples still request their original server paint.

Native figure placement already ran in the browser. Its collision search now runs in
a dedicated Worker using the same pure function as the fallback. DOM measurements,
source anchors, selection holds and publication stay in the figure owner. Width/font
changes and document replacement reject obsolete results; failed Workers use the
identical local algorithm. This moves CPU work away from the interface without claiming
that these already-local figures previously needed compiler requests.

`tests/canvas-worker-browser.mjs` verifies eight native figures at 13, 18 and 30 px,
with 390 px online and 768 px offline viewports. Each of the four Chrome/WebKit and
online/offline cases passed 326 geometry/semantic checks and 30 exact Worker/fallback
plan comparisons, with zero canvas API requests. Offline reload uses the real cached
Worker modules and accepted document. These are browser correctness checks, not a
physical iPhone responsiveness benchmark.

= Validation and coverage limits

`tests/compiler-pool-browser.mjs` uses actual HTTP leases, generated WASM and Python
acceptance in Chrome and WebKit. It checks base/source-carrier execution, shared
publication, pagehide reassignment, competing source edits, verified highlight
writes and dynamic geometry with native incremental fallback. The separate offline
fixture exercises Service Worker delivery; routing interception in the compiler
fixture disables Service Workers so intercepted POSTs actually reach Playwright.

`tests/highlight-offline-browser.mjs` uses real Service Worker caching and dropped
HTTP connections in Chrome and WebKit. It verifies offline reload, reconnect,
lost acknowledgments after an actual source write, preservation of a newer selection,
and rejection after a competing source edit. Browser-local requests retain their
original document, service, revision and fragments. Each has an independent durable
key; pending work is never described as saved. Reconnect uses the normal server
source validation and candidate compilation. A changed service or source requires
reselection, even if the selected words still appear in the latest document.

The server records request IDs and payload digests in SQLite before attempting the
source operation. Confirmed results replay without repeating the write. If a crash
leaves a pending receipt, its outcome is uncertain: the Reader asks for source review
instead of automatically attempting the write again. This avoids claiming a filesystem
write and receipt update are one atomic transaction. Settings show pending and
review-needed counts; clearing reviewed results does not discard pending requests.
Browser storage loss still requires recovery from the current server document.

An offline cached document does not itself authorize a source write. No installation
or physical iPhone run is implied by the desktop validation above. New viewers offer
browser compilation by default at the user's request; a saved false preference remains
disabled. Actual phone memory and sustained-use behavior still require device evidence.

The final service suite ran 248 tests successfully with seven optional skips requiring
the external source-history engine or companion Tail Hosting checkout. The HTML Node
and architecture run passed 188 tests. Reader lint, the preview TypeScript/production
build, documentation checks and strict OpenSpec validation passed. Installation tests
used a temporary clean commit and verified every allowlisted module in the archived
HTTP layout; no user service was installed or restarted. The measurement JSON retains
the immutable benchmark corpus identity separately from these integration checks.

= Managed rollout (2026-10-24)

Flow `0.1.32` and its immutable HTML Reader are installed from clean commit
`e3004738`, with compiler identity `6a194fad0b95c8b4`. The existing compatible
native engine, signing certificate and designated requirement are retained. The
menu-bar app is relaunched, and its bundled PDF includes the offline/device-compute
instructions. At this rollout, browser participation required a saved true preference
or an explicit toggle; the subsequent default-enabled update changes that initial policy.

Reader-only supplementary fonts supply the four installed Arial variants alongside
the inherited project fonts. The isolated actual PDE preflight passes the content
gate with unchanged textual content, 3,434 source correspondences and 307 navigation
ranges. Its authored source files and common edit sequence 130 remain unchanged.
Project/signing configuration bytes are preserved. PDE and Reader resume running;
Ewald remains stopped. Both focus records were empty before installation and remain
empty; verification does not create a selection or modify source.

All 577 immutable runtime files match their hashes. The 68 first-party/compiler
routes and accepted HTML match disk bytes over loopback and the registered HTTPS
origin. Chrome and desktop WebKit each confirm accepted PDE rendering, a complete
offline snapshot, default-disabled browser computation, explicit WASM Worker readiness
and no horizontal page overflow or page errors. Chrome additionally passes actual
PDE offline reload and reconnect. WebKit's actual PDE offline reload and physical
iPhone behavior are not claimed. The original paged service delivers complete light
and dark document frames through its configured-origin protocol.

The rollout runs 15 Reader manager tests, the isolated immutable installer test and
83 native app tests. The native suite's optional persistent-signing case is covered
by a separate three-test run with the configured certificate. The opt-in compiler
pool regression passes in Chrome and WebKit. Deployment receipts, pre-install and
pre-correction configuration/launcher snapshots, screenshots and signed app outputs
are in `dist/web-computation-rollout/`; previous app bundles and immutable Reader
releases remain available. The tracked rollout verification JSON records identities,
checks and coverage limits. Existing reader tabs should reload once to adopt the
updated app shell.

== Default-enabled update

At the user's request, Flow `0.1.33` and Reader commit `8ffcbd29` enable browser
participation for viewers without a saved choice. Explicit viewer true/false choices
survive reloads. Older document-scoped choices are restored before Worker registration
when no newer viewer choice exists, fixing their previous reload behavior. Capacity
still requires the accepted document, a visible page and a connection.

Chrome and desktop WebKit pass isolated compiler-pool checks for automatic readiness,
legacy disabled-choice recovery, saved choices and the existing compilation/lifecycle
contracts. The actual HTTPS Reader confirms automatic registration and saved false/true
across reloads in both engines. All 577 runtime hashes and 68 asset routes per origin
match; the accepted PDE and original paged light/dark document frames are delivered.
Project/signing settings, source sequence 130 and previous running/stopped services are
preserved. The signed app and bundled guide are updated and the menu-bar app is
relaunched. Physical iPhone behavior remains unmeasured. Receipts and recovery snapshots
are in `dist/default-on-rollout/`.

== Verify computation on an actual iPhone

Open the HTTPS Reader on the iPhone. If reading settings shows *업데이트 적용*,
apply it to activate the complete waiting shell and reload. For a legacy Reader
without this button, close all Reader tabs and the home-screen app before reopening
so its waiting Service Worker can activate. Expand *이 기기 계산 확인* and confirm
*진단 1* next to this device before checking. Select *High* under *이 기기 계산 부하*.
Low keeps device diagnostic actions disabled and explains how to enable them.
The panel identifies this connection with its device name and short ID.

Tap *1. 간단 검사* and keep this page visible until *통과* appears. Then tap
*2. 현재 문서 검사* with source editing paused. This can take several minutes.
Success means this device returned a result matching the server's reference from
the same captured inputs. The reference does not replace failed device execution.
Neither test edits source or publishes its temporary document. A small-test success
alone does not demonstrate that the full PDE fits the physical device's memory.
For the iPhone 15 that restarted during full-document checks, use Low for reading;
the slider does not change the document's compilation memory requirements in High.

Use *결과 복사* and paste the result into the Codex conversation after each check.
Failures display recovery instructions; connection loss, time limits, source changes
and differing output cannot silently become success through another executor.
The expandable recent-work list distinguishes browser result receipt, server execution
and final document publication. Names describe connections rather than authenticated
hardware. History is bounded to 64 records and clears when the Reader service restarts.
Physical-device results must be recorded separately from desktop Chrome/WebKit tests.

The diagnostic rollout uses Reader commit 2c66e08a. It also retires obsolete
dependency paths after a successful compiler discovery; retaining previous release
package paths prevented portable snapshots after an update. The isolated upgrade
fixture and device checks pass in Chrome and desktop WebKit. On the actual HTTPS PDE,
Chrome's quick check passed in 0.252 seconds of device response, and the full document
matched the native reference with 19.835 seconds of device response and 41.014 seconds
total checking time. These are desktop measurements. Both checks left the accepted
document unchanged. All 580 installed runtime hashes and the changed HTTP/HTTPS
routes were verified. The physical iPhone check is awaiting the user's results.


= Device termination evidence

Device checks retain the pinned job termination in their copied result. Explicit
browser signals distinguish hidden pages, page exit, offline state, disabled
computation, disposal, transport errors, worker errors, compiler errors and client
deadlines. Missing heartbeats mean unreported response loss; they do not prove a
browser crash or memory exhaustion. Screen locking and switching apps both may
hide a page and cannot be distinguished by that signal. Only bounded reason codes
enter public execution history; raw exceptions and source content do not.

Physical iPhone evidence on 2026-10-24 confirmed the quick check (0.592 seconds).
The full document lost its connection after 28.835 seconds, before the 90-second
limit. This predates termination instrumentation and its cause remains unknown.


== Silent loss and page recovery observations

The next physical iPhone quick check passed in 0.772 seconds, but the document
check lost heartbeats after 23.487 seconds. The user observed a white flash or
automatic page reload. This narrows the symptom to a page execution interruption,
but it does not identify the underlying cause. These failures remain separate from
the successful desktop PDE check.

Worker progress now records font preparation, file preparation, synchronous Typst
computation, output extraction and result transmission. The latest observation,
server-observed heartbeat age, phase age, previous request round-trip time and
foreground timer delay are bounded and copied with a pinned failure. Observed WASM
allocation is the value at that phase boundary, not a peak or total process memory.

An optional per-tab sessionStorage checkpoint retains only the public connection ID,
termination reason and bounded progress. It contains no lease tokens or source text.
A later registration correlates same-page connection retries versus a new page
instance with recent failed checks. Storage denial does not block compilation.
New-page recovery cannot distinguish an automatic reload from a manual reload.
The eight-second connection lease and ninety-second document-check deadline are
unchanged; a late observation cannot revive an expired lease.


== Cached-shell update delivery

A subsequent iPhone check lost heartbeats after 24.806 seconds (8.357 seconds since
the last response). Its preceding quick check succeeded without any progress
observation, although current clients await a progress heartbeat before submitting
that result. The later iPhone connection did report the new ready phase. This
identifies legacy execution at the failed check; it does not identify the cause of
the original page interruption.

A real Service Worker fixture reproduces an ordinary reload retaining an older
shell while a fully cached update waits. Reading settings now offers an explicit
*업데이트 적용* action. Activation uses the waiting worker and reloads after the
controller changes; it does not reload an active reading session automatically.
Offline snapshots and browser preferences remain available. Registration bypasses
HTTP import caches. Existing legacy pages require closing their clients once to
activate the waiting version and gain this action.

Compiler registration declares diagnosticsVersion. The server rejects explicit
checks without the current version before dispatch; ordinary compilation remains
compatible. The diagnostic panel shows *진단 1* when the current evidence contract
is registered, making cache delivery visible before another large test.


During cached-shell rollout verification, native Reader compilation repeatedly
exceeded its 90-second invocation bound under concurrent host work. An isolated
base compile with one parallel job passed the content gate in 58.446 seconds. The
Reader CLI executor therefore bounds native compilation to one job; request
inputs, deadlines and publication/source guards are unchanged. This neither
measures an isolated speedup nor changes the separate paged preview service.


== Current-protocol physical evaluation failure

A physical iPhone current-document check using diagnosticsVersion 1 reached Typst
calculation and lost its heartbeat after 20.004 seconds. The last phase boundary
reported 33,357,824 WASM bytes (31.8 MiB); its last response had been 8.023 seconds
earlier. A new page instance recovered an unreported-stop checkpoint still marked
evaluating. This records page recovery, but cannot distinguish manual and automatic
reload or establish an iOS memory termination reason. The same connection passed
the quick check in 0.320 seconds.

A subsequent desktop Chrome check on the same accepted document passed the exact
native-reference comparison without changing publication. WASM allocation at the
evaluation boundary was 32,833,536 bytes (31.3 MiB); by output extraction it was
2,370,830,336 bytes, and the returned metrics reported 2,379,874,304 bytes (about
2.22 GiB). WASM computation took 20.868 seconds, device response 27.446 seconds and
full comparison 77.914 seconds. These are allocated linear-memory observations on
the Mac, not physical iPhone memory measurements. The earlier 3.23 GiB corpus
benchmark used different captured inputs and should not replace this current run.

The low iPhone boundary value therefore does not rule out memory growth after
entering computation. Memory pressure is the next hypothesis to investigate, not a
confirmed termination cause. Further physical whole-document repetition should
follow measured reductions or bounds in the WASM runtime. Smaller delegated tasks
need independently measured memory use; splitting an output alone does not avoid
Typst evaluation of shared document state.
