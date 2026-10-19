// Run against serve.py with fixtures/adaptive-annotations.typ as its entrypoint.
// PLAYWRIGHT_MODULE may name the desktop's bundled Playwright index.mjs.
import assert from "node:assert/strict";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { resolve } from "node:path";
const engines = await import(process.env.PLAYWRIGHT_MODULE || "playwright");
const engine = process.env.BROWSER_ENGINE || "chromium";

const address = process.argv[2];
if (!address) throw new Error("Provide the disposable annotation fixture URL");
const entry = new URL(address);
entry.searchParams.set("section", "section-0");
const output = process.argv[3] || "dist/reader-adaptive-annotations";
await mkdir(output, { recursive: true });
const browser = await engines[engine].launch({
  ...(engine === "chromium" && process.env.CHROME_BIN
    ? { executablePath: process.env.CHROME_BIN }
    : {}),
  headless: true,
});
const checks = [];
const errors = [];
const check = (name, condition) => {
  assert.ok(condition, name);
  checks.push(name);
};
const containedClose = (button) => {
  const r = button.getBoundingClientRect();
  const p = button.closest(".flow-note").getBoundingClientRect();
  const style = getComputedStyle(button);
  const outset = Math.max(0, parseFloat(style.outlineOffset) + parseFloat(style.outlineWidth));
  return (
    r.width >= 44 &&
    r.height >= 44 &&
    r.left - outset >= p.left + 4 &&
    r.right + outset <= p.right - 4 &&
    r.top - outset >= p.top + 4 &&
    r.bottom + outset <= p.bottom - 4
  );
};
try {
  const page = await browser.newPage({ viewport: { width: 390, height: 844 } });
  page.on("pageerror", (error) => errors.push(String(error)));
  await page.goto(entry.href);
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
  await page.waitForFunction(
    (id) => document.getElementById(id)?.dataset.noteMode === "label",
    ids.find((note) => note.text === "kernel").id,
  );
  const longID = ids.find((note) => note.text.startsWith("The two terms")).id;
  const collisionID = ids.find((note) => note.text === "denominator").id;
  const deltaID = ids.find((note) => note.text.normalize("NFKC") === "δji").id;
  const delta = page.locator(`#${deltaID}`);
  const collision = page.locator(`#${collisionID}`);
  const long = page.locator(`#${longID}`);
  const target = page
    .locator(`[data-reader-note~="${longID}"][data-note-interactive="true"]`)
    .first();
  check(
    "Compiled native braces, brackets and authored notes retain fourteen complete bodies",
    ids.length === 14,
  );
  check(
    "Short names appear as labels on a phone",
    (await kernel.getAttribute("data-note-mode")) === "label",
  );
  check("Long annotations start closed", !(await long.isVisible()));
  await page.waitForFunction(
    (id) => document.getElementById(id)?.dataset.noteMode === "label",
    deltaID,
  );
  await delta.scrollIntoViewIfNeeded();
  await page.waitForFunction(
    (id) => document.querySelector(`#${id} .flow-math-view`)?.dataset.mathState === "ready",
    deltaID,
  );
  check("An indexed delta is a visible mathematical label", await delta.isVisible());
  check(
    "The delta label retains native subscript and superscript semantics",
    (await delta.locator("mjx-assistive-mml msubsup").count()) === 1,
  );
  check(
    "No target equation is cloned into a note",
    (await page.locator(".flow-note-targets").count()) === 0,
  );

  await page.evaluate(
    (id) =>
      [...document.querySelectorAll(`[data-reader-note~="${id}"]`)]
        .find((n) => !n.closest("mjx-assistive-mml,.flow-math-stage"))
        ?.scrollIntoView({ block: "center" }),
    collisionID,
  );
  await page.waitForFunction(
    (id) => document.getElementById(id)?.dataset.noteMode === "label",
    collisionID,
  );
  check(
    "A short denominator name uses the free space above its fraction",
    await collision.isVisible(),
  );

  const wideID = ids.find((note) => note.text.startsWith("WWWW")).id;
  await page.setViewportSize({ width: 320, height: 844 });
  const setFont = (font) =>
    page.evaluate((font) => {
      while (Number(document.querySelector("#reader-size").value) !== font)
        document
          .querySelector(
            Number(document.querySelector("#reader-size").value) < font
              ? "#reader-larger"
              : "#reader-smaller",
          )
          .click();
    }, font);
  await setFont(30);
  await page.evaluate(
    (id) =>
      [...document.querySelectorAll(`[data-reader-note~="${id}"]`)]
        .find((n) => !n.closest("mjx-assistive-mml,.flow-math-stage"))
        ?.scrollIntoView({ block: "center" }),
    wideID,
  );
  const wide = page.locator(`#${wideID}`);
  const wideTarget = page
    .locator(`[data-reader-note~="${wideID}"][data-note-interactive="true"]`)
    .first();
  await wideTarget.waitFor();
  await page.waitForFunction(
    (id) =>
      [...document.querySelectorAll(`[data-reader-note~="${id}"]`)].some(
        (n) =>
          !n.closest("mjx-assistive-mml,.flow-math-stage") &&
          n.closest(".flow-math-view")?.dataset.mathState === "ready",
      ),
    wideID,
  );
  await page.evaluate(
    () => new Promise((done) => requestAnimationFrame(() => requestAnimationFrame(done))),
  );
  check(
    "A short name physically wider than the phone retains an accessible fallback",
    (await wide.getAttribute("data-note-mode")) === "popover" && !(await wide.isVisible()),
  );
  await wideTarget.focus();
  await wideTarget.press("Enter");
  await wide.waitFor({ state: "visible" });
  const layoutPasses = () =>
    page.evaluate(
      () =>
        new Promise((done) => {
          window.dispatchEvent(new Event("resize"));
          document.dispatchEvent(new Event("selectionchange"));
          requestAnimationFrame(() => requestAnimationFrame(() => requestAnimationFrame(done)));
        }),
    );
  await layoutPasses();
  check(
    "A short fallback reserves room for its complete close control",
    await wide.locator(".flow-note-close").evaluate(containedClose),
  );
  check(
    "Remeasuring keeps the fallback open and retains focus",
    (await wide.isVisible()) &&
      (await wide.getAttribute("data-open")) === "true" &&
      (await wideTarget.getAttribute("aria-expanded")) === "true" &&
      (await wide.locator(".flow-note-close").evaluate((n) => n === document.activeElement)),
  );
  await page.keyboard.press("Escape");
  await wide.waitFor({ state: "hidden" });
  check(
    "Dismissal returns focus to the short-name target",
    await wideTarget.evaluate((n) => n === document.activeElement),
  );
  await page.setViewportSize({ width: 390, height: 844 });
  await setFont(13);

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
  check(
    "The entire close target and its focus ring fit inside the popover",
    await long.locator(".flow-note-close").evaluate(containedClose),
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
  await page.waitForFunction(() =>
    [...document.querySelectorAll('.flow-note[data-note-mode="side"]')].every((note) => {
      const target = [...document.querySelectorAll(`[data-reader-note~="${note.id}"]`)].find(
        (n) => !n.closest("mjx-assistive-mml,.flow-math-stage"),
      );
      const h = target.closest(".flow-equation,p").getBoundingClientRect();
      const r = note.getBoundingClientRect();
      return (
        r.top >= h.top &&
        r.bottom <= h.bottom + 1 &&
        r.right <= h.right + 1 &&
        r.left >=
          h.right -
            parseFloat(getComputedStyle(target.closest(".flow-equation,p")).paddingRight) +
            19
      );
    }),
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
  const localRails = await page.evaluate(() => {
    const article = document.querySelector("#reader-document");
    const style = getComputedStyle(article);
    const contentWidth =
      article.clientWidth - parseFloat(style.paddingLeft) - parseFloat(style.paddingRight);
    const ordinary = [...article.querySelectorAll("p")].find((n) =>
      n.textContent.startsWith("The minus sign"),
    );
    const notes = [...article.querySelectorAll('.flow-note[data-note-mode="side"]')];
    const groups = [...article.querySelectorAll(".flow-annotation-side")];
    return {
      contentWidth,
      ordinaryWidth: ordinary.clientWidth - parseFloat(getComputedStyle(ordinary).paddingRight),
      contained: notes.every((note) => {
        const id = note.id;
        const target = [...article.querySelectorAll(`[data-reader-note~="${id}"]`)].find(
          (n) => !n.closest("mjx-assistive-mml,.flow-math-stage"),
        );
        const host = target.closest(".flow-equation,p");
        const h = host.getBoundingClientRect(),
          r = note.getBoundingClientRect();
        const padding = parseFloat(getComputedStyle(host).paddingRight);
        return (
          host.classList.contains("flow-annotation-side") &&
          r.left >= h.right - padding + 19 &&
          r.right <= h.right + 1 &&
          r.top >= h.top &&
          r.bottom <= h.bottom + 1
        );
      }),
      untouched: [...article.querySelectorAll(".flow-equation,p")]
        .filter((n) => !groups.includes(n))
        .every(
          (n) =>
            !n.style.getPropertyValue("--flow-side-width") &&
            !n.style.getPropertyValue("--flow-side-height"),
        ),
    };
  });
  check(
    "Tablet prose uses the wider reading canvas",
    localRails.contentWidth >= 1000 &&
      Math.abs(localRails.ordinaryWidth - localRails.contentWidth) < 1,
  );
  check(
    "Side notes fit inside the width and height of their own annotated row",
    localRails.contained,
  );
  check("Unannotated passages reserve no side-note space", localRails.untouched);
  await page.evaluate(() => scrollTo(0, 0));
  await page.screenshot({ path: `${output}/side-landscape.png` });

  await page.setViewportSize({ width: 1024, height: 1366 });
  await page.waitForFunction(
    () => document.querySelector("#reader-document").dataset.annotationLayout === "compact",
  );
  check("Portrait proportions disable the side column even on a wide tablet", true);
  check(
    "Portrait restoration releases every local side reservation",
    (await page.locator(".flow-annotation-side").count()) === 0,
  );
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
      const stacked = ids.filter((note) => note.text.endsWith("identifier")).map((note) => note.id);
      await page.evaluate(
        (id) =>
          [...document.querySelectorAll(`[data-reader-note~="${id}"]`)]
            .find((n) => !n.closest("mjx-assistive-mml,.flow-math-stage"))
            ?.scrollIntoView({ block: "center" }),
        stacked[0],
      );
      await page.waitForFunction(
        (ids) => ids.every((id) => document.getElementById(id)?.dataset.noteMode === "label"),
        stacked,
      );
      const separated = await page.evaluate((ids) => {
        const boxes = ids.map((id) => document.getElementById(id).getBoundingClientRect());
        return boxes.every((a, i) =>
          boxes
            .slice(i + 1)
            .every(
              (b) =>
                a.right <= b.left || a.left >= b.right || a.bottom <= b.top || a.top >= b.bottom,
            ),
        );
      }, stacked);
      check(`${width}px/${font}px competing short names stay visible and separated`, separated);
      if (width === 320 && font === 30) {
        const padding = () =>
          page.evaluate((id) => {
            const target = [...document.querySelectorAll(`[data-reader-note~="${id}"]`)].find(
              (n) => !n.closest("mjx-assistive-mml,.flow-math-stage"),
            );
            return target
              .closest(".flow-equation")
              .style.getPropertyValue("--flow-annotation-padding");
          }, stacked[0]);
        const reserved = await padding();
        check("Crowded names reserve additional label rows", parseFloat(reserved) > font * 2.2);
        await page.evaluate(() => scrollBy(0, 20));
        await layoutPasses();
        check(
          "Scrolling reuses label rows without growing the equation",
          (await padding()) === reserved,
        );
        await page.screenshot({ path: `${output}/competing-labels.png` });
      }
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
      const proseID = ids.find((note) => note.text === "passage").id;
      await page.evaluate(
        (id) =>
          [...document.querySelectorAll(`[data-reader-note~="${id}"]`)]
            .find((n) => !n.closest("mjx-assistive-mml,.flow-math-stage"))
            ?.scrollIntoView({ block: "center" }),
        proseID,
      );
      await page.waitForFunction(
        (id) => document.getElementById(id)?.dataset.noteMode === "label",
        proseID,
      );
      const clearProse = await page.evaluate((id) => {
        const label = document.getElementById(id).getBoundingClientRect();
        const target = [...document.querySelectorAll(`[data-reader-note~="${id}"]`)].find(
          (n) => !n.closest("mjx-assistive-mml,.flow-math-stage"),
        );
        const text = document.createTreeWalker(target.closest("p"), NodeFilter.SHOW_TEXT);
        for (let node = text.nextNode(); node; node = text.nextNode()) {
          if (!node.data.trim()) continue;
          const range = document.createRange();
          range.selectNodeContents(node);
          if (
            [...range.getClientRects()].some(
              (r) =>
                label.left < r.right &&
                label.right > r.left &&
                label.top < r.bottom &&
                label.bottom > r.top,
            )
          )
            return false;
        }
        return true;
      }, proseID);
      check(`${width}px/${font}px inline labels avoid surrounding prose`, clearProse);
      await target.click();
      await long.waitFor({ state: "visible" });
      check(
        `${width}px/${font}px keeps the close target and focus ring inside the popover`,
        await long.locator(".flow-note-close").evaluate(containedClose),
      );
      await long.locator(".flow-note-close").click();
      await long.waitFor({ state: "hidden" });
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
  await wideTarget.click();
  await wide.waitFor({ state: "visible" });
  await layoutPasses();
  check(
    "A short-name popover also stays open without native popover support",
    await wide.isVisible(),
  );
  await page.keyboard.press("Escape");
  await wide.waitFor({ state: "hidden" });
  const touch = await browser.newPage({
    viewport: { width: 320, height: 844 },
    isMobile: true,
    hasTouch: true,
  });
  touch.on("pageerror", (error) => errors.push(String(error)));
  await touch.goto(entry.href);
  await touch.waitForFunction((id) => document.getElementById(id)?.dataset.noteMode, wideID);
  await touch.evaluate(() => {
    while (Number(document.querySelector("#reader-size").value) < 30)
      document.querySelector("#reader-larger").click();
  });
  await touch.evaluate(
    (id) =>
      [...document.querySelectorAll(`[data-reader-note~="${id}"]`)]
        .find((n) => !n.closest("mjx-assistive-mml,.flow-math-stage"))
        ?.scrollIntoView({ block: "center" }),
    wideID,
  );
  await touch.waitForFunction(
    (id) =>
      [...document.querySelectorAll(`[data-reader-note~="${id}"]`)].some(
        (n) =>
          !n.closest("mjx-assistive-mml,.flow-math-stage") &&
          n.closest(".flow-math-view")?.dataset.mathState === "ready",
      ),
    wideID,
  );
  const touchCollisionTarget = touch
    .locator(`[data-reader-note~="${wideID}"][data-note-interactive="true"]`)
    .first();
  const touchCollision = touch.locator(`#${wideID}`);
  await touchCollisionTarget.waitFor();
  for (let attempt = 0; attempt < 3; attempt++) {
    await touchCollisionTarget.tap();
    await touchCollision.waitFor({ state: "visible" });
    await touch.evaluate(
      () => new Promise((done) => requestAnimationFrame(() => requestAnimationFrame(done))),
    );
    check(
      `Touch attempt ${attempt + 1} keeps an oversized short note visible`,
      await touchCollision.isVisible(),
    );
    await touchCollision.locator(".flow-note-close").tap();
    await touchCollision.waitFor({ state: "hidden" });
  }
  const touchTarget = touch
    .locator(`[data-reader-note~="${longID}"][data-note-interactive="true"]`)
    .first();
  await touchTarget.waitFor();
  await touchTarget.tap();
  await touch.locator(`#${longID}`).waitFor({ state: "visible" });
  check("A touch tap opens the longer note", true);
  check(
    "The touch close control also fits inside the popover",
    await touch.locator(`#${longID} .flow-note-close`).evaluate(containedClose),
  );
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
