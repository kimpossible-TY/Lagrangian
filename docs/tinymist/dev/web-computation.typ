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

= Validation and remaining work

`tests/compiler-pool-browser.mjs` uses actual HTTP leases, generated WASM and Python
acceptance in Chrome and WebKit. It checks base/source-carrier execution, shared
publication, pagehide reassignment, competing source edits, verified highlight
writes and dynamic geometry with native incremental fallback. The separate offline
fixture exercises Service Worker delivery; routing interception in the compiler
fixture disables Service Workers so intercepted POSTs actually reach Playwright.

Additional local decoration/figure computation and persistent offline highlight
intents are separate unfinished tasks. An offline cached document currently does
not authorize a source write. No installation or physical iPhone run is implied by
the desktop validation above.
