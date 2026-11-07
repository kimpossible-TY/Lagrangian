= UI regression baseline

The Phase 0 harness checks static shell hooks with the Node test runner and checks generated Homepage, Reader and paragraph-chat selectors after the isolated fixtures render. It captures Chrome screenshots at 1280 × 800 and 390 × 844, in light and dark themes. The mobile size is viewport-only: it is not an iOS browser or physical-device test.

Install Playwright outside the repository or make it available to Node. Set `FLOW_READER_PLAYWRIGHT_MODULE` to its `index.mjs` when it is not locally resolvable. The default browser is `/Applications/Google Chrome.app/Contents/MacOS/Google Chrome`; `CHROME_BIN` overrides it. Python 3 is required. Run from the repository root:

```sh
export FLOW_READER_PLAYWRIGHT_MODULE=/absolute/path/to/playwright/index.mjs
node --test tools/flow-reader/tests/test_selector_contract.mjs
node tools/flow-reader/tests/ui-baseline.mjs --update-baseline
node tools/flow-reader/tests/ui-baseline.mjs
```

Review captures before promoting a new baseline with `--update-baseline`; this replaces all twelve local baseline images. Captures, baselines, diff images and `report.json` live under `.local/ui-baseline/`, which is gitignored. Pixel output depends on Chrome, system fonts and platform, so local storage avoids presenting one machine's pixels as universal truth. `baseline/version.json` records Chrome and Playwright versions, commit, dirty state, viewport and browser settings. Compare those with the current report metadata before interpreting changes; record the exact working-tree patch separately when dirty.

Each report entry says `match`, `different`, `size-mismatch` or `missing-baseline`, with changed and total pixel counts when comparable. Inspect `current/` alongside `baseline/`; `diff/` highlights changed pixels in red. Diffs and missing baselines do not fail the process and are not a CI gate. Fixture, browser, selector and other harness errors exit nonzero. The harness blocks requests outside its local fixture origins, fixes the browser clock and Homepage inventory timestamp, waits for fonts, and disables motion.
