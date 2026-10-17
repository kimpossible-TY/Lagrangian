# Width-aware math renderer evaluation

This isolated probe evaluates MathJax 4.1.3 against the accepted Reader's MathML.
It is not connected to the installed Reader, and a completed probe is not a
mobile-reading acceptance result. The user requires all essential content to be
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

The probe preserves SVG islands and enables embedded HTML in MathML tokens.
All scripts, font data, and fonts are served locally. The enhanced speech and
exploration features are disabled **only in this layout probe**: speech-worker
startup did not complete in the initial self-hosted configuration. Accessibility,
speech, and production CSP support remain unverified.

The report measures component scroll width and visible glyph/SVG bounds on both
sides. It also records text-order changes, SVG counts, and the ordered list of
annotation marker occurrences. Text-order changes are not proof of mathematical
corruption: for example, MathJax renders superscripts before subscripts in DOM
order. They do show why saved quotations cannot blindly use presentation DOM text.
Repeated marker attributes can represent one logical term split over several
lines. No marker must be resolved to only its first presentation fragment.

This is an isolated display-equation corpus, including embedded annotation
payloads as exported. It does not evaluate figures, surrounding paragraphs,
equation-number placement, graphical annotation programs, or visual mathematical
equivalence. SVG count equality does not prove SVG fidelity or readability.

## Recorded PDE result, 2026-10-17

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

Useful primary references:

- [MathJax automatic line breaking](https://docs.mathjax.org/en/stable/output/linebreaks.html)
- [MathML input and embedded HTML](https://docs.mathjax.org/en/v4.1/options/input/mathml.html)
- [MathJax output options](https://docs.mathjax.org/en/stable/options/output/index.html)
- [MathML Core](https://www.w3.org/TR/mathml-core/)
