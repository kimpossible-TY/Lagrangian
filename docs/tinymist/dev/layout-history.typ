= Compact layout iteration history

The maintained Typst core in `vendor/typst` comes from the already-pinned
`tinymist/v0.15.1` revision. Its upstream provenance, original manifest and license
remain beside the patch. The public compiler and `Output` interfaces are unchanged.

During convergence, the compiler previously retained each complete unsuccessful
output so it could borrow that output's introspector. HTML and paged outputs already
store their introspectors in separate shared allocations. `src/history.rs` now clones
that shared reference and releases the output container before the next iteration.
It does not clone the introspector's contents. Unknown output types, including bundle
outputs, retain their original complete-output history.

All previous introspectors remain ordered and available. The next attempt still
uses the latest introspector; convergence still validates the same constraints;
the five-attempt bound and nonconvergence analysis still use the full introspection
history. Final output, warnings, delayed errors and tracing follow the original loop.

If an output owns D bytes and its introspector owns I bytes, history-owned storage
changes from up to four (D + I) sets to up to four I sets for the supported targets.
This is an ownership model, not an allocator estimate: shared objects can be counted
in both sets, and memoization may retain the same output allocations independently.
The current output, evaluated content and cache remain outside this reduction.
Neither lower live allocation nor releasing a reference implies a smaller existing
WASM linear-memory allocation or a proven physical iPhone memory limit.

= Regression verification

Core tests check that the page vector and HTML child vector become uniquely owned
by the test after history releases the document, while the exact original
introspector remains shared. An unknown output keeps its original lifetime.

A test-only `Output` wrapper delegates layout to the same HTML/paged implementations
but preserves full-output history through the public fallback. Comparing it to
the known targets exercises the same compiler algorithm under both ownership
policies without introducing a production baseline switch. Fixtures cover plain
content, references, counters, queries, nonconvergent state, missing references,
explicit failures and nonempty traced values. Successful exports are compared as
complete HTML and PDF bytes; warnings, hints, spans and errors are compared too.

Run warning-free core and native adapter tests with:

```sh
RUSTFLAGS=-Dwarnings CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0 cargo test -p typst -p tinymist-web-compiler --locked -j 2
RUSTFLAGS=-Dwarnings CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0 cargo clippy -p typst --all-targets --locked -j 2
cargo fmt --check --all
python3 tools/flow-reader/build-browser-compiler.py --output dist/layout-history/compact-assets --jobs 2
```

= Browser comparison method

Build the baseline from an isolated archive of the pre-change commit, recording
its commit and generated asset manifest. Build the candidate using the same
toolchain and build script. Copy the frozen PDE corpus into separate measurement
directories; update the compiler identity in each snapshot and corpus
manifest, and recompute the engine-bound snapshot digest. File/font hashes, bytes, inputs, timestamp and entry must remain equal.

Run `tools/flow-reader/tests/compiler-browser.mjs` with each asset directory and
the corresponding `FLOW_COMPILER_CORPUS`, using the same browser versions and
`FLOW_COMPILER_ROUNDS`. Progress notifications must not resolve pending compile
requests. Compare every resulting HTML artifact byte-for-byte, alongside returned
diagnostics, output size, compile time and allocated WASM memory. Run the fixture
without a corpus as well to cover PDF, edits, missing files and restoration.

Physical-device viability and installed service delivery are separate verification
scopes. This optimization does not install or restart a service.

= Recorded comparison (2026-10-24)

Baseline source commit: `ef112cf2504ab6c54cf2e85d762ba5568b477ed5`.
The isolated archive used the same Rust 1.92 toolchain, release build script and
wasm-bindgen 0.2.125 as the candidate. No compiler adapter, world or comemo source
changes separate these builds. Generated manifests and evidence are under
`dist/layout-history/`; `comparison.json` records complete asset hashes, input
identity, output hashes, diagnostics equality and per-run measurements.

The input is the frozen PDE corpus: 188 files, 20 explicit fonts and 10,494,755
input bytes. Both Chrome 156 and desktop WebKit (Safari 26.5 user agent) ran one
initial compilation plus two source edits for each build. All six candidate HTML
artifacts matched their baseline byte-for-byte, and all diagnostics matched.
The initial output hash also matches the corpus's recorded native HTML hash.

#table(
  columns: (2fr, 1fr, 1fr),
  [WASM allocated memory, both browsers], [Baseline], [Compact history],
  [After first compilation], [2,264.4375 MiB], [2,258.6875 MiB],
  [Maximum over three compilations], [3,309.6875 MiB], [3,309.625 MiB],
)

The first compilation allocated 5.75 MiB less. The repeated-run high-water mark
fell by only one 64 KiB WASM page and remains about 3.23 GiB. The ownership tests
prove previous output containers are released, but this experiment does not show
that layout history was the dominant source of overall memory pressure. It does
not quantify live allocator memory or separate memoization from other owners.

#table(
  columns: (2fr, 1fr, 1fr),
  [Compile time], [Baseline], [Compact history],
  [Chrome, initial], [30.823 s], [47.726 s],
  [Chrome, two edits], [13.606 / 13.043 s], [13.175 / 4.587 s],
  [Desktop WebKit, initial], [25.120 s], [30.079 s],
  [Desktop WebKit, two edits], [5.119 / 6.611 s], [3.817 / 4.014 s],
)

No speedup is established. Initial compilations were slower in these observations;
edit timings were mixed. This 8 GiB Mac had substantial swap use and uncontrolled
background workloads, so the measurements do not isolate a latency regression or
improvement caused by this patch. An initial attempt overlapping Rust builds was
stopped and excluded; the reported browser runs were serialized after those builds.

Four core tests and the native browser-adapter test passed with warnings denied.
Core Clippy with all targets, workspace formatting, the affected JavaScript lint
and formatting checks, OpenSpec validation and generated-document checks passed.
The final WASM binary passed HTML/PDF, edit, missing-input and restore fixtures in
both desktop browsers. This is not a full-workspace test run, a full-PDE PDF memory
benchmark, a long-duration soak, or a physical iPhone test. No deployment occurred.
