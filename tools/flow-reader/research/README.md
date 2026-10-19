# Width-aware math renderer evaluation

This isolated probe evaluates MathJax 4.1.3 against the accepted Reader's MathML.
It remains an isolated benchmark; the development Reader now has a separate
integration described in `docs/tinymist/dev/responsive-reader.typ`. A completed
probe is not a mobile-reading acceptance result. The user requires all essential content to be
readable inline without zoom, horizontal movement, slides, or reveal actions.

Build a corpus from a compiled `document.html` (not from private source paths
committed to this repository). Install the exact evaluation dependencies inside
ignored development output, retaining their licenses:

```sh
npm install --ignore-scripts --save-exact --prefix dist/reflow-deps \
  mathjax@4.1.3 @mathjax/mathjax-newcm-font@4.1.3
python3 tools/flow-reader/research/math_reflow_probe.py /absolute/path/document.html \
  --output dist/reader-reflow-probe \
  --mathjax dist/reflow-deps/node_modules/mathjax \
  --font dist/reflow-deps/node_modules/@mathjax/mathjax-newcm-font
python3 -m http.server 56986 --bind 127.0.0.1 --directory dist/reader-reflow-probe
```

Open `/math-reflow.html?font=18` at the intended viewport. The page processes all
outer display equations in batches of 25 and puts the final JSON report in
`#report`, with `body[data-state="ready"]` when finished. Reload after changing
width; MathJax display line breaking is computed during typesetting. Use
`?font=30&index=45` to inspect one corpus root. The root index is zero-based and
includes inline roots. Save the JSON report and representative screenshots.

Add `&rows=1` to evaluate the candidate derivation-row composition. This moves
the original cells into separately breakable mathematical rows; nested matrices,
cases, vectors, and tables with spans remain intact. The report checks text
preservation before typesetting and records the number of composed derivations.
For a paired comparison, compile both adapters against the same frozen project
dependencies, generate both corpora, and place the earlier corpus beside the new
one as `baseline-corpus.json`. Use `&source=baseline` for that file, without `rows=1`.

The probe preserves SVG islands and enables embedded HTML in MathML tokens.
All scripts, font data, and fonts are served locally. The enhanced speech and
exploration features are disabled **only in this layout probe**: speech-worker
startup did not complete in the initial self-hosted configuration. Accessibility,
speech, and production CSP support remain unverified.

The report measures component scroll width, visible glyph/SVG bounds, and complete
stretched-operator surfaces on both sides. The clipped overlapping glyph pieces
used to construct a stretched bar or fence are not separate visible ink. It also
records text-order changes, SVG counts, and the ordered list of
annotation marker occurrences. Text-order changes are not proof of mathematical
corruption: for example, MathJax renders superscripts before subscripts in DOM
order. They do show why saved quotations cannot blindly use presentation DOM text.
Repeated marker attributes can represent one logical term split over several
lines. No marker must be resolved to only its first presentation fragment.

This is an isolated display-equation corpus. The current probe moves embedded
annotation prose into visible notes before typesetting, matching the Reader's
note relocation; it retains the note bodies. It does not draw dynamic decoration
layers or graphical relationships. It does not evaluate figures, surrounding paragraphs,
equation-number placement, graphical annotation programs, or visual mathematical
equivalence. SVG count equality does not prove SVG fidelity or readability.

## Recorded PDE result, 2026-10-17

This earlier run measured annotation payloads inside their exported MathML tokens.
Its counts are historical and cannot be compared directly with the paired run
below, which also uses a later source snapshot.

The accepted document SHA-256 was
`fb664809f1aff548bb2ea8c5379e9c8b3a87f5cd48167755685b072355040a96`.
It contains 6,747 outer MathML roots, of which 1,411 are display equations.
The previously recorded 6,864 count includes nested MathML roots.

| Browser viewport / body font | Available equation width | Overflowing equations | Input errors | SVG count changes | Marker occurrence changes | Presentation text changes |
| --- | --- | --- | --- | --- | --- | --- |
| 390px / 18px | 343px | 81 | 0 | 0 | 31 | 604 |
| 320px / 30px | 273px | 294 | 0 | 0 | 61 | 607 |

The desktop browser reserves 15px for its scrollbar. Reports and screenshots
are under `dist/reader-reflow-probe`. These results reject a direct renderer swap
as sufficient for the user's requirement. They do not establish iPhone behavior.

Two actionable causes were found in the original exported MathML:

- Annotated terms with an underlay/overlay are flattened into complete SVGs in
  `mannot/src/mark.typ`. Root 297 contains a 35.9116em-wide SVG term. Automatic
  MathML line breaking cannot recompose its internal symbols. Preserve the term's
  mathematical structure and represent its decoration separately.
- Typst's aligned derivations are multi-column `mtable` nodes. Root 214 combines
  a leading expression, continuation equations, and footnote cells. Layout needs
  to distinguish alignment scaffolding from genuine matrices and choose new
  continuation alignment for the available width.

## Paired semantic-decoration and derivation run, 2026-10-17

The project was being edited independently, so both compiles used one frozen
dependency snapshot. The previous adapter is commit `9110cc36`. The baseline
HTML SHA-256 is `a2374d6e9101aa229a2f02438b9d37390d72d079a7a60c215e713e67a91a22fb`;
the semantic HTML is `b4d1ea3bdf8e6b11af8372c6a852c7846a26db6a83aeaa2fa14216735c5b69b0`.
Each has 6,759 outer MathML roots and 1,412 display roots. Both use the same
visible-note preparation and MathJax 4.1.3 settings. The candidate additionally
preserves mannot bodies as MathML and composes 398 derivation tables into rows.

| Viewport / font | Baseline overflowing equations | Candidate overflowing equations |
| --- | --- | --- |
| 390px / 18px | 26 | 12 |
| 320px / 30px | 240 | 96 |

All four runs have zero input errors and SVG count changes. Row composition
preserves input text order. Presentation text order still changes during MathJax
typesetting (616 and 619 candidate equations respectively); logical selections
must therefore remain independent of that DOM order. At 320px/30px, 46 marker
occurrence lists and 14 decoration occurrence lists change. These need explicit
fragment identity handling, not a first-node lookup.

This comparison measures the combined candidate, not the separate contribution
of each change. Dynamic decoration paint is absent from the probe, so reduced
overflow is not proof of complete decorated-equation fidelity. The remaining
overflows, graphical anchors, accessibility, and logical selection behavior still
prevent production adoption. Evidence is under `dist/reader-semantic-checks`:
`source-hashes.json`, `frozen-baseline/`, `frozen-semantic/`, and the four
`frozen-{baseline,semantic}-{390-18,320-30}.json` reports.

## Logical token and quotation identity

Use `?font=30&rows=1&identity=1` to stamp source tokens and bind them to every
rendered occurrence. Add `&scope=all` to include inline roots. The report records
binding failures and logical text changes independently of presentation text
changes. It does not replace visual fidelity or accessibility checks.

The frozen semantic corpus above passes at 320px/30px: all 6,759 outer math roots
have zero binding failures and zero logical quotation changes. Its 324 logical
marked nodes bind to 395 visual fragments. The display-only run likewise passes
for 1,412 roots, 322 marks, and 393 fragments. Mathematical alphabet encoding,
variation selectors, whitespace, and stretchy operators are mapped explicitly;
source characters remain unchanged in the quotation model.

The browser selection fixture uses the same module as the Reader's quotation
helpers. Copy the following beside an existing probe (which supplies its pinned
local MathJax/font assets), then open `/math-identity.html` at 320px:

```sh
cp tools/flow-reader/tests/fixtures/math-identity.html dist/reader-reflow-probe/
cp tools/flow-reader/tests/identity-browser.js dist/reader-reflow-probe/
cp -R tools/flow-reader/web/rendering dist/reader-reflow-probe/
cp -R tools/flow-reader/web/ui dist/reader-reflow-probe/
```

It checks native prose exclusion, source order, actual script reordering,
superscript-only selection, disjoint logical intervals, base/subscript-only
highlighting, all marker fragments, relationship geometry from the detached
original mark, and width fit. The fixture paints the base
and subscripts while leaving the superscript unpainted. Reports and the screenshot
are under `dist/reader-identity-checks`. These helpers are wired into Reader
selection and reading-position text. The later runtime fixture verifies the
integrated renderer, local assets, and asynchronous update handling independently.

## Native cancellation and overline comparison

The native adapters remove all 77 mathematical SVG islands in the frozen PDE
corpus while retaining its 6,759 outer math roots. This probe prepares tagged
cancellation enclosures for visual line breaking; the actual Reader draws their
original paint separately and preserves assistive enclosure notation. Overlines
use explicitly stretchy spacing bars around semantic bodies.

The paired reports under `dist/reader-math-overflow-checks` use `rows=1&identity=1&scope=all`
for both adapters, with identical frozen input files and measurement code. Their
overflow counts are 16 before / 14 after at 390px/18px and 164 before / 157 after
at 320px/30px. All four runs have zero rendering, token-binding, logical-text,
and SVG-count errors. The newer measurement includes complete stretched surfaces;
do not compare these counts directly with the earlier 1,412-display-root reports
or measurements that omitted complete stretched-operator surfaces.
This remains an isolated probe without dynamic paint, relationships, or the
Reader runtime's bounded small-overhang correction. Full layout, assistive-device
checks, and mobile rollout remain pending.

## Actual Reader candidate renderer

Snapshot the current Reader modules, styles, local renderer, and fonts directly:

```sh
python3 tools/flow-reader/research/math_runtime_probe.py /absolute/path/document.html \
  --output dist/reader-runtime-probe
python3 -m http.server 61508 --bind 127.0.0.1 --directory dist/reader-runtime-probe
```

Open `/math-runtime.html?font=30&width=273`. This calls `ResponsiveMath.candidate`
with the common body width (and equation padding), including its inline
promotion and small-overhang correction. It checks all 6,759 input roots and
6,873 expressions after annotation relocation. The report includes source and
renderer hashes, actual promotions, overflow, token binding, and canonical text.
Use `&index=1139` to inspect a single input root. All assets load from this origin.

Paired snapshots before/after inline promotion have 97 / 53 overflows at a 273px
body with 30px text, and eight / five at 343px with 18px text. All four runs have
zero rendering, token-binding, logical-text, or SVG-count errors. Canonical source
text uses the same whitespace normalization as published quotations, including
non-breaking spaces in equation references.

This audit uses common reading widths and font context. Actual surrounding
paragraph styles, publication, selection, dynamic decoration paint, relationships,
figures, and device accessibility need separate browser validation. The report
keeps those acceptance flags false. Evidence is under `dist/reader-inline-checks`.

The structured renderer snapshots additionally record `math-frames.js`. At the
same two widths/fonts it reduces all remaining 53 / five overflows to zero,
without rendering, token-binding, canonical-text, or SVG-count errors. These
results cover the same 6,759 source roots and 6,873 composed expressions. The
actual Reader structure fixture separately passes 69 checks at each of 320px and
390px, including large reading text, matrix structure and fonts, spanning paint,
canonical copy, and whole-page width. Evidence is under `dist/reader-frame-checks`.
Add `&preview=1` with a single `index` to retain a composed expression for visual
inspection; the probe still does not exercise dynamic paint or publication.

Useful primary references:

- [MathJax automatic line breaking](https://docs.mathjax.org/en/stable/output/linebreaks.html)
- [MathML input and embedded HTML](https://docs.mathjax.org/en/v4.1/options/input/mathml.html)
- [MathJax output options](https://docs.mathjax.org/en/stable/options/output/index.html)
- [MathML Core](https://www.w3.org/TR/mathml-core/)
