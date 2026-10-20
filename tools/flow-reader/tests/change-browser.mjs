// Run with FLOW_READER_PACKAGES and an installed Playwright module.
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { createInterface } from "node:readline";
import { once } from "node:events";
import { fileURLToPath } from "node:url";

const { webkit } = await import(process.env.FLOW_READER_PLAYWRIGHT_MODULE || "playwright");
const fixture = spawn(
  process.env.PYTHON || "python3",
  [fileURLToPath(new URL("./change_fixture.py", import.meta.url))],
  { stdio: ["ignore", "pipe", "inherit"] },
);
const lines = createInterface({ input: fixture.stdout });
const url = await new Promise((resolve, reject) => {
  lines.once("line", (line) => resolve(JSON.parse(line).url));
  fixture.once("exit", (code) => reject(new Error(`Fixture exited: ${code}`)));
});
const browser = await webkit.launch({ headless: true }).catch((error) => {
  fixture.kill("SIGTERM");
  throw error;
});
const page = await browser.newPage({ viewport: { width: 390, height: 844 }, locale: "ko-KR" });
const errors = [];
page.on("pageerror", (error) => errors.push(error.message));
const checks = [];
const check = (name) => {
  checks.push(name);
  process.stdout.write(`PASS ${name}\n`);
};
const edit = async (step) => {
  const response = await page.request.post(url + "api/test-edit", { data: { step } });
  assert.ok(response.ok());
  return response.json();
};
const target = () =>
  page.locator("#reader-document p").filter({ hasText: /^Edited passage version/ });
const aligned = async (name) => {
  await page
    .waitForFunction(
      () => {
        const rect = [...document.querySelectorAll("#reader-document p")]
          .find((node) => node.textContent.startsWith("Edited passage version"))
          ?.getBoundingClientRect();
        return rect && rect.top >= 70 && rect.bottom <= innerHeight;
      },
      null,
      { timeout: 15000 },
    )
    .catch(async (error) => {
      process.stdout.write(
        JSON.stringify(
          await page.evaluate(async () => ({
            scrollY,
            target: [...document.querySelectorAll("#reader-document p")]
              .filter((node) => node.textContent.startsWith("Edited passage version"))
              .map((node) => ({ text: node.textContent, top: node.getBoundingClientRect().top })),
            hint: await fetch("api/manifest")
              .then((response) => response.json())
              .then((value) => value.lastChange),
            status: document.querySelector("#reader-status").textContent,
            button: !document.querySelector("#reader-change-jump").hidden,
          })),
        ) + "\n",
      );
      throw error;
    });
  check(name);
};
const ready = () =>
  page.waitForFunction(
    () =>
      document.querySelector("#reader-document [data-reader-key]") &&
      document.querySelector("#reader-document").getAttribute("aria-busy") === "false",
  );
let entry = 0;
const away = async () => {
  await page.goto(url + `?entry=${++entry}#first`);
  await ready();
  await page
    .waitForFunction(
      () => {
        const rect = document.getElementById("first")?.getBoundingClientRect();
        return rect && rect.top >= 0 && rect.bottom <= innerHeight;
      },
      null,
      { timeout: 15000 },
    )
    .catch(async (error) => {
      process.stdout.write(
        JSON.stringify(
          await page.evaluate(() => ({
            url: location.href,
            scrollY,
            first: document.getElementById("first")?.outerHTML,
            firstTop: document.getElementById("first")?.getBoundingClientRect().top,
            headings: [...document.querySelectorAll("#reader-document h2")].map(
              (node) => node.outerHTML,
            ),
            status: document.querySelector("#reader-status").textContent,
            history: history.state,
          })),
        ) + "\n",
      );
      throw error;
    });
};
try {
  await page.goto(url);
  await ready();
  await edit(1);
  await aligned("live accepted edit follows the distant body target");
  await away();
  await page.waitForTimeout(400);
  await page.reload();
  await aligned("reload prioritizes the saved visual edit over the stored reading position");
  await away();
  assert.equal(await page.locator("#reader-change-jump").isVisible(), false);
  check("an explicit named link retains its destination");
  await page.locator("#reader-menu").click();
  await page.locator('#reader-outline a[href="#last"]').click();
  await page.waitForFunction(() => {
    const rect = document.getElementById("last")?.getBoundingClientRect();
    return rect && rect.top >= 0 && rect.bottom <= innerHeight;
  });
  await page.goBack();
  await page.waitForFunction(() => {
    const rect = document.getElementById("first")?.getBoundingClientRect();
    return rect && rect.top >= 0 && rect.bottom <= innerHeight;
  });
  assert.equal(await page.locator("#reader-change-jump").isVisible(), false);
  check("browser history retains the prior reading entry without replaying the edit");

  // Hold gestures across the polling boundary, then use the deferred button.
  await page.evaluate(() => {
    window.gestureTimer = setInterval(
      () => document.dispatchEvent(new WheelEvent("wheel", { bubbles: true })),
      150,
    );
  });
  await edit(2);
  await page.locator("#reader-change-jump").waitFor({ state: "visible", timeout: 15000 });
  await page.evaluate(() => clearInterval(window.gestureTimer));
  assert.ok(await page.locator("#first").isVisible());
  check("recent scrolling preserves the current passage and exposes the change button");
  await page.setViewportSize({ width: 320, height: 844 });
  const buttonBounds = await page.locator("#reader-change-jump").boundingBox();
  assert.ok(buttonBounds.x >= 0 && buttonBounds.x + buttonBounds.width <= 320);
  check("the deferred button fits a 320px reading viewport");
  await page.locator("#reader-change-jump").click();
  await aligned("the button mounts and reveals the latest edited section");
  assert.equal(await page.locator("#reader-change-jump").isVisible(), false);
  await page.setViewportSize({ width: 390, height: 844 });

  await away();
  // A network interruption must retain reading state without replaying resume.
  await page.route("**/api/state", (route) =>
    route.fulfill({ status: 503, body: "Temporarily unavailable" }),
  );
  await page.waitForTimeout(3300);
  await page.unroute("**/api/state");
  await page.waitForTimeout(3300);
  assert.ok(await page.locator("#first").isVisible());
  assert.equal(await page.locator("#reader-change-jump").isVisible(), false);
  check("connection recovery does not replay an observed edit");
  await page.locator("#reader-appearance-open").click();
  await page.locator('label:has(input[name="reader-appearance"][value="dark"])').click();
  await page.locator("#reader-larger").click();
  await page.keyboard.press("Escape");
  await page.waitForTimeout(400);
  assert.ok(await page.locator("#first").isVisible());
  assert.equal(await page.locator("#reader-change-jump").isVisible(), false);
  check("appearance and font changes do not replay an observed edit");

  // The reader must recheck gestures after the remote target was requested.
  let release;
  let fetched;
  const requested = new Promise((resolve) => {
    fetched = resolve;
  });
  await page.route("**/api/sections/section-15?*", async (route) => {
    fetched();
    await new Promise((resolve) => {
      release = resolve;
    });
    await route.continue();
  });
  await page.waitForTimeout(2700);
  await edit(3);
  await requested;
  await page.evaluate(() => document.dispatchEvent(new WheelEvent("wheel", { bubbles: true })));
  release();
  await page.locator("#reader-change-jump").waitFor({ state: "visible", timeout: 15000 });
  assert.ok(await page.locator("#first").isVisible());
  await page.unroute("**/api/sections/section-15?*");
  await page.locator("#reader-change-jump").click();
  await aligned("a gesture during target loading defers the pending jump");

  await away();
  await page.evaluate(() => {
    const node = document.querySelector("#reader-document p");
    const range = document.createRange();
    range.selectNodeContents(node);
    getSelection().removeAllRanges();
    getSelection().addRange(range);
  });
  const selected = await page.evaluate(() => getSelection().toString());
  await edit(4);
  await page.waitForTimeout(3500);
  assert.equal(await page.evaluate(() => getSelection().toString()), selected);
  assert.ok(await page.locator("#first").isVisible());
  await page.evaluate(() => getSelection().removeAllRanges());
  await aligned("active text selection survives until release before following an edit");

  const beforeComment = await page.request.get(url + "api/manifest").then((r) => r.json());
  await edit("comment");
  await page.waitForTimeout(3500);
  const afterComment = await page.request.get(url + "api/manifest").then((r) => r.json());
  assert.equal(afterComment.lastChange.token, beforeComment.lastChange.token);
  assert.equal(await page.locator("#reader-change-jump").isVisible(), false);
  check("a nonvisual saved comment retains the last-edit token");
  const beforeFailure = afterComment.revision;
  await edit("failure");
  await page.waitForTimeout(3500);
  assert.equal(
    (await page.request.get(url + "api/manifest").then((r) => r.json())).revision,
    beforeFailure,
  );
  assert.ok((await target().textContent()).includes("version 4"));
  check("a failed compilation retains the accepted document and history");

  for (const [step, name] of [
    [5, "an inserted short note becomes the automatic change destination"],
    [6, "an edited unwrapped note body becomes the change destination"],
    [7, "a title-only note edit becomes the change destination"],
  ]) {
    await away();
    await page.waitForTimeout(2700);
    await edit(step);
    const hint = await page.request.get(url + "api/manifest").then((r) => r.json());
    assert.ok(hint.lastChange?.target.startsWith("reader-callout-"));
    await page.waitForFunction(
      (id) => {
        const rect = document.getElementById(id)?.getBoundingClientRect();
        return rect && rect.top >= 0 && rect.bottom <= innerHeight;
      },
      hint.lastChange.target,
      { timeout: 15000 },
    );
    await page.waitForTimeout(1200);
    const noteBounds = await page.locator(`#${hint.lastChange.target}`).boundingBox();
    assert.ok(noteBounds.y >= 0 && noteBounds.y + noteBounds.height <= 844, name);
    assert.ok(
      await page
        .locator(`#${hint.lastChange.target}`)
        .evaluate(
          (node) =>
            node.classList.contains("flow-note") && node.textContent.includes("Green function"),
        ),
    );
    check(name);
  }
  assert.deepEqual(errors, []);
  process.stdout.write(JSON.stringify({ passed: checks.length, errors }) + "\n");
} finally {
  await browser.close();
  lines.close();
  if (fixture.exitCode === null) {
    fixture.kill("SIGTERM");
    await once(fixture, "exit");
  }
}
