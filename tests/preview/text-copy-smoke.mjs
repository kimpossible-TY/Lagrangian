// Native selection serialization with a disposable real-engine document.
// PREVIEW_BROWSER=webkit selects desktop WebKit; physical iPhone handles remain separate.
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { mkdtemp, readFile, realpath, rm, writeFile } from "node:fs/promises";
import { createServer, request } from "node:http";
import { homedir, tmpdir } from "node:os";
import { resolve } from "node:path";
import { setTimeout as delay } from "node:timers/promises";

const engine = process.argv[2];
assert.ok(engine, "Pass a preview engine executable");
const playwright = await import(
  process.env.PLAYWRIGHT_MODULE ||
    resolve(
      homedir(),
      ".cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright/index.mjs",
    )
);
const frontend = await readFile(
  process.env.PREVIEW_FRONTEND_HTML ||
    new URL("../../tools/typst-preview-frontend/dist/index.html", import.meta.url),
  "utf8",
);
const temp = await realpath(await mkdtemp(resolve(tmpdir(), "flow-text-copy-")));
const file = resolve(temp, "main.typ"),
  focusFile = resolve(temp, "focus.json");
const title = "Proposition 3.3.2 (Fourier Transform Of Sphere Surface Measure)";
const wrapped = "Lemma 3.3.3 (Wrapped Title With Multiple Styled Fragments)";
const styled = (text) =>
  text
    .split(" ")
    .map((word, index) => `#text(size: ${index % 2 ? 9 : 11}pt)[${word}]`)
    .join(" ");
await writeFile(
  file,
  `#set page(width: 420pt, height: 620pt, margin: 30pt)
#set text(size: 11pt, hyphenate: false)
#strong[Proposition] #strong[3.3.2] (${styled("Fourier Transform Of Sphere Surface Measure")})

#block(width: 150pt)[#strong[Lemma] #strong[3.3.3] (${styled("Wrapped Title With Multiple Styled Fragments")})]

Next paragraph stays separate.

#pagebreak()
Another page remains selectable.
`,
);
let child,
  browser,
  proxy,
  logs = "";
const errors = [];
const ready = (page) =>
  page.waitForFunction(() => {
    const d = document.getElementById("typst-container")?.documents?.[0]?.impl;
    return (
      d?.moduleInitialized &&
      !d.isRendering &&
      !d.patchQueue.length &&
      d.vpTimeout === undefined &&
      !d.svgResizeAnchor &&
      document.getElementById("typst-preview-status").hidden &&
      document.querySelector(".typst-touch-selection-line")
    );
  });
const capture = (page, quote) =>
  page.evaluate((quote) => {
    const lines = [...document.querySelectorAll(".typst-touch-selection-line")];
    const text = lines.map((line) => line.textContent).join("");
    // Typst omits spaces at line wraps. Ignore whitespace only when locating
    // endpoints; assertions below use the browser's unmodified selected text.
    const offsets = [...text.matchAll(/\S/g)].map((match) => match.index);
    const needle = quote.replace(/\s/g, "");
    const index = text.replace(/\s/g, "").indexOf(needle);
    if (index < 0) throw new Error(`Missing quote: ${quote}\nRendered text: ${text}`);
    const start = offsets[index],
      end = offsets[index + needle.length - 1] + 1;
    const range = document.createRange();
    const rows = new Set();
    let offset = 0,
      fragments = 0;
    for (const line of lines) {
      const next = offset + line.textContent.length;
      if (offset <= start && start < next) range.setStart(line.firstChild, start - offset);
      if (offset < end && end <= next) range.setEnd(line.firstChild, end - offset);
      if (start < next && offset < end) {
        rows.add(line.parentElement);
        fragments++;
      }
      offset = next;
    }
    getSelection().removeAllRanges();
    getSelection().addRange(range);
    return { text: getSelection().toString(), rows: rows.size, fragments };
  }, quote);
const assertGeometry = async (page) => {
  const maximumError = await page.evaluate(() => {
    const sources = [...document.querySelectorAll(".tsel")].map((source) => ({
      text: source.textContent,
      rect: source.parentElement.getBoundingClientRect(),
    }));
    return Math.max(
      ...[...document.querySelectorAll(".typst-touch-selection-line")].map((line) => {
        const rect = line.getBoundingClientRect();
        return Math.min(
          ...sources
            .filter((source) => source.text === line.textContent)
            .map((source) =>
              Math.max(
                ...["left", "top", "width", "height"].map((key) =>
                  Math.abs(rect[key] - source.rect[key]),
                ),
              ),
            ),
        );
      }),
    );
  });
  assert.ok(maximumError < 1, `Selection geometry drifted by ${maximumError}px`);
};

try {
  child = spawn(
    engine,
    [
      "preview",
      file,
      "--root",
      temp,
      "--no-open",
      "--partial-rendering=true",
      "--data-plane-host=127.0.0.1:0",
      "--control-plane-host=127.0.0.1:0",
    ],
    {
      env: {
        ...process.env,
        TINYMIST_ALLOWED_ORIGINS: "",
        TINYMIST_PREVIEW_FOCUS_FILE: focusFile,
        TINYMIST_PREVIEW_CHANGE_FILE: resolve(temp, "changes.json"),
      },
      stdio: ["ignore", "pipe", "pipe"],
    },
  );
  child.stdout.on("data", (data) => (logs += data));
  child.stderr.on("data", (data) => (logs += data));
  child.on("error", (error) => (logs += error.message));
  let address;
  const deadline = Date.now() + 30000;
  while (!(address = /Data plane server listening on: (127\.0\.0\.1:\d+)/.exec(logs)?.[1])) {
    assert.ok(Date.now() < deadline && child.exitCode === null, logs);
    await delay(25);
  }
  let browserAddress;
  proxy = createServer((_req, res) => {
    res.setHeader("Content-Type", "text/html");
    res.end(frontend.replaceAll("ws://127.0.0.1:23625", `ws://${browserAddress}`));
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
  const page = await browser.newPage({
    viewport: { width: 393, height: 852 },
    hasTouch: true,
    isMobile: true,
    deviceScaleFactor: 3,
  });
  page.on("pageerror", (error) => errors.push(error.message));
  await page.goto(`http://${browserAddress}/`);
  await ready(page);
  const selected = await capture(page, title);
  assert.ok(selected.fragments > 4, "The title must exercise several styled fragments");
  assert.equal(selected.rows, 1);
  assert.equal(selected.text, title);
  await assertGeometry(page);
  await page.getByRole("button", { name: "Save for Codex", exact: true }).click();
  await page.waitForFunction(() =>
    /[Ss]aved.*for Codex/.test(document.querySelector(".typst-focus-status").textContent),
  );
  assert.equal(JSON.parse(await readFile(focusFile, "utf8")).selection.text, title);
  assert.equal((await capture(page, "Fourier Transform Of")).text, "Fourier Transform Of");
  const multiline = await capture(page, wrapped);
  assert.ok(multiline.rows > 1);
  assert.equal(multiline.text.replace(/\s+/g, " "), wrapped);
  assert.equal(multiline.text.split("\n").length, multiline.rows);
  const paragraphs = await capture(page, `${wrapped}Next paragraph stays separate.`);
  assert.ok(paragraphs.text.endsWith(")\nNext paragraph stays separate."));
  await page.evaluate(() => {
    getSelection().removeAllRanges();
    const d = document.getElementById("typst-container").documents[0];
    d.impl.currentScaleRatio = 1.25;
    d.addViewportChange();
  });
  await ready(page);
  assert.equal((await capture(page, title)).text, title);
  await assertGeometry(page);
  await page.evaluate(() => getSelection().removeAllRanges());
  assert.deepEqual(errors, []);
  console.log(
    `${browserName}: title, partial range, wrapped rows, paragraphs, saved text and zoom geometry passed`,
  );
} catch (error) {
  console.error(logs.slice(-3000), errors);
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
