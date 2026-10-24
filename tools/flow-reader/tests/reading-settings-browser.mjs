// Real Reader shell and adapters with disposable document/API responses.
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { createServer } from "node:http";

const playwright = await import(process.env.FLOW_READER_PLAYWRIGHT_MODULE || "playwright");
const web = new URL("../web/", import.meta.url);
const manifest = {
  revision: "settings-fixture",
  language: "ko",
  sections: [{ id: "intro", title: "읽기의 흐름" }],
  outline: [{ id: "intro", section: "intro", title: "읽기의 흐름", level: 1 }],
  anchors: { intro: "intro" },
  blocks: {},
};
const content =
  '<!doctype html><html lang="ko"><body><h1 id="intro">읽기의 흐름</h1>' +
  Array.from(
    { length: 35 },
    (_, i) =>
      `<p id="p-${i}">문장 사이에서 생각이 이어집니다. 읽기 좋은 화면은 내용을 가장 가까이에 두고, 필요한 설정은 손이 닿는 곳에 놓습니다.</p>`,
  ).join("") +
  "</body></html>";
const server = createServer(async (request, response) => {
  try {
    const path = new URL(request.url, "http://fixture.test").pathname;
    let body,
      type = "application/json";
    if (path === "/api/state")
      body = JSON.stringify({ revision: manifest.revision, contentGatePassed: true });
    else if (path === "/api/manifest") body = JSON.stringify(manifest);
    else if (path === "/api/sections/intro") {
      body = content;
      type = "text/html";
    } else if (path.endsWith("/api/compiler/config")) body = JSON.stringify({ enabled: false });
    else if (path.endsWith("/api/compiler/status"))
      body = JSON.stringify({ workers: [], history: [] });
    else {
      const file = new URL(path === "/" ? "index.html" : path.slice(1), web);
      if (!file.href.startsWith(web.href)) throw new Error("Outside fixture assets");
      body = await readFile(file);
      type = path.endsWith(".js")
        ? "text/javascript"
        : path.endsWith(".css")
          ? "text/css"
          : "text/html";
    }
    response.writeHead(200, { "Content-Type": type });
    response.end(body);
  } catch {
    response.writeHead(404).end();
  }
});
await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
const url = `http://127.0.0.1:${server.address().port}/`;
let checks = 0;
async function verify(browser, viewport, { fallback = false, zoom = false } = {}) {
  const page = await browser.newPage({ viewport });
  const errors = [];
  page.on("pageerror", (error) => errors.push(error.message));
  if (fallback)
    await page.addInitScript(() => {
      HTMLElement.prototype.showPopover = undefined;
      HTMLElement.prototype.hidePopover = undefined;
    });
  await page.goto(url);
  await page.waitForFunction(
    () => document.querySelector("#reader-document").getAttribute("aria-busy") === "false",
  );
  if (zoom)
    await page.evaluate(() => {
      document.documentElement.style.fontSize = "200%";
    });
  const trigger = page.locator("#reader-appearance-open");
  const panel = page.locator("#reader-appearance-panel");
  const opened = async () => {
    await trigger.click();
    await panel.waitFor({ state: "visible" });
    await page.waitForTimeout(230);
  };
  const fits = async () => {
    const geometry = await panel.evaluate((node) => {
      const rect = node.getBoundingClientRect();
      return {
        left: rect.left,
        right: rect.right,
        top: rect.top,
        bottom: rect.bottom,
        overflow: node.scrollWidth > node.clientWidth + 1,
        viewport: [innerWidth, innerHeight],
      };
    });
    assert.ok(geometry.left >= 0 && geometry.right <= geometry.viewport[0] + 1);
    assert.ok(geometry.top >= 0 && geometry.bottom <= geometry.viewport[1] + 1);
    assert.equal(geometry.overflow, false, "settings never require horizontal panning");
    checks++;
  };
  await opened();
  await fits();
  assert.equal(await trigger.getAttribute("aria-expanded"), "true");
  for (const id of [
    "reader-smaller",
    "reader-larger",
    "reader-theme",
    "reader-compute-level",
    "reader-apply-update",
    "reader-offline-status",
    "reader-highlight-queue-status",
    "reader-highlight-results-clear",
    "reader-compiler-diagnostics",
    "reader-diagnostic-copy",
    "reader-compiler-devices",
    "reader-compiler-history",
  ])
    assert.equal(await panel.locator(`[id="${id}"]`).count(), 1, `${id} remains available`);
  const original = Number(await page.locator("#reader-size").textContent());
  await page.locator("#reader-larger").hover();
  await page.mouse.down();
  assert.equal(Number(await page.locator("#reader-size").textContent()), original);
  await page.mouse.move(2, viewport.height - 2);
  await page.mouse.up();
  assert.equal(Number(await page.locator("#reader-size").textContent()), original);
  if ((await trigger.getAttribute("aria-expanded")) !== "true") await opened();
  await page.locator("#reader-larger").click();
  assert.equal(Number(await page.locator("#reader-size").textContent()), original + 1);
  await page.locator("#reader-smaller").click();
  assert.equal(Number(await page.locator("#reader-size").textContent()), original);
  checks++;
  if (fallback) {
    await page.locator("#reader-theme").selectOption("dark");
    assert.equal(await page.locator("html").getAttribute("data-theme"), "dark");
  } else {
    const dark = panel.locator('input[name="reader-appearance"][value="dark"]');
    await panel.locator('label:has(input[value="dark"])').click();
    assert.equal(await dark.isChecked(), true);
    assert.equal(await page.locator("html").getAttribute("data-theme"), "dark");
    await dark.focus();
    await page.keyboard.press("ArrowLeft");
    assert.equal(await page.locator("html").getAttribute("data-theme"), "light");
  }
  await fits();
  await panel.locator("#reader-compiler-diagnostics > summary").click();
  assert.equal(await panel.locator("#reader-compiler-diagnostics").getAttribute("open"), "");
  assert.equal(await panel.locator('[data-diagnostic="quick"]').isDisabled(), true);
  await panel.locator(".reader-compiler-log-details > summary").click();
  await fits();
  // Expanded diagnostics must remain reachable without hiding oversized children.
  assert.deepEqual(
    await panel.evaluate((node) => {
      const bounds = node.getBoundingClientRect();
      return [...node.querySelectorAll("button, input[type=range], summary")]
        .filter((control) => control.getClientRects().length)
        .filter((control) => {
          const rect = control.getBoundingClientRect();
          return rect.left < bounds.left || rect.right > bounds.right + 1;
        })
        .map((control) => control.id || control.textContent.trim());
    }),
    [],
  );
  const compute = panel.locator("#reader-compute-level");
  await compute.focus();
  await page.keyboard.press("ArrowRight");
  assert.equal(await compute.inputValue(), "1");
  assert.equal(await compute.getAttribute("aria-valuetext"), "High");
  checks++;
  await page.keyboard.press("Escape");
  await panel.waitFor({ state: "hidden" });
  assert.equal(await trigger.getAttribute("aria-expanded"), "false");
  assert.equal(await trigger.evaluate((node) => node === document.activeElement), true);
  checks++;
  await opened();
  await page.mouse.click(2, viewport.height - 2);
  await panel.waitFor({ state: "hidden" });
  assert.equal(await trigger.getAttribute("aria-expanded"), "false");
  // Reverse an exit before its decorative transition completes.
  await trigger.click();
  await panel.locator(".reader-appearance-close").click();
  await trigger.click();
  await panel.waitFor({ state: "visible" });
  await page.waitForTimeout(230);
  assert.equal(await trigger.getAttribute("aria-expanded"), "true");
  await fits();
  await page.setViewportSize({ width: Math.min(320, viewport.width), height: 568 });
  await page.waitForTimeout(230);
  await fits();
  await page.emulateMedia({ reducedMotion: "reduce", forcedColors: "active" });
  await fits();
  assert.deepEqual(
    await panel.evaluate((node) => ({
      transition: getComputedStyle(node).transitionDuration,
      transform: getComputedStyle(node).transform,
    })),
    { transition: "0s", transform: "none" },
  );
  await page.locator(".reader-appearance-close").click();
  await panel.waitFor({ state: "hidden" });
  await page.reload();
  await opened();
  assert.equal(Number(await page.locator("#reader-size").textContent()), original);
  assert.equal(await compute.inputValue(), "1", "explicit High choice survives reload");
  assert.equal(await compute.getAttribute("aria-valuetext"), "High");
  await compute.focus();
  await page.keyboard.press("ArrowLeft");
  assert.equal(await compute.inputValue(), "0");
  assert.equal(await compute.getAttribute("aria-valuetext"), "Low");
  checks++;
  assert.deepEqual(errors, []);
  await page.close();
}
try {
  for (const engine of (process.env.FLOW_READER_BROWSER_ENGINES || "chromium,webkit").split(",")) {
    const browser = await playwright[engine].launch({
      headless: true,
      ...(engine === "chromium" && process.env.FLOW_READER_CHROMIUM_CHANNEL
        ? { channel: process.env.FLOW_READER_CHROMIUM_CHANNEL }
        : {}),
    });
    try {
      for (const viewport of [
        { width: 320, height: 568 },
        { width: 390, height: 844 },
        { width: 844, height: 390 },
        { width: 1280, height: 900 },
      ])
        await verify(browser, viewport);
      await verify(browser, { width: 320, height: 568 }, { zoom: true });
      await verify(browser, { width: 390, height: 844 }, { fallback: true });
      console.log(`${engine}: settings controls, focus, interruption, resize and fallback passed`);
    } finally {
      await browser.close();
    }
  }
  console.log(`${checks} reading-settings browser checks passed`);
} finally {
  server.closeAllConnections();
  await new Promise((resolve) => server.close(resolve));
}
