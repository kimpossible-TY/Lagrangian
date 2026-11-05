// Real compiled MathML namespaces, native spacing and Reader MathJax rendering.
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { once } from "node:events";
import { mkdir, writeFile } from "node:fs/promises";
import { resolve } from "node:path";
import { createInterface } from "node:readline";
import { fileURLToPath } from "node:url";

assert.ok(process.env.FLOW_READER_PACKAGES, "Set FLOW_READER_PACKAGES");
const playwright = await import(process.env.FLOW_READER_PLAYWRIGHT_MODULE || "playwright");
const root = fileURLToPath(new URL("../", import.meta.url));
const output = resolve(process.argv[2] || "dist/reader-dots-space");
await mkdir(output, { recursive: true });
const script = `
from http.server import ThreadingHTTPServer
import json, os, sys, tempfile, threading
from pathlib import Path
from flow_reader.compiler.project import Project
from flow_reader.server.state import ReaderState
from flow_reader.server.http import handler_for
from flow_reader.services.paragraph_chat import ParagraphChat
with tempfile.TemporaryDirectory(prefix='reader-dots-browser-') as temporary:
    work=Path(temporary)
    source=work/'source'
    source.mkdir()
    entry=source/'main.typ'
    entry.write_bytes((Path(sys.argv[1])/'tests/fixtures/dots-space.typ').read_bytes())
    project=Project(source,Path('main.typ'),Path(os.environ['FLOW_READER_PACKAGES']),
                    compiler=os.environ.get('FLOW_READER_TYPST','typst'))
    state=ReaderState(project,work/'output','',False,change_file=work/'changes.json')
    state._paragraph_chat=ParagraphChat(state,directory=work/'private-chat')
    state.compile()
    assert state.revision and state.report['contentGatePassed'], state.report
    server=ThreadingHTTPServer(('127.0.0.1',0),handler_for(state))
    thread=threading.Thread(target=server.serve_forever,daemon=True)
    thread.start()
    print(server.server_port,flush=True)
    try:
        sys.stdin.read()
    finally:
        server.shutdown()
        server.server_close()
        state.close()
        thread.join()
`;
const service = spawn("python3", ["-B", "-u", "-c", script, root], {
  env: { ...process.env, PYTHONPATH: root },
  stdio: ["pipe", "pipe", "inherit"],
});
const lines = createInterface({ input: service.stdout });
const checks = [];
async function deadline(promise, milliseconds, description) {
  let timer;
  try {
    return await Promise.race([
      promise,
      new Promise((_, reject) => {
        timer = setTimeout(() => reject(new Error(`Timed out: ${description}`)), milliseconds);
      }),
    ]);
  } finally {
    clearTimeout(timer);
  }
}
try {
  const [port] = await deadline(
    Promise.race([
      once(lines, "line"),
      once(service, "exit").then(([code]) => {
        throw new Error(`Fixture exited before readiness: ${code}`);
      }),
    ]),
    30000,
    "fixture readiness",
  );
  assert.match(port, /^\d+$/);
  const origin = `http://127.0.0.1:${port}`;
  for (const engine of (process.env.FLOW_READER_BROWSER_ENGINES || "chromium,webkit").split(",")) {
    const browser = await playwright[engine].launch({
      headless: true,
      ...(engine === "chromium" && process.env.FLOW_READER_CHROMIUM_CHANNEL
        ? { channel: process.env.FLOW_READER_CHROMIUM_CHANNEL }
        : {}),
      ...(engine === "webkit" && process.env.FLOW_READER_WEBKIT_EXECUTABLE
        ? { executablePath: process.env.FLOW_READER_WEBKIT_EXECUTABLE }
        : {}),
    });
    try {
      // Keep the offline shell from intercepting the next /document.html
      // navigation; this test compares network MathML with the live renderer.
      const page = await browser.newPage({ serviceWorkers: "block" });
      const errors = [];
      page.on("pageerror", (error) => errors.push(error.message));
      for (const width of [390, 1280]) {
        await page.setViewportSize({ width, height: 900 });
        await page.goto(origin + "/document.html");
        const native = await page.evaluate(() => {
          const rows = [...document.querySelectorAll('[data-flow-selection-ignore="dots-space"]')];
          const paragraphs = [...document.querySelectorAll("p")];
          const formula = (prefix) =>
            paragraphs
              .find((node) => node.textContent.startsWith(prefix))
              .querySelector("math")
              .getBoundingClientRect().width;
          return {
            rows: rows.length,
            mathNamespaces: rows.every(
              (node) => node.namespaceURI === "http://www.w3.org/1998/Math/MathML",
            ),
            nestedMath: document.querySelectorAll("math math").length,
            helperWidth: formula("Inline formula"),
            controlWidth: formula("Reference formula"),
            standalone: paragraphs.some(
              (node) => node.textContent === "Before helper ⋯ after helper.",
            ),
          };
        });
        assert.equal(native.rows, 7);
        assert.ok(native.mathNamespaces, `${engine}: every helper must be real MathML`);
        assert.equal(native.nestedMath, 0);
        assert.ok(native.standalone);
        assert.ok(native.helperWidth > 0);
        assert.ok(Math.abs(native.helperWidth - native.controlWidth) < 0.5, JSON.stringify(native));

        await page.goto(origin);
        await page.waitForSelector(".flow-math-view");
        const views = page.locator("#reader-document .flow-math-view");
        const count = await views.count();
        assert.equal(count, 6);
        for (let index = 0; index < count; index++) {
          await views.nth(index).scrollIntoViewIfNeeded();
          await page.waitForFunction(
            (index) =>
              document.querySelectorAll("#reader-document .flow-math-view")[index]?.dataset
                .mathState === "ready",
            index,
          );
        }
        const rendered = await page.evaluate(async () => {
          const { logicalTextIndex } = await import("/rendering/math/identity.js");
          const paragraphs = [...document.querySelectorAll("#reader-document p")];
          const view = (prefix) =>
            paragraphs
              .find((node) => node.textContent.startsWith(prefix))
              .querySelector(".flow-math-view");
          const helper = view("Inline formula"),
            control = view("Reference formula");
          return {
            helperWidth: helper.getBoundingClientRect().width,
            controlWidth: control.getBoundingClientRect().width,
            helperLogicalText: logicalTextIndex(helper, { includeNested: true }).text,
            helperUserSelect: getComputedStyle(
              helper.querySelector('[data-flow-selection-ignore="dots-space"]'),
            ).userSelect,
            standaloneView: Boolean(view("Before helper")),
            numbered: [...document.querySelectorAll(".flow-equation-number")].map(
              (node) => node.textContent,
            ),
          };
        });
        assert.ok(rendered.standaloneView);
        assert.deepEqual(rendered.numbered, ["(1)", "(2)"]);
        assert.equal(
          rendered.helperLogicalText.normalize("NFKC"),
          "α⋯β",
          "The mathematical reading-order model retains every token",
        );
        assert.equal(
          rendered.helperUserSelect,
          "none",
          "Generated marker keeps selection exclusion",
        );
        assert.ok(
          Math.abs(rendered.helperWidth - rendered.controlWidth) < 0.5,
          JSON.stringify(rendered),
        );
        assert.deepEqual(errors, []);
        await page.screenshot({ path: resolve(output, `${engine}-${width}.png`), fullPage: true });
        checks.push({ engine, width, native, rendered });
      }
    } finally {
      await browser.close();
    }
  }
  await writeFile(resolve(output, "result.json"), JSON.stringify({ checks }, null, 2) + "\n");
  console.log(`Dots helper browser checks passed: ${checks.length} engine/viewport cases`);
} finally {
  lines.close();
  service.stdin.end();
  if (service.exitCode === null && service.signalCode === null) {
    try {
      await deadline(once(service, "exit"), 10000, "fixture shutdown");
    } catch {
      // Only this test's directly spawned fixture is eligible for termination.
      service.kill("SIGKILL");
      await deadline(once(service, "exit"), 5000, "owned fixture termination");
    }
  }
}
