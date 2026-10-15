// Disposable real-engine benchmark. Desktop timings are not iPhone measurements.
// PREVIEW_FRONTEND_HTML selects a built frontend without replacing the installed engine.
// PREVIEW_BROWSER=webkit uses an installed Playwright WebKit build; default: local Chrome.
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { mkdtemp, readFile, realpath, rm, writeFile } from "node:fs/promises";
import { homedir, tmpdir } from "node:os";
import { createServer, request } from "node:http";
import { resolve } from "node:path";
import { setTimeout as delay } from "node:timers/promises";

const root = resolve(import.meta.dirname, "../..");
const engine = process.argv[2];
assert.ok(engine, "Pass a preview engine executable");
const playwright = await import(
  process.env.PLAYWRIGHT_MODULE ||
    resolve(
      homedir(),
      ".cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright/index.mjs",
    )
);
const frontendPath =
  process.env.PREVIEW_FRONTEND_HTML ||
  resolve(root, "tools/typst-preview-frontend/dist/index.html");
const frontend = await readFile(frontendPath, "utf8");
const temp = await realpath(await mkdtemp(resolve(tmpdir(), "flow-performance-")));
const file = resolve(temp, "main.typ");
const pageCount = 300;
const source = (revision) => `#let dark = sys.inputs.at("theme", default: "light") == "dark"
#set page(width: 420pt, height: 620pt, margin: 30pt, fill: if dark { rgb("17212f") } else { white })
#set text(size: 11pt, fill: if dark { white } else { black })
${Array.from(
  { length: pageCount },
  (_, i) => `${i ? "#pagebreak()" : ""}
= Reading page ${i + 1}
${i === 0 ? `Revision ${revision}.` : "Unchanged passage."}
${Array.from({ length: 5 }, (_, row) => `Paragraph ${row + 1} on page ${i + 1}. A smooth preview keeps the current passage available while the document is updated.\n\n$ integral_0^1 x^${row + 1} dif x = 1/${row + 2} $`).join("\n\n")}`,
).join("\n")}
`;
await writeFile(file, source(0));
let child,
  browser,
  proxy,
  logs = "";
const errors = [];
const until = async (predicate, label) => {
  const deadline = Date.now() + 60000;
  while (Date.now() < deadline) {
    const value = await predicate();
    if (value) return value;
    if (child.exitCode !== null || child.signalCode !== null) throw new Error(logs);
    await delay(25);
  }
  throw new Error(`Timeout: ${label}\n${logs.slice(-3000)}`);
};
const settle = async (page) => {
  await page.waitForFunction(
    () => {
      const d = document.getElementById("typst-container")?.documents?.[0]?.impl;
      return (
        d?.moduleInitialized &&
        !d.isRendering &&
        !d.patchQueue.length &&
        d.vpTimeout === undefined &&
        !d.svgResizeAnchor &&
        document.getElementById("typst-preview-status").hidden &&
        document.querySelectorAll(".typst-touch-selection-line").length > 0
      );
    },
    null,
    { timeout: 60000 },
  );
  await page.evaluate(
    () => new Promise((done) => requestAnimationFrame(() => requestAnimationFrame(done))),
  );
};
const counters = (page) => page.evaluate(() => structuredClone(window.previewPerf));

try {
  child = spawn(
    engine,
    [
      "preview",
      file,
      "--root",
      temp,
      "--no-open",
      "--follow-system-theme",
      "--partial-rendering=true",
      "--data-plane-host=127.0.0.1:0",
      "--control-plane-host=127.0.0.1:0",
    ],
    {
      env: {
        ...process.env,
        TINYMIST_ALLOWED_ORIGINS: "",
        TINYMIST_PREVIEW_FOCUS_FILE: resolve(temp, "focus.json"),
        TINYMIST_PREVIEW_CHANGE_FILE: resolve(temp, "changes.json"),
      },
      stdio: ["ignore", "pipe", "pipe"],
    },
  );
  child.stdout.on("data", (data) => (logs += data));
  child.stderr.on("data", (data) => (logs += data));
  child.on("error", (error) => (logs += error.message));
  const address = await until(
    () => /Data plane server listening on: (127\.0\.0\.1:\d+)/.exec(logs)?.[1],
    "listener",
  );
  // Serve a real loopback response: request interception can change Chrome's
  // address-space classification and block a same-host WebSocket handshake.
  let browserAddress;
  proxy = createServer((_req, res) => {
    res.setHeader("Content-Type", "text/html");
    res.end(
      frontend
        .replaceAll("ws://127.0.0.1:23625", `ws://${browserAddress}`)
        .replaceAll("preview-arg:systemTheme:false", "preview-arg:systemTheme:true"),
    );
  });
  proxy.on("upgrade", (req, socket, head) => {
    const upstream = request(`http://${address}${req.url}`, {
      headers: { ...req.headers, host: address, origin: `http://${address}` },
    });
    upstream.on("upgrade", (response, peer, peerHead) => {
      socket.write(
        `HTTP/1.1 101 Switching Protocols\r\n${Object.entries(response.headers)
          .map(([key, value]) => `${key}: ${value}`)
          .join("\r\n")}\r\n\r\n`,
      );
      if (head.length) peer.write(head);
      if (peerHead.length) socket.write(peerHead);
      socket.pipe(peer).pipe(socket);
      socket.on("error", () => peer.destroy());
      peer.on("error", () => socket.destroy());
      socket.on("close", () => peer.destroy());
    });
    upstream.on("error", () => socket.destroy());
    upstream.end();
  });
  await new Promise((done) => proxy.listen(0, "127.0.0.1", done));
  browserAddress = `127.0.0.1:${proxy.address().port}`;
  const browserName = process.env.PREVIEW_BROWSER || "chromium";
  browser = await playwright[browserName].launch({
    headless: true,
    ...(browserName === "chromium" ? { channel: "chrome" } : {}),
  });
  const context = await browser.newContext({
    viewport: { width: 393, height: 852 },
    hasTouch: true,
    isMobile: true,
    deviceScaleFactor: 3,
    colorScheme: "light",
  });
  const page = await context.newPage();
  page.on("pageerror", (error) => errors.push(error.message));
  let consoleErrors = 0;
  page.on("console", (message) => {
    if (message.type() === "error" && consoleErrors++ < 5) console.error(message.text());
  });
  await page.addInitScript(() => {
    const metrics = (window.previewPerf = {
      calls: {},
      ms: {},
      frames: [],
      ready: [],
      layouts: 0,
      opens: 0,
    });
    const original = WebSocket;
    window.previewSockets = [];
    window.WebSocket = class extends original {
      constructor(...args) {
        super(...args);
        window.previewSockets.push(this);
        this.addEventListener("open", () => {
          metrics.opens++;
        });
        this.addEventListener("message", ({ data }) => {
          if (!(data instanceof ArrayBuffer)) return;
          const bytes = new Uint8Array(data);
          const kind = new TextDecoder().decode(bytes.subarray(0, bytes.indexOf(44)));
          if (kind === "new" || kind === "diff-v1")
            metrics.frames.push({ kind, bytes: bytes.length, at: performance.now() });
        });
      }
    };
    let session;
    Object.defineProperty(window, "TypstRenderSession", {
      configurable: true,
      get: () => session,
      set: (value) => {
        session = value;
        for (const name of ["manipulateData", "render_in_window", "retrievePagesInfo"]) {
          const original = value.prototype[name];
          value.prototype[name] = function (...args) {
            const start = performance.now();
            try {
              return original.apply(this, args);
            } finally {
              metrics.calls[name] = (metrics.calls[name] || 0) + 1;
              metrics.ms[name] = (metrics.ms[name] || 0) + performance.now() - start;
            }
          };
        }
      },
    });
    document.addEventListener("typst-text-layout", () => metrics.layouts++, true);
    let last = 0;
    const sample = () => {
      const d = document.getElementById("typst-container")?.documents?.[0]?.impl;
      if (
        metrics.frames.length > last &&
        d?.moduleInitialized &&
        !d.isRendering &&
        !d.patchQueue.length &&
        document.getElementById("typst-preview-status").hidden &&
        document.querySelector(".typst-touch-selection-line")
      ) {
        last = metrics.frames.length;
        metrics.ready.push({
          frame: last,
          at: performance.now(),
          afterFrameMs: performance.now() - metrics.frames.at(-1).at,
        });
      }
      requestAnimationFrame(sample);
    };
    requestAnimationFrame(sample);
  });
  await page.goto(`http://${browserAddress}/`);
  await settle(page);
  assert.equal(await page.locator(".typst-page-inner").count(), pageCount);
  const initial = await counters(page);

  // Keep the visible page range fixed while exercising actual scroll events.
  const start = await counters(page);
  await page.evaluate(() => {
    window.firstSelectionLine = document.querySelector(".typst-touch-selection-line");
  });
  for (let step = 0; step < 12; step++) {
    await page.evaluate(
      (top) => {
        document.getElementById("typst-container-main").scrollTop = top;
      },
      10 + step * 3,
    );
    await delay(100);
    await settle(page);
  }
  const end = await counters(page);
  const scrolling = {
    svgCalls: (end.calls.render_in_window || 0) - (start.calls.render_in_window || 0),
    svgMs: (end.ms.render_in_window || 0) - (start.ms.render_in_window || 0),
    layouts: end.layouts - start.layouts,
    retainedSelectionNode: await page.evaluate(
      () => window.firstSelectionLine === document.querySelector(".typst-touch-selection-line"),
    ),
  };
  if (process.env.PERFORMANCE_VERIFY_REUSE === "1") {
    assert.equal(scrolling.svgCalls, 0, "same-window scroll must reuse rendered content");
    assert.equal(scrolling.layouts, 0, "same-window scroll must retain selection layout");
    assert.equal(scrolling.retainedSelectionNode, true);
  }

  const updates = [];
  for (let revision = 1; revision <= 3; revision++) {
    const before = await counters(page);
    const start = await page.evaluate(() => performance.now());
    await writeFile(file, source(revision));
    await page.waitForFunction(
      (count) => window.previewPerf.ready.length > count,
      before.ready.length,
    );
    await settle(page);
    const after = await counters(page);
    assert.match(
      await page.locator(".typst-touch-selection").innerText(),
      new RegExp(`Revision ${revision}`),
    );
    updates.push({
      editToReadyMs: after.ready.at(-1).at - start,
      frameToReadyMs: after.ready.at(-1).afterFrameMs,
      svgCalls: after.calls.render_in_window - before.calls.render_in_window,
    });
  }

  // A selected range must keep both visible text and ordered deltas frozen.
  await page.evaluate(() => {
    const line = [...document.querySelectorAll(".typst-touch-selection-line")].find((line) =>
      line.textContent.includes("Revision"),
    );
    const range = document.createRange();
    range.selectNodeContents(line);
    getSelection().removeAllRanges();
    getSelection().addRange(range);
  });
  const held = await counters(page);
  await writeFile(file, source(4));
  await page.waitForFunction(
    (count) => window.previewPerf.frames.length > count,
    held.frames.length,
  );
  await delay(150);
  assert.equal((await counters(page)).calls.manipulateData, held.calls.manipulateData);
  assert.match(await page.locator(".typst-touch-selection").innerText(), /Revision 3/);
  await page.waitForFunction(
    () => document.getElementById("typst-preview-status").dataset.phase === "selection-held",
  );
  const release = page.getByRole("button", { name: "Clear selection and update" });
  assert.equal(await release.isVisible(), true);
  assert.equal(
    await page
      .locator(".typst-preview-status-ring")
      .evaluate((ring) => getComputedStyle(ring).display),
    "none",
  );
  assert.equal(await page.locator("#typst-preview-status").getAttribute("data-busy"), "false");
  // Pressing must retain the selection until explicit activation, without hiding the button.
  await release.dispatchEvent("pointerdown");
  assert.match(await page.evaluate(() => getSelection().toString()), /Revision 3/);
  await release.tap();
  await settle(page);
  assert.equal(await page.evaluate(() => getSelection().isCollapsed), true);
  assert.equal(await release.isVisible(), false);
  assert.match(await page.locator(".typst-touch-selection").innerText(), /Revision 4/);

  await page.evaluate(() => {
    const range = document.createRange();
    range.selectNodeContents(document.querySelector(".typst-touch-selection-line"));
    getSelection().removeAllRanges();
    getSelection().addRange(range);
  });
  await writeFile(file, source(4) + "\nKeyboard activation check.\n");
  await release.waitFor({ state: "visible" });
  await release.focus();
  await page.keyboard.press("Enter");
  await settle(page);
  assert.equal(await page.evaluate(() => getSelection().isCollapsed), true);
  assert.equal(await release.isVisible(), false);

  // Crossing pages and changing zoom must invalidate the appropriate caches.
  for (const number of [150, 299, 1]) {
    await page.evaluate((number) => {
      const scroller = document.getElementById("typst-container-main");
      const rect = document
        .querySelector(`.typst-page-inner[data-page-number="${number - 1}"]`)
        .getBoundingClientRect();
      scroller.scrollTop += rect.top - scroller.getBoundingClientRect().top;
      document.getElementById("typst-container").documents[0].addViewportChange();
    }, number);
    await settle(page);
    assert.match(
      await page.locator(".typst-touch-selection").innerText(),
      new RegExp(`Reading page ${number}`),
    );
  }
  await page.evaluate(() => {
    const d = document.getElementById("typst-container").documents[0];
    d.impl.currentScaleRatio = 1.25;
    d.addViewportChange();
  });
  await settle(page);
  await page.selectOption(".typst-theme-selector", "dark");
  await settle(page);
  assert.equal(
    await page.evaluate(
      () => document.getElementById("typst-container").documents[0].impl.currentScaleRatio,
    ),
    1.25,
  );
  const opens = (await counters(page)).opens;
  await page.evaluate(() => window.previewSockets.at(-1).close());
  await page.waitForFunction((opens) => window.previewPerf.opens > opens, opens);
  await settle(page);
  assert.match(await page.locator(".typst-touch-selection").innerText(), /Revision 4/);
  assert.deepEqual(errors, []);
  const result = {
    browser: browserName,
    version: browser.version(),
    device: "desktop, 393x852 touch emulation",
    engine,
    frontendPath,
    frontendBytes: Buffer.byteLength(frontend),
    pageCount,
    initial: {
      navigationToReadyMs: initial.ready[0].at,
      frameToReadyMs: initial.ready[0].afterFrameMs,
      documentBytes: initial.frames[0].bytes,
      calls: initial.calls,
      ms: initial.ms,
    },
    scrolling,
    updates,
    verified: [
      "live edits",
      "selection hold/release",
      "distant pages",
      "zoom",
      "theme",
      "reconnect",
    ],
  };
  if (process.env.PERFORMANCE_OUTPUT)
    await writeFile(process.env.PERFORMANCE_OUTPUT, `${JSON.stringify(result, null, 2)}\n`);
  console.log(JSON.stringify(result, null, 2));
} catch (error) {
  console.error(logs.slice(-5000), errors);
  const page = browser?.contexts()[0]?.pages()[0];
  if (page)
    console.error(
      await page.evaluate(() => ({
        status: document.getElementById("typst-preview-status")?.outerHTML,
        pages: document.querySelectorAll(".typst-page-inner").length,
        lines: document.querySelectorAll(".tsel").length,
        overlays: document.querySelectorAll(".typst-touch-selection-line").length,
        coarse: matchMedia("(pointer: coarse)").matches,
        metrics: window.previewPerf,
      })),
    );
  throw error;
} finally {
  await browser?.close();
  proxy?.closeAllConnections();
  proxy?.close();
  if (child && child.exitCode === null && child.signalCode === null) {
    const exited = new Promise((done) => child.once("exit", done));
    child.kill("SIGINT");
    await Promise.race([exited, delay(5000)]);
    if (child.exitCode === null && child.signalCode === null) {
      child.kill("SIGKILL");
      await exited;
    }
  }
  await rm(temp, { recursive: true, force: true });
}
