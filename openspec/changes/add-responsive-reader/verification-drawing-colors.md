# Complete drawing color adaptation

The four follow-up color failures are corrected in the HTML appearance owner:

- Numeric Oklab/Oklch colors emitted by Typst resolve into bounded sRGB with
  authored alpha. Existing RGB input remains supported. `color.js` is an
  explicitly served appearance asset, and the existing drawing-theme parseColor
  export remains available to its consumers.
- Paint resolves on drawable shapes and text independently, so a shared group
  fill remains a pale surface on its rectangle and readable ink on its text.
- Fixed color/currentColor ink receives foreground correction. Unpainted and
  symbolic symbol definitions retain each use instance's distinct color, while
  explicitly painted reusable definitions still adapt.
- Authored attribute/style changes invalidate source paint. Cloneable original
  inline values/priorities distinguish authored edits from presentation. Removed
  values, none, resource URLs and currentColor resolve afresh. Enclosing HTML,
  native label and MathML color edits use the same ownership rule.

Validation on 2026-10-23:

- `node --test tools/flow-reader/tests/test_*.mjs
  tools/reader-common/tests/architecture.mjs`: all 168 tests passed, including
  parser and appearance tests and both dependency-boundary checks; no skips.
- Chromium and WebKit each passed 17 browser scenarios: repeated appearances,
  Oklab and alpha, mixed inherited paint, fixed currentColor, attribute/inline
  changes and removal, URLs/none, post-edit clones, native/MathML/enclosing text
  color, important inline paint, explicit defs paths and distinct plain/inherit/
  currentColor symbol instances. Detached mutation/reinsertion produces no page
  errors, and the observer settles for three consecutive idle frames.
- The optional compiled-document run rendered all four Oklab figures from
  `dist/reader-highlight-checks/pde/document.html`: 34 fills (4/22/6/2), all
  matching their numeric source-based expected paint, with original alpha,
  attributes and SVG resources preserved. All 81 solid vector foreground checks
  passed in both appearances. Source native labels are exported separately;
  glyph contrast is exercised by the deterministic fixture.
- The original photographed diagram's ten blue/purple cells still pass in each
  scenario. Actual-figure light/dark screenshots were inspected. Evidence is in
  `dist/reader-color-fixes/`, including each engine's `compiled-colors.json` and
  `*-compiled-oklab.png`. Thirty authored Oklab shades remain thirty rendered
  shades in light mode and twenty-nine in dark mode after 8-bit rounding.
- Reader ESLint passed with zero warnings, changed JS/HTML formatting checks
  passed, and strict OpenSpec/whitespace validation passed.
- `python3 -m unittest discover -s tools/flow-reader/tests -p test_install.py -v`
  passed its real isolated archive/install/import/HTTP-delivery test, including
  the new appearance asset.

Reproduce the browser verification with the same environment documented in
`verification-cetz-shading.md`, selecting the compiled snapshot and an evidence
directory, then run `node tools/flow-reader/tests/drawing-theme-browser.mjs`.
Without a compiled-document path the deterministic regression fixture still
runs. Oklab conversions were independently checked against both engines' sRGB
canvas output. No full-document recompilation, physical iPhone or installed-user
service verification was performed; these are source and isolated-layout fixes.
