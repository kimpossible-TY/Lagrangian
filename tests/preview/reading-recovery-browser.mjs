// Real browser geometry and revision guards; no services or user profiles.
import assert from "node:assert/strict";
import { build } from "esbuild";
import { homedir } from "node:os";
import { resolve } from "node:path";

const playwright = await import(
  process.env.PLAYWRIGHT_MODULE ||
    resolve(
      homedir(),
      ".cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright/index.mjs",
    )
);
const compiled = await build({
  entryPoints: ["tools/typst-preview-frontend/src/features/session/reading-recovery.ts"],
  bundle: true,
  write: false,
  format: "iife",
  globalName: "Recovery",
});
const browser = await playwright.webkit.launch({ headless: true });
try {
  const page = await browser.newPage({ viewport: { width: 900, height: 800 } });
  await page.setContent(`
    <style>
      #scroller { width: 400px; height: 400px; overflow: auto; overflow-anchor: none; }
      .tsel { font: 20px sans-serif; }
    </style>
    <div id="scroller"><div id="root"></div></div>
  `);
  await page.addScriptTag({ content: compiled.outputFiles[0].text });
  const results = await page.evaluate(() => {
    const scroller = document.getElementById("scroller");
    const root = document.getElementById("root");
    const render = (before, text = "The same reading passage") => {
      root.innerHTML = `<svg xmlns="http://www.w3.org/2000/svg" width="400" height="${before + 1000}">
        <rect class="typst-page-inner" data-page-number="0" data-page-width="400" data-page-height="${before}" width="400" height="${before}"/>
        <rect class="typst-page-inner" data-page-number="1" data-page-width="400" data-page-height="1000" y="${before}" width="400" height="1000"/>
        <g class="typst-page" data-page-number="1" transform="translate(0 ${before})">
          <foreignObject x="20" y="200" width="350" height="40">
            <div xmlns="http://www.w3.org/1999/xhtml" class="tsel">${text}</div>
          </foreignObject>
        </g>
      </svg>`;
    };
    render(1000);
    scroller.scrollTop = 1200;
    const recovery = new Recovery.ReadingRecovery(scroller, root);
    recovery.afterRender("document-a", "4");
    recovery.beforeReset();
    render(1400);
    const shiftedBeforeRestore = scroller.scrollTop;
    const restored = recovery.afterRender("document-a", "1");
    const shiftedAfterRestore = scroller.scrollTop;

    recovery.beforeReset();
    render(1800, "Changed passage at the same engine revision");
    const stale = recovery.afterRender("document-a", "1");
    const staleTop = scroller.scrollTop;

    scroller.scrollTop = 2000;
    recovery.beforeReset();
    render(2200, "Changed passage at the same engine revision");
    const unrelated = recovery.afterRender("document-b", "1");
    const unrelatedTop = scroller.scrollTop;

    scroller.scrollTop = 2400;
    recovery.beforeReset();
    render(2400, "Changed passage at the same engine revision");
    scroller.dispatchEvent(new WheelEvent("wheel"));
    scroller.scrollTop = 2600;
    const userNavigated = recovery.afterRender("document-b", "2");
    const navigatedTop = scroller.scrollTop;
    recovery.dispose();
    return {
      shiftedBeforeRestore,
      restored,
      shiftedAfterRestore,
      stale,
      staleTop,
      unrelated,
      unrelatedTop,
      userNavigated,
      navigatedTop,
    };
  });
  assert.equal(results.shiftedBeforeRestore, 1200);
  assert.equal(results.restored, true);
  assert.equal(results.shiftedAfterRestore, 1600);
  assert.equal(results.stale, false);
  assert.equal(results.staleTop, 1600);
  assert.equal(results.unrelated, false);
  assert.equal(results.unrelatedTop, 2000);
  assert.equal(results.userNavigated, false);
  assert.equal(results.navigatedTop, 2600);
  console.log(JSON.stringify({ browser: `WebKit ${browser.version()}`, ...results }, null, 2));
} finally {
  await browser.close();
}
