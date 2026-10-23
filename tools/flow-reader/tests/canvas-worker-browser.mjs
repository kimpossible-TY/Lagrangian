// Real Worker placement, source geometry and offline reflow in the Reader shell.
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { once } from "node:events";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createInterface } from "node:readline";
import { fileURLToPath } from "node:url";

const playwright = await import(process.env.FLOW_READER_PLAYWRIGHT_MODULE || "playwright");
assert.ok(process.env.FLOW_READER_PACKAGES, "Set FLOW_READER_PACKAGES");
const root = fileURLToPath(new URL("../", import.meta.url));
const work = await mkdtemp(join(tmpdir(), "flow-canvas-worker-"));
const script = `
from pathlib import Path
from http.server import ThreadingHTTPServer
import os, sys, threading
from flow_reader.compiler.project import Project
from flow_reader.server.state import ReaderState
from flow_reader.server.http import handler_for
root, work = map(Path, sys.argv[1:])
project = Project(root / 'tests/fixtures', Path('native-canvases.typ'), Path(os.environ['FLOW_READER_PACKAGES']), compiler=os.environ.get('FLOW_READER_TYPST', 'typst'), semantic_canvases=True)
state = ReaderState(project, work / 'output', '', False)
state.compile()
assert state.revision, state.report
class Handler(handler_for(state)):
    def handle(self):
        if (work / 'disconnected').exists(): return
        super().handle()
server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
threading.Thread(target=server.serve_forever, daemon=True).start()
print(server.server_port, flush=True)
try:
    sys.stdin.read()
finally:
    server.shutdown()
    state.close()
`;
const service = spawn("python3", ["-u", "-c", script, root, work], {
  env: { ...process.env, PYTHONPATH: root },
  stdio: ["pipe", "pipe", "pipe"],
});
let log = "";
service.stderr.on("data", (data) => {
  log += data;
});
const lines = createInterface({ input: service.stdout });
const nativeChecks = await readFile(new URL("native-canvases-browser.js", import.meta.url), "utf8");
try {
  const [port] = await once(lines, "line");
  const url = `http://127.0.0.1:${port}/?fonts=13,30,18`;
  for (const engine of ["chromium", "webkit"]) {
    const browser = await playwright[engine].launch({
      headless: true,
      ...(engine === "chromium" ? { channel: "chrome" } : {}),
    });
    try {
      const page = await browser.newPage({ viewport: { width: 390, height: 844 } });
      const errors = [],
        requests = [];
      const canonical = await (
        await page.request.get(`http://127.0.0.1:${port}/document.html`)
      ).text();
      page.on("pageerror", (error) => errors.push(error.message));
      page.on("request", (request) => {
        if (request.url().endsWith("/api/canvases")) requests.push(request.url());
      });
      await page.addInitScript(() => {
        const RealWorker = globalThis.Worker;
        globalThis.canvasJobs = [];
        globalThis.Worker = class extends RealWorker {
          constructor(url, options) {
            super(url, options);
            this.canvas = String(url).endsWith("/canvas-worker.js");
            this.jobs = new Map();
            if (this.canvas)
              this.addEventListener("message", ({ data }) => {
                const job = this.jobs.get(data.id);
                if (job) job.plan = data.plan;
              });
          }
          postMessage(data, options) {
            if (this.canvas) {
              const job = structuredClone(data);
              this.jobs.set(data.id, job);
              globalThis.canvasJobs.push(job);
            }
            super.postMessage(data, options);
          }
        };
      });
      const verify = async (offline) => {
        await page.evaluate((source) => {
          globalThis.nativeCanvasReference = source;
        }, canonical);
        await page.addScriptTag({ type: "module", content: nativeChecks });
        await page.waitForFunction(
          () => ["ready", "error"].includes(document.body.dataset.nativeCanvasesState),
          null,
          { timeout: 180000 },
        );
        const report = await page.locator("#native-canvases-report").textContent().then(JSON.parse);
        assert.deepEqual(report.errors, [], JSON.stringify(report));
        const parity = await page.evaluate(async () => {
          const { composeCanvas } = await import("/rendering/graphics/canvas-layout.js");
          const completed = globalThis.canvasJobs.filter((job) => job.plan);
          return {
            count: completed.length,
            equal: completed.every(
              (job) => JSON.stringify(job.plan) === JSON.stringify(composeCanvas(...job.input)),
            ),
          };
        });
        assert.ok(parity.count >= 8, JSON.stringify(parity));
        assert.equal(parity.equal, true);
        assert.equal(requests.length, 0);
        console.log(
          `${engine} ${offline ? "offline" : "online"}: ${report.checks.length} geometry/semantic checks, ${parity.count} exact Worker plans, zero canvas requests`,
        );
      };
      await page.goto(url);
      await page.waitForFunction(
        () => document.querySelectorAll("[data-flow-canvas-model]").length > 0,
      );
      await verify(false);
      await page.evaluate(() => navigator.serviceWorker.ready);
      await page.waitForFunction(
        () =>
          navigator.serviceWorker.controller &&
          document.querySelector("#reader-offline-status").textContent.includes("오프라인에서도"),
        null,
        { timeout: 60000 },
      );
      await writeFile(join(work, "disconnected"), "");
      await page.reload();
      await page.waitForFunction(
        () => document.querySelectorAll("[data-flow-canvas-model]").length > 0,
      );
      await page.setViewportSize({ width: 768, height: 1024 });
      await verify(true);
      assert.deepEqual(errors, []);
    } finally {
      await rm(join(work, "disconnected"), { force: true });
      await browser.close();
    }
  }
} catch (error) {
  console.error(log.slice(-4000));
  throw error;
} finally {
  lines.close();
  service.stdin.end();
  if (service.exitCode === null) await once(service, "exit");
  await rm(work, { recursive: true, force: true });
}
