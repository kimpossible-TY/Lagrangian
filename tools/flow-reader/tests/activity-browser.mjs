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
      assert.equal(await page.locator("#reader-activity").isVisible(), true);
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
          const bounds = await page.locator("#reader-activity").boundingBox();
          assert.ok(bounds.x >= 0 && bounds.x + bounds.width <= width);
          assert.ok(bounds.y >= 50 && bounds.y + bounds.height <= 844);
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

      // A real native selection survives polling and a WebKit touch tap releases it.
      await selectPassage();
      Object.assign(state, { revision: "r2", compiling: false });
      await phase("selection-held");
      assert.equal(await page.locator(".reader-activity-ring").isVisible(), false);
      assert.equal(await page.locator("#version").textContent(), "Accepted r1");
      assert.ok(await page.evaluate(() => !getSelection().isCollapsed));
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
