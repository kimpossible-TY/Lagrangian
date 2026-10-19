// Run against the compiled fixtures/side-footnotes.typ Reader.
import assert from "node:assert/strict";
import { mkdir, writeFile } from "node:fs/promises";
const engines = await import(process.env.PLAYWRIGHT_MODULE || "playwright");
const engine = process.env.BROWSER_ENGINE || "chromium";
const origin = process.argv[2];
const output = process.argv[3] || "dist/reader-footnotes";
await mkdir(output, { recursive: true });
const browser = await engines[engine].launch({
  headless: true,
  ...(engine === "chromium" && process.env.CHROME_BIN
    ? { executablePath: process.env.CHROME_BIN }
    : {}),
});
const checks = [],
  errors = [];
const check = (name, condition) => {
  assert.ok(condition, name);
  checks.push(name);
};
const settle = (page) =>
  page.evaluate(
    () =>
      new Promise((done) => {
        let count = 6;
        const frame = () => (--count ? requestAnimationFrame(frame) : done());
        requestAnimationFrame(frame);
      }),
  );
try {
  const page = await browser.newPage({ viewport: { width: 1280, height: 960 } });
  page.on("pageerror", (error) => errors.push(String(error)));
  const requests = [];
  page.on("request", (request) => requests.push(request.url()));
  await page.goto(origin);
  await page.waitForFunction(
    () =>
      document.querySelectorAll('[data-note-kind="footnote"][data-note-mode="side"]').length === 4,
  );
  await settle(page);
  check(
    "Footnotes load beside references while their endnote section stays unmounted",
    (await page.locator('[role="doc-endnotes"]').count()) === 0,
  );
  check(
    "Two same-host references share one local projection",
    await page.evaluate(() => {
      const paragraph = [...document.querySelectorAll("p")].find((node) =>
        node.textContent.startsWith("Two references"),
      );
      const refs = [...paragraph.querySelectorAll("[data-reader-note]")];
      return refs.length === 2 && refs[0].dataset.readerNote === refs[1].dataset.readerNote;
    }),
  );
  const target = await page
    .locator('[data-note-kind="footnote"]')
    .first()
    .getAttribute("data-footnote-target");
  const manifest = await (await page.request.get(new URL("api/manifest", origin).href)).json();
  const footSection = manifest.anchors[target];
  check(
    "Concurrent note loads share one revision-bound endnote section request",
    requests.filter((url) => url.includes(`/api/sections/${footSection}?`)).length === 1,
  );
  const source = await (await page.request.get(new URL("document.html", origin).href)).text();
  check(
    "Projected bodies match canonical source content and preserve language",
    await page.evaluate(
      async ({ source }) => {
        const { logicalTextIndex } = await import("/math-identity.js");
        const parsed = new DOMParser().parseFromString(source, "text/html");
        return [...document.querySelectorAll('[data-note-kind="footnote"]')].every((note) => {
          const original = parsed.getElementById(note.dataset.footnoteTarget);
          original.querySelectorAll('[role="doc-backlink"]').forEach((node) => node.remove());
          return (
            logicalTextIndex(original, { includeNested: true }).text ===
              logicalTextIndex(note.querySelector(".flow-note-body"), {
                includeNested: true,
                includeNotes: true,
              }).text && note.lang === "en"
          );
        });
      },
      { source },
    ),
  );
  for (const font of [13, 18]) {
    await page.evaluate((font) => {
      while (+document.querySelector("#reader-size").value !== font)
        document
          .querySelector(
            +document.querySelector("#reader-size").value < font
              ? "#reader-larger"
              : "#reader-smaller",
          )
          .click();
    }, font);
    await settle(page);
    check(
      `${font}px footnotes stay in local rows with visible connected dividers`,
      await page.evaluate(() =>
        [...document.querySelectorAll('[data-note-kind="footnote"]')].every((note) => {
          const path = document.querySelector(`path[data-note="${note.id}"]`);
          if (!path) return false;
          const h = path.parentElement.getBoundingClientRect(),
            r = note.getBoundingClientRect();
          return (
            r.top >= h.top &&
            r.bottom <= h.bottom + 1 &&
            r.right <= h.right + 1 &&
            getComputedStyle(path).fill === "none"
          );
        }),
      ),
    );
    check(
      `${font}px ordinary paragraphs retain the full available width`,
      await page.evaluate(() =>
        [...document.querySelectorAll("p")]
          .filter((n) => n.textContent.startsWith("Ordinary paragraph"))
          .every((n) => getComputedStyle(n).paddingRight === "0px" && !n.style.minHeight),
      ),
    );
  }
  const link = page.locator(`[role="doc-noteref"] a[href="#${target}"]`).first();
  await link.click();
  check(
    "Activating a reference focuses the adjacent body without mounting endnotes",
    await page.evaluate(
      () =>
        document.activeElement.dataset.noteKind === "footnote" &&
        !document.querySelector('[role="doc-endnotes"]'),
    ),
  );
  await page.screenshot({ path: `${output}/landscape.png` });
  await page.setViewportSize({ width: 1024, height: 1366 });
  await page.waitForFunction(() => !document.querySelector(".flow-side-lines"));
  check(
    "Portrait releases gutters and all generated footnotes",
    await page.evaluate(
      () =>
        !document.querySelector(".flow-annotation-side") &&
        [...document.querySelectorAll('[data-note-kind="footnote"]')].every((n) => n.hidden),
    ),
  );
  await link.click();
  await page.waitForFunction((target) => {
    const note = document.getElementById(target);
    return note && note.getBoundingClientRect().top < innerHeight;
  }, target);
  check(
    "Compact reference navigation reaches the original body and backlink",
    await page.evaluate((target) => {
      const note = document.getElementById(target);
      return (
        !!note.querySelector('[role="doc-backlink"] a') &&
        note.getBoundingClientRect().top < innerHeight
      );
    }, target),
  );
  await page.locator(`[id="${target}"] [role="doc-backlink"] a`).click();
  await page.waitForFunction(() => !!document.querySelector('[role="doc-noteref"]'));
  check(
    "Original backlinks return to the referring passage",
    (await page.locator('[role="doc-noteref"]').count()) > 0,
  );

  // Hold a remote body while the reader replaces its source section.
  const delayed = await browser.newPage({ viewport: { width: 1280, height: 960 } });
  delayed.on("pageerror", (error) => errors.push(String(error)));
  let release;
  const blocked = new Promise((resolve) => {
    release = resolve;
  });
  let requested;
  const pending = new Promise((resolve) => {
    requested = resolve;
  });
  await delayed.route(`**/api/sections/${footSection}?*`, async (route) => {
    requested();
    await blocked;
    await route.continue();
  });
  await delayed.goto(origin);
  await pending;
  await delayed.evaluate(() => {
    window.pendingFootnoteNodes = [...document.querySelectorAll('[data-note-kind="footnote"]')];
  });
  check(
    "Pending remote bodies leave the original reference usable",
    (await delayed.locator('[role="doc-noteref"] a').count()) > 0,
  );
  // History restoration remounts the same IDs while the old body is pending.
  await delayed.evaluate(() =>
    window.dispatchEvent(
      new PopStateEvent("popstate", {
        state: { readerAnchor: { section: "section-0" } },
      }),
    ),
  );
  await delayed.waitForFunction(() =>
    window.pendingFootnoteNodes.every((node) => !node.isConnected),
  );
  release();
  await delayed.waitForFunction(
    () =>
      document.querySelectorAll('[data-note-kind="footnote"][data-note-mode="side"]').length === 4,
  );
  await settle(delayed);
  check(
    "A late body cannot recreate a projection in its replacement section",
    await delayed.evaluate(() =>
      window.pendingFootnoteNodes.every(
        (node) => !node.isConnected && !node.querySelector(".flow-note-body").textContent,
      ),
    ),
  );
  check(
    "No duplicate document IDs after navigation",
    await delayed.evaluate(() => {
      const ids = [...document.querySelectorAll("[id]")].map((n) => n.id);
      return ids.length === new Set(ids).size;
    }),
  );
  await delayed.close();

  const failed = await browser.newPage({ viewport: { width: 1280, height: 960 } });
  failed.on("pageerror", (error) => errors.push(String(error)));
  await failed.route(`**/api/sections/${footSection}?*`, (route) => route.abort());
  await failed.goto(origin);
  await failed.waitForFunction(() => !!document.querySelector('[role="doc-noteref"] a'));
  await settle(failed);
  check(
    "Failed remote loads preserve the numbered link and reserve no empty column",
    await failed.evaluate(
      () =>
        !document.querySelector(".flow-annotation-side") &&
        !!document.querySelector('[role="doc-noteref"] a[href^="#"]'),
    ),
  );
  await failed.unroute(`**/api/sections/${footSection}?*`);
  await failed.locator(`[role="doc-noteref"] a[href="#${target}"]`).first().click();
  await failed.waitForFunction((target) => !!document.getElementById(target), target);
  check("A reference still reaches its original note after a failed projection load", true);
  check("No JavaScript exceptions", errors.length === 0);
  await writeFile(`${output}/report.json`, JSON.stringify({ engine, checks, errors }, null, 2));
  console.log(JSON.stringify({ engine, checks: checks.length, errors }));
} finally {
  await browser.close();
}
