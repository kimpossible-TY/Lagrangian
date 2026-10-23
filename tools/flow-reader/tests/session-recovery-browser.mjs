/* global recoveryTest */
// Real Reader shell against isolated accepted snapshots. No installed service or compiler is used.
import assert from "node:assert/strict";
import { once } from "node:events";
import { readFile } from "node:fs/promises";
import { createServer } from "node:http";

const playwright = await import(process.env.FLOW_READER_PLAYWRIGHT_MODULE || "playwright");
const web = new URL("../web/", import.meta.url);
const assets = JSON.parse(await readFile(new URL("assets.json", web), "utf8"));
let manifest;
let unavailable = false;
let stateRequests = 0;
let sectionRequests = 0;
let savedSelection;
function documentManifest(revision = "r1", documentID = "book", startedAt = 1) {
  return {
    revision,
    documentID,
    service: { pid: 10, startedAt },
    sections: [{ id: "section-0" }],
    outline: [],
    anchors: {},
    blocks: Object.fromEntries(
      Array.from({ length: 50 }, (_, i) => [`paragraph-${i}`, "section-0"]),
    ),
  };
}
function body() {
  return `<html lang="en"><body>${Array.from(
    { length: 50 },
    (_, i) =>
      `<p id="paragraph-${i}" data-reader-key="paragraph-${i}">Passage ${i}: The reader preserves this exact selected text through a connection interruption. ${i === 49 ? manifest.revision + " " + manifest.documentID : "Reading stays at the same location."}</p>`,
  ).join("")}</body></html>`;
}
const server = createServer(async (request, response) => {
  try {
    const path = new URL(request.url, "http://localhost").pathname.slice(1) || "index.html";
    let payload, type;
    if (path.startsWith("api/") && unavailable) {
      response.writeHead(503).end();
      return;
    }
    if (path === "api/state") {
      stateRequests++;
      payload = JSON.stringify({ ...manifest, exitCode: 0, contentGatePassed: true });
      type = "application/json";
    } else if (path === "api/manifest") {
      payload = JSON.stringify(manifest);
      type = "application/json";
    } else if (path === "api/sections/section-0") {
      sectionRequests++;
      payload = body();
      type = "text/html";
    } else if (path === "api/focus") {
      let data = "";
      for await (const chunk of request) data += chunk;
      savedSelection = JSON.parse(data);
      payload = JSON.stringify({ status: "stale" });
      type = "application/json";
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
    response.writeHead(500).end();
  }
});
server.listen(0, "127.0.0.1");
await once(server, "listening");
let checks = 0;
const check = (name, value) => {
  assert.ok(value, name);
  checks++;
};
try {
  for (const engine of (process.env.FLOW_READER_BROWSER_ENGINES || "chromium,webkit").split(",")) {
    manifest = documentManifest();
    unavailable = false;
    const browser = await playwright[engine].launch({
      headless: true,
      ...(engine === "chromium" && process.env.FLOW_READER_CHROMIUM_CHANNEL
        ? { channel: process.env.FLOW_READER_CHROMIUM_CHANNEL }
        : {}),
    });
    try {
      const context = await browser.newContext({ viewport: { width: 390, height: 844 } });
      const page = await context.newPage();
      const errors = [];
      page.on("pageerror", (error) => {
        errors.push(error.message);
        console.error(error);
      });
      const phase = (value) =>
        page.waitForFunction(
          (expected) => document.querySelector("#reader-activity").dataset.phase === expected,
          value,
        );
      const wake = () => page.evaluate(() => window.dispatchEvent(new Event("online")));
      const ready = async () => {
        await page.waitForSelector("#paragraph-20", { timeout: 10000 }).catch(async (error) => {
          console.error(
            await page.evaluate(() => ({
              state: document.querySelector("#reader-activity")?.outerHTML,
              body: document.querySelector("#reader-document")?.innerHTML,
              hidden: document.hidden,
            })),
            stateRequests,
            sectionRequests,
          );
          throw error;
        });
        await phase("ready");
      };
      await page.goto(`http://127.0.0.1:${server.address().port}/`);
      await ready();
      await page.evaluate(() => {
        const node = document.querySelector("#paragraph-20");
        scrollBy(0, node.getBoundingClientRect().top - 110);
        const range = document.createRange();
        range.setStart(node.firstChild, 12);
        range.setEnd(node.firstChild, 52);
        getSelection().removeAllRanges();
        getSelection().addRange(range);
        globalThis.recoveryTest = {
          node,
          text: getSelection().toString(),
          top: node.getBoundingClientRect().top,
        };
      });
      await page.waitForSelector("#reader-codex-save", { state: "visible" });
      const stable = () =>
        page.evaluate(
          () =>
            recoveryTest.node === document.querySelector("#paragraph-20") &&
            getSelection().toString() === recoveryTest.text &&
            Math.abs(recoveryTest.node.getBoundingClientRect().top - recoveryTest.top) < 2,
        );
      await context.setOffline(true);
      await phase("reconnecting");
      check("offline reader keeps the actual DOM, selection and reading position", await stable());
      await context.setOffline(false);
      await ready();
      check("online resume retains DOM, selection and reading position", await stable());

      const beforeRestart = sectionRequests;
      unavailable = true;
      await wake();
      await phase("reconnecting");
      manifest = documentManifest("r1", "book", 2);
      unavailable = false;
      await wake();
      await ready();
      check(
        "same accepted revision after process restart needs no replacement render",
        (await stable()) && sectionRequests === beforeRestart,
      );
      await page.locator("#reader-codex-save").evaluate((node) => node.click());
      await page.waitForFunction(() =>
        document.querySelector("#reader-highlight-message").textContent.includes("다시 선택"),
      );
      check(
        "preserved selection keeps its captured service identity for explicit source validation",
        savedSelection.service.startedAt === 1,
      );

      await page.evaluate(() => {
        const range = document.createRange();
        range.setStart(recoveryTest.node.firstChild, 12);
        range.setEnd(recoveryTest.node.firstChild, 52);
        getSelection().removeAllRanges();
        getSelection().addRange(range);
      });
      await page.waitForSelector("#reader-codex-save", { state: "visible" });
      manifest = documentManifest("r2", "book", 3);
      await wake();
      await phase("selection-held");
      check("a changed accepted revision waits for the selected passage", await stable());
      await page.locator("#reader-selection-cancel").evaluate((node) => node.click());
      await ready();
      check(
        "released selection publishes the new revision at the existing passage",
        await page.evaluate(
          () =>
            recoveryTest.node !== document.querySelector("#paragraph-20") &&
            Math.abs(
              document.querySelector("#paragraph-20").getBoundingClientRect().top -
                recoveryTest.top,
            ) < 2 &&
            document.querySelector("#paragraph-49").textContent.includes("r2 book"),
        ),
      );

      const beforePagehide = stateRequests;
      await page.evaluate(() =>
        window.dispatchEvent(new PageTransitionEvent("pagehide", { persisted: true })),
      );
      await page.waitForTimeout(150);
      check("bfcache suspension performs no refresh", stateRequests === beforePagehide);
      manifest = documentManifest("r3", "book", 4);
      await page.evaluate(() =>
        window.dispatchEvent(new PageTransitionEvent("pageshow", { persisted: true })),
      );
      await page.waitForFunction(() =>
        document.querySelector("#paragraph-49").textContent.includes("r3 book"),
      );
      await ready();
      check(
        "bfcache pageshow refreshes immediately and preserves location",
        await page.evaluate(
          () =>
            Math.abs(
              document.querySelector("#paragraph-20").getBoundingClientRect().top -
                recoveryTest.top,
            ) < 2,
        ),
      );

      await page.evaluate(() => {
        const node = document.querySelector("#paragraph-20");
        const range = document.createRange();
        range.selectNodeContents(node);
        getSelection().removeAllRanges();
        getSelection().addRange(range);
      });
      await page.waitForSelector("#reader-codex-save", { state: "visible" });
      manifest = documentManifest("r3", "other-book", 5);
      await wake();
      await phase("selection-held");
      await page.evaluate(() => scrollBy(0, 20));
      await page.waitForTimeout(350);
      check(
        "held old-document reading cannot save its anchor under the incoming document identity",
        await page.evaluate(
          () =>
            localStorage.getItem("flow-reader:other-book:position") === null &&
            history.state.readerDocumentID === "book",
        ),
      );
      await page.locator("#reader-selection-cancel").evaluate((node) => node.click());
      await page.waitForFunction(() =>
        document.querySelector("#paragraph-49").textContent.includes("other-book"),
      );
      await ready();
      check(
        "a different document starts at its own location",
        await page.evaluate(() => scrollY < 2),
      );
      check(
        "equal revision text cannot reuse another document's cached sections",
        await page.evaluate(() =>
          document.querySelector("#paragraph-49").textContent.includes("other-book"),
        ),
      );
      manifest = documentManifest("r4", "other-book", 6);
      await page.route("**/api/manifest?*", (route) =>
        route.fulfill({
          contentType: "application/json",
          body: JSON.stringify({ ...manifest, service: { pid: 10, startedAt: 7 } }),
        }),
      );
      await wake();
      await phase("reconnecting");
      check(
        "a manifest from a different service epoch cannot replace accepted content",
        await page.evaluate(() =>
          document.querySelector("#paragraph-49").textContent.includes("r3 other-book"),
        ),
      );
      await page.unroute("**/api/manifest?*");

      let release;
      let requested;
      const pending = new Promise((resolve) => {
        requested = resolve;
      });
      let delayed = false;
      await page.route("**/api/manifest?*", async (route) => {
        if (delayed) {
          await route.continue();
          return;
        }
        delayed = true;
        const snapshot = JSON.stringify(manifest);
        requested();
        await new Promise((resolve) => {
          release = resolve;
        });
        // The earlier request may already have been aborted by wake.
        await route.fulfill({ contentType: "application/json", body: snapshot }).catch(() => {});
      });
      await wake();
      await pending;
      manifest = documentManifest("r5", "other-book", 8);
      await wake();
      await page.waitForFunction(() =>
        document.querySelector("#paragraph-49").textContent.includes("r5 other-book"),
      );
      release();
      await page.waitForTimeout(150);
      check(
        "a late response from a superseded connection cannot repaint the newer document",
        await page.evaluate(() =>
          document.querySelector("#paragraph-49").textContent.includes("r5 other-book"),
        ),
      );
      await page.unroute("**/api/manifest?*");
      await page.evaluate(() => {
        const observer = new MutationObserver(() => {
          observer.disconnect();
          document.dispatchEvent(new WheelEvent("wheel", { bubbles: true }));
          scrollTo(0, 900);
          recoveryTest.gestureScroll = scrollY;
        });
        observer.observe(document.querySelector("#reader-document"), { childList: true });
      });
      manifest = documentManifest("r6", "other-book", 9);
      await wake();
      await page.waitForFunction(() =>
        document.querySelector("#paragraph-49").textContent.includes("r6 other-book"),
      );
      await ready();
      check(
        "a new reading gesture between mount and restore wins over the old anchor",
        await page.evaluate(() => Math.abs(scrollY - recoveryTest.gestureScroll) < 2),
      );
      assert.deepEqual(errors, []);
      console.log(`PASS ${engine} session recovery`);
      await context.close();
    } finally {
      await browser.close();
    }
  }
  console.log(`Passed ${checks} browser session recovery checks.`);
} finally {
  server.closeAllConnections();
  await new Promise((resolve, reject) =>
    server.close((error) => (error ? reject(error) : resolve())),
  );
}
