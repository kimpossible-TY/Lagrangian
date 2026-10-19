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
  const page = await browser.newPage({ viewport, locale: "ko-KR" });
  const errors = [];
  let highlights = 0;
  let codexSaves = 0;
  page.on("pageerror", (error) => errors.push(error.message));
  page.on("request", (request) => {
    if (request.url().endsWith("/api/highlight")) highlights++;
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
        const { logicalTextIndex, rangesFor } = await import("/math-identity.js");
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
        const index = logicalTextIndex(wholeMath ? math : block);
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
