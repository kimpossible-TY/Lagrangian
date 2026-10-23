// Real documents and WebKit; synthetic lifecycle events cannot reproduce physical iOS suspension.
// PREVIEW_PROBE_PROXY=1 negotiates the additive probe through a transport fixture for older engines.
// PREVIEW_DESKTOP=1 also verifies desktop SVG text selection rather than the mobile overlay.
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { mkdtemp, readFile, realpath, rm, writeFile } from "node:fs/promises";
import { homedir, tmpdir } from "node:os";
import { createServer } from "node:http";
import { resolve } from "node:path";
import { setTimeout as delay } from "node:timers/promises";
import WebSocket, { WebSocketServer } from "ws";

const engine = process.argv[2];
assert.ok(engine, "Pass a preview engine executable");
const desktop = process.env.PREVIEW_DESKTOP === "1";
const playwright = await import(
  process.env.PLAYWRIGHT_MODULE ||
    resolve(
      homedir(),
      ".cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright/index.mjs",
    )
);
const temp = await realpath(await mkdtemp(resolve(tmpdir(), "flow-background-recovery-")));
const file = resolve(temp, "main.typ");
const frontend = await readFile(
  new URL("../../tools/typst-preview-frontend/dist/index.html", import.meta.url),
  "utf8",
);
const source = (revision) => `#set page(width: 320pt, height: 440pt)
#let theme = sys.inputs.at("theme", default: "light")
${Array.from({ length: 20 }, (_, i) => `${i ? "#pagebreak()" : ""}\n= Page ${i + 1}\nRevision ${revision}. A readable passage survives reconnection.`).join("\n")}
`;
await writeFile(file, source(0));
let child;
let logs = "",
  address,
  browserAddress,
  browser,
  hold = false,
  blackhole = false;
const startEngine = () => {
  logs = "";
  address = undefined;
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
};
const stopEngine = async () => {
  if (child.exitCode !== null || child.signalCode !== null) return;
  const exited = new Promise((done) => child.once("exit", done));
  child.kill("SIGTERM");
  await exited;
};
startEngine();
const pairs = new Set();
const emulateProbe = process.env.PREVIEW_PROBE_PROXY === "1";
const expectProbe = emulateProbe || process.env.PREVIEW_EXPECT_PROBE === "1";
const until = async (predicate, label) => {
  const deadline = Date.now() + 30000;
  while (Date.now() < deadline) {
    if (child.exitCode !== null || child.signalCode !== null) throw new Error(logs);
    if (await predicate()) return;
    await delay(20);
  }
  throw new Error(`Timed out: ${label}\n${logs.slice(-3000)}`);
};
const proxy = createServer((_request, response) => {
  response.writeHead(200, { "Content-Type": "text/html" });
  response.end(
    frontend
      .replaceAll("ws://127.0.0.1:23625", `ws://${browserAddress}`)
      .replaceAll("preview-arg:systemTheme:false", "preview-arg:systemTheme:true"),
  );
});
const wss = new WebSocketServer({ server: proxy });
wss.on("connection", (downstream, request) => {
  const upstream = new WebSocket(`ws://${address}${request.url}`, { origin: `http://${address}` });
  const pair = { downstream, upstream, queued: [], requests: [] };
  pairs.add(pair);
  downstream.on("message", (data) => {
    const message = data.toString();
    if (message === "ping" && emulateProbe) {
      if (!blackhole) downstream.send("pong,", { binary: true });
      return;
    }
    if (message === "current" && emulateProbe) downstream.send("keepalive,true", { binary: true });
    if (upstream.readyState === WebSocket.OPEN) upstream.send(message);
    else pair.requests.push(message);
  });
  upstream.on("open", () => pair.requests.splice(0).forEach((message) => upstream.send(message)));
  upstream.on("message", (data, binary) => {
    if (blackhole) return;
    const kind = data.subarray(0, data.indexOf(44)).toString();
    if (hold && ["new", "diff-v1"].includes(kind)) pair.queued.push([data, binary]);
    else if (downstream.readyState === WebSocket.OPEN) downstream.send(data, { binary });
  });
  downstream.on("close", () => {
    upstream.close();
    pairs.delete(pair);
  });
  upstream.on("close", () => downstream.close());
  upstream.on("error", () => downstream.close());
  downstream.on("error", () => upstream.close());
});
const ready = (page) =>
  page.waitForFunction((desktop) => {
    const d = document.getElementById("typst-container")?.documents?.[0]?.impl;
    return (
      d?.moduleInitialized &&
      !d.isRendering &&
      !d.patchQueue.length &&
      document.getElementById("typst-preview-status").hidden &&
      document.querySelector(desktop ? ".tsel" : ".typst-touch-selection-line")
    );
  }, desktop);
const visibility = (page, hidden) =>
  page.evaluate((hidden) => {
    window.testHidden = hidden;
    document.dispatchEvent(new Event("visibilitychange"));
  }, hidden);
const network = (page, online) =>
  page.evaluate((online) => {
    window.testOnline = online;
    window.dispatchEvent(new Event(online ? "online" : "offline"));
  }, online);
const counters = (page) => page.evaluate(() => ({ ...window.recoveryMetrics }));
const flush = () => {
  hold = false;
  for (const pair of pairs)
    for (const [data, binary] of pair.queued.splice(0)) pair.downstream.send(data, { binary });
};

try {
  await until(
    () => (address = /Data plane server listening on: (127\.0\.0\.1:\d+)/.exec(logs)?.[1]),
    "listener",
  );
  await new Promise((done) => proxy.listen(0, "127.0.0.1", done));
  browserAddress = `127.0.0.1:${proxy.address().port}`;
  browser = await playwright.webkit.launch({ headless: true });
  const context = await browser.newContext({
    viewport: desktop ? { width: 1280, height: 900 } : { width: 393, height: 852 },
    hasTouch: !desktop,
    isMobile: !desktop,
    colorScheme: "light",
  });
  const page = await context.newPage();
  const errors = [];
  page.on("pageerror", (error) => errors.push(error.message));
  await page.addInitScript(() => {
    window.testHidden = false;
    window.testOnline = true;
    Object.defineProperty(document, "hidden", { get: () => window.testHidden });
    Object.defineProperty(navigator, "onLine", { get: () => window.testOnline });
    window.recoveryMetrics = {
      attempts: 0,
      opens: 0,
      full: 0,
      resets: 0,
      merges: 0,
      layouts: 0,
      probes: 0,
    };
    window.recoverySockets = [];
    const NativeSocket = WebSocket;
    window.WebSocket = class extends NativeSocket {
      constructor(...args) {
        super(...args);
        window.recoveryMetrics.attempts++;
        window.recoverySockets.push(this);
        this.addEventListener("open", () => window.recoveryMetrics.opens++);
        this.addEventListener("message", ({ data }) => {
          if (
            data instanceof ArrayBuffer &&
            new TextDecoder().decode(new Uint8Array(data, 0, Math.min(4, data.byteLength))) ===
              "new,"
          )
            window.recoveryMetrics.full++;
        });
      }
      send(data) {
        if (data === "ping") window.recoveryMetrics.probes++;
        return super.send(data);
      }
    };
    let session;
    Object.defineProperty(window, "TypstRenderSession", {
      configurable: true,
      get: () => session,
      set: (value) => {
        session = value;
        for (const [name, metric] of [
          ["reset", "resets"],
          ["manipulateData", "merges"],
        ]) {
          const original = value.prototype[name];
          value.prototype[name] = function (...args) {
            window.recoveryMetrics[metric]++;
            return original.apply(this, args);
          };
        }
      },
    });
    document.addEventListener("typst-text-layout", () => window.recoveryMetrics.layouts++, true);
  });
  await page.goto(`http://${browserAddress}`);
  await ready(page);
  await page.evaluate(() => {
    const d = document.getElementById("typst-container").documents[0].impl;
    d.currentScaleRatio = 1.25;
    document.getElementById("typst-container-main").scrollTop = 1500;
    d.addViewportChange();
  });
  await ready(page);
  await page.evaluate((desktop) => {
    const line = document.querySelector(desktop ? ".tsel" : ".typst-touch-selection-line");
    const text = document.createTreeWalker(line, NodeFilter.SHOW_TEXT).nextNode();
    const range = document.createRange();
    range.selectNodeContents(text);
    getSelection().removeAllRanges();
    getSelection().addRange(range);
    window.recoverySelection = { node: text, text: getSelection().toString() };
  }, desktop);
  const baseline = await counters(page);
  const readingTop = await page.evaluate(
    () => document.getElementById("typst-container-main").scrollTop,
  );
  await visibility(page, true);
  await visibility(page, false);
  if (expectProbe) await page.waitForFunction(() => window.recoveryMetrics.probes > 0);
  await delay(200);
  assert.equal((await counters(page)).opens, baseline.opens);
  assert.equal((await counters(page)).full, baseline.full);

  hold = true;
  await network(page, false);
  await visibility(page, true);
  await stopEngine();
  await page.waitForFunction(
    () => document.getElementById("typst-preview-status").dataset.phase === "reconnecting",
  );
  await delay(1200);
  assert.equal((await counters(page)).opens, baseline.opens);
  assert.equal((await counters(page)).attempts, baseline.attempts);
  startEngine();
  await until(
    () => (address = /Data plane server listening on: (127\.0\.0\.1:\d+)/.exec(logs)?.[1]),
    "restarted engine listener",
  );
  await visibility(page, false);
  await delay(1200);
  assert.equal((await counters(page)).attempts, baseline.attempts);
  await network(page, true);
  await until(() => [...pairs].some((pair) => pair.queued.length), "held replacement full frame");
  assert.equal(
    await page.evaluate(
      () => document.getElementById("typst-container").documents[0].impl.moduleInitialized,
    ),
    true,
  );
  flush();
  await page.waitForFunction(
    () => document.getElementById("typst-preview-status").dataset.phase === "selection-held",
  );
  const held = await counters(page);
  assert.equal(held.resets, baseline.resets);
  assert.equal(held.merges, baseline.merges);
  assert.equal(held.layouts, baseline.layouts);
  assert.equal(
    await page.evaluate(
      () =>
        window.recoverySelection.node.isConnected &&
        getSelection().toString() === window.recoverySelection.text,
    ),
    true,
  );
  assert.equal(
    await page.evaluate(
      () => document.getElementById("typst-container").documents[0].impl.currentScaleRatio,
    ),
    1.25,
  );

  await page.evaluate(() => getSelection().removeAllRanges());
  await ready(page);
  const recovered = await counters(page);
  assert.ok(recovered.resets > baseline.resets);
  assert.ok(recovered.merges > baseline.merges);
  assert.ok(
    Math.abs(
      (await page.evaluate(() => document.getElementById("typst-container-main").scrollTop)) -
        readingTop,
    ) < 4,
  );
  await visibility(page, true);
  for (const pair of pairs) pair.downstream.close();
  await page.waitForFunction(
    () => document.getElementById("typst-preview-status").dataset.phase === "reconnecting",
  );
  await writeFile(file, source(1));
  await visibility(page, false);
  await page.waitForFunction(() =>
    Array.from(document.querySelectorAll(".tsel")).some((line) =>
      line.textContent.includes("Revision 1"),
    ),
  );
  await ready(page);
  assert.ok((await counters(page)).merges > recovered.merges);

  if (expectProbe) {
    const opens = (await counters(page)).opens;
    blackhole = true;
    hold = true;
    await visibility(page, true);
    await visibility(page, false);
    await page.waitForFunction((opens) => window.recoveryMetrics.opens > opens, opens);
    blackhole = false;
    hold = false;
    await page.evaluate(() => window.recoverySockets.at(-1).send("current"));
    await ready(page);
  }
  await page.selectOption(".typst-theme-selector", "dark");
  await ready(page);
  assert.deepEqual(errors, []);
  console.log(
    JSON.stringify(
      {
        browser: `WebKit ${browser.version()}`,
        selectionSurface: desktop ? "desktop SVG" : "mobile overlay",
        probeFixture: emulateProbe,
        nativeProbe: expectProbe && !emulateProbe,
        baseline,
        held,
        recovered,
        verified: [
          "healthy socket reuse",
          "hidden retry suppression",
          "offline retry suppression",
          "engine subprocess restart recovery",
          "retained document while awaiting full frame",
          "no reset/merge/layout before selection release",
          "full-frame render after selection release",
          "native selection and zoom retention",
          "changed source recovery",
          ...(expectProbe ? ["unresponsive foreground transport replacement"] : []),
          "theme replacement",
        ],
      },
      null,
      2,
    ),
  );
} catch (error) {
  const page = browser?.contexts()[0]?.pages()[0];
  if (page)
    console.error(
      await page.evaluate(() => ({
        metrics: window.recoveryMetrics,
        status: document.getElementById("typst-preview-status")?.dataset.phase,
        pending: document.getElementById("typst-container")?.documents?.[0]?.impl.patchQueue.length,
        selected: getSelection()?.toString(),
      })),
    );
  throw error;
} finally {
  await browser?.close();
  for (const pair of pairs) {
    pair.downstream.terminate();
    pair.upstream.terminate();
  }
  wss.close();
  proxy.closeAllConnections();
  proxy.close();
  await stopEngine();
  await rm(temp, { recursive: true, force: true });
}
