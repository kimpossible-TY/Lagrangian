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
capacity. A visible, online page registers only after its WASM Worker initializes.
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
or physical iPhone run is implied by the desktop validation above. The optional browser
compiler should remain opt-in until the actual phone can sustain the PDE memory load.

The final service suite ran 248 tests successfully with seven optional skips requiring
the external source-history engine or companion Tail Hosting checkout. The HTML Node
and architecture run passed 188 tests. Reader lint, the preview TypeScript/production
build, documentation checks and strict OpenSpec validation passed. Installation tests
used a temporary clean commit and verified every allowlisted module in the archived
HTTP layout; no user service was installed or restarted. The measurement JSON retains
the immutable benchmark corpus identity separately from these integration checks.
