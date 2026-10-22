// Run against a disposable Reader serving fixtures/annotation-grouping.typ.
import assert from "node:assert/strict";
import { mkdir, writeFile } from "node:fs/promises";
import { resolve } from "node:path";

const engines = await import(process.env.PLAYWRIGHT_MODULE || "playwright");
const engine = process.env.BROWSER_ENGINE || "chromium";
const address = process.argv[2];
if (!address) throw new Error("Provide the disposable grouping fixture URL");
const output = resolve(process.argv[3] || "dist/reader-annotation-grouping", engine);
await mkdir(output, { recursive: true });
const browser = await engines[engine].launch({
  ...(engine === "chromium" && process.env.CHROME_BIN
    ? { executablePath: process.env.CHROME_BIN }
    : {}),
  headless: true,
});
const omitted = [
  "brace-note",
  "bracket-note",
  "native-underbrace",
  "native-overbrace",
  "native-underbracket",
  "native-overbracket",
  "equation-note",
];
const errors = [];
const requests = [];
const checks = [];
try {
  const page = await browser.newPage({ viewport: { width: 390, height: 844 } });
  page.on("pageerror", (error) => errors.push(String(error)));
  page.on("request", (request) => {
    if (new URL(request.url()).pathname === "/api/decorations")
      requests.push(...Object.keys(request.postDataJSON().decorations));
  });
  await page.goto(address);
  await page.waitForFunction(() => document.querySelector(".flow-note"));
  const allowed = await page
    .locator("[data-flow-decoration]")
    .evaluateAll((nodes) => nodes.map((node) => node.dataset.flowDecoration));

  for (const [width, font] of [
    [390, 13],
    [320, 30],
    [1280, 18],
    [390, 13],
  ]) {
    await page.setViewportSize({ width, height: width > 1000 ? 960 : 844 });
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
    for (const tag of omitted) {
      await page.evaluate((tag) => {
        [...document.querySelectorAll(`[data-flow-mark="${tag}"]`)]
          .find((node) => !node.closest("mjx-assistive-mml,.flow-math-stage"))
          .scrollIntoView({ block: "center" });
      }, tag);
      await page.waitForFunction(
        (tag) =>
          [...document.querySelectorAll(`[data-flow-mark="${tag}"]`)].some(
            (node) =>
              !node.closest("mjx-assistive-mml,.flow-math-stage") &&
              node.closest(".flow-math-view")?.dataset.mathState === "ready" &&
              node.dataset.readerNote,
          ),
        tag,
      );
      const state = await page.evaluate(async (tag) => {
        const { logicalTextIndex } = await import("/rendering/math/identity.js");
        const nodes = [...document.querySelectorAll(`[data-flow-mark="${tag}"]`)].filter(
          (node) => !node.closest("mjx-assistive-mml,.flow-math-stage"),
        );
        return {
          text: logicalTextIndex(nodes[0].closest(".flow-math-view"), {
            includeNested: true,
          }).text.normalize("NFKC"),
          decorated: nodes.some(
            (node) =>
              node.hasAttribute("data-flow-decoration") ||
              node.hasAttribute("data-flow-anchor") ||
              node.querySelector("mjx-munder,mjx-mover,munder,mover"),
          ),
          note: nodes[0].dataset.readerNote.split(" ")[0],
        };
      }, tag);
      assert.equal(
        state.decorated,
        false,
        `${width}px/${font}px ${tag} has no grouping paint/outset`,
      );
      if (tag === "brace-note") assert.equal(state.text, "a+b+c+d+e+f+g+h+i+j+k+l=z");
      if (tag === "bracket-note") {
        const mode = width > 1000 ? "side" : "popover";
        await page.waitForFunction(
          ({ id, mode }) => document.getElementById(id)?.dataset.noteMode === mode,
          { id: state.note, mode },
        );
        if (mode === "popover") {
          await page.evaluate((id) => {
            [...document.querySelectorAll(`[data-reader-note~="${id}"]`)]
              .find((node) => !node.closest("mjx-assistive-mml,.flow-math-stage"))
              .dispatchEvent(new MouseEvent("click", { bubbles: true }));
          }, state.note);
          await page.waitForFunction((id) => document.getElementById(id)?.dataset.open, state.note);
          assert.match(
            await page.locator(`#${state.note}`).textContent(),
            /complete marked expression/,
          );
          await page.locator(`#${state.note} .flow-note-close`).click();
        }
      }
      checks.push({ width, font, tag, text: state.text });
    }
    for (const tag of ["underline-note", "callback-note", "tag-only"]) {
      await page.evaluate((tag) => {
        [...document.querySelectorAll(`[data-flow-mark="${tag}"]`)]
          .find((node) => !node.closest("mjx-assistive-mml,.flow-math-stage"))
          .scrollIntoView({ block: "center" });
      }, tag);
      await page.waitForFunction(
        (tag) =>
          [...document.querySelectorAll(`[data-flow-mark="${tag}"]`)].some(
            (node) =>
              !node.closest("mjx-assistive-mml,.flow-math-stage") &&
              node.dataset.decorationState === "ready" &&
              node.dataset.flowAnchor,
          ),
        tag,
      );
      checks.push({ width, font, tag, retained: true });
    }
    await page.evaluate(() => window.scrollTo(0, 0));
    await page.screenshot({ path: resolve(output, `${width}-${font}.png`) });
  }
  assert.ok(
    requests.every((id) => allowed.includes(id)),
    "Only retained decorations request paint",
  );
  assert.deepEqual(errors, []);
  await writeFile(
    resolve(output, "report.json"),
    JSON.stringify({ engine, checks, requests, errors }, null, 2),
  );
  console.log(`${engine}: ${checks.length} grouping/reflow checks passed`);
} finally {
  await browser.close();
}
