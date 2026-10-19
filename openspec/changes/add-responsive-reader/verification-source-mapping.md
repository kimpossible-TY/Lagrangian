# HTML source range verification

## Implementation

Compile-only carriers preserve original workspace paths, hashes and exclusive
source ranges. The accepted document remains the original HTML. Matching block
identity and full canonical text authorize a carried range; repeated signatures
also require agreement of the complete ordered block sequence. A failed carrier
compile retains literal fallback. Source enumeration and shadow inputs are
shared with source Highlight rather than copied into another service.

Saved for Codex and both editor-navigation directions use the accepted map.
Neither action compiles or writes source. Saved ranges use Unicode columns;
editor positions remain UTF-8 byte columns. Partial formulas, unsupported output,
cross-file selections, stale hashes and ambiguous reverse mappings are rejected.

## Evidence

- Python Reader suite with actual Typst packages: 145 tests passed with one
  optional test skipped. This includes installed-layout delivery and eight new
  mapping tests covering closure/proof bodies, complete math, CRLF, Korean,
  smart quotes, duplicate occurrence shifts, repeated includes, multiblock and
  cross-file selections, source hashes, path boundaries and compiler failure.
- Shared/HTML/terminal Node tests: 110 passed.
- Paged frontend: 82 tests across 11 files passed.
- Actual WebKit and Chrome selection flows: 164 checks across 320, 390 and 768px
  widths passed, including a mixed-math proof saved through the actual focus API,
  matching source API coordinates and reverse cursor navigation.
- Chromium, HTML service and disposable Neovim: 21 integration checks passed.
- Strict OpenSpec validation, generated Markdown check and compilation of all
  three changed canonical Typst guides passed. Yarn is unavailable; the reader
  gate's Node, Python and Vitest commands were run directly.
- An isolated full PDE compile retained 3,439 corresponding blocks. The reported
  `the same kernel formula` paragraph resolved to `chapter 3/3.6.typ`, line 152,
  UTF-8 columns 0–265, with the same block returned by reverse cursor mapping.

The source-carrier pass adds one isolated verification compilation when building
an accepted HTML document. Dynamic geometry and source-highlight candidate builds
skip this extra pass. No physical-device interaction was repeated.
