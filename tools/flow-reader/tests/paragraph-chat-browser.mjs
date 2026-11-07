import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { createInterface } from "node:readline";
import { once } from "node:events";
import { fileURLToPath } from "node:url";

const engines = await import(process.env.FLOW_READER_PLAYWRIGHT_MODULE || "playwright");
const engine = process.env.ENGINE || process.env.BROWSER_ENGINE || process.argv[2] || "chromium";
assert.ok(["chromium", "webkit"].includes(engine), "ENGINE must be chromium or webkit");
const fixture = spawn(
  process.env.PYTHON || "python3",
  [fileURLToPath(new URL("./paragraph_chat_fixture.py", import.meta.url))],
  { stdio: ["ignore", "pipe", "inherit"] },
);
const lines = createInterface({ input: fixture.stdout });
const { url, token } = await new Promise((resolve, reject) => {
  lines.once("line", (line) => resolve(JSON.parse(line)));
  fixture.once("exit", (code) => reject(new Error(`Fixture exited: ${code}`)));
});
let browser;
try {
  browser = await engines[engine].launch({
    headless: true,
    ...(engine === "chromium" && process.env.CHROME_BIN
      ? { executablePath: process.env.CHROME_BIN }
      : {}),
  });
} catch (error) {
  fixture.kill("SIGTERM");
  await once(fixture, "exit");
  lines.close();
  throw error;
}
let checks = 0;
const check = (name, value) => {
  assert.ok(value, name);
  checks++;
};
const control = async (body) => {
  const response = await fetch(url + "fixture-control", {
    method: "POST",
    headers: { "Content-Type": "application/json", "X-Fixture-Token": token },
    body: JSON.stringify(body),
  });
  assert.ok(response.ok);
};
const history = async () => {
  const state = await (await fetch(url + "api/state")).json();
  const response = await fetch(url + "api/chat/list", {
    method: "POST",
    headers: { "Content-Type": "application/json", Origin: new URL(url).origin },
    body: JSON.stringify(state),
  });
  assert.ok(response.ok);
  return (await response.json()).conversations;
};
try {
  const context = await browser.newContext({
    viewport: { width: 1280, height: 850 },
    serviceWorkers: "block",
    hasTouch: true,
  });
  const page = await context.newPage();
  const errors = [];
  page.on("pageerror", (error) => errors.push(error.message));
  await page.goto(url + "?terminal=1");
  await page.waitForFunction(
    () =>
      document.querySelector("#first[data-reader-key]") &&
      document.querySelector("#reader-document").getAttribute("aria-busy") === "false",
  );
  const select = async (text) => {
    await page.evaluate(async (text) => {
      const { logicalTextIndex, rangesFor } = await import(
        new URL("rendering/math/identity.js", location.href).href
      );
      const host = [...document.querySelectorAll("#reader-document [data-reader-key]")].find(
        (node) => logicalTextIndex(node).text.includes(text),
      );
      const index = logicalTextIndex(host),
        start = index.text.indexOf(text);
      const ranges = rangesFor(index, start, start + text.length);
      const range = document.createRange();
      range.setStart(ranges[0].startContainer, ranges[0].startOffset);
      range.setEnd(ranges.at(-1).endContainer, ranges.at(-1).endOffset);
      getSelection().removeAllRanges();
      getSelection().addRange(range);
    }, text);
    await page.locator("#reader-chat-ask").waitFor({ state: "visible" });
    await page.waitForTimeout(120);
  };
  check("Saved action is replaced", (await page.locator("#reader-codex-save").count()) === 0);
  for (const [text, id] of [
    ["Suffix case", "unicode-suffix"],
    ["Prefix case", "unicode-prefix"],
  ]) {
    await select(text);
    const opened = page.waitForResponse((response) => response.url().endsWith("/api/chat/open"));
    await page.locator("#reader-chat-ask").click();
    check(`${id} opens with a complete Unicode context`, (await opened).ok());
    const chat = page.locator(`#${id} + .reader-chat`);
    await chat.locator("textarea").waitFor({ state: "visible" });
    await chat.getByRole("button", { name: "Close conversation", exact: true }).click();
  }
  await select("First paragraph");
  await page.locator("#reader-chat-ask").click();
  const first = page.locator("#first + .reader-chat");
  await first.locator("textarea").waitFor({ state: "visible" });
  check(
    "Ask opens a composer without sending",
    (await first.locator(".reader-chat-messages").textContent()) === "",
  );
  await page.waitForTimeout(200);
  check("Empty capsule uses nearby reading-column whitespace with limited margin spill", await first.evaluate(async (root) => {
    const { documentInk, overlapsInk } = await import(new URL("features/paragraph-chat/geometry.js", location.href).href);
    const box = root.querySelector(".reader-chat-panel").getBoundingClientRect();
    const anchor = document.querySelector("#first .reader-chat-marker").getBoundingClientRect();
    const article = document.querySelector("#reader-document");
    const edge = article.getBoundingClientRect().right - parseFloat(getComputedStyle(article).paddingRight);
    return root.classList.contains("reader-chat-side") && box.right <= edge + 24 &&
      Math.hypot(Math.max(box.left - anchor.right, anchor.left - box.right, 0),
        Math.max(box.top - anchor.bottom, anchor.top - box.bottom, 0)) <= 160 &&
      !overlapsInk(box, documentInk(article));
  }));
  await page.evaluate(() => {
    const anchor = document.querySelector("#first .reader-chat-marker").getBoundingClientRect();
    const obstacle = document.createElement("figure");
    obstacle.id = "chat-local-obstacle";
    obstacle.style.cssText = `position:fixed;left:0;top:${anchor.top - 500}px;width:100vw;height:1500px;margin:0;pointer-events:none`;
    document.querySelector("#reader-document").append(obstacle);
  });
  await page.waitForFunction(() => !document.querySelector("#first + .reader-chat").classList.contains("reader-chat-side"));
  check("Blocked nearby whitespace falls below without a distant right-margin escape", await first.locator("textarea").isVisible());
  await page.locator("#chat-local-obstacle").evaluate((node) => node.remove());
  await page.waitForFunction(() => document.querySelector("#first + .reader-chat").classList.contains("reader-chat-side"));
  await first
    .locator("select[aria-label='ChatGPT model'] option[value='fixture-model']")
    .waitFor({ state: "attached" });
  check(
    "A new conversation defaults to GPT-6 Luna xhigh",
    (await first.locator("select[aria-label='ChatGPT model']").inputValue()) === "gpt-6-luna" &&
      (await first.locator("select[aria-label='ChatGPT model'] option:checked").textContent()).includes("xhigh"),
  );
  check(
    "Send is an accessible icon-only control",
    (await first.getByRole("button", { name: "보내기", exact: true }).textContent()) === "↑" &&
      (await first.locator(".reader-chat-send span").getAttribute("aria-hidden")) === "true",
  );
  check(
    "Paragraphs contain no credential controls",
    (await page.locator(".reader-chat input").count()) === 0,
  );
  await first.locator(".reader-chat-settings-open").click();
  const settings = page.locator("dialog.reader-chat-settings");
  check(
    "One shared settings dialog links account management to Homepage",
    (await settings.count()) === 1 && (await settings.textContent()).includes("Homepage"),
  );
  check(
    "Document settings never contain host proof or auth mutation buttons",
    (await page
      .locator("input[aria-label='Host authorization token'],button[data-oai-siwc-button]")
      .count()) === 0,
  );
  await settings.getByRole("button", { name: "Close ChatGPT settings", exact: true }).click();
  check(
    "Settings close restores the originating composer focus",
    await first.locator(".reader-chat-settings-open").evaluate((e) => e === document.activeElement),
  );
  await first.locator("select[aria-label='ChatGPT model']").selectOption("fixture-model");
  await first.locator("textarea").fill("Explain the first paragraph");
  await first.locator("button[type=submit]").click();
  await page.waitForFunction(
    () =>
      document.querySelector("#first + .reader-chat .reader-chat-status")?.dataset.state ===
      "completed",
  );
  check(
    "Answer safely renders model markup as text",
    (await first.locator(".reader-chat-messages img").count()) === 0 &&
      (await first.locator(".reader-chat-messages").textContent()).includes("<img src=x"),
  );
  const firstID = await first.getAttribute("data-conversation-id");
  await first.getByRole("button", { name: "Close conversation", exact: true }).click();
  await select("its own question.");
  await page.locator("#reader-chat-ask").click();
  await page.waitForFunction(
    () =>
      document.querySelector("#first + .reader-chat blockquote")?.textContent ===
      "its own question.",
  );
  check(
    "Reselecting updates the existing composer",
    (await first.getAttribute("data-conversation-id")) === firstID,
  );
  await first.locator("textarea").fill("Explain the newer selection");
  await first.locator("button[type=submit]").click();
  await page.waitForFunction(
    () =>
      document.querySelector("#first + .reader-chat .reader-chat-status")?.dataset.state ===
        "completed" &&
      document
        .querySelector("#first + .reader-chat .reader-chat-messages")
        ?.textContent.includes("Explain the newer selection"),
  );
  const reselection = (await history()).find((record) => record.conversation_id === firstID);
  check(
    "Both questions retain their immutable selected passages",
    JSON.stringify(
      reselection.thread.filter((m) => m.role === "user").map((m) => m.context.selection),
    ) === JSON.stringify(["First paragraph", "its own question."]),
  );
  check(
    "Earlier selection remains visible in history",
    (await first.locator(".reader-chat-message-context blockquote").allTextContents()).includes(
      "First paragraph",
    ),
  );
  await first.locator(".reader-chat-message-context summary").first().click();
  await control({ mode: "markdown" });
  await first.locator("textarea").fill("Format the boundary term");
  await first.locator("button[type=submit]").click();
  await page.waitForFunction(
    () =>
      document.querySelector("#first + .reader-chat .reader-chat-status")?.dataset.state ===
      "completed",
  );
  const answer = first.locator('.reader-chat-message[data-role="assistant"]').last();
  await answer.locator('.reader-chat-math[data-typeset="true"]').first().waitFor();
  check(
    "Markdown hierarchy and local MathJax render without model HTML or images",
    (await answer.locator("strong").count()) > 0 &&
      (await answer.locator("mjx-container").count()) >= 2 &&
      (await answer.locator("img,script,iframe,a[href^='javascript:']").count()) === 0,
  );
  check(
    "Code remains literal and prior context stays open through answer updates",
    (await answer.locator("pre code").textContent()).includes("<script>") &&
      (await first
        .locator(".reader-chat-message-context")
        .first()
        .evaluate((e) => e.open)),
  );
  check(
    "Late math cannot replace a newer answer and unsupported commands stay literal",
    await page.evaluate(async () => {
      const { renderChatContent } = await import(
        new URL("features/paragraph-chat/content.js", location.href).href
      );
      const math = globalThis.MathJax,
        original = math.tex2chtmlPromise;
      const target = document.createElement("div");
      document.body.append(target);
      let release, begin;
      const started = new Promise((resolve) => (begin = resolve));
      math.tex2chtmlPromise = () => {
        begin();
        return new Promise((resolve) => (release = resolve));
      };
      try {
        const old = renderChatContent(target, "\\(x\\)");
        await started;
        await renderChatContent(target, "Newer answer");
        const result = document.createElement("span");
        result.textContent = "obsolete math";
        release(result);
        await old;
        if (target.textContent !== "Newer answer") return false;
        await renderChatContent(target, "\\(\\require{html}\\)");
        return target.textContent.includes("require") && !target.querySelector("[data-typeset]");
      } finally {
        math.tex2chtmlPromise = original;
        target.remove();
      }
    }),
  );
  await control({ mode: "stall" });
  await first.locator("textarea").fill("Interrupt this response");
  await first.locator("button[type=submit]").click();
  await first.getByRole("button", { name: "Interrupt", exact: true }).waitFor({ state: "visible" });
  check(
    "Accepted question is not duplicated in the streaming composer",
    (await first.locator("textarea").inputValue()) === "" &&
      (await first.locator(".reader-chat-messages").textContent()).includes(
        "Interrupt this response",
      ),
  );
  await first.locator("button[type=submit]").evaluate((e) => e.click());
  check(
    "Streaming disables duplicate sends",
    (await history())
      .find((r) => r.conversation_id === firstID)
      .thread.filter((m) => m.role === "user" && m.text === "Interrupt this response").length === 1,
  );
  await first.getByRole("button", { name: "Interrupt", exact: true }).click();
  await page.waitForFunction(
    () =>
      document.querySelector("#first + .reader-chat .reader-chat-status")?.dataset.state ===
      "interrupted",
  );
  check(
    "Interruption preserves draft and hides the stop control",
    (await first.locator("textarea").inputValue()) === "Interrupt this response" &&
      !(await first.getByRole("button", { name: "Interrupt", exact: true }).isVisible()),
  );
  await first.locator("textarea").fill("Another interrupted question");
  await first.locator("button[type=submit]").click();
  await first.getByRole("button", { name: "Interrupt", exact: true }).waitFor({ state: "visible" });
  await first.locator("textarea").fill("A new follow-up draft");
  await first.getByRole("button", { name: "Interrupt", exact: true }).click();
  await page.waitForFunction(
    () =>
      document.querySelector("#first + .reader-chat .reader-chat-status")?.dataset.state ===
      "interrupted",
  );
  check(
    "Interruption preserves a new follow-up draft",
    (await first.locator("textarea").inputValue()) === "A new follow-up draft",
  );
  await control({ mode: "success" });
  let lostAckSends = 0;
  await page.route("**/api/chat/send", async (route) => {
    lostAckSends++;
    const accepted = await route.fetch();
    assert.ok(accepted.ok());
    const payload = route.request().postDataJSON();
    const deadline = Date.now() + 5000;
    for (;;) {
      const record = (await history()).find((r) => r.conversation_id === payload.conversationID);
      if (record.status === "completed" && record.thread.some((m) => m.id === payload.messageID))
        break;
      assert.ok(Date.now() < deadline, "Fake provider completes before acknowledgment is lost");
      await new Promise((resolve) => setTimeout(resolve, 25));
    }
    await route.fulfill({
      status: 503,
      contentType: "application/json",
      body: '{"error":"Fixture lost acknowledgment"}',
    });
  });
  await first.locator("textarea").fill("Lost acknowledgment question");
  await first.locator("button[type=submit]").click();
  await page.waitForFunction(
    () =>
      document.querySelector("#first + .reader-chat textarea")?.value === "" &&
      document.querySelector("#first + .reader-chat .reader-chat-status")?.dataset.state ===
        "completed",
  );
  await first.locator("button[type=submit]").evaluate((button) => button.click());
  const recovered = (await history()).find((record) => record.conversation_id === firstID);
  check(
    "Lost acknowledgment recovers the original completed message without resending",
    lostAckSends === 1 &&
      recovered.thread.filter((m) => m.role === "user" && m.text === "Lost acknowledgment question")
        .length === 1,
  );
  await page.unroute("**/api/chat/send");
  await first.getByRole("button", { name: "Close conversation", exact: true }).click();
  await page.waitForTimeout(500);
  const firstMarker = page.locator("#first .reader-chat-marker");
  await firstMarker.waitFor({ state: "visible" });
  check("Wide folded conversation keeps only the same inline logo", await firstMarker.evaluate((button) =>
    button.textContent === "" && button.querySelector(".reader-chat-marker-bubble").getBoundingClientRect().width === 28,
  ) && !(await first.locator(".reader-chat-summary").isVisible()));
  await page.setViewportSize({ width: 2048, height: 900 });
  await firstMarker.focus();
  await page.keyboard.press("Enter");
  await first.locator("textarea").waitFor({ state: "visible" });
  check("Long conversation falls below when nearby space is blocked, despite a wide viewport", !(await first.getAttribute("class")).includes("reader-chat-side"));
  const firstInput = first.locator("textarea");
  await firstInput.fill("Draft survives adaptive placement");
  await firstInput.evaluate((input) => {
    input.focus();
    input.setSelectionRange(6, 14);
    window.chatContinuityFixture = { input, panel: input.closest(".reader-chat-panel"), marker: document.querySelector("#first .reader-chat-marker") };
    const messages = input.closest(".reader-chat-panel").querySelector(".reader-chat-messages");
    messages.scrollTop = 60;
  });
  const transcriptScroll = await first.locator(".reader-chat-messages").evaluate((node) => node.scrollTop);
  check("Long conversation scrolls while composer remains inside its capsule", transcriptScroll > 0 && await first.evaluate((root) => {
    const panel = root.querySelector(".reader-chat-panel").getBoundingClientRect();
    return root.querySelector("textarea").getBoundingClientRect().bottom <= panel.bottom;
  }));
  for (const width of [390, 1280, 2048, 390, 2048]) {
    await page.setViewportSize({ width, height: 900 });
    await page.waitForTimeout(180);
    check(`Resize ${width} retains controls, draft, caret, model and focus`, await firstInput.evaluate((input) => {
      const saved = window.chatContinuityFixture;
      return input === saved.input && input.closest(".reader-chat-panel") === saved.panel &&
        document.querySelector("#first .reader-chat-marker") === saved.marker &&
        input.value === "Draft survives adaptive placement" && input.selectionStart === 6 && input.selectionEnd === 14 &&
        document.activeElement === input && input.closest(".reader-chat").querySelector("select").value === "fixture-model";
    }));
    check(`Resize ${width} retains transcript scroll`, Math.abs(await first.locator(".reader-chat-messages").evaluate((node) => node.scrollTop) - transcriptScroll) < 2);
  }
  const stablePlacement = await first.getAttribute("class");
  for (const width of [2100, 2048, 2300, 2048]) {
    await page.setViewportSize({ width, height: 900 });
    await page.waitForTimeout(120);
    check(`Wider screen ${width} does not send a blocked conversation to distant margin space`, (await first.getAttribute("class")) === stablePlacement);
  }
  await firstInput.fill("");
  await page.keyboard.press("Escape");
  check("Escape returns annotation focus", await firstMarker.evaluate((node) => node === document.activeElement));
  await page.keyboard.press("Space");
  check("Space opens the conversation", await first.locator("textarea").isVisible());
  await page.keyboard.press("Escape");
  await firstMarker.tap();
  check("Touch opens without changing canonical selection", await first.locator("textarea").isVisible() && await page.evaluate(() => getSelection().isCollapsed));
  await page.keyboard.press("Escape");
  await page.setViewportSize({ width: 1280, height: 850 });
  await select("second independent");
  check(
    "Terminal bridge reuses Ask",
    await page.evaluate(() => globalThis.flowReaderTerminal.action("ask")),
  );
  const second = page.locator("#second + .reader-chat");
  await second.locator("textarea").waitFor({ state: "visible" });
  check(
    "Paragraphs have independent histories",
    (await second.getAttribute("data-conversation-id")) !== firstID &&
      (await second.locator(".reader-chat-messages").textContent()) === "",
  );
  await second.locator(".reader-chat-settings-open").click();
  check(
    "Different paragraphs share the same settings destination",
    (await page.locator("dialog.reader-chat-settings").count()) === 1,
  );
  await page.getByRole("button", { name: "Close ChatGPT settings", exact: true }).click();
  check(
    "Shared settings returns focus to the second composer",
    await second
      .locator(".reader-chat-settings-open")
      .evaluate((e) => e === document.activeElement),
  );
  await second.locator("textarea").fill("An unsent durable draft");
  await page.waitForTimeout(600);
  await page.reload();
  await page.locator("#second .reader-chat-marker").waitFor();
  await page.locator("#second .reader-chat-marker").click();
  check(
    "Reload restores host draft",
    (await second.locator("textarea").inputValue()) === "An unsent durable draft",
  );
  check(
    "Conversation identity survives reopen",
    (await first.getAttribute("data-conversation-id")) === firstID,
  );
  await control({ mode: "disconnect" });
  await second
    .locator("select[aria-label='ChatGPT model'] option[value='fixture-model']")
    .waitFor({ state: "attached" });
  await second.locator("select[aria-label='ChatGPT model']").selectOption("fixture-model");
  await second.locator("button[type=submit]").click();
  await page.waitForFunction(
    () =>
      document.querySelector("#second + .reader-chat .reader-chat-status")?.dataset.state ===
      "failed",
  );
  check(
    "Failed stream preserves draft and partial state",
    (await second.locator("textarea").inputValue()) === "An unsent durable draft" &&
      (
        await second
          .locator('.reader-chat-message[data-status="failed"] .reader-chat-content')
          .textContent()
      ).includes("Incomplete"),
  );
  await control({ mode: "success" });
  await second.locator("button[type=submit]").click();
  await page.waitForFunction(
    () =>
      document.querySelector("#second + .reader-chat .reader-chat-status")?.dataset.state ===
      "completed",
  );
  await page.setViewportSize({ width: 2300, height: 900 });
  await firstMarker.click();
  await page.waitForTimeout(300);
  check("Nearby open conversations avoid overlapping capsules", await page.evaluate(() => {
    const first = document.querySelector("#first + .reader-chat");
    const second = document.querySelector("#second + .reader-chat");
    const a = first.querySelector(".reader-chat-panel").getBoundingClientRect();
    const b = second.querySelector(".reader-chat-panel").getBoundingClientRect();
    return !(a.left < b.right && a.right > b.left && a.top < b.bottom && a.bottom > b.top);
  }));
  await first.getByRole("button", { name: "Close conversation", exact: true }).click();
  await page.setViewportSize({ width: 390, height: 844 });
  await page.waitForFunction(() => document.documentElement.scrollWidth <= innerWidth + 1);
  const composerInput = second.locator("textarea");
  const compactHeight = await composerInput.evaluate((input) => input.getBoundingClientRect().height);
  check("Empty mobile composer begins compact", compactHeight <= 55);
  check("Connection control is in the conversation header", await second.locator(".reader-chat-heading .reader-chat-settings-open").isVisible());
  await composerInput.fill("First line\nSecond line\nThird line\nFourth line");
  const expandedHeight = await composerInput.evaluate((input) => input.getBoundingClientRect().height);
  check("Composer grows for multiline questions", expandedHeight > compactHeight + 20);
  await composerInput.fill("");
  check("Composer shrinks when text is cleared", (await composerInput.evaluate((input) => input.getBoundingClientRect().height)) <= 55);
  if (process.env.FLOW_READER_CHAT_MOBILE_SCREENSHOT) {
    await second.scrollIntoViewIfNeeded();
    await page.screenshot({ path: process.env.FLOW_READER_CHAT_MOBILE_SCREENSHOT });
  }
  check(
    "Mobile chat layout does not scan document ink",
    await page.evaluate(async () => {
      const original = document.createTreeWalker;
      let scans = 0;
      document.createTreeWalker = function (...args) {
        if (args[0] === document.querySelector("#reader-document")) scans++;
        return original.apply(this, args);
      };
      try {
        window.dispatchEvent(new Event("resize"));
        await new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)));
        return scans === 0;
      } finally {
        document.createTreeWalker = original;
      }
    }),
  );
  check(
    "Mobile expanded composer fits without page overflow",
    await second.evaluate((root) => {
      const b = root.getBoundingClientRect();
      return (
        b.left >= 0 &&
        b.right <= innerWidth + 1 &&
        document.documentElement.scrollWidth <= innerWidth + 1
      );
    }),
  );
  await second.getByRole("button", { name: "Close conversation", exact: true }).click();
  await page.waitForTimeout(300);
  check(
    "Narrow viewport falls back inline",
    !(await second.getAttribute("class")).includes("reader-chat-side"),
  );
  const marker = page.locator("#second > .reader-chat-anchor .reader-chat-marker");
  await marker.waitFor({ state: "visible" });
  check("Compact entry is a logo annotation with no separate block row", await marker.evaluate((button) => {
    const b = button.getBoundingClientRect();
    const image = button.querySelector("img");
    const bubble = button.querySelector(".reader-chat-marker-bubble").getBoundingClientRect();
    const panelRoot = document.querySelector("#second + .reader-chat");
    return b.width >= 44 && b.height >= 44 && bubble.width === 28 && bubble.height === 24 && image.complete && image.naturalWidth > 0 &&
      button.textContent === "" && panelRoot.getBoundingClientRect().height === 0;
  }));
  await marker.focus();
  await page.keyboard.press("Enter");
  check("Keyboard annotation opens the same paragraph capsule", await second.locator("textarea").isVisible());
  await page.keyboard.press("Escape");
  check("Closing returns focus to compact annotation", await marker.evaluate((button) => document.activeElement === button));
  await page.setViewportSize({ width: 1280, height: 850 });
  await page.waitForTimeout(200);
  check("Wide resize retains the annotation and its focus", await marker.evaluate((button) => document.activeElement === button && button.getBoundingClientRect().width === 44) && !(await second.locator(".reader-chat-summary").isVisible()));
  await page.setViewportSize({ width: 390, height: 844 });
  await page.waitForTimeout(200);
  check("Resize restores annotation without duplication", (await page.locator("#second > .reader-chat-anchor").count()) === 1 && await marker.evaluate((button) => document.activeElement === button));
  check("Copy composition excludes the inline chat annotation", await page.evaluate(async () => {
    const { selectedReaderText } = await import(new URL("features/selection/dom-selection.js", location.href).href);
    const { composeCopyText } = await import(new URL("features/selection/copy-text.js", location.href).href);
    const manifest = await (await fetch("api/state")).json();
    const range = document.createRange();
    range.selectNodeContents(document.querySelector("#second"));
    const fragments = selectedReaderText(document.querySelector("#reader-document"), manifest, range);
    return composeCopyText(fragments) === "A second independent paragraph.";
  }));
  await page.evaluate(() => {
    const old = document.querySelector("#second"), replacement = document.createElement("p");
    for (const { name, value } of old.attributes) replacement.setAttribute(name, value);
    replacement.textContent = "A second independent paragraph.";
    old.replaceWith(replacement);
  });
  await marker.waitFor({ state: "visible" });
  check("Remounted paragraph gets exactly one current annotation", (await page.locator("#second > .reader-chat-anchor").count()) === 1);
  const equationText = await page.evaluate(async () => {
    const { logicalTextIndex } = await import(new URL("rendering/math/identity.js", location.href).href);
    return logicalTextIndex(document.querySelector("#equation")).text;
  });
  await select(equationText);
  await page.locator("#reader-chat-ask").click();
  const equationChat = page.locator("#equation + .reader-chat");
  await equationChat.locator("textarea").waitFor({ state: "visible" });
  await equationChat.getByRole("button", { name: "Close conversation", exact: true }).click();
  await page.locator("#equation > .reader-chat-anchor .reader-chat-marker").waitFor({ state: "visible" });
  check("Equation annotation shares the equation row and preserves its number", await page.locator("#equation").evaluate((equation) => {
    const anchor = equation.querySelector(".reader-chat-anchor");
    return getComputedStyle(anchor).gridRowStart === "1" && getComputedStyle(anchor).gridColumnStart === "3" &&
      equation.querySelector(".flow-equation-number").textContent === "(1)";
  }));
  check(
    "Chat does not pollute canonical paragraph copy",
    await page.evaluate(async () => {
      const { logicalTextIndex } = await import(
        new URL("rendering/math/identity.js", location.href).href
      );
      return (
        logicalTextIndex(document.querySelector("#first")).text ===
        "First paragraph keeps its own question." &&
        logicalTextIndex(document.querySelector("#second")).text ===
        "A second independent paragraph."
      );
    }),
  );
  await page.setViewportSize({ width: 1280, height: 850 });
  await page.waitForTimeout(300);
  const previousArticleStyle = await page.locator("#reader-document").getAttribute("style");
  await page.locator("#reader-document").evaluate((article) => {
    article.style.maxWidth = "none";
    article.style.width = "100%";
    article.style.boxSizing = "border-box";
  });
  await marker.waitFor({ state: "visible" });
  check("Wide viewport with no margin also uses the annotation", !(await second.getAttribute("class")).includes("reader-chat-side"));
  await page.locator("#reader-document").evaluate((article, style) => {
    if (style === null) article.removeAttribute("style");
    else article.setAttribute("style", style);
  }, previousArticleStyle);
  await marker.waitFor({ state: "visible" });
  check("Annotation divider is removed", (await page.locator(".flow-side-divider").count()) === 0);
  check(
    "Meaningful annotation connector remains",
    (await page.locator(".flow-side-connector").count()) > 0,
  );
  check(
    "Short mathematical label remains near its equation",
    await page
      .locator('.flow-note[data-note-short="true"]')
      .evaluateAll((notes) =>
        notes.some(
          (note) =>
            note.dataset.noteMode === "label" &&
            note.textContent.includes("kernel") &&
            Math.abs(
              note.getBoundingClientRect().top -
                document.getElementById("equation").getBoundingClientRect().top,
            ) < 80,
        ),
      ),
  );
  check(
    "Equation identity and number remain",
    (await page.locator("#equation .flow-equation-number").textContent()) === "(1)",
  );
  check(
    "Long annotation remains in left whitespace",
    await page
      .locator(".flow-note[data-note-mode=side]")
      .evaluateAll(
        (notes) =>
          notes.length > 0 &&
          notes.every((note) => note.getBoundingClientRect().right < innerWidth / 2),
      ),
  );
  const stable = await page.evaluate(() => ({ height: document.body.scrollHeight, y: scrollY }));
  await page.waitForTimeout(600);
  check(
    "Reflow settles without a resize loop",
    await page.evaluate((prior) => Math.abs(document.body.scrollHeight - prior.height) < 2, stable),
  );
  if (process.env.FLOW_READER_CHAT_SCREENSHOT)
    await page.screenshot({ path: process.env.FLOW_READER_CHAT_SCREENSHOT, fullPage: true });
  await control({ delete: true });
  await page.reload();
  await page.locator(".reader-chat-unresolved .reader-chat-summary").waitFor();
  await page.locator(".reader-chat-unresolved .reader-chat-summary").click();
  check(
    "Deleted anchor remains accessible as unresolved",
    (await page.locator(".reader-chat-unresolved").textContent()).includes(
      "문단 위치를 확인하지 못했습니다",
    ),
  );
  check("No browser errors", errors.length === 0);
  console.log(JSON.stringify({ checks, errors }));
  await context.close();
} finally {
  await browser.close();
  fixture.kill("SIGTERM");
  await once(fixture, "exit");
  lines.close();
}
