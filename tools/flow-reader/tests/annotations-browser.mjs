// Run against serve.py with fixtures/adaptive-annotations.typ as its entrypoint.
// PLAYWRIGHT_MODULE may name the desktop's bundled Playwright index.mjs.
import assert from "node:assert/strict";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { resolve } from "node:path";
const { chromium } = await import(process.env.PLAYWRIGHT_MODULE || "playwright");

const address = process.argv[2];
if (!address) throw new Error("Provide the disposable annotation fixture URL");
const output = process.argv[3] || "dist/reader-adaptive-annotations";
await mkdir(output, { recursive: true });
const browser = await chromium.launch({
  ...(process.env.CHROME_BIN ? { executablePath: process.env.CHROME_BIN } : {}),
  headless: true,
});
const checks = [];
const errors = [];
const check = (name, condition) => {
  assert.ok(condition, name);
  checks.push(name);
};
try {
  const page = await browser.newPage({ viewport: { width: 390, height: 844 } });
  page.on("pageerror", (error) => errors.push(String(error)));
  await page.goto(address);
  await page.waitForFunction(() => document.querySelector('.flow-note[data-note-mode="label"]'));
  await page.waitForFunction(() =>
    document.querySelector('.flow-equation .flow-math-view[data-math-state="ready"]'),
  );
  const ids = await page.locator('.flow-note[data-note-kind="text"]').evaluateAll(async (nodes) => {
    const { logicalTextIndex } = await import("/math-identity.js");
    return nodes.map((node) => ({
      id: node.id,
      text: logicalTextIndex(node.querySelector(".flow-note-body"), {
        includeNotes: true,
        includeNested: true,
      }).text,
    }));
  });
  const kernel = page.locator(`#${ids.find((note) => note.text === "kernel").id}`);
  const longID = ids.find((note) => note.text.startsWith("The two terms")).id;
  const long = page.locator(`#${longID}`);
  const target = page
    .locator(`[data-reader-note~="${longID}"][data-note-interactive="true"]`)
    .first();
  check(
    "Compiled native braces, brackets and authored notes retain seven complete bodies",
    ids.length === 7,
  );
  check(
    "Short names appear as labels on a phone",
    (await kernel.getAttribute("data-note-mode")) === "label",
  );
  check("Long annotations start closed", !(await long.isVisible()));
  check(
    "No target equation is cloned into a note",
    (await page.locator(".flow-note-targets").count()) === 0,
  );

  await target.focus();
  await target.press("Enter");
  await long.waitFor({ state: "visible" });
  check(
    "Keyboard activation opens the original rich note",
    (await long.locator("strong").textContent()) === "original emphasis",
  );
  await page.waitForFunction(
    (id) => document.querySelector(`#${id} .flow-math-view`)?.dataset.mathState === "ready",
    longID,
  );
  await page.screenshot({ path: `${output}/popover-phone.png` });
  await page.keyboard.press("Escape");
  await long.waitFor({ state: "hidden" });
  check(
    "Escape returns focus to the annotated term",
    await target.evaluate((node) => node === document.activeElement),
  );
  await target.press("Space");
  await long.waitFor({ state: "visible" });
  await long.locator(".flow-note-close").click();
  await long.waitFor({ state: "hidden" });
  await target.click();
  await long.waitFor({ state: "visible" });
  const contained = await long.evaluate((node) => {
    const r = node.getBoundingClientRect();
    return (
      r.left >= 11 && r.right <= innerWidth - 11 && r.top >= 55 && r.bottom <= innerHeight - 11
    );
  });
  check("An open popover fits inside the phone viewport", contained);
  await page.locator(".reader-toolbar").click({ position: { x: 190, y: 20 } });
  await long.waitFor({ state: "hidden" });
  check("Outside activation dismisses the popover", true);

  await target.evaluate((node) => {
    const range = document.createRange();
    range.selectNodeContents(node);
    getSelection().removeAllRanges();
    getSelection().addRange(range);
    node.dispatchEvent(new MouseEvent("click", { bubbles: true }));
  });
  check("Selecting a marked expression does not open its note", !(await long.isVisible()));
  await page.evaluate(() => getSelection().removeAllRanges());
  await kernel.locator(".flow-note-body").evaluate((node) => {
    node.dataset.originalBody = "true";
  });

  await page.setViewportSize({ width: 1280, height: 800 });
  await page.waitForFunction(
    () => document.querySelector("#reader-document").dataset.annotationLayout === "side",
  );
  await page.waitForFunction(() =>
    [...document.querySelectorAll(".flow-note")].every((n) => n.dataset.noteMode === "side"),
  );
  check(
    "Wide landscape screens show every original note in the side column",
    await long.isVisible(),
  );
  check(
    "Presentation changes reuse the original body node",
    (await kernel.locator(".flow-note-body").getAttribute("data-original-body")) === "true",
  );
  const rail = await page
    .locator('.flow-note[data-note-mode="side"]')
    .evaluateAll((notes) => notes.map((n) => n.getBoundingClientRect().toJSON()));
  check(
    "Side notes stack without overlapping each other",
    rail.every((r, i) => !i || r.top >= rail[i - 1].bottom),
  );
  check(
    "Side notes do not introduce horizontal page movement",
    await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1),
  );
  await page.evaluate(() => scrollTo(0, 0));
  await page.screenshot({ path: `${output}/side-landscape.png` });

  await page.setViewportSize({ width: 1024, height: 1366 });
  await page.waitForFunction(
    () => document.querySelector("#reader-document").dataset.annotationLayout === "compact",
  );
  check("Portrait proportions disable the side column even on a wide tablet", true);
  for (const width of [320, 390, 768]) {
    await page.setViewportSize({ width, height: 844 });
    for (const font of [18, 30]) {
      await page.evaluate((font) => {
        while (Number(document.querySelector("#reader-size").value) !== font)
          document
            .querySelector(
              Number(document.querySelector("#reader-size").value) < font
                ? "#reader-larger"
                : "#reader-smaller",
            )
            .click();
      }, font);
      await page.locator(".flow-equation").first().scrollIntoViewIfNeeded();
      await page.waitForFunction(
        () =>
          document.querySelector(".flow-equation .flow-math-view").dataset.mathState === "ready",
      );
      const retained = await page.evaluate(async () => {
        const { logicalTextIndex } = await import("/math-identity.js");
        const source = new DOMParser().parseFromString(
          await (await fetch("/document.html")).text(),
          "text/html",
        );
        return (
          logicalTextIndex(source.querySelector(".flow-equation math")).text ===
          logicalTextIndex(document.querySelector(".flow-equation .flow-math-view")).text
        );
      });
      check(
        `${width}px/${font}px retains canonical mathematical text and a bounded page`,
        retained &&
          (await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1)),
      );
      await page.evaluate(
        () => new Promise((done) => requestAnimationFrame(() => requestAnimationFrame(done))),
      );
      const clearLabels = await page.evaluate(() => {
        const labels = [...document.querySelectorAll('.flow-note[data-note-mode="label"]')].map(
          (n) => n.getBoundingClientRect(),
        );
        const ink = [
          ...document.querySelectorAll(
            ".flow-equation mjx-c,.flow-equation mjx-utext,.flow-equation mjx-stretchy-h,.flow-equation mjx-stretchy-v",
          ),
        ]
          .filter((n) => !n.closest("mjx-assistive-mml,.flow-math-stage"))
          .map((n) => n.getBoundingClientRect());
        return labels.every((a) =>
          ink.every(
            (b) => a.right <= b.left || a.left >= b.right || a.bottom <= b.top || a.top >= b.bottom,
          ),
        );
      });
      check(`${width}px/${font}px labels never obscure mathematical ink`, clearLabels);
    }
  }
  await page.setViewportSize({ width: 1280, height: 800 });
  await page.waitForFunction(
    () => document.querySelector("#reader-document").dataset.annotationLayout === "compact",
  );
  check("A large reading font keeps notes compact when the real side space is insufficient", true);
  await page.reload();
  await page.waitForFunction(() => document.querySelector(".flow-note[data-note-mode]"));
  check("Reload restores working note presentation", true);
  if (process.argv[4]) {
    const source = resolve(process.argv[4]);
    assert.ok(source.startsWith(resolve("dist/reader-adaptive-annotations") + "/"));
    const original = await readFile(source, "utf8");
    await page.setViewportSize({ width: 390, height: 844 });
    await page.waitForFunction(() => document.querySelector('[data-note-interactive="true"]'));
    await target.click();
    await long.waitFor({ state: "visible" });
    await long.evaluate((node) => {
      node.dataset.retainedNote = "true";
    });
    const before = await page.evaluate(
      async () => (await (await fetch("/api/state")).json()).revision,
    );
    try {
      await writeFile(source, original + "\nA newly saved trailing paragraph.\n");
      await page.waitForFunction(async (revision) => {
        const state = await (await fetch("/api/state")).json();
        return !state.compiling && state.revision !== revision;
      }, before);
      check(
        "A real accepted source edit leaves the open original note intact",
        (await long.getAttribute("data-retained-note")) === "true" && (await long.isVisible()),
      );
      await long.locator(".flow-note-close").click();
      await page.waitForFunction(() =>
        document
          .querySelector("#reader-document")
          .textContent.includes("A newly saved trailing paragraph."),
      );
      check(
        "Closing the note publishes the pending source revision",
        (await page.locator('[data-retained-note="true"]').count()) === 0,
      );
    } finally {
      await writeFile(source, original);
    }
  }
  await page.addInitScript(() => {
    HTMLElement.prototype.showPopover = undefined;
    HTMLElement.prototype.hidePopover = undefined;
  });
  await page.setViewportSize({ width: 390, height: 844 });
  await page.reload();
  await page.waitForFunction(() => document.querySelector('[data-note-interactive="true"]'));
  await target.click();
  await long.waitFor({ state: "visible" });
  check("An older browser without native popovers still opens the authored note", true);
  await page.keyboard.press("Escape");
  await long.waitFor({ state: "hidden" });
  check("The fallback also supports Escape dismissal", true);
  const touch = await browser.newPage({
    viewport: { width: 390, height: 844 },
    isMobile: true,
    hasTouch: true,
  });
  touch.on("pageerror", (error) => errors.push(String(error)));
  await touch.goto(address);
  const touchTarget = touch
    .locator(`[data-reader-note~="${longID}"][data-note-interactive="true"]`)
    .first();
  await touchTarget.waitFor();
  await touchTarget.tap();
  await touch.locator(`#${longID}`).waitFor({ state: "visible" });
  check("A touch tap opens the longer note", true);
  await touch.evaluate(() => {
    document.documentElement.dataset.theme = "dark";
  });
  await touch.screenshot({ path: `${output}/popover-touch-dark.png` });
  await touch.locator(`#${longID} .flow-note-close`).tap();
  await touch.locator(`#${longID}`).waitFor({ state: "hidden" });
  check("Touch dismissal also works in dark appearance", true);
  await touch.close();
  check("Browser reports no JavaScript failures", errors.length === 0);
  await writeFile(`${output}/browser-report.json`, JSON.stringify({ checks, errors }, null, 2));
  console.log(JSON.stringify({ checks: checks.length, errors }));
} finally {
  await browser.close();
}
