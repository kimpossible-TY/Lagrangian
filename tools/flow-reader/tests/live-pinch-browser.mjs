/* global pinchTest */
// Serve the real Reader shell and modules with a deterministic saved document.
// Touch events here are synthetic; physical iPhone gesture arbitration is separate.
import assert from "node:assert/strict";
import { once } from "node:events";
import { readFile } from "node:fs/promises";
import { createServer } from "node:http";

const playwright = await import(process.env.FLOW_READER_PLAYWRIGHT_MODULE || "playwright");
const web = new URL("../web/", import.meta.url);
const assets = JSON.parse(await readFile(new URL("assets.json", web), "utf8"));
const vendor = "vendor/mathjax-4.1.3/";
const vendorManifest = JSON.parse(await readFile(new URL(vendor + "manifest.json", web), "utf8"));
for (const file of Object.keys(vendorManifest.files)) assets[vendor + file] = vendor + file;
const manifest = {
  revision: "live-pinch-fixture",
  documentID: "live-pinch-fixture",
  service: "pinch-test",
  sections: [{ id: "section-0" }],
  outline: [{ id: "start", level: 1, title: "Live reading", section: "section-0" }],
  anchors: { start: "section-0" },
  blocks: {},
};
const body = `<html lang="en"><body><h1 id="start">Live reading</h1>
  <p>See <a href="#start">the start</a> while reading.</p>
  <math display="block"><mrow><mfrac><mi>x</mi><mn>2</mn></mfrac><mo>+</mo><mi>y</mi><mo>=</mo><mn>1</mn></mrow></math>
  ${Array.from({ length: 70 }, (_, i) => `<p id="passage-${i}">Passage ${i}: Live text reflow retains the original reading location while the reader moves two fingers. The text and mathematics remain in their original order.</p>`).join("")}
  </body></html>`;
const server = createServer(async (request, response) => {
  try {
    const path = new URL(request.url, "http://localhost").pathname.slice(1) || "index.html";
    let payload, type;
    if (path === "api/state") {
      payload = JSON.stringify({ ...manifest, exitCode: 0, contentGatePassed: true });
      type = "application/json";
    } else if (path === "api/manifest") {
      payload = JSON.stringify(manifest);
      type = "application/json";
    } else if (path === "api/sections/section-0") {
      payload = body;
      type = "text/html";
    } else if (path === "reading-navigation-browser.js") {
      payload = await readFile(new URL("./reading-navigation-browser.js", import.meta.url));
      type = "text/javascript";
    } else if (assets[path]) {
      payload = await readFile(new URL(assets[path], web));
      type = path.endsWith(".js")
        ? "text/javascript"
        : path.endsWith(".css")
          ? "text/css"
          : path.endsWith(".html")
            ? "text/html"
            : "application/octet-stream";
    } else {
      response.writeHead(404).end();
      return;
    }
    response.writeHead(200, { "Content-Type": type });
    response.end(payload);
  } catch {
    response.writeHead(404).end();
  }
});
server.listen(0, "127.0.0.1");
await once(server, "listening");

try {
  for (const engine of ["chromium", "webkit"]) {
    const browser = await playwright[engine].launch({
      headless: true,
      ...(engine === "chromium" && process.env.FLOW_READER_CHROMIUM_CHANNEL
        ? { channel: process.env.FLOW_READER_CHROMIUM_CHANNEL }
        : {}),
    });
    try {
      const page = await browser.newPage({ viewport: { width: 390, height: 844 }, hasTouch: true });
      const errors = [];
      page.on("pageerror", (error) => errors.push(error.message));
      await page.goto(`http://127.0.0.1:${server.address().port}/`);
      await page.waitForFunction(() =>
        document.querySelector('.flow-math-view[data-math-state="ready"]'),
      );
      await page.evaluate(() => {
        for (let i = 0; i < 5; i++) document.querySelector("#reader-larger").click();
      });
      await page.waitForFunction(() =>
        document.querySelector('.flow-math-view[data-math-state="ready"]'),
      );
      await page.evaluate(() => {
        const article = document.querySelector("#reader-document");
        const target = document.querySelector("#passage-20");
        scrollBy(0, target.getBoundingClientRect().top - 60);
        const data = (globalThis.pinchTest = {
          writes: [],
          anchorTop: target.getBoundingClientRect().top,
          mathFont: parseFloat(getComputedStyle(article.querySelector("mjx-container")).fontSize),
        });
        const write = Storage.prototype.setItem;
        Storage.prototype.setItem = function (key, value) {
          if (key.endsWith(":fontSizeV2")) data.writes.push(value);
          return write.call(this, key, value);
        };
        const touch = (id, x) => {
          const contact = {
            identifier: id,
            target,
            clientX: x,
            clientY: 250,
            pageX: x,
            pageY: 250,
          };
          try {
            return new Touch(contact);
          } catch {
            return contact;
          }
        };
        data.left = touch(1, 80);
        data.right = touch(2, 180);
        data.send = (name, touches, changed = touches) => {
          const event = new Event(name, { bubbles: true, cancelable: true });
          Object.defineProperties(event, {
            touches: { value: touches },
            changedTouches: { value: changed },
          });
          target.dispatchEvent(event);
        };
        data.send("touchstart", [data.left, data.right]);
        data.send("touchmove", [data.left, touch(2, 220)]);
      });
      await page.waitForFunction(() => Number(document.querySelector("#reader-size").value) === 25);
      const live = await page.evaluate(() => ({
        font: getComputedStyle(document.querySelector("#reader-document")).fontSize,
        writes: pinchTest.writes,
        anchorError: Math.abs(
          document.querySelector("#passage-20").getBoundingClientRect().top - pinchTest.anchorTop,
        ),
        mathGrew:
          parseFloat(getComputedStyle(document.querySelector("mjx-container")).fontSize) >
          pinchTest.mathFont,
        scale: visualViewport?.scale ?? 1,
      }));
      assert.equal(live.font, "25px");
      assert.deepEqual(live.writes, []);
      assert.ok(live.anchorError < 2, `Reading anchor drifted ${live.anchorError}px`);
      assert.equal(live.mathGrew, true);
      assert.equal(live.scale, 1);
      await page.evaluate(() => {
        pinchTest.send("touchend", [pinchTest.left], [pinchTest.right]);
        pinchTest.send("touchend", [], [pinchTest.left]);
      });
      assert.deepEqual(await page.evaluate(() => pinchTest.writes), ["25"]);
      await page.waitForFunction(
        () => !document.querySelector('.flow-math-view[data-math-state="pending"]'),
      );
      await page.addScriptTag({ type: "module", url: "/reading-navigation-browser.js" });
      await page.waitForFunction(() => document.body.dataset.readingNavigationState, undefined, {
        timeout: 30000,
      });
      const report = JSON.parse(await page.locator("#reading-navigation-report").textContent());
      assert.deepEqual(report.errors, []);
      assert.deepEqual(errors, []);
      console.log(
        `${engine}: live body/math size, stable reading anchor, one preference write and ${report.checks.length} gesture checks passed`,
      );
    } finally {
      await browser.close();
    }
  }
} finally {
  server.close();
  await once(server, "close");
}
