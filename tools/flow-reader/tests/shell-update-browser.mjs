// Actual Service Worker upgrade keeps an open Reader until the user applies it.
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { createServer } from "node:http";
import { once } from "node:events";

const playwright = await import(process.env.FLOW_READER_PLAYWRIGHT_MODULE || "playwright");
const offline = await readFile(new URL("../web/features/session/offline.js", import.meta.url));
const worker = await readFile(
  new URL("../web/features/session/offline-worker.js", import.meta.url),
);
let release = "one";
let disconnected = false;
const server = createServer((request, response) => {
  if (disconnected) return request.socket.destroy();
  const path = new URL(request.url, "http://localhost").pathname;
  const files = {
    "/reader/":
      '<!doctype html><meta charset="utf-8"><p id="version"></p><p id="passage">Reading selection survives a pending upgrade.</p><button id="reader-apply-update" hidden>업데이트 적용</button><script type="module" src="entry.js"></script>',
    "/reader/entry.js": `import { OfflineReader } from './features/session/offline.js';
      document.querySelector('#version').textContent = ${JSON.stringify(release)};
      const button = document.querySelector('#reader-apply-update');
      const reader = new OfflineReader({updateAvailable(ready) {button.hidden = !ready;}});
      globalThis.reader = reader;
      button.onclick = async () => {if (await reader.applyUpdate()) location.reload();};`,
    "/reader/offline.js": offline,
    "/reader/offline-worker.js": worker,
    "/reader/service-worker.js": `import { runOfflineWorker } from './offline-worker.js';
      runOfflineWorker(self, ${JSON.stringify({ version: release, files: ["index.html", "entry.js", "features/session/offline.js", "offline-worker.js"] })});`,
  };
  // The actual Reader registers ../../service-worker.js relative to features/session/offline.js.
  files["/reader/features/session/offline.js"] = files["/reader/offline.js"];
  files["/reader/index.html"] = files["/reader/"];
  const data = files[path];
  response.writeHead(data ? 200 : 404, {
    "Content-Type": path.endsWith(".js") ? "text/javascript" : "text/html",
    "Cache-Control": "no-store",
  });
  response.end(data || "not found");
});
await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
const origin = `http://127.0.0.1:${server.address().port}/reader/`;
try {
  for (const engine of (process.env.FLOW_READER_BROWSER_ENGINES || "chromium,webkit").split(",")) {
    release = "one";
    const browser = await playwright[engine].launch({
      headless: true,
      ...(engine === "chromium" && process.env.FLOW_READER_CHROMIUM_CHANNEL
        ? { channel: process.env.FLOW_READER_CHROMIUM_CHANNEL }
        : {}),
    });
    try {
      const page = await browser.newPage();
      await page.goto(origin);
      await page.waitForFunction(() => navigator.serviceWorker.controller);
      assert.equal(await page.locator("#version").textContent(), "one");
      await page.evaluate(() => {
        const range = document.createRange();
        range.selectNodeContents(document.querySelector("#passage"));
        getSelection().removeAllRanges();
        getSelection().addRange(range);
      });
      release = "two";
      await page.evaluate(async () => (await navigator.serviceWorker.getRegistration()).update());
      await page.locator("#reader-apply-update").waitFor({ state: "visible", timeout: 30000 });
      assert.equal(await page.locator("#version").textContent(), "one", "no unsolicited reload");
      assert.match(await page.evaluate(() => getSelection().toString()), /selection survives/);
      // Reproduce the stale-shell behavior of an ordinary refresh while an update waits.
      await page.reload();
      assert.equal(await page.locator("#version").textContent(), "one");
      await page.locator("#reader-apply-update").click();
      await page.waitForFunction(() => document.querySelector("#version").textContent === "two");
      await page.waitForFunction(() => document.querySelector("#reader-apply-update").hidden);
      disconnected = true;
      await page.reload();
      await page.waitForFunction(() => document.querySelector("#version").textContent === "two");
      disconnected = false;
      console.log(`${engine}: stale shell reproduced, explicit update and offline restart passed`);
    } finally {
      disconnected = false;
      await browser.close();
    }
  }
} finally {
  server.closeAllConnections();
  server.close();
  await once(server, "close");
}
