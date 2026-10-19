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

- Python Reader suite with actual Typst packages: 145 tests run, 144 passed and
  one optional test skipped. This includes installed-layout delivery and eight new
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

## Installed delivery

Installed runtime `3d59f262dfda4c20b7a48f7c00137bac4e6ebbee` from a clean
detached snapshot of the current branch, preserving unrelated checkout files.
Backed up configuration, launcher, LaunchAgent and current focus, then used the
existing installer to update only the owned HTML Reader. Restored the identical
saved selection through `/api/focus`; no workspace source was edited.

The live record is now `selected`, with source `chapter 3/3.6.typ:152:1`, exclusive
end `152:266`, matching excerpt/hash and `needs_reselection: false`. Source and
cursor APIs agree on the same block. Unqualified `tail-hosting focus` in the PDE
project returns that record as `latest_saved_text`. All 479 archived release
files and 41 first-party HTTP assets matched their immutable bytes. Registered
HTTPS matched the accepted loopback revision. The measured accepted full
compilation took 30.8 seconds; the paged service was not restarted.

Recovery files and machine-readable verification receipts remain at
`.local/source-map-rollout-1792405337957108000/`.
