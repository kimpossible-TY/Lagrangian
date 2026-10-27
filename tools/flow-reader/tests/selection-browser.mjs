// Run with FLOW_READER_PACKAGES and an installed Playwright module.
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { createInterface } from "node:readline";
import { once } from "node:events";
import { readFile, realpath } from "node:fs/promises";
import { fileURLToPath } from "node:url";

const { webkit, chromium } = await import(
  process.env.FLOW_READER_PLAYWRIGHT_MODULE || "playwright"
);
const fixture = spawn(
  process.env.PYTHON || "python3",
  [fileURLToPath(new URL("./selection_fixture.py", import.meta.url))],
  { stdio: ["ignore", "pipe", "inherit"] },
);
const lines = createInterface({ input: fixture.stdout });
const { url, entry, focusFile } = await new Promise((resolve, reject) => {
  lines.once("line", (line) => resolve(JSON.parse(line)));
  fixture.once("exit", (code) => reject(new Error(`Fixture exited: ${code}`)));
});
let checks = 0;
const check = (name, result) => {
  assert.ok(result, name);
  checks++;
};

async function verify(browser, viewport) {
  // Request interception does not see Service Worker fetches. This fixture
  // exercises selection actions against controlled failures, so block the
  // offline worker; offline delivery has its own fixtures.
  const context = await browser.newContext({
    viewport,
    locale: "ko-KR",
    serviceWorkers: "block",
  });
  const page = await context.newPage();
  await page.addInitScript(() => {
    window.__copied = null;
    const clipboard = {
      writeText: async (text) => {
        window.__copied = text;
      },
    };
    for (const target of [navigator, Navigator.prototype]) {
      try {
        Object.defineProperty(target, "clipboard", { configurable: true, value: clipboard });
        break;
      } catch {
        /* The other prototype may accept the stub. */
      }
    }
  });
  const errors = [];
  let highlights = 0;
  let codexSaves = 0;
  let sourceTexts = 0;
  page.on("pageerror", (error) => errors.push(error.message));
  page.on("request", (request) => {
    if (request.url().endsWith("/api/highlight")) highlights++;
    if (request.url().endsWith("/api/source-text")) sourceTexts++;
    if (request.method() === "POST" && request.url().endsWith("/api/focus")) codexSaves++;
  });
  const ready = () =>
    page.waitForFunction(
      () =>
        document.querySelector("#reader-document [data-reader-key]") &&
        document.querySelector("#reader-document").getAttribute("aria-busy") === "false",
    );
  const select = async (exact, wholeMath = false) => {
    await page.evaluate(
      async ({ exact, wholeMath }) => {
        const { logicalTextIndex, rangesFor } = await import("/rendering/math/identity.js");
        const blocks = [...document.querySelectorAll("#reader-document [data-reader-key]")];
        const block =
          wholeMath === "display"
            ? document.querySelector("#reader-document .flow-equation")
            : blocks.find((node) => logicalTextIndex(node).text.includes(exact));
        if (!block) throw new Error(`Missing selection ${exact}`);
        block.scrollIntoView();
        const math =
          block.querySelector(".flow-math-view") ??
          block.querySelector(".flow-inline-equation,.flow-equation,math");
        const index = logicalTextIndex(wholeMath && wholeMath !== "block" ? math : block);
        const start = wholeMath ? 0 : index.text.indexOf(exact);
        const ranges = rangesFor(
          index,
          start,
          wholeMath ? index.text.length : start + exact.length,
        );
        const range = document.createRange();
        range.setStart(ranges[0].startContainer, ranges[0].startOffset);
        range.setEnd(ranges.at(-1).endContainer, ranges.at(-1).endOffset);
        getSelection().removeAllRanges();
        getSelection().addRange(range);
      },
      { exact, wholeMath },
    );
    await page.locator("#reader-source-highlight").waitFor({ state: "visible" });
    await page.waitForTimeout(100);
  };
  const click = (id) => page.locator(id).evaluate((node) => node.click());
  const copyReady = () =>
    page.waitForFunction(() => {
      const button = document.querySelector("#reader-copy");
      return button && !button.hidden && !button.disabled;
    });
  const selectMathGlyph = (marker = null) =>
    page.evaluate(async (marker) => {
      const { logicalTextIndex, rangesFor } = await import("/rendering/math/identity.js");
      const block = marker
        ? [...document.querySelectorAll("#reader-document [data-reader-key]")].find((node) =>
            logicalTextIndex(node).text.includes(marker),
          )
        : document.querySelector("#reader-document .flow-equation");
      const math = block?.querySelector(".flow-math-view");
      if (!math) throw new Error(`Missing mathematics for ${marker ?? "display"}`);
      block.scrollIntoView();
      const index = logicalTextIndex(math);
      const ranges = rangesFor(index, 0, 1);
      const range = document.createRange();
      range.setStart(ranges[0].startContainer, ranges[0].startOffset);
      range.setEnd(ranges.at(-1).endContainer, ranges.at(-1).endOffset);
      getSelection().removeAllRanges();
      getSelection().addRange(range);
      document.dispatchEvent(new Event("selectionchange"));
      return index.text;
    }, marker);
  const nativeCopy = () =>
    page.evaluate(() => {
      const data = new DataTransfer();
      document
        .querySelector("#reader-document")
        .dispatchEvent(new ClipboardEvent("copy", { clipboardData: data, bubbles: true, cancelable: true }));
      return data.getData("text/plain");
    });
  const copied = () => page.waitForFunction(() => window.__copied !== null);
  const strikeCount = () => page.locator(".reader-review-marks span").count();
  const accepted = async (previous) => {
    const deadline = Date.now() + 15000;
    while (Date.now() < deadline) {
      const state = await (await page.request.get(url + "api/state")).json();
      if (!state.compiling && (!previous || state.revision !== previous)) return state.revision;
      await page.waitForTimeout(60);
    }
    throw new Error("Saved source did not produce an accepted revision");
  };
  try {
    await page.goto(url);
    await ready();
    await accepted();
    await page.waitForFunction(() => document.querySelector(".flow-math-view"));
    const original = await readFile(entry, "utf8");
    await select("Trailing paragraph 7");
    const toolbar = await page.locator("#reader-selection").boundingBox();
    check(
      "Selection controls stay inside a narrow visible viewport",
      toolbar.x >= 0 &&
        toolbar.x + toolbar.width <= viewport.width + 1 &&
        toolbar.y + toolbar.height <= viewport.height,
    );

    await page.waitForFunction(
      () => document.querySelector(".flow-equation .flow-math-view"),
    );
    const firstSourceRequests = sourceTexts;
    await selectMathGlyph();
    await page.waitForTimeout(400);
    await copyReady();
    const copyBox = await page.locator("#reader-copy").boundingBox();
    check(
      "Copy offers a named 44px action target",
      copyBox.width >= 44 &&
        copyBox.height >= 44 &&
        (await page.locator("#reader-copy span").textContent()) === "복사",
    );
    await click("#reader-copy");
    await copied();
    check(
      "Copy expands a partial formula to its verified Typst source",
      (await page.evaluate(() => window.__copied)) === "$ alpha^2 + beta + 1 $" &&
        sourceTexts === firstSourceRequests + 1,
    );

    await selectMathGlyph();
    await page.waitForTimeout(400);
    await copyReady();
    await page.evaluate(() => {
      window.__copied = null;
    });
    await click("#reader-copy");
    await copied();
    check(
      "A repeated selection reuses the verified excerpt",
      sourceTexts === firstSourceRequests + 1 &&
        (await page.evaluate(() => window.__copied)) === "$ alpha^2 + beta + 1 $",
    );

    await page.evaluate(async () => {
      const { logicalTextIndex, rangesFor } = await import("/rendering/math/identity.js");
      const block = [...document.querySelectorAll("#reader-document [data-reader-key]")].find(
        (node) => logicalTextIndex(node).text.includes("Complete mathematics"),
      );
      const index = logicalTextIndex(block);
      const ranges = rangesFor(index, 0, index.text.length);
      const range = document.createRange();
      range.setStart(ranges[0].startContainer, ranges[0].startOffset);
      range.setEnd(ranges.at(-1).endContainer, ranges.at(-1).endOffset);
      block.scrollIntoView();
      getSelection().removeAllRanges();
      getSelection().addRange(range);
      document.dispatchEvent(new Event("selectionchange"));
      return index.text;
    });
    await page.waitForTimeout(400);
    await copyReady();
    const nativeMixed = await nativeCopy();
    check(
      "Native copy keeps prose and replaces the complete formula with Typst",
      nativeMixed.includes("Complete mathematics") &&
        nativeMixed.includes("$alpha^2 + beta$") &&
        nativeMixed.includes("remains selectable") &&
        !nativeMixed.includes("𝛼"),
    );

    await page.waitForFunction(
      () => document.querySelector(".flow-equation .flow-math-view"),
    );
    await page.evaluate(() => {
      window.__copied = null;
      document
        .querySelector("#reader-document")
        .dispatchEvent(new PointerEvent("pointerdown", { bubbles: true, pointerType: "touch" }));
    });
    await selectMathGlyph();
    await page.waitForTimeout(700);
    check(
      "A touch selection settles on the complete expression",
      await page.evaluate(() => {
        const text = getSelection().toString();
        return text.includes("\u{1D6FD}") && text.includes("1");
      }),
    );

    const backwardAnchor = await page.evaluate(async () => {
      const { logicalTextIndex, rangesFor } = await import("/rendering/math/identity.js");
      const equation = document.querySelector("#reader-document .flow-equation");
      const number = equation.querySelector(".flow-equation-number");
      const prose = [...document.querySelectorAll("#reader-document [data-reader-key]")].find(
        (node) => logicalTextIndex(node).text.includes("Another independent selection"),
      );
      const mathIndex = logicalTextIndex(equation.querySelector(".flow-math-view"));
      const proseIndex = logicalTextIndex(prose);
      const glyph = rangesFor(mathIndex, 0, 1)[0];
      const end = rangesFor(proseIndex, 0, 10).at(-1);
      getSelection().setBaseAndExtent(
        end.endContainer,
        end.endOffset,
        glyph.startContainer,
        glyph.startOffset,
      );
      document.dispatchEvent(new Event("selectionchange"));
      return getComputedStyle(number).userSelect;
    });
    await page.waitForTimeout(700);
    check("Equation numbers are not selectable", backwardAnchor === "none");
    check(
      "Snapping an upward selection preserves its anchor and expands the formula",
      await page.evaluate(() => {
        const selection = getSelection();
        const math = document.querySelector("#reader-document .flow-equation .flow-math-view");
        return (
          selection.anchorNode?.parentElement
            ?.closest("[data-reader-key]")
            ?.textContent.includes("Another independent selection") &&
          selection.focusNode === math &&
          selection.focusOffset === 0
        );
      }),
    );

    await page.evaluate(() => getSelection().removeAllRanges());
    await page.waitForFunction(() => {
      const equation = document.querySelector(
        '.flow-equation:has([data-flow-selection-ignore="dots-space"])',
      );
      return equation?.querySelector('.flow-math-view[data-math-state="ready"]') &&
        equation.querySelector('.flow-math-view [data-flow-selection-ignore="footnote"]');
    });
    const ignoredMarkers = await page.evaluate(() => {
      const equation = document.querySelector(
        '.flow-equation:has([data-flow-selection-ignore="dots-space"])',
      );
      const view = equation.querySelector(".flow-math-view");
      const dots = view.querySelector('[data-flow-selection-ignore="dots-space"]');
      const footnote = view.querySelector('[data-flow-selection-ignore="footnote"]');
      const range = document.createRange();
      range.selectNodeContents(equation);
      getSelection().removeAllRanges();
      getSelection().addRange(range);
      return {
        text: getSelection().toString(),
        number: equation.querySelector(".flow-equation-number").textContent.trim(),
        dots: getComputedStyle(dots).userSelect,
        footnote: getComputedStyle(footnote).userSelect,
        link: Boolean(footnote.querySelector('a[href^="#"]')),
      };
    });
    check(
      "Selection across an equation excludes its generated markers",
      ignoredMarkers.dots === "none" && ignoredMarkers.footnote === "none" &&
        !ignoredMarkers.text.includes(ignoredMarkers.number) &&
        !ignoredMarkers.text.includes("⋯") && !ignoredMarkers.text.includes("1") &&
        ignoredMarkers.link,
    );

    await page.evaluate(() => {
      window.__copied = null;
    });
    await selectMathGlyph("\u{1D6FE}");
    await page.waitForTimeout(400);
    await copyReady();
    await click("#reader-copy");
    await copied();
    await page.waitForFunction(() =>
      document.querySelector("#reader-highlight-message").textContent.includes("화면에 표시된 글자"),
    );
    check(
      "An unverified expression falls back to displayed text with a notice",
      !(await page.evaluate(() => window.__copied)).startsWith("$") &&
        (await page.evaluate(() => window.__copied)).includes("\u{1D6FE}") &&
        (await page.locator("#reader-highlight-message").textContent()).includes(
          "화면에 표시된 글자",
        ),
    );
    await click("#reader-selection-cancel");

    await select("Trailing paragraph 7");
    await page.locator("#reader-strike").click();
    await page.waitForFunction(() => document.querySelector(".reader-review-marks span"));
    check(
      "Red strike paints immediately without changing source",
      (await strikeCount()) > 0 && (await readFile(entry, "utf8")) === original && highlights === 0,
    );
    check(
      "Strike leaves undo and clear available after selection collapses",
      (await page.locator("#reader-strike-undo").isVisible()) &&
        (await page.evaluate(() => getSelection().isCollapsed)),
    );
    await click("#reader-larger");
    await page.setViewportSize({
      width: viewport.width === 320 ? 430 : 320,
      height: viewport.height,
    });
    await page.waitForTimeout(300);
    check("Strike survives font reflow and width changes", (await strikeCount()) > 0);
    await page.reload();
    await ready();
    await page.waitForFunction(() => document.querySelector(".reader-review-marks span"));
    check("Strike survives reload", (await strikeCount()) > 0);
    await click("#reader-strike-undo");
    check(
      "Undo removes the most recent strike without compiling",
      (await strikeCount()) === 0 && highlights === 0,
    );
    await select("Trailing paragraph 7");
    await click("#reader-strike");
    await select("Another independent selection");
    await click("#reader-strike");
    await click("#reader-strike-clear");
    check(
      "Clear removes every strike without changing source",
      (await strikeCount()) === 0 && (await readFile(entry, "utf8")) === original,
    );
    await page.setViewportSize(viewport);

    const state = await (await page.request.get(url + "api/state")).json();
    const legacyKey = `flow-reader:${state.documentID}:highlights:v1`;
    const legacyValue = JSON.stringify([
      {
        id: "legacy",
        fragments: [{ key: "old", exact: "Old local quotation", prefix: "", suffix: "" }],
      },
    ]);
    await page.evaluate(({ key, value }) => localStorage.setItem(key, value), {
      key: legacyKey,
      value: legacyValue,
    });
    await page.reload();
    await ready();
    check("Old local quotations are not automatically sent to Codex", codexSaves === 0);
    check(
      "The quotation library UI is removed",
      (await page.locator("#reader-highlights-open, #reader-highlights").count()) === 0,
    );
    await select("Trailing paragraph 7");
    const savedResponse = page.waitForResponse(
      (response) => response.url().endsWith("/api/focus") && response.request().method() === "POST",
    );
    await click("#reader-codex-save");
    const saved = await (await savedResponse).json();
    check(
      `Save for Codex records the exact selection and source context: ${JSON.stringify(saved)}`,
      saved.status === "selected" &&
        saved.selection.text === "Trailing paragraph 7" &&
        saved.source.filepath === (await realpath(entry)),
    );
    check(
      "Saving context does not edit source or highlight it",
      highlights === 0 && (await readFile(entry, "utf8")) === original,
    );
    check(
      "The server writes the private focus record",
      JSON.parse(await readFile(focusFile, "utf8")).selection.text === saved.selection.text,
    );
    const readContext = await (await page.request.get(url + "api/focus")).json();
    check(
      "The selection reader validates the saved context",
      readContext.selection_usable &&
        readContext.service_matches &&
        readContext.source_excerpt_matches_disk,
    );
    check(
      "Legacy local quotation data remains untouched",
      (await page.evaluate((key) => localStorage.getItem(key), legacyKey)) === legacyValue,
    );

    await select("Wrapped proof 한글", "block");
    const wrappedResponse = page.waitForResponse(
      (response) => response.url().endsWith("/api/focus") && response.request().method() === "POST",
    );
    await click("#reader-codex-save");
    const wrapped = await (await wrappedResponse).json();
    const navigation = await (await page.request.post(url + "api/source", {
      data: { revision: state.revision, fragments: wrapped.selection.fragments },
    })).json();
    const cursor = await (await page.request.post(url + "api/cursor", {
      data: { revision: state.revision, path: navigation.path,
              line: navigation.line, column: navigation.column },
    })).json();
    check(
      "A mixed math proof saves the same source range used by Sync Editor",
      wrapped.status === "selected" && navigation.status === "located" &&
        wrapped.source.filepath === navigation.path && wrapped.source.line === navigation.line &&
        wrapped.source.range.end.line === navigation.end_line &&
        cursor.status === "located" && cursor.key === wrapped.selection.fragments[0].key,
    );
    check(
      "Range mapping leaves workspace source and delivered HTML free of carriers",
      (await readFile(entry, "utf8")) === original &&
        !(await page.content()).includes("data-flow-source-edge"),
    );

    await page.route("**/api/focus", (route) =>
      route.fulfill({ status: 503, body: "Unavailable" }),
    );
    await select("Trailing paragraph 8");
    const failedSave = page.waitForResponse(
      (response) => response.url().endsWith("/api/focus") && response.request().method() === "POST",
    );
    await page.locator("#reader-codex-save").evaluate((button) => {
      button.dispatchEvent(new PointerEvent("pointerdown", { bubbles: true, cancelable: true }));
      getSelection().removeAllRanges();
      button.click();
    });
    await failedSave;
    await page.waitForFunction(() =>
      document
        .querySelector("#reader-highlight-message")
        .textContent.includes("저장하지 못했습니다"),
    );
    check(
      "A failed Codex save retains the range after native collapse",
      await page.locator("#reader-codex-save").isVisible(),
    );
    await page.unroute("**/api/focus");
    const retriedSave = page.waitForResponse(
      (response) => response.url().endsWith("/api/focus") && response.request().method() === "POST",
    );
    await click("#reader-codex-save");
    check(
      "The retained range can be retried without reselecting",
      (await (await retriedSave).json()).selection.text === "Trailing paragraph 8",
    );

    let releaseCodex;
    let notifyCodex;
    const codexRequested = new Promise((resolve) => {
      notifyCodex = resolve;
    });
    await page.route("**/api/focus", async (route) => {
      notifyCodex();
      await new Promise((resolve) => {
        releaseCodex = resolve;
      });
      await route.fulfill({ response: await route.fetch() });
    });
    await select("Trailing paragraph 8");
    await click("#reader-codex-save");
    await codexRequested;
    check(
      "A pending Codex save blocks duplicate submission",
      await page.locator("#reader-codex-save").isDisabled(),
    );
    await select("Trailing paragraph 9");
    const delayedSave = page.waitForResponse(
      (response) => response.url().endsWith("/api/focus") && response.request().method() === "POST",
    );
    releaseCodex();
    await delayedSave;
    await page.waitForFunction(() =>
      document
        .querySelector("#reader-highlight-message")
        .textContent.includes("Codex용 텍스트 저장됨"),
    );
    check(
      "An older Codex acknowledgment preserves a newer selection",
      (await page.evaluate(() => getSelection().toString())) === "Trailing paragraph 9",
    );
    await page.unroute("**/api/focus");
    await click("#reader-selection-cancel");

    // A native toolbar tap may collapse selection before its click arrives.
    await select("Shared macro words");
    const macroResponse = page.waitForResponse((response) =>
      response.url().endsWith("/api/highlight"),
    );
    await page.locator("#reader-source-highlight").evaluate((button) => {
      button.dispatchEvent(new PointerEvent("pointerdown", { bubbles: true, cancelable: true }));
      getSelection().removeAllRanges();
      button.click();
    });
    const macroStatus = await (await macroResponse).json();
    assert.equal(
      macroStatus.status,
      "unmapped",
      JSON.stringify({
        macroStatus,
        state: await page.evaluate(async () =>
          fetch("api/state").then((response) => response.json()),
        ),
      }),
    );
    await page.waitForFunction(() =>
      document.querySelector("#reader-highlight-message").textContent.includes("정확히 연결"),
    );
    check(
      "Rejected macro output keeps Save for Codex after native collapse",
      (await page.locator("#reader-codex-save").isVisible()) &&
        (await readFile(entry, "utf8")) === original,
    );
    const macroSavedResponse = page.waitForResponse(
      (response) => response.url().endsWith("/api/focus") && response.request().method() === "POST",
    );
    await click("#reader-codex-save");
    const macroSaved = await (await macroSavedResponse).json();
    check(
      "Generated content saves its text with explicit unavailable source",
      macroSaved.status === "unmapped" &&
        macroSaved.selection.text === "Shared macro words" &&
        macroSaved.source === null,
    );
    await click("#reader-selection-cancel");

    // A response to an older selection must preserve a newly selected passage.
    let release;
    let requested;
    const pending = new Promise((resolve) => {
      requested = resolve;
    });
    await page.route("**/api/highlight", async (route) => {
      requested();
      await new Promise((resolve) => {
        release = resolve;
      });
      await route.fulfill({
        contentType: "application/json",
        body: JSON.stringify({ status: "unmapped" }),
      });
    });
    await select("selected ordinary passage");
    await click("#reader-source-highlight");
    await pending;
    check(
      "Pending highlights disable duplicate submission",
      await page.locator("#reader-source-highlight").isDisabled(),
    );
    await select("Another independent selection");
    release();
    await page.waitForFunction(() => !document.querySelector("#reader-source-highlight").disabled);
    check(
      "An older response preserves a newer selection",
      await page.evaluate(() =>
        getSelection().toString().includes("Another independent selection"),
      ),
    );
    await page.unroute("**/api/highlight");
    await click("#reader-selection-cancel");

    await select("selected ordinary passage");
    const beforeProse = await page.evaluate(
      async () => (await fetch("api/state").then((response) => response.json())).revision,
    );
    const proseResult = page.waitForResponse((response) =>
      response.url().endsWith("/api/highlight"),
    );
    await page.locator("#reader-source-highlight").click();
    assert.equal((await (await proseResult).json()).status, "highlighted");
    check(
      "Highlight writes the real Typst helper to the source",
      (await readFile(entry, "utf8")).includes("#highlighted[selected ordinary passage]"),
    );
    await accepted(beforeProse);
    await page.reload();
    await ready();
    await page.waitForFunction(() => document.querySelector(".flow-math-view"));
    await page
      .locator("#reader-document mark")
      .first()
      .waitFor({ state: "attached", timeout: 10000 })
      .catch(async (error) => {
        console.log(
          JSON.stringify(
            await page.evaluate(async () => ({
              body: document.querySelector("#reader-document").innerHTML,
              state: await fetch("api/state").then((response) => response.json()),
              html: await fetch("document.html").then((response) => response.text()),
            })),
            null,
            2,
          ),
        );
        throw error;
      });
    check(
      "Source highlighting survives document reload",
      (await page.locator("#reader-document mark").count()) > 0,
    );

    await select("Complete mathematics", true);
    const beforeMath = await page.evaluate(
      async () => (await fetch("api/state").then((response) => response.json())).revision,
    );
    const mathResult = page.waitForResponse((response) =>
      response.url().endsWith("/api/highlight"),
    );
    await click("#reader-source-highlight");
    assert.equal((await (await mathResult).json()).status, "highlighted");
    check(
      "Complete native mathematics uses the math-aware source helper",
      (await readFile(entry, "utf8")).includes("#highlighted[$alpha^2 + beta$]"),
    );
    await accepted(beforeMath);
    if (viewport.width === 320) {
      await page.reload();
      await ready();
      await page.waitForSelector(".flow-equation .flow-math-view");
      await select("", "display");
      const before = await accepted();
      const response = page.waitForResponse((response) =>
        response.url().endsWith("/api/highlight"),
      );
      await click("#reader-source-highlight");
      assert.equal((await (await response).json()).status, "highlighted");
      check(
        "A complete numbered equation does not require selecting its generated number",
        (await readFile(entry, "utf8")).includes("#highlighted[$ alpha^2 + beta + 1 $]"),
      );
      await accepted(before);
    }
    assert.deepEqual(errors, []);
    console.log(`PASS ${viewport.width}×${viewport.height}`);
  } finally {
    await context.close();
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
        { width: 320, height: 740 },
        { width: 390, height: 844 },
        { width: 768, height: 600 },
      ])
        await verify(browser, viewport);
    } finally {
      await browser.close();
    }
  }
  console.log(`Passed ${checks} selection action checks.`);
} finally {
  fixture.kill("SIGTERM");
  await once(fixture, "exit");
  lines.close();
}
