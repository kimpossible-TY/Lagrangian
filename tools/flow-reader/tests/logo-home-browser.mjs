// Run with CHROME_BIN and FLOW_READER_PLAYWRIGHT_MODULE as needed.
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { once } from "node:events";
import { createServer } from "node:http";
import { createInterface } from "node:readline";
import { fileURLToPath } from "node:url";

const { chromium } = await import(process.env.FLOW_READER_PLAYWRIGHT_MODULE || "playwright");
const fixture = spawn(process.env.PYTHON || "python3", [fileURLToPath(new URL("./paragraph_chat_fixture.py", import.meta.url))], { stdio: ["ignore", "pipe", "inherit"] });
const lines = createInterface({ input: fixture.stdout });
const { url } = await new Promise((resolve, reject) => {
  lines.once("line", (line) => resolve(JSON.parse(line)));
  fixture.once("exit", (code) => reject(new Error(`Fixture exited: ${code}`)));
});
// Serve the same shell at the standalone root, with no Homepage route.
const standalone = createServer(async (request, response) => {
  try {
    const upstream = await fetch(new URL(request.url.slice(1), url));
    response.writeHead(upstream.status, { "content-type": upstream.headers.get("content-type") || "application/octet-stream" });
    response.end(Buffer.from(await upstream.arrayBuffer()));
  } catch {
    response.writeHead(502).end();
  }
});
standalone.listen(0, "127.0.0.1");
await once(standalone, "listening");
let browser;
try {
  browser = await chromium.launch({ headless: true, ...(process.env.CHROME_BIN ? { executablePath: process.env.CHROME_BIN } : {}) });
  const context = await browser.newContext({ viewport: { width: 900, height: 700 }, hasTouch: true, serviceWorkers: "block" });
  const page = await context.newPage();
  const brand = page.locator("button.reader-brand");
  const popover = page.locator("#reader-logo-popover");
  const open = async (address) => {
    await page.goto(address);
    await brand.waitFor({ state: "visible" });
  };
  const drag = async (dx, dy) => {
    const box = await brand.boundingBox();
    const x = box.x + box.width / 2, y = box.y + box.height / 2;
    await page.mouse.move(x, y);
    await page.mouse.down();
    await page.mouse.move(x + dx, y + dy, { steps: 5 });
    await page.mouse.up();
  };
  await open(url + "?terminal=1");
  for (const [dx, dy] of [[15, 0], [-80, 0], [15, 80]]) {
    await drag(dx, dy);
    assert.equal(new URL(page.url()).pathname, "/d/fixture/");
    assert.equal(await popover.isVisible(), false);
  }
  await brand.click();
  assert.equal(await popover.isVisible(), true);
  await brand.click();
  assert.equal(await popover.isVisible(), false);
  await drag(80, 0);
  await page.waitForURL(new URL("/", url).href);
  await open(url);
  assert.equal(await brand.evaluate((element) => getComputedStyle(element).touchAction), "pan-y");
  assert.equal(await brand.locator("svg").evaluate((element) => getComputedStyle(element).touchAction), "pan-y");
  const box = await brand.boundingBox();
  const x = Math.round(box.x + box.width / 2), y = Math.round(box.y + box.height / 2);
  const cdp = await context.newCDPSession(page);
  const touchPoint = (offset) => ({ x: x + offset, y, id: 1, radiusX: 4, radiusY: 4 });
  await cdp.send("Input.dispatchTouchEvent", { type: "touchStart", touchPoints: [touchPoint(0)] });
  for (const offset of [8, 16, 32, 48, 64, 80]) {
    await cdp.send("Input.dispatchTouchEvent", { type: "touchMove", touchPoints: [touchPoint(offset)] });
  }
  assert.equal(await brand.evaluate((element) => element.classList.contains("reader-logo-dragging")), true);
  await cdp.send("Input.dispatchTouchEvent", { type: "touchEnd", touchPoints: [] });
  await page.waitForURL(new URL("/", url).href);
  await open(url);
  await brand.focus();
  await page.keyboard.press("Enter");
  assert.equal(await popover.isVisible(), true);
  await page.keyboard.press("Tab");
  assert.equal(await page.locator(".reader-logo-home-link").evaluate((link) => link === document.activeElement), true);
  await page.keyboard.press("Enter");
  await page.waitForURL(new URL("/", url).href);
  const singleURL = `http://127.0.0.1:${standalone.address().port}/`;
  await open(singleURL);
  await brand.click();
  assert.equal(await popover.isVisible(), true);
  assert.equal(await page.locator(".reader-logo-home-link").isVisible(), false);
  await brand.click();
  await drag(80, 0);
  assert.equal(page.url(), singleURL);
  assert.equal(await popover.isVisible(), false);
  await context.close();
} finally {
  if (browser) await browser.close();
  standalone.close();
  fixture.kill("SIGTERM");
  await once(fixture, "exit");
  lines.close();
}
