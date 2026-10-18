// Run with FLOW_READER_PLAYWRIGHT_MODULE pointing to an installed Playwright.
// A disposable API fixture exercises the real Reader shell and section loader.
import assert from "node:assert/strict";
import { createServer } from "node:http";
import { readFile } from "node:fs/promises";

const { webkit, chromium } = await import(
  process.env.FLOW_READER_PLAYWRIGHT_MODULE || "playwright"
);
const web = new URL("../web/", import.meta.url);
const manifest = {
  revision: "outline-fixture",
  language: "en",
  sections: [],
  outline: [],
  anchors: {},
  blocks: {},
};
const documents = new Map();
for (let chapter = 0; chapter < 36; chapter++) {
  for (let part = 0; part < 4; part++) {
    const section = `section-${manifest.sections.length}`;
    const heading = `heading-${chapter}`;
    const passage = `passage-${chapter}-${part}`;
    const title = `Chapter ${chapter}: A long outline retains the current reading location`;
    manifest.sections.push({ id: section, title });
    let body = "";
    if (part === 0) {
      const level = chapter % 3 === 0 ? 2 : chapter % 3 === 1 ? 3 : 7;
      body +=
        level === 7
          ? `<div role="heading" aria-level="7" id="${heading}">${title}</div>`
          : `<h${level} id="${heading}">${title}</h${level}>`;
      manifest.outline.push({ id: heading, section, title, level });
      manifest.anchors[heading] = section;
    }
    manifest.anchors[passage] = section;
    body += `<p id="${passage}" style="min-height:2000px">Body passage ${chapter}.${part}.</p>`;
    if (chapter === 20 && part === 0) {
      const id = "inner-heading-20";
      manifest.outline.push({
        id,
        section,
        title: "A subsection in the same transport section",
        level: 8,
      });
      manifest.anchors[id] = section;
      body += `<div role="heading" aria-level="8" id="${id}">A subsection</div><p style="min-height:2000px">Subsection body.</p>`;
    }
    documents.set(section, `<!doctype html><html lang="en"><body>${body}</body></html>`);
  }
}
const server = createServer(async (request, response) => {
  try {
    const path = new URL(request.url, "http://fixture.test").pathname;
    let body;
    let type = "application/json";
    if (path === "/api/state") {
      body = JSON.stringify({ revision: manifest.revision, contentGatePassed: true });
    } else if (path === "/api/manifest") body = JSON.stringify(manifest);
    else if (path.startsWith("/api/sections/")) {
      body = documents.get(path.slice("/api/sections/".length));
      type = "text/html";
    } else {
      const file = new URL(path === "/" ? "index.html" : path.slice(1), web);
      if (!file.href.startsWith(web.href)) throw new Error("Outside fixture assets");
      body = await readFile(file);
      type = path.endsWith(".js")
        ? "text/javascript"
        : path.endsWith(".css")
          ? "text/css"
          : "text/html";
    }
    response.writeHead(body === undefined ? 404 : 200, { "Content-Type": type });
    response.end(body);
  } catch {
    response.writeHead(404).end();
  }
});
await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
const url = `http://127.0.0.1:${server.address().port}/`;
let checks = 0;
async function verify(browser, viewport, reducedMotion) {
  const page = await browser.newPage({ viewport, reducedMotion });
  const errors = [];
  page.on("pageerror", (error) => errors.push(error.message));
  const ready = async (target) => {
    await page.goto(`${url}?visit=${checks}#${target}`);
    await page.waitForFunction(
      (id) =>
        document.querySelector("#reader-document").getAttribute("aria-busy") === "false" &&
        document.getElementById(id)?.getBoundingClientRect().top < 130,
      target,
    );
    await page.waitForTimeout(250);
  };
  const open = async (heading, swipe = false) => {
    const before = await page.evaluate(() => scrollY);
    // Avoid Playwright scrolling the sticky toolbar before dispatching a click.
    if (!swipe) {
      await page.locator("#reader-menu").evaluate((node) => {
        node.focus({ preventScroll: true });
        node.click();
      });
    } else {
      await page.locator("#reader-document").evaluate((node) => {
        let time = 0;
        const touch = (x) => ({ identifier: 1, target: node, clientX: x, clientY: 300 });
        const start = touch(48),
          end = touch(innerWidth - 40);
        for (const [name, touches, changed] of [
          ["touchstart", [start], [start]],
          ["touchmove", [end], [end]],
          ["touchend", [], [end]],
        ]) {
          const event = new Event(name, { bubbles: true, cancelable: true });
          Object.defineProperties(event, {
            touches: { value: touches },
            changedTouches: { value: changed },
            timeStamp: { value: (time += 30) },
          });
          node.dispatchEvent(event);
        }
      });
    }
    const result = await page.evaluate(() => {
      const outline = document.querySelector("#reader-outline");
      const links = outline.querySelectorAll('[aria-current="location"]');
      const current = links[0];
      const list = outline.getBoundingClientRect();
      const item = current?.getBoundingClientRect();
      return {
        current: current?.hash,
        count: links.length,
        focused: current === document.activeElement,
        visible: item && item.top >= list.top - 1 && item.bottom <= list.bottom + 1,
        centerDistance: item && Math.abs((item.top + item.bottom - list.top - list.bottom) / 2),
        scrollY,
      };
    });
    assert.equal(result.current, `#${heading}`, JSON.stringify(result));
    assert.equal(result.count, 1);
    assert.ok(result.visible, JSON.stringify(result));
    assert.ok(result.centerDistance < 2, JSON.stringify(result));
    assert.ok(result.focused, JSON.stringify(result));
    assert.ok(Math.abs(result.scrollY - before) < 1, JSON.stringify({ before, ...result }));
    checks++;
  };
  try {
    // Direct entry leaves the earlier heading outside the mounted reading window.
    await ready("passage-24-3");
    assert.equal(await page.locator("#reader-document #heading-24").count(), 0);
    await open("heading-24");
    // Reopening discards a previous manual outline scroll, in both directions.
    for (const top of [0, 100000]) {
      await page.evaluate(
        (value) => (document.querySelector("#reader-outline").scrollTop = value),
        top,
      );
      await page.keyboard.press("Escape");
      await open("heading-24");
    }
    await page.keyboard.press("Escape");
    assert.ok(
      await page.locator("#reader-menu").evaluate((node) => node === document.activeElement),
    );
    await open("heading-24", true);
    await page.keyboard.press("Escape");

    // A mounted following heading must not claim the preceding continuation.
    await ready("passage-24-3");
    await page.evaluate(() => window.scrollBy(0, 1100));
    await page.locator("#heading-25").waitFor({ state: "attached" });
    await open("heading-24");
    await page.keyboard.press("Escape");
    await page.evaluate(() => document.getElementById("heading-25").scrollIntoView());
    await open("heading-25");
    await page.keyboard.press("Enter");
    await page.locator("#reader-navigation").waitFor({ state: "hidden" });
    assert.ok(
      await page.locator("#reader-document").evaluate((node) => node === document.activeElement),
    );
    checks++;

    // Native and deeper ARIA headings share the same location behavior.
    for (const chapter of [8, 21]) {
      await ready(`heading-${chapter}`);
      await open(`heading-${chapter}`);
      await page.keyboard.press("Escape");
    }
    await ready("heading-20");
    await page.evaluate(() => {
      window.scrollBy(
        0,
        document.getElementById("inner-heading-20").getBoundingClientRect().top - 500,
      );
    });
    await open("heading-20");
    await page.keyboard.press("Escape");
    await page.evaluate(() => document.getElementById("inner-heading-20").scrollIntoView());
    await open("inner-heading-20");
    await page.keyboard.press("Escape");
    assert.deepEqual(errors, []);
    console.log(`PASS ${viewport.width}×${viewport.height}, ${reducedMotion}`);
  } finally {
    await page.close();
  }
}
try {
  for (const engine of [webkit, chromium]) {
    const browser = await engine.launch({
      headless: true,
      ...(engine === chromium ? { channel: "chrome" } : {}),
    });
    try {
      for (const viewport of [
        { width: 390, height: 844 },
        { width: 320, height: 740 },
        { width: 768, height: 360 },
      ]) {
        for (const motion of ["no-preference", "reduce"]) await verify(browser, viewport, motion);
      }
    } finally {
      await browser.close();
    }
  }
  console.log(`Passed ${checks} outline location checks.`);
} finally {
  server.closeAllConnections();
  await new Promise((resolve) => server.close(resolve));
}
