// Exercise the real Reader shell using isolated semantic sections and asset routes.
import assert from "node:assert/strict";
import { mkdir, readFile } from "node:fs/promises";
import { createServer } from "node:http";

const playwright = await import(process.env.FLOW_READER_PLAYWRIGHT_MODULE || "playwright");
const web = new URL("../web/", import.meta.url);
const assets = JSON.parse(await readFile(new URL("assets.json", web), "utf8"));
const manifest = {
  revision: "reference-fixture",
  sections: [],
  outline: [],
  anchors: {},
  blocks: {},
};
const documents = new Map();
for (let section = 0; section < 8; section++) {
  const id = `section-${section}`;
  const heading = `heading-${section}`;
  manifest.sections.push({ id });
  manifest.anchors[heading] = id;
  manifest.outline.push({ id: heading, title: `Chapter ${section}`, level: 1, section: id });
  const passages = Array.from({ length: 24 }, (_, passage) => {
    const target = `passage-${section}-${passage}`;
    manifest.anchors[target] = id;
    return `<p id="${target}">Passage ${section}.${passage}: ${"Reading a reference preserves the surrounding passage through reflow. ".repeat(8)}
      <a class="remote" href="#heading-7">Last chapter</a>
      <a class="local" href="#passage-${section}-20">Local reference</a>
      <a class="invalid" href="#missing">Missing reference</a>
      <a class="external" href="https://example.invalid/" target="_blank">External reference</a></p>`;
  }).join("");
  documents.set(
    id,
    `<html lang="en"><body><h1 id="${heading}">Chapter ${section}</h1>${passages}</body></html>`,
  );
}
const server = createServer(async (request, response) => {
  try {
    const path = new URL(request.url, "http://localhost").pathname.slice(1) || "index.html";
    let body, type;
    if (path === "api/state" || path === "api/manifest") {
      body = JSON.stringify({ ...manifest, contentGatePassed: true });
      type = "application/json";
    } else if (path.startsWith("api/sections/")) {
      body = documents.get(path.slice("api/sections/".length));
      type = "text/html";
    } else if (assets[path]) {
      body = await readFile(new URL(assets[path], web));
      type = path.endsWith(".js")
        ? "text/javascript"
        : path.endsWith(".css")
          ? "text/css"
          : "text/html";
    }
    response.writeHead(body === undefined ? 404 : 200, { "Content-Type": type || "text/plain" });
    response.end(body);
  } catch {
    response.writeHead(404).end();
  }
});
await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
const url = `http://127.0.0.1:${server.address().port}/`;
const evidence = process.env.FLOW_READER_REFERENCE_EVIDENCE;
if (evidence) await mkdir(evidence, { recursive: true });

async function verify(browser, viewport, reducedMotion) {
  const page = await browser.newPage({ viewport, reducedMotion });
  const errors = [];
  page.on("pageerror", (error) => errors.push(error.message));
  const back = page.locator("#reader-reference-back");
  const follow = (id, selector) =>
    page.locator(`#${id} ${selector}`).evaluate((node) => node.click());
  const settle = () => page.waitForTimeout(350);
  const position = async (id) => {
    await page
      .locator(`#${id}`)
      .evaluate((node) => scrollBy(0, node.getBoundingClientRect().top - 55));
    await settle();
    return page.locator(`#${id}`).evaluate((node) => node.getBoundingClientRect().top);
  };
  const returned = async (id, top, href) => {
    await back.click();
    await back.waitFor({ state: "hidden" });
    await settle();
    const actual = await page
      .locator(`#${id}`)
      .evaluate((node) => node.getBoundingClientRect().top);
    assert.ok(Math.abs(actual - top) <= 3, JSON.stringify({ id, top, actual }));
    assert.equal(page.url(), href);
    assert.equal(
      await page.locator("#reader-document").evaluate((node) => node === document.activeElement),
      true,
    );
  };
  try {
    await page.goto(`${url}#heading-0`);
    await page.locator("#passage-0-4").waitFor();
    await settle();
    assert.equal(await back.isHidden(), true);
    const href = page.url();
    const top = await position("passage-0-4");
    await follow("passage-0-4", ".invalid");
    assert.equal(await back.isHidden(), true);
    await page
      .locator("#passage-0-4 .external")
      .evaluate((node) =>
        node.addEventListener("click", (event) => event.preventDefault(), { once: true }),
      );
    await follow("passage-0-4", ".external");
    assert.equal(await back.isHidden(), true);

    // Local and remote links both remember the viewport before activation.
    await follow("passage-0-4", ".local");
    await back.waitFor({ state: "visible" });
    const mountedOrigin = await page.locator("#passage-0-4").elementHandle();
    await returned("passage-0-4", top, href);
    assert.equal(
      await mountedOrigin.evaluate((node) => node.isConnected),
      true,
      "a local return retains the mounted section and its composed mathematics",
    );
    await mountedOrigin.dispose();
    await follow("passage-0-4", ".remote");
    await page.locator("#heading-7").waitFor();
    await back.waitFor({ state: "visible" });
    assert.equal(await page.locator("#passage-0-4").count(), 0, "origin section is unmounted");
    await page.evaluate(() => {
      for (let i = 0; i < 7; i++) document.querySelector("#reader-larger").click();
    });
    await page.setViewportSize({ width: viewport.width + 40, height: viewport.height });
    await returned("passage-0-4", top, href);

    // A later reference replaces the single destination without a stack.
    await follow("passage-0-4", ".remote");
    await back.waitFor({ state: "visible" });
    const latestURL = page.url();
    const latestTop = await position("passage-7-4");
    await follow("passage-7-4", ".local");
    await returned("passage-7-4", latestTop, latestURL);
    await page.locator("#reader-reference-back").evaluate((node) => node.click());
    assert.equal(page.url(), latestURL);

    // A failed return keeps its action and can be retried.
    await page.locator("#reader-menu").evaluate((node) => {
      node.focus({ preventScroll: true });
      node.click();
    });
    await page.locator('#reader-outline a[href$="#heading-0"]').click();
    await back.waitFor({ state: "visible" });
    // History navigation preserves the origin while evicting its cached section.
    for (let section = 1; section <= 6; section++) {
      await page.evaluate((index) => {
        history.pushState(null, "", `#heading-${index}`);
        dispatchEvent(new PopStateEvent("popstate"));
      }, section);
      await page.waitForFunction(
        (index) =>
          document.querySelector("#reader-document").getAttribute("aria-busy") === "false" &&
          document.getElementById(`heading-${index}`)?.getBoundingClientRect().top < 130,
        section,
      );
    }
    await page.route("**/api/sections/section-7?*", (route) =>
      route.fulfill({ status: 503, body: "offline" }),
    );
    const failure = page.waitForResponse((response) => response.status() === 503);
    await back.click();
    await failure;
    await page.waitForFunction(
      () => document.querySelector("#reader-document").getAttribute("aria-busy") === "false",
    );
    await settle();
    assert.equal(await back.isVisible(), true);
    await page.unroute("**/api/sections/section-7?*");
    await returned("passage-7-4", latestTop, latestURL);

    // A local link supersedes a remote request and owns the latest origin.
    let pendingRoute;
    await page.route("**/api/sections/section-0?*", (route) => {
      pendingRoute = route;
    });
    await page.locator("#reader-menu").evaluate((node) => {
      node.focus({ preventScroll: true });
      node.click();
    });
    await page.locator('#reader-outline a[href$="#heading-0"]').click();
    const deadline = Date.now() + 5000;
    while (!pendingRoute) {
      assert.ok(Date.now() < deadline, "remote request reaches the section loader");
      await page.waitForTimeout(10);
    }
    const interruptedTop = await position("passage-7-4");
    await follow("passage-7-4", ".local");
    await pendingRoute.fulfill({
      status: 200,
      contentType: "text/html",
      body: documents.get("section-0"),
    });
    await page.unroute("**/api/sections/section-0?*");
    await settle();
    assert.equal(await page.locator("#heading-0").count(), 0);
    await returned("passage-7-4", interruptedTop, latestURL);

    // Deferred visual changes do not replace a reference origin or overlap it.
    await follow("passage-7-4", ".local");
    await page.setViewportSize(viewport);
    await page.evaluate(() => (document.querySelector("#reader-change-jump").hidden = false));
    const bounds = await page.locator("#reader-navigation-actions").evaluate((node) => {
      const [a, b] = [...node.children].map((child) => child.getBoundingClientRect());
      return {
        overlap: a.left < b.right && a.right > b.left && a.top < b.bottom && a.bottom > b.top,
        fits: [a, b].every((r) => r.left >= 0 && r.right <= innerWidth && r.bottom <= innerHeight),
      };
    });
    assert.deepEqual(bounds, { overlap: false, fits: true });
    if (evidence && viewport.width === 320 && reducedMotion === "no-preference")
      await page.screenshot({ path: `${evidence}/${browser.browserType().name()}-320.png` });
    assert.deepEqual(errors, []);
    console.log(`PASS reference return ${viewport.width}px, ${reducedMotion}`);
  } finally {
    await page.close();
  }
}
try {
  for (const engine of ["chromium", "webkit"]) {
    const browser = await playwright[engine].launch({
      headless: true,
      ...(engine === "chromium"
        ? { channel: process.env.FLOW_READER_CHROMIUM_CHANNEL || "chrome" }
        : {}),
    });
    try {
      for (const width of [320, 390])
        for (const motion of ["no-preference", "reduce"])
          await verify(browser, { width, height: 740 }, motion);
    } finally {
      await browser.close();
    }
  }
} finally {
  server.closeAllConnections();
  await new Promise((resolve) => server.close(resolve));
}
