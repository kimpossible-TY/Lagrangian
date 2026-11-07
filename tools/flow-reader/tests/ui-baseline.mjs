import assert from "node:assert/strict";
import { spawn, execFileSync } from "node:child_process";
import { once } from "node:events";
import { createInterface } from "node:readline";
import { mkdir, readFile, writeFile, copyFile, rm } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { resolve, dirname, join } from "node:path";
import { createRequire } from "node:module";

const moduleName = process.env.FLOW_READER_PLAYWRIGHT_MODULE || "playwright";
const { chromium } = await import(moduleName);
const require = createRequire(import.meta.url);
const modulePath = moduleName.startsWith("/") ? moduleName : require.resolve(moduleName);
const playwrightVersion = JSON.parse(await readFile(join(dirname(modulePath), "package.json"), "utf8")).version;
const chrome = process.env.CHROME_BIN || "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const root = resolve(".local/ui-baseline");
const update = process.argv.includes("--update-baseline");
const contractOnly = process.argv.includes("--contract-only");
const fixtures = [];
let browser;
async function startFixture(file) {
  const child = spawn(process.env.PYTHON || "python3", ["-B", fileURLToPath(new URL(file, import.meta.url))], {
    stdio: ["ignore", "pipe", "inherit"],
    env: { ...process.env, PYTHONPATH: [fileURLToPath(new URL("..", import.meta.url)), process.env.PYTHONPATH].filter(Boolean).join(":") },
  });
  fixtures.push(child);
  const lines = createInterface({ input: child.stdout });
  return await new Promise((resolve, reject) => {
    lines.once("line", (line) => { try { resolve(JSON.parse(line)); } catch (error) { reject(error); } });
    child.once("error", reject);
    child.once("exit", (code) => reject(new Error(`Fixture exited: ${code}`)));
  });
}
async function rendered(page, selectors) {
  for (const selector of selectors) assert.ok(await page.locator(selector).count(), `Missing rendered selector: ${selector}`);
}
async function settle(page) {
  await page.evaluate(() => document.fonts.ready);
  await page.addStyleTag({ content: "*, *::before, *::after { animation: none !important; transition: none !important; caret-color: transparent !important; }" });
}
async function openChat(page) {
  await page.evaluate(async () => {
    const { logicalTextIndex, rangesFor } = await import(new URL("rendering/math/identity.js", location.href).href);
    const node = document.querySelector("#first"), index = logicalTextIndex(node);
    const ranges = rangesFor(index, 0, "First paragraph".length), range = document.createRange();
    range.setStart(ranges[0].startContainer, ranges[0].startOffset);
    range.setEnd(ranges.at(-1).endContainer, ranges.at(-1).endOffset);
    getSelection().removeAllRanges();
    getSelection().addRange(range);
  });
  await page.locator("#reader-chat-ask").waitFor({ state: "visible" });
  await page.locator("#reader-chat-ask").click();
  await page.locator("#first + .reader-chat textarea").waitFor({ state: "visible" });
  await page.locator("#first + .reader-chat select[aria-label='ChatGPT model'] option[value='fixture-model']").waitFor({ state: "attached" });
  await rendered(page, ["#first[data-reader-key] + .reader-chat", "#first + .reader-chat .reader-chat-messages", "#first + .reader-chat select[aria-label='ChatGPT model']", "#first + .reader-chat button[type=submit]"]);
}
async function compare(page, baseline, current, diff) {
  await rm(diff, { force: true });
  let before;
  try { before = await readFile(baseline); } catch (error) { if (error.code === "ENOENT") return { status: "missing-baseline" }; throw error; }
  const after = await readFile(current);
  const result = await page.evaluate(async ([a, b]) => {
    const image = async (base64) => { const img = new Image(); img.src = `data:image/png;base64,${base64}`; await img.decode(); return img; };
    const [left, right] = await Promise.all([image(a), image(b)]);
    if (left.width !== right.width || left.height !== right.height) return { status: "size-mismatch", baselineSize: [left.width, left.height], currentSize: [right.width, right.height] };
    const canvas = document.createElement("canvas"); canvas.width = left.width; canvas.height = left.height;
    const ctx = canvas.getContext("2d", { willReadFrequently: true });
    ctx.drawImage(left, 0, 0); const x = ctx.getImageData(0, 0, canvas.width, canvas.height);
    ctx.clearRect(0, 0, canvas.width, canvas.height); ctx.drawImage(right, 0, 0); const y = ctx.getImageData(0, 0, canvas.width, canvas.height);
    const out = ctx.createImageData(canvas.width, canvas.height); let changed = 0;
    for (let i = 0; i < x.data.length; i += 4) {
      const different = x.data[i] !== y.data[i] || x.data[i+1] !== y.data[i+1] || x.data[i+2] !== y.data[i+2] || x.data[i+3] !== y.data[i+3];
      if (different) changed++;
      out.data[i] = different ? 255 : y.data[i] * 0.25; out.data[i+1] = different ? 0 : y.data[i+1] * 0.25; out.data[i+2] = different ? 0 : y.data[i+2] * 0.25; out.data[i+3] = 255;
    }
    ctx.putImageData(out, 0, 0);
    return { status: changed ? "different" : "match", changedPixels: changed, totalPixels: canvas.width * canvas.height, png: canvas.toDataURL("image/png").split(",")[1] };
  }, [before.toString("base64"), after.toString("base64")]);
  if (result.png) { await writeFile(diff, Buffer.from(result.png, "base64")); delete result.png; }
  return result;
}
try {
  const home = await startFixture("./home_fixture.py"), reader = await startFixture("./paragraph_chat_fixture.py");
  browser = await chromium.launch({ headless: true, executablePath: chrome });
  const metadata = { chrome: browser.version(), playwright: playwrightVersion, commit: execFileSync("git", ["rev-parse", "HEAD"], { encoding: "utf8" }).trim(), dirty: Boolean(execFileSync("git", ["status", "--porcelain"], { encoding: "utf8" }).trim()), deviceScaleFactor: 1, locale: "en-US", timezone: "UTC", viewports: { desktop: { width: 1280, height: 800 }, mobile: { width: 390, height: 844 } } };
  const report = { metadata, results: [] };
  if (!contractOnly) for (const dir of ["baseline", "current", "diff"]) await mkdir(join(root, dir), { recursive: true });
  for (const [size, viewport] of Object.entries(metadata.viewports)) for (const theme of ["light", "dark"]) {
    // Test-only: allow settle() to inject its deterministic capture styles under the app's CSP.
    const context = await browser.newContext({ viewport, deviceScaleFactor: 1, locale: metadata.locale, timezoneId: metadata.timezone, colorScheme: theme, reducedMotion: "reduce", serviceWorkers: "block", bypassCSP: true });
    const allowed = new Set([new URL(home.url).origin, new URL(reader.url).origin]);
    const blocked = [];
    await context.route("**/*", async (route) => {
      const url = new URL(route.request().url());
      if (!allowed.has(url.origin)) { blocked.push(url.origin); await route.abort(); return; }
      if (url.pathname === "/api/home/documents") {
        const response = await route.fetch(), body = await response.json(); body.checkedAt = 1700000000;
        await route.fulfill({ response, json: body });
      } else await route.continue();
    });
    const page = await context.newPage();
    const errors = [];
    page.on("pageerror", (error) => errors.push(error.message));
    await page.clock.install({ time: new Date("2024-01-01T00:00:00Z") });
    async function capture(name) {
      await settle(page);
      if (!contractOnly) {
        const key = `${size}-${theme}-${name}`, current = join(root, "current", `${key}.png`), baseline = join(root, "baseline", `${key}.png`), diff = join(root, "diff", `${key}.png`);
        await page.screenshot({ path: current, animations: "disabled" });
        if (update) { report.results.push({ key, status: "baseline-updated" }); }
        else report.results.push({ key, ...await compare(page, baseline, current, diff) });
      }
    }
    await page.goto(home.url); await page.locator(".document-card").first().waitFor();
    await rendered(page, ["#document-list .document-card", ".document-card .reader-link"]); await capture("home");
    await page.goto(reader.url + "?terminal=1");
    await page.waitForFunction(() => document.querySelector("#first[data-reader-key]") && document.querySelector("#reader-document").getAttribute("aria-busy") === "false");
    await rendered(page, ["#reader-document #first[data-reader-key]", "#reader-document #equation .flow-equation-number"]); await capture("reader");
    await openChat(page); await capture("chat");
    assert.deepEqual(errors, [], "Browser page errors");
    assert.deepEqual(blocked, [], "Unexpected network requests");
    await context.close();
  }
  if (!contractOnly) {
    await writeFile(join(root, "report.json"), JSON.stringify(report, null, 2) + "\n");
    if (update) {
      for (const { key } of report.results) await copyFile(join(root, "current", `${key}.png`), join(root, "baseline", `${key}.png`));
      await writeFile(join(root, "baseline", "version.json"), JSON.stringify(metadata, null, 2) + "\n");
    }
    console.log(`Report: ${join(root, "report.json")}`);
  } else console.log("Rendered selector contract passed");
} finally {
  if (browser) await browser.close();
  for (const child of fixtures) if (child.exitCode === null && child.signalCode === null) { child.kill("SIGTERM"); await once(child, "exit"); }
}
