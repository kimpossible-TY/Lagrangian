import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { createInterface } from "node:readline";
import { once } from "node:events";
import { fileURLToPath } from "node:url";

const { chromium } = await import(process.env.FLOW_READER_PLAYWRIGHT_MODULE || "playwright");
const fixture = spawn(
  "python3",
  ["-B", fileURLToPath(new URL("./preview_proxy_fixture.py", import.meta.url))],
  {
    stdio: ["ignore", "pipe", "inherit"],
  },
);
const lines = createInterface({ input: fixture.stdout });
let browser;
try {
  const { url, token, backendURL } = await new Promise((resolve, reject) => {
    lines.once("line", (line) => resolve(JSON.parse(line)));
    fixture.once("exit", (code) => reject(new Error(`Fixture exited ${code}`)));
  });
  browser = await chromium.launch({
    headless: true,
    ...(process.env.CHROME_BIN ? { executablePath: process.env.CHROME_BIN } : {}),
  });
  const page = await browser.newPage();
  const errors = [],
    requests = [],
    sockets = [];
  page.on("pageerror", (error) => errors.push(error.message));
  page.on("request", (request) => requests.push(request.url()));
  page.on("websocket", (socket) => sockets.push(socket.url()));
  await page.addInitScript(() => {
    window.cspViolations = [];
    document.addEventListener("securitypolicyviolation", (event) => {
      window.cspViolations.push({ directive: event.violatedDirective, blocked: event.blockedURI });
    });
  });
  await page.goto(url);
  const preview = page.getByRole("link", { name: "Fixture preview · Paged Reader", exact: true });
  await preview.waitFor();
  assert.equal(await preview.getAttribute("href"), url + "p/alpha/");
  await preview.click();
  await page.waitForFunction(() => window.previewLoaded && window.socket?.readyState === 1);
  assert.equal(page.url(), url + "p/alpha/");
  const wasm = await page.evaluate(async () => {
    const response = await fetch("data:application/wasm;base64,AGFzbQEAAAA=");
    const bytes = await response.arrayBuffer();
    const { instance } = await WebAssembly.instantiate(bytes);
    return instance instanceof WebAssembly.Instance;
  });
  assert.equal(wasm, true);
  assert.deepEqual(await page.evaluate(() => window.cspViolations), []);
  for (const path of [
    "p/alpha/assets/client.js",
    "p/alpha/assets/theme.css?x=1",
    "p/alpha/images/picture.png",
  ])
    assert.ok(requests.includes(url + path), path);
  const roundtrip = await page.evaluate(async () => {
    const frames = [];
    await new Promise((resolve, reject) => {
      const socket = new WebSocket(new URL("/_theme/dark?keep=1", location.href));
      socket.binaryType = "arraybuffer";
      socket.onerror = reject;
      socket.onopen = () => socket.send(new Uint8Array([0, 255, 1]));
      socket.onmessage = (event) => {
        frames.push([...new Uint8Array(event.data)]);
        if (frames.length === 2) {
          socket.close();
          resolve();
        }
      };
    });
    return frames;
  });
  assert.deepEqual(roundtrip, [
    [104, 101, 108, 108, 111],
    [0, 255, 1],
  ]);
  assert.ok(sockets.every((socket) => socket.startsWith(url.replace("http:", "ws:") + "p/alpha/")));
  const control = async (operation) => {
    const response = await fetch(url + "fixture-control", {
      method: "POST",
      headers: { "Content-Type": "application/json", "X-Fixture-Token": token },
      body: JSON.stringify({ operation }),
    });
    assert.ok(response.ok);
  };
  await control("stop");
  await page.waitForFunction(() => window.socket.readyState === 3);
  assert.equal((await fetch(url + "p/alpha/")).status, 503);
  await control("restart");
  await page.reload();
  await page.waitForFunction(() => window.socket?.readyState === 1);
  assert.equal((await fetch(backendURL)).status, 200);
  assert.deepEqual(errors, []);
  console.log(
    "Preview proxy browser: Homepage link, scoped assets, root/theme WS binary frames, stop/restart and direct port passed.",
  );
} finally {
  await browser?.close();
  fixture.kill("SIGTERM");
  if (fixture.exitCode === null) await once(fixture, "exit");
  lines.close();
}
