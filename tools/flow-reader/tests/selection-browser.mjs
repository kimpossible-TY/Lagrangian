// Run with FLOW_READER_PACKAGES and an installed Playwright module.
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { createInterface } from "node:readline";
import { once } from "node:events";
import { readFile, realpath, writeFile } from "node:fs/promises";
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
const { url, entry } = await new Promise((resolve, reject) => {
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
  const highlightHttp400s = [];
  let highlights = 0;
  let chatOpens = 0;
  let sourceTexts = 0;
  page.on("pageerror", (error) => errors.push(error.message));
  page.on("request", (request) => {
    if (request.url().endsWith("/api/highlight")) highlights++;
    if (request.url().endsWith("/api/source-text")) sourceTexts++;
    if (request.method() === "POST" && request.url().endsWith("/api/chat/open")) chatOpens++;
  });
  page.on("response", (response) => {
    if (response.url().endsWith("/api/highlight") && response.status() === 400) {
      highlightHttp400s.push(response.status());
    }
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
        .dispatchEvent(
          new ClipboardEvent("copy", { clipboardData: data, bubbles: true, cancelable: true }),
        );
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

    await page.waitForFunction(() => document.querySelector(".flow-equation .flow-math-view"));
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

    await page.waitForFunction(() => document.querySelector(".flow-equation .flow-math-view"));
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
      return (
        equation?.querySelector('.flow-math-view[data-math-state="ready"]') &&
        equation.querySelector('.flow-math-view [data-flow-selection-ignore="footnote"]')
      );
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
      ignoredMarkers.dots === "none" &&
        ignoredMarkers.footnote === "none" &&
        !ignoredMarkers.text.includes(ignoredMarkers.number) &&
        !ignoredMarkers.text.includes("⋯") &&
        !ignoredMarkers.text.includes("1") &&
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
      document
        .querySelector("#reader-highlight-message")
        .textContent.includes("화면에 표시된 글자"),
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
    check("Old local quotations do not automatically open chat", chatOpens === 0);
    check(
      "The quotation library UI is removed",
      (await page.locator("#reader-highlights-open, #reader-highlights").count()) === 0,
    );
    await select("Trailing paragraph 7");
    const savedResponse = page.waitForResponse(
      (response) =>
        response.url().endsWith("/api/chat/open") && response.request().method() === "POST",
    );
    await click("#reader-chat-ask");
    const saved = (await (await savedResponse).json()).conversations[0];
    check(
      `Ask records the exact selection and verified source context: ${JSON.stringify(saved)}`,
      saved.status === "idle" &&
        saved.quote === "Trailing paragraph 7" &&
        saved.context.source.filepath === (await realpath(entry)),
    );
    check(
      "Saving context does not edit source or highlight it",
      highlights === 0 && (await readFile(entry, "utf8")) === original,
    );
    check("Ask opens without starting inference", saved.thread.length === 0);
    check(
      "Legacy local quotation data remains untouched",
      (await page.evaluate((key) => localStorage.getItem(key), legacyKey)) === legacyValue,
    );

    await select("Wrapped proof 한글", "block");
    const wrappedResponse = page.waitForResponse(
      (response) =>
        response.url().endsWith("/api/chat/open") && response.request().method() === "POST",
    );
    await click("#reader-chat-ask");
    const wrapped = (await (await wrappedResponse).json()).conversations[0];
    const navigation = await (
      await page.request.post(url + "api/source", {
        data: { revision: state.revision, fragments: wrapped.context.fragments },
      })
    ).json();
    const cursor = await (
      await page.request.post(url + "api/cursor", {
        data: {
          revision: state.revision,
          path: navigation.path,
          line: navigation.line,
          column: navigation.column,
        },
      })
    ).json();
    check(
      "A mixed math proof captures the same source range used by Sync Editor",
      wrapped.status === "idle" &&
        navigation.status === "located" &&
        wrapped.context.source.filepath === navigation.path &&
        wrapped.context.source.line === navigation.line &&
        wrapped.context.source.range.end.line === navigation.end_line &&
        cursor.status === "located" &&
        cursor.key === wrapped.context.fragments[0].key,
    );
    check(
      "Range mapping leaves workspace source and delivered HTML free of carriers",
      (await readFile(entry, "utf8")) === original &&
        !(await page.content()).includes("data-flow-source-edge"),
    );

    await page.route("**/api/chat/open", (route) =>
      route.fulfill({ status: 503, body: "Unavailable" }),
    );
    await select("Trailing paragraph 8");
    const failedSave = page.waitForResponse(
      (response) =>
        response.url().endsWith("/api/chat/open") && response.request().method() === "POST",
    );
    await page.locator("#reader-chat-ask").evaluate((button) => {
      button.dispatchEvent(new PointerEvent("pointerdown", { bubbles: true, cancelable: true }));
      getSelection().removeAllRanges();
      button.click();
    });
    await failedSave;
    await page.waitForFunction(() =>
      document
        .querySelector("#reader-highlight-message")
        .textContent.includes("Could not open chat"),
    );
    check(
      "A failed Ask retains the range after native collapse",
      await page.locator("#reader-chat-ask").isVisible(),
    );
    await page.unroute("**/api/chat/open");
    const retriedSave = page.waitForResponse(
      (response) =>
        response.url().endsWith("/api/chat/open") && response.request().method() === "POST",
    );
    await click("#reader-chat-ask");
    check(
      "The retained range can be retried without reselecting",
      (await (await retriedSave).json()).conversations[0].quote === "Trailing paragraph 8",
    );

    let releaseCodex;
    let notifyCodex;
    const codexRequested = new Promise((resolve) => {
      notifyCodex = resolve;
    });
    await page.route("**/api/chat/open", async (route) => {
      notifyCodex();
      await new Promise((resolve) => {
        releaseCodex = resolve;
      });
      await route.fulfill({ response: await route.fetch() });
    });
    await select("Trailing paragraph 8");
    await click("#reader-chat-ask");
    await codexRequested;
    check(
      "A pending Ask blocks duplicate submission",
      await page.locator("#reader-chat-ask").isDisabled(),
    );
    await select("Trailing paragraph 9");
    const delayedSave = page.waitForResponse(
      (response) =>
        response.url().endsWith("/api/chat/open") && response.request().method() === "POST",
    );
    releaseCodex();
    await delayedSave;
    await page.waitForFunction(() => !document.querySelector("#reader-chat-ask").disabled);
    check(
      "An older chat acknowledgment preserves a newer selection",
      (await page.evaluate(() => getSelection().toString())) === "Trailing paragraph 9",
    );
    await page.unroute("**/api/chat/open");
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
      "Rejected macro output keeps Ask after native collapse",
      (await page.locator("#reader-chat-ask").isVisible()) &&
        (await readFile(entry, "utf8")) === original,
    );
    const macroSavedResponse = page.waitForResponse(
      (response) =>
        response.url().endsWith("/api/chat/open") && response.request().method() === "POST",
    );
    await click("#reader-chat-ask");
    const macroSaved = (await (await macroSavedResponse).json()).conversations[0];
    check(
      "Generated content saves its text with explicit unavailable source",
      macroSaved.status === "idle" &&
        macroSaved.quote === "Shared macro words" &&
        macroSaved.context.source === null,
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

      const waitForDenseMathReady = async () => {
        await page.evaluate(() => {
          const blocks = [...document.querySelectorAll("#reader-document [data-reader-key]")];
          const startIndex = blocks.findIndex((node) =>
            node.textContent.includes("Dense selection intro."),
          );
          if (startIndex < 0 || startIndex + 4 >= blocks.length) {
            throw new Error("Missing dense math fixture blocks");
          }
          for (const block of blocks.slice(startIndex, startIndex + 5)) block.scrollIntoView();
        });
        await page.waitForFunction(() => {
          const blocks = [...document.querySelectorAll("#reader-document [data-reader-key]")];
          const startIndex = blocks.findIndex((node) =>
            node.textContent.includes("Dense selection intro."),
          );
          if (startIndex < 0 || startIndex + 4 >= blocks.length) return false;
          const section = blocks.slice(startIndex, startIndex + 5);
          const views = section.flatMap((block) => [...block.querySelectorAll(".flow-math-view")]);
          return (
            views.length === 22 &&
            views.every((view) => ["ready", "overflow"].includes(view.dataset.mathState)) &&
            Boolean(section[1].querySelector(".flow-equation-number")) &&
            Boolean(section[4].querySelector(".flow-equation-number"))
          );
        });
      };
      const denseSelection = async ({
        from,
        to,
        endMode = "block",
        numberOnly = false,
        applySelection = false,
      }) => {
        const currentState = await (await page.request.get(url + "api/state")).json();
        const result = await page.evaluate(
          async ({ manifest, from, to, endMode, numberOnly, applySelection }) => {
            const { logicalTextIndex, rangesFor } = await import("/rendering/math/identity.js");
            const { selectedReaderText } = await import("/features/selection/dom-selection.js");
            const article = document.querySelector("#reader-document");
            const blocks = [...article.querySelectorAll("[data-reader-key]")];
            const startIndex = blocks.findIndex((node) =>
              node.textContent.includes("Dense selection intro."),
            );
            const section = blocks.slice(startIndex, startIndex + 5);
            const range = document.createRange();
            if (numberOnly) {
              const number = section[from].querySelector(".flow-equation-number");
              const index = logicalTextIndex(number);
              const ranges = rangesFor(index, 0, index.text.length);
              range.setStart(ranges[0].startContainer, ranges[0].startOffset);
              range.setEnd(ranges.at(-1).endContainer, ranges.at(-1).endOffset);
            } else {
              const startIndexObj = logicalTextIndex(section[from]);
              const startRanges = rangesFor(startIndexObj, 0, startIndexObj.text.length);
              const endTarget =
                endMode === "math" ? section[to].querySelector(".flow-math-view") : section[to];
              const endIndexObj = logicalTextIndex(endTarget);
              const endRanges = rangesFor(endIndexObj, 0, endIndexObj.text.length);
              range.setStart(startRanges[0].startContainer, startRanges[0].startOffset);
              range.setEnd(endRanges.at(-1).endContainer, endRanges.at(-1).endOffset);
            }
            const fragments = selectedReaderText(article, manifest, range);
            let liveFragments = null;
            if (applySelection) {
              section[from].scrollIntoView();
              getSelection().removeAllRanges();
              getSelection().addRange(range);
              document.dispatchEvent(new Event("selectionchange"));
              if (getSelection().rangeCount) {
                liveFragments = selectedReaderText(article, manifest, getSelection().getRangeAt(0));
              }
            }
            return {
              fragments,
              liveFragments,
              eq2Number: section[1].querySelector(".flow-equation-number").textContent.trim(),
              eq5Number: section[4].querySelector(".flow-equation-number").textContent.trim(),
            };
          },
          { manifest: currentState, from, to, endMode, numberOnly, applySelection },
        );
        return { ...result, state: currentState };
      };
      const clearSelection = async () => {
        await page.evaluate(() => {
          window.__copied = null;
          document.querySelector("#reader-highlight-message").textContent = "";
          getSelection().removeAllRanges();
          document.dispatchEvent(new Event("selectionchange"));
        });
        await page.waitForFunction(() => document.querySelector("#reader-copy").hidden);
      };

      await page.reload();
      await ready();
      await waitForDenseMathReady();
      const beforeDense = await readFile(entry, "utf8");
      const realEntry = await realpath(entry);
      const restoreDense = async (previousRevision) => {
        await writeFile(entry, beforeDense, "utf8");
        await accepted(previousRevision);
        await page.reload();
        await ready();
        await waitForDenseMathReady();
      };

      // (1) Multi-block focus & source mapping across Blocks 1–5 with and without Block 5's equation number.
      const withNumber = await denseSelection({ from: 0, to: 4, endMode: "block" });
      const withoutNumber = await denseSelection({ from: 0, to: 4, endMode: "math" });
      assert.equal(withNumber.fragments.length, 5);
      assert.ok(withNumber.fragments[4].exact.includes(withNumber.eq5Number));
      assert.equal(withoutNumber.fragments.length, 5);
      assert.ok(!withoutNumber.fragments[4].exact.includes(withoutNumber.eq5Number));
      const locatedRanges = [];
      for (const candidate of [withNumber, withoutNumber]) {
        const focusResponse = await page.request.post(url + "api/focus", {
          data: {
            revision: candidate.state.revision,
            fragments: candidate.fragments,
            service: candidate.state.service,
            viewerID: 42,
          },
        });
        assert.equal(focusResponse.status(), 200);
        const focusBody = await focusResponse.json();
        const sourceResponse = await page.request.post(url + "api/source", {
          data: { revision: candidate.state.revision, fragments: candidate.fragments },
        });
        assert.equal(sourceResponse.status(), 200);
        const sourceBody = await sourceResponse.json();
        assert.equal(focusBody.status, "selected");
        assert.equal(focusBody.source?.filepath, realEntry);
        assert.equal(sourceBody.status, "located");
        assert.equal(sourceBody.path, realEntry);
        locatedRanges.push([sourceBody.line, sourceBody.end_line]);
      }
      check(
        "Multi-block selection across numbered display equations locates with or without the trailing equation number",
        locatedRanges[0][0] === locatedRanges[1][0] && locatedRanges[0][1] === locatedRanges[1][1],
      );

      // (2) 22-formula Typst source copy via #reader-copy without fallback notice.
      await clearSelection();
      await denseSelection({ from: 0, to: 4, endMode: "block", applySelection: true });
      await copyReady();
      await click("#reader-copy");
      await copied();
      await page.waitForFunction(
        () => document.querySelector("#reader-highlight-message").textContent.trim().length > 0,
      );
      const copiedDense = await page.evaluate(() => window.__copied);
      const copyMessage = await page.locator("#reader-highlight-message").textContent();
      const expectedFormulas = [
        "$ u_1 + v_1 = w_1 $",
        ...Array.from({ length: 11 }, (_, i) => `$a_${i + 1}$`),
        ...Array.from({ length: 9 }, (_, i) => `$b_${i + 1}$`),
        "$ u_2 + v_2 = w_2 $",
      ];
      check(
        "Copy across 22 formulas copies Typst source for all 22 formulas without fallback notice",
        copiedDense.includes("$ u_1 + v_1 = w_1 $") &&
          copiedDense.includes("$a_11$") &&
          copiedDense.includes("$b_9$") &&
          copiedDense.includes("$ u_2 + v_2 = w_2 $") &&
          expectedFormulas.every((formula) => copiedDense.includes(formula)) &&
          !copyMessage.includes("수식 원문을 확인할 수 없어 화면에 표시된 글자로 복사했습니다.") &&
          copyMessage.includes("수식을 Typst 원문으로 복사했습니다."),
      );
      await click("#reader-selection-cancel");

      // (3) Equation-number-only selection is rejected by both /api/focus and /api/highlight.
      const numberOnly = await denseSelection({ from: 1, to: 1, numberOnly: true });
      assert.equal(numberOnly.fragments.length, 1);
      assert.equal(numberOnly.fragments[0].exact, numberOnly.eq2Number);
      const numberFocusResponse = await page.request.post(url + "api/focus", {
        data: {
          revision: numberOnly.state.revision,
          fragments: numberOnly.fragments,
          service: numberOnly.state.service,
          viewerID: 42,
        },
      });
      assert.equal(numberFocusResponse.status(), 200);
      const numberFocusBody = await numberFocusResponse.json();
      const numberSourceResponse = await page.request.post(url + "api/source", {
        data: { revision: numberOnly.state.revision, fragments: numberOnly.fragments },
      });
      assert.equal(numberSourceResponse.status(), 200);
      const numberSourceBody = await numberSourceResponse.json();
      const numberHighlightResponse = await page.request.post(url + "api/highlight", {
        data: { revision: numberOnly.state.revision, fragments: numberOnly.fragments },
      });
      assert.equal(numberHighlightResponse.status(), 200);
      const numberHighlightBody = await numberHighlightResponse.json();
      check(
        "Equation-number-only selection is unmapped for focus, source, and highlight",
        numberFocusBody.status === "unmapped" &&
          numberFocusBody.source === null &&
          numberSourceBody.status === "unmapped" &&
          numberHighlightBody.status === "unmapped" &&
          (await readFile(entry, "utf8")) === beforeDense,
      );

      // (4) /api/highlight returns HTTP 200 highlighted (zero HTTP 400) for:
      // (a) Block 2 including its generated equation number,
      // (b) 23-segment Block 3 paragraph, and
      // (c) multi-block selection spanning Block 1 + Block 2 + Block 3.
      const block3Source =
        "Term " + Array.from({ length: 11 }, (_, i) => `$a_${i + 1}$`).join(" and ") + " end.";

      // (4a) Block 2 including its generated equation number.
      const block2Selection = await denseSelection({
        from: 1,
        to: 1,
        endMode: "block",
        applySelection: true,
      });
      assert.ok(block2Selection.fragments[0].exact.includes(block2Selection.eq2Number));
      const before4a = block2Selection.state.revision;
      if (block2Selection.liveFragments?.[0]?.exact.includes(block2Selection.eq2Number)) {
        await page.locator("#reader-source-highlight").waitFor({ state: "visible" });
        await page.waitForFunction(
          () => !document.querySelector("#reader-source-highlight").disabled,
        );
        const res4aPromise = page.waitForResponse((response) =>
          response.url().endsWith("/api/highlight"),
        );
        await click("#reader-source-highlight");
        const res4a = await res4aPromise;
        assert.equal(res4a.status(), 200);
        assert.ok(
          res4a.request().postDataJSON().fragments[0].exact.includes(block2Selection.eq2Number),
        );
        assert.equal((await res4a.json()).status, "highlighted");
      } else {
        const res4a = await page.request.post(url + "api/highlight", {
          data: { revision: before4a, fragments: block2Selection.fragments },
        });
        assert.equal(res4a.status(), 200);
        assert.equal((await res4a.json()).status, "highlighted");
      }
      check(
        "Highlighting a numbered display equation including its equation number writes #highlighted[...]",
        (await readFile(entry, "utf8")).includes("#highlighted[$ u_1 + v_1 = w_1 $]"),
      );
      await restoreDense(await accepted(before4a));

      // (4b) 23-segment Block 3 paragraph.
      await clearSelection();
      const block3Selection = await denseSelection({
        from: 2,
        to: 2,
        endMode: "block",
        applySelection: true,
      });
      assert.equal(block3Selection.fragments[0].segments.length, 23);
      await page.locator("#reader-source-highlight").waitFor({ state: "visible" });
      await page.waitForFunction(
        () => !document.querySelector("#reader-source-highlight").disabled,
      );
      const before4b = block3Selection.state.revision;
      const res4bPromise = page.waitForResponse((response) =>
        response.url().endsWith("/api/highlight"),
      );
      await click("#reader-source-highlight");
      const res4b = await res4bPromise;
      assert.equal(res4b.status(), 200);
      assert.equal(res4b.request().postDataJSON().fragments[0].segments.length, 23);
      assert.equal((await res4b.json()).status, "highlighted");
      check(
        "Highlighting a 23-segment inline-math paragraph writes #highlighted[...] without HTTP 400",
        (await readFile(entry, "utf8")).includes(`#highlighted[${block3Source}]`),
      );
      await restoreDense(await accepted(before4b));

      // (4c) Multi-block selection spanning Block 1 + Block 2 + Block 3.
      await clearSelection();
      const multiSelection = await denseSelection({
        from: 0,
        to: 2,
        endMode: "block",
        applySelection: true,
      });
      assert.equal(multiSelection.fragments.length, 3);
      assert.ok(multiSelection.fragments[1].exact.includes(multiSelection.eq2Number));
      assert.equal(multiSelection.fragments[2].segments.length, 23);
      await page.locator("#reader-source-highlight").waitFor({ state: "visible" });
      await page.waitForFunction(
        () => !document.querySelector("#reader-source-highlight").disabled,
      );
      const before4c = multiSelection.state.revision;
      const res4cPromise = page.waitForResponse((response) =>
        response.url().endsWith("/api/highlight"),
      );
      await click("#reader-source-highlight");
      const res4c = await res4cPromise;
      assert.equal(res4c.status(), 200);
      const req4c = res4c.request().postDataJSON();
      assert.equal(req4c.fragments.length, 3);
      assert.ok(req4c.fragments[1].exact.includes(multiSelection.eq2Number));
      assert.equal(req4c.fragments[2].segments.length, 23);
      assert.equal((await res4c.json()).status, "highlighted");
      check(
        "Highlighting a multi-block selection spanning prose, numbered display equation, and 23-segment paragraph writes #highlighted[...]",
        (await readFile(entry, "utf8")).includes(
          `#highlighted[Dense selection intro.\n\n$ u_1 + v_1 = w_1 $\n\n${block3Source}]`,
        ),
      );
      await restoreDense(await accepted(before4c));
      check(
        "Dense highlight regressions produced zero HTTP 400 responses",
        highlightHttp400s.length === 0,
      );
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
