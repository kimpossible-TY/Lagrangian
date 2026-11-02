// Deterministic session responses exercise the real Reader shell in both engines.
// Run with FLOW_READER_PLAYWRIGHT_MODULE pointing to an installed Playwright module.
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { createServer } from "node:http";
import { once } from "node:events";

const playwright = await import(process.env.FLOW_READER_PLAYWRIGHT_MODULE || "playwright");
const web = new URL("../web/", import.meta.url);
const assets = JSON.parse(await readFile(new URL("assets.json", web), "utf8"));
const state = {
  revision: null,
  compiling: true,
  exitCode: 0,
  contentGatePassed: true,
  documentID: "activity-fixture",
  service: "activity-test",
};
let offline = false;
let sectionFailure = false;
let sectionGate = null;
const server = createServer(async (request, response) => {
  const path = new URL(request.url, "http://localhost").pathname.slice(1) || "index.html";
  const send = (body, type, code = 200) => {
    response.writeHead(code, { "Content-Type": type, "Cache-Control": "no-store" });
    response.end(body);
  };
  if (path === "api/state")
    return send(JSON.stringify(state), "application/json", offline ? 503 : 200);
  if (path === "api/manifest")
    return send(
      JSON.stringify({
        revision: state.revision,
        documentID: state.documentID,
        service: state.service,
        sections: [{ id: "section-0" }],
        outline: [{ id: "start", level: 1, title: "Reading", section: "section-0" }],
        anchors: { start: "section-0" },
        blocks: {},
      }),
      "application/json",
    );
  if (path === "api/sections/section-0") {
    const revision = state.revision;
    if (sectionGate) await sectionGate;
    return send(
      `<html lang="en"><head><title>Activity fixture</title></head><body>
        <h1 id="start">Reading</h1>
        <p id="version">Accepted ${revision}</p>
        ${"<p>Reading text remains available while a saved update is pending.</p>".repeat(70)}
      </body></html>`,
      "text/html",
      sectionFailure ? 503 : 200,
    );
  }
  if (assets[path])
    return send(
      await readFile(new URL(assets[path], web)),
      path.endsWith(".js")
        ? "text/javascript"
        : path.endsWith(".css")
          ? "text/css"
          : path.endsWith(".html")
            ? "text/html"
            : "application/octet-stream",
    );
  send("Not found", "text/plain", 404);
});
server.listen(0, "127.0.0.1");
await once(server, "listening");
const url = `http://127.0.0.1:${server.address().port}/`;

try {
  for (const engine of ["chromium", "webkit"]) {
    Object.assign(state, { revision: null, compiling: true, exitCode: 0 });
    const browser = await playwright[engine].launch({
      headless: true,
      ...(engine === "chromium" && process.env.FLOW_READER_CHROMIUM_CHANNEL
        ? { channel: process.env.FLOW_READER_CHROMIUM_CHANNEL }
        : {}),
    });
    try {
      const page = await browser.newPage({
        viewport: { width: 390, height: 844 },
        hasTouch: true,
        locale: "ko-KR",
      });
      const errors = [];
      page.on("pageerror", (error) => errors.push(error.message));
      const phase = (value) =>
        page.waitForFunction(
          (expected) => document.querySelector("#reader-activity").dataset.phase === expected,
          value,
        );
      const ready = async (revision) => {
        await phase("ready");
        assert.equal(await page.locator("#version").textContent(), `Accepted ${revision}`);
        assert.equal(await page.locator("#reader-activity").isVisible(), false);
      };
      const selectPassage = () =>
        page.evaluate(() => {
          const paragraph = [...document.querySelectorAll("#reader-document p")].find((node) => {
            const rect = node.getBoundingClientRect();
            return rect.top > 200 && rect.bottom < innerHeight;
          });
          const range = document.createRange();
          range.selectNodeContents(paragraph);
          getSelection().removeAllRanges();
          getSelection().addRange(range);
        });
      await page.goto(url);
      await phase("compiling");
      assert.equal(await page.locator("#reader-activity").isVisible(), false);
      assert.equal(await page.locator("#reader-logo").getAttribute("data-phase"), "compiling");
      let releaseSection;
      sectionGate = new Promise((resolve) => (releaseSection = resolve));
      Object.assign(state, { revision: "r1", compiling: false });
      await phase("loading");
      releaseSection();
      sectionGate = null;
      await ready("r1");

      // Activity stays visible deep in a document and fits narrow themes/viewports.
      await page.evaluate(() => scrollTo(0, 1500));
      state.compiling = true;
      await phase("compiling");
      for (const theme of ["light", "dark"]) {
        for (const width of [320, 390, 768]) {
          await page.setViewportSize({ width, height: 844 });
          await page.evaluate((value) => (document.documentElement.dataset.theme = value), theme);
          const bounds = await page.locator(".reader-brand").boundingBox();
          assert.ok(bounds.x >= 0 && bounds.x + bounds.width <= width);
          assert.ok(bounds.y >= 0 && bounds.y + bounds.height <= 844);
        }
      }
      await page.setViewportSize({ width: 390, height: 844 });
      await page.emulateMedia({ reducedMotion: "reduce" });
      assert.equal(
        await page
          .locator(".reader-activity-ring")
          .evaluate((node) => getComputedStyle(node).animationName),
        "none",
      );

      assert.equal(
        await page
          .locator(".reader-logo-beam")
          .evaluate((node) => getComputedStyle(node).animationName),
        "none",
      );
      // The logo explains activity; details remain in advanced settings.
      assert.equal(await page.locator(".reader-logo-panel").count(), 0);
      const brand = page.locator(".reader-brand");
      const brandLabel = await brand.getAttribute("aria-label");
      assert.ok(
        brandLabel && (brandLabel.includes("연결됨") || brandLabel.includes("문서를")),
        "logo button exposes accessible name for current state only",
      );
      assert.equal(
        await brand.getAttribute("aria-keyshortcuts"),
        "Shift+Enter",
        "logo button exposes Shift+Enter shortcut",
      );
      assert.equal(await brand.getAttribute("aria-expanded"), "false");
      assert.equal(await brand.getAttribute("aria-controls"), "reader-logo-popover");

      await brand.click();
      assert.equal(await brand.getAttribute("aria-expanded"), "true");
      assert.equal(await page.locator("#reader-logo-popover").isVisible(), true);
      await page.keyboard.press("Escape");
      assert.equal(await brand.getAttribute("aria-expanded"), "false");
      assert.equal(await page.locator("#reader-logo-popover").isVisible(), false);
      // Shift+Enter invokes the deliberate refresh action.
      state.compiling = false;
      await brand.focus();
      await Promise.all([page.waitForNavigation(), page.keyboard.press("Shift+Enter")]);
      await ready("r1");
      await page.locator("#reader-appearance-open").click();
      await page.locator(".reader-settings-advanced > summary").click();
      assert.equal(await page.locator("#reader-offline-status").isVisible(), true);
      await page.keyboard.press("Escape");

      // A real native selection survives polling, and logo tap/click in held state preserves it.
      await selectPassage();
      Object.assign(state, { revision: "r2", compiling: false });
      await phase("selection-held");
      assert.equal(await page.locator(".reader-activity-ring").isVisible(), false);
      assert.equal(await page.locator("#version").textContent(), "Accepted r1");
      assert.ok(await page.evaluate(() => !getSelection().isCollapsed));

      // Logo tap in held state must NOT reload and must keep the active selection.
      await brand.tap();
      assert.equal(
        await page.evaluate(() => getSelection().isCollapsed),
        false,
        "logo tap keeps selection",
      );
      assert.equal(
        await page.locator("#version").textContent(),
        "Accepted r1",
        "held-state tap does not reload",
      );

      // A second logo click dismisses the popover while preserving selection.
      await brand.click();
      assert.equal(
        await page.evaluate(() => getSelection().isCollapsed),
        false,
        "logo click keeps selection",
      );
      assert.equal(
        await page.locator("#version").textContent(),
        "Accepted r1",
        "held-state click does not reload",
      );
      assert.equal(await page.locator("#reader-logo-popover").isVisible(), false);
      await brand.focus();
      await page.keyboard.press("Shift+Enter");
      assert.equal(
        await page.evaluate(
          () => document.activeElement === document.querySelector("#reader-activity button"),
        ),
        true,
      );
      assert.equal(await page.evaluate(() => !getSelection().isCollapsed), true);

      if (process.env.FLOW_READER_ACTIVITY_SCREENSHOTS)
        for (const theme of ["light", "dark"]) {
          await page.evaluate((value) => (document.documentElement.dataset.theme = value), theme);
          await page.screenshot({
            path: `${process.env.FLOW_READER_ACTIVITY_SCREENSHOTS}/${engine}-${theme}.png`,
          });
        }
      await page.locator("#reader-activity button").tap();
      await ready("r2");
      assert.equal(await page.evaluate(() => getSelection().isCollapsed), true);

      // A waiting service worker shows an update badge and activates the applyUpdate path.
      await page.evaluate(() => {
        window.__offlineApplied = false;
        const fakeOffline = {
          registration: { waiting: {} },
          applyUpdate: async () => {
            window.__offlineApplied = true;
            return false;
          },
        };
        window.__readerLogo.offline = fakeOffline;
        window.__readerLogo.setUpdateWaiting(true);
      });
      assert.equal(await page.locator(".reader-logo-badge").textContent(), "↑");
      assert.ok(
        (await brand.getAttribute("aria-description")).includes("업데이트 적용"),
        "accessible description reflects update action",
      );
      const logoBounds = await brand.boundingBox();
      await page.mouse.move(
        logoBounds.x + logoBounds.width / 2,
        logoBounds.y + logoBounds.height / 2,
      );
      await page.mouse.down();
      await page.waitForTimeout(550);
      await page.mouse.up();
      assert.equal(await page.locator("#reader-logo-popover").isVisible(), false);
      assert.equal(
        await page.evaluate(() => window.__offlineApplied),
        true,
        "logo click calls applyUpdate",
      );
      await page.evaluate(() => {
        window.__readerLogo.setUpdateWaiting(false);
        window.__readerLogo.offline = null;
      });

      // A selection made during the fetch also holds publication; keyboard release works.
      sectionGate = new Promise((resolve) => (releaseSection = resolve));
      state.revision = "late-selection";
      await phase("loading");
      await selectPassage();
      releaseSection();
      sectionGate = null;
      await phase("selection-held");
      assert.equal(await page.locator("#version").textContent(), "Accepted r2");
      await page.locator("#reader-activity button").focus();
      await page.keyboard.press("Enter");
      await ready("late-selection");

      // Dialog dismissal uses the same immediate resume path without clearing text.
      await page.locator("#reader-menu").click();
      Object.assign(state, { revision: "r3" });
      await phase("interaction-held");
      assert.equal(await page.locator("#reader-activity button").isVisible(), false);
      await page.locator("#reader-navigation-close").click();
      await ready("r3");

      state.exitCode = 1;
      await phase("compile-error");
      assert.equal(await page.locator("#version").textContent(), "Accepted r3");
      assert.equal(await page.locator(".reader-activity-ring").isVisible(), true);
      assert.equal(
        await page
          .locator(".reader-activity-ring")
          .evaluate((node) => getComputedStyle(node).animationName),
        "none",
      );
      state.exitCode = 0;
      offline = true;
      await phase("reconnecting");
      assert.equal(await page.locator("#version").textContent(), "Accepted r3");
      offline = false;
      await ready("r3");

      sectionFailure = true;
      state.revision = "r4";
      await phase("load-error");
      assert.equal(await page.locator("#version").textContent(), "Accepted r3");
      sectionFailure = false;
      await ready("r4");
      assert.deepEqual(errors, []);
      process.stdout.write(
        `PASS ${engine}: loading, updates, late selection, tap/keyboard release, dialog, errors, recovery, layout and reduced motion\n`,
      );
    } finally {
      await browser.close();
    }
  }
} finally {
  server.closeAllConnections();
  server.close();
  await once(server, "close");
}
