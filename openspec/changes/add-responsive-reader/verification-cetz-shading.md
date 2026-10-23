# CeTZ pale cell shading

The compiled PDE snapshot at `dist/reader-highlight-checks/pde/document.html`
contains the photographed "Successive reflections change orientation and sign"
figure: six blue `#f0f5ff` fills and four purple `#f0ebf8` fills. The previous
drawing adapter treated both pale colors as neutral foreground ink and converted
them to `#292824` on the light reading surface. Direct comparison with the
previous committed implementation reproduces that conversion. The corrected
presentation on `#faf9f6` is blue `rgb(235 239 247)` and purple
`rgb(235 229 240)`.

Pale geometric fills now retain their tint as a surface wash. Source colors
below the foreground contrast threshold recover their pigment and coverage over
white, then composite an adapted tint over the actual enclosing surface. Source
alpha is retained separately. Glyphs, including pale inherited symbol/use ink,
keep foreground contrast; strokes and marked-term underlays retain their existing
contrast rules. Authored SVG attributes and cached source colors remain intact.

Validation on 2026-10-23:

- All 160 HTML Reader Node tests passed. The five focused drawing-theme tests
  also passed after adding green-tinted light/dark callout surfaces.
- `drawing-theme-browser.mjs` passed five appearance scenarios in each of
  Chromium and WebKit: light/dark round trips, inherited glyphs, cell hues,
  alpha, native labels, stroke contrast, masks, gradient resources, original
  attributes and late/cloned paint on a different background.
- The same browser run loaded the actual compiled figure's SVG and checked all
  ten pale cell fills in every scenario. Both appearances' WebKit screenshots
  were inspected; the cells retain subtle blue/purple shading. Evidence is in
  `dist/reader-cetz-shading/{chromium,webkit}-{light,dark}.png`.
- The complete `lint:readers` ESLint command passed with zero warnings; changed
  test files passed again after the callout assertions were refined. Formatting,
  strict OpenSpec validation and whitespace checks passed.

Reproduce the browser run with `FLOW_READER_PLAYWRIGHT_MODULE` pointing to an
installed Playwright module, `FLOW_READER_DRAWING_DOCUMENT` pointing to the
compiled snapshot, and optional `FLOW_READER_DRAWING_SCREENSHOTS` selecting an
evidence directory:

```sh
node tools/flow-reader/tests/drawing-theme-browser.mjs
```

Without the optional document path, the browser runner exercises the standalone
SVG fixture. This validation used previously compiled CeTZ output; it did not
recompile the full document or verify physical iPhone rendering. No installed
release or user service was changed.
