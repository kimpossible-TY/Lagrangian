# Reading settings redesign verification

## Result

Integrated the HTML/CSS design supplied by Antigravity's Argon session through
reason-network. Theme previews and the font stepper form the first group;
offline/highlight status and device computation have separate tonal groups.
Diagnostics and connection history retain native disclosures and all existing
actions and preference keys. The toolbar still has its two icon actions.

`reading-settings.js` now owns native/fallback panel placement and dismissal;
`theme.js` retains early theme application and preference/control synchronization.
The CSS preference is 21.5rem (344px at the default root size), bounded to the
visual viewport. Integration fixes cover WebKit Escape focus return, diagnostic
button overflow at 200% text sizing, the older-browser native-select baseline,
opening-animation specificity and the nested disclosure's expanded indicator.

The material is a CSS frosted-glass approximation with opaque child groups and
locally chosen timing/blur values. It does not implement native Liquid Glass
refraction or claim Apple's shipped constants or a measured frame rate.

## Checks run

- `node --test tools/flow-reader/tests/test_*.mjs tools/reader-common/tests/architecture.mjs`:
  192 tests passed, no failures or skips.
- The exact ESLint command from `lint:readers`, run through
  `node_modules/.bin/eslint` because Yarn was not on PATH: passed with zero warnings.
- Prettier checks on changed HTML, CSS, JavaScript and browser fixture: passed.
- `reading-settings-browser.mjs` in installed Chrome (Playwright Chromium channel)
  and Playwright WebKit: 120 checks passed. Each engine exercised 320×568,
  390×844, 844×390 and 1280×900 viewports, plus 320×568 at 200% root text sizing
  and a simulated missing-Popover-API fallback.
- That fixture checked font-button activation and canceled pointer release,
  radio keyboard selection/native-select fallback, light/dark state, both
  diagnostic disclosures, Low/High keyboard input and reload persistence,
  Escape/close focus return, outside dismissal, reopen during exit, viewport
  resizing, reduced motion, forced colors and horizontal bounds with diagnostics
  expanded. Missing Popover APIs and 200% root sizing are simulations rather
  than an old-browser installation or native Dynamic Type.
- `live-pinch-browser.mjs`: both engines passed real body/math reflow, stable
  reading anchors, one final preference write and 36 gesture checks each,
  including the existing fallback settings clone.
- An isolated Chrome capture sampled opening opacity at 0, approximately 0.71
  after 70ms and 1 at rest, with the transform settling to none. Visual inspection
  covered phone light/dark and expanded diagnostics at 320px/200% text sizing.
  Captures are local generated artifacts under `dist/reader-settings-redesign/`.
- `node scripts/link-docs.mjs --check`, Typst compilation of the updated reader
  architecture source, `openspec validate add-responsive-reader --strict` and
  `git diff --check`: passed.

## Limits

The fixtures use disposable documents and API responses. They do not establish
physical iPhone/iPad, VoiceOver, native text-scaling, device rendering performance
or real WASM diagnostic execution coverage. Reduced-transparency and increased-
contrast treatments were reviewed in CSS; they were not separately emulated.

## Rollout deployment

- Clean immutable release installed via `tools/flow-reader/install.py`:
  `0f581f493f13db327c43805abc8d7c533c19120d-wasm-6a194fad0b95c8b4`.
- Running service `typst-pde-reader` verified on port 23627 (PID 78210).
- Local loopback and public Tailscale HTTPS endpoints confirmed serving redesigned
  HTML and CSS (`reader-settings-group`, `reader-settings-status-card`, `reader-compute-section`).
- Document compilation verified healthy (`contentGatePassed: true`, exit code 0,
  67 canvases, 15 graphics, 171 decorations).
- Detailed verification metadata recorded in `verification-reading-settings-rollout.json`.
