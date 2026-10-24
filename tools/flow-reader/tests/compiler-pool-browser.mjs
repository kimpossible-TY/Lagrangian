// Actual Reader HTTP leases, WASM Worker and Python acceptance in isolated projects.
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { once } from "node:events";
import { mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { createInterface } from "node:readline";
import { fileURLToPath } from "node:url";

const playwright = await import(process.env.FLOW_READER_PLAYWRIGHT_MODULE || "playwright");
assert.ok(process.env.FLOW_READER_PACKAGES, "Set FLOW_READER_PACKAGES");
const root = fileURLToPath(new URL("../", import.meta.url));
const assets = resolve(process.env.FLOW_COMPILER_ASSETS || "dist/reader-compiler");
const work = await mkdtemp(join(tmpdir(), "flow-browser-pool-"));
const evidence = resolve("dist/device-diagnostics-browser");
await mkdir(evidence, { recursive: true });
const entry = join(work, "main.typ");
await writeFile(entry, "Initial shared document $x^2$.\n");
const script = `
from pathlib import Path
from http.server import ThreadingHTTPServer
import json, os, sys, threading
from flow_reader.compiler.project import Project
from flow_reader.server.state import ReaderState
from flow_reader.server.http import handler_for
root = Path(sys.argv[1])
project = Project(root, Path('main.typ'), Path(os.environ['FLOW_READER_PACKAGES']))
(root / 'output').mkdir()
(root / 'output/report.json').write_text(json.dumps(dict(dependencies=[str(root.parent / 'retired-release/package.typ')])))
state = ReaderState(project, root / 'output', '', False, browser_compiler=sys.argv[2])
state.compile()
assert state.revision, state.report
assert str(root.parent / 'retired-release/package.typ') not in state.accepted_dependencies
class Handler(handler_for(state)):
    def do_GET(self):
        if self.path == '/test/status':
            with state.compiler_pool.condition:
                result = dict(workers=len(state.compiler_pool.workers),
                              completed=state.compiler_pool.completed,
                              fallbacks=state.compiler_pool.fallbacks,
                              jobs=[dict(id=key, worker=job.worker, lease=job.lease)
                                    for key, job in state.compiler_pool.jobs.items()])
            result.update(revision=state.revision, compiling=state.compiling)
            result['nativeDynamicRequests'] = state.renderer.dynamic_compiler.requests if state.renderer.dynamic_compiler else 0
            return self.respond(json.dumps(result).encode(), 'application/json')
        super().do_GET()
server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
threading.Thread(target=server.serve_forever, daemon=True).start()
print(server.server_port, flush=True)
try:
    for line in sys.stdin:
        state.compile()
        print(json.dumps(dict(revision=state.revision, report=state.report)), flush=True)
finally:
    state.close()
    server.shutdown()
    server.server_close()
`;
const service = spawn("python3", ["-u", "-c", script, work, assets], {
  env: { ...process.env, PYTHONPATH: root },
  stdio: ["pipe", "pipe", "inherit"],
});
const lines = createInterface({ input: service.stdout });
async function until(read, predicate, description) {
  const deadline = Date.now() + 90000;
  while (Date.now() < deadline) {
    const value = await read();
    if (predicate(value)) return value;
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  throw new Error(`Timed out: ${description}`);
}
try {
  const [port] = await once(lines, "line");
  assert.match(port, /^\d+$/);
  const origin = `http://127.0.0.1:${port}`;
  const status = () => fetch(origin + "/test/status").then((r) => r.json());
  const compile = () => {
    const done = once(lines, "line").then(([line]) => JSON.parse(line));
    service.stdin.write("compile\n");
    return done;
  };
  for (const engine of (process.env.FLOW_READER_BROWSER_ENGINES || "chromium,webkit").split(",")) {
    const browser = await playwright[engine].launch({
      headless: true,
      ...(engine === "chromium" && process.env.FLOW_READER_CHROMIUM_CHANNEL
        ? { channel: process.env.FLOW_READER_CHROMIUM_CHANNEL }
        : {}),
    });
    try {
      // Separate contexts represent two devices, both foreground in this test.
      // Network interception must see result POSTs; SW recovery has its own fixture.
      const first = await browser.newPage({
        viewport: { width: 390, height: 844 },
        serviceWorkers: "block",
      });
      const errors = [];
      first.on("pageerror", (error) => errors.push(error.message));
      await first.goto(origin);
      await first.waitForFunction(() => document.querySelector("#reader-compiler-enabled"));
      assert.equal(await first.locator("#reader-compiler-enabled").isChecked(), true);
      await until(status, (s) => s.workers === 1, "first Worker readiness");
      const initialRevision = (await status()).revision;
      await first.locator("#reader-appearance-open").click();
      await first.locator("#reader-compiler-diagnostics > summary").click();
      for (const mode of ["quick", "document"]) {
        await first.locator(`[data-diagnostic="${mode}"]`).click();
        await first.waitForFunction(
          () =>
            ["passed", "failed"].includes(
              document.querySelector("#reader-diagnostic-result").dataset.status,
            ),
          null,
          { timeout: 90000 },
        );
        const diagnostics = await fetch(origin + "/api/compiler/status").then((r) => r.json());
        const check = diagnostics.history.find((item) => item.executor === "diagnostic");
        assert.equal(check.purpose, mode);
        assert.equal(check.status, "passed", JSON.stringify(check));
        assert.ok(check.outputHash);
        const execution = diagnostics.history.find((item) => item.purpose === `test-${mode}`);
        assert.equal(execution.lastProgress.phase, "sending-result");
        assert.ok(execution.lastProgress.wasmMemoryBytes > 0);
        assert.equal(
          (await status()).revision,
          initialRevision,
          "checks cannot publish a document",
        );
        await first.screenshot({ path: join(evidence, `${engine}-${mode}-diagnostic.png`) });
      }
      // Reload recovery keeps the pinned failure and adds the previous tab checkpoint.
      let heldResult;
      let resultReady;
      const resultHeld = new Promise((resolve) => {
        resultReady = resolve;
      });
      await first.route("**/api/compiler/result", (route) => {
        heldResult = route;
        resultReady();
      });
      await first.locator('[data-diagnostic="quick"]').click();
      await resultHeld;
      await first.evaluate(() => window.dispatchEvent(new PageTransitionEvent("pagehide")));
      await heldResult.abort().catch(() => {});
      await first.unroute("**/api/compiler/result");
      await first.reload();
      await until(status, (s) => s.workers === 1, "reloaded Worker readiness");
      const recovered = await fetch(origin + "/api/compiler/status").then((r) => r.json());
      const interrupted = recovered.history.find((item) => item.executor === "diagnostic");
      assert.equal(interrupted.status, "failed");
      assert.equal(interrupted.recovery.mode, "page-restart");
      assert.equal(interrupted.recovery.progress.phase, "sending-result");
      await first.locator("#reader-appearance-open").click();
      await first.locator("#reader-compiler-diagnostics > summary").click();
      await first.waitForFunction(() =>
        document
          .querySelector("#reader-diagnostic-result")
          .textContent.includes("페이지가 다시 시작"),
      );
      await first.locator(".reader-appearance-close").click();
      const before = await status();
      await writeFile(entry, `Shared browser output ${engine} $y^2$.\n`);
      await first.locator("#reader-appearance-open").click();
      await first.locator('[data-diagnostic="document"]').click();
      await first.waitForFunction(
        () => document.querySelector("#reader-diagnostic-result").dataset.status === "failed",
      );
      assert.match(
        await first.locator("#reader-diagnostic-result").textContent(),
        /문서가 바뀌었습니다/,
      );
      assert.equal((await status()).revision, before.revision);
      await first.locator(".reader-appearance-close").click();
      const accepted = await compile();
      assert.equal(accepted.report.contentGatePassed, true);
      assert.notEqual(accepted.revision, before.revision);
      const after = await status();
      assert.ok(
        after.completed >= before.completed + 2,
        "base and source carriers must execute on browser",
      );
      assert.equal(after.fallbacks, before.fallbacks);
      await first.waitForFunction(() =>
        document.querySelector("#reader-document").textContent.includes("Shared browser output"),
      );

      const second = await browser.newPage({
        viewport: { width: 768, height: 1024 },
        serviceWorkers: "block",
      });
      second.on("pageerror", (error) => errors.push(error.message));
      await second.goto(origin);
      assert.equal(await second.locator("#reader-compiler-enabled").isChecked(), true);
      await until(status, (s) => s.workers === 2, "second default-enabled Worker readiness");
      await second.evaluate(() => {
        const toggle = document.querySelector("#reader-compiler-enabled");
        toggle.checked = false;
        toggle.dispatchEvent(new Event("change"));
      });
      await until(status, (s) => s.workers === 1, "explicit disabling releases the Worker");
      await second.reload();
      await second.waitForFunction(() =>
        document.querySelector("#reader-document [data-reader-key]"),
      );
      assert.equal(await second.locator("#reader-compiler-enabled").isChecked(), false);
      assert.equal(
        (await status()).workers,
        1,
        "Reload preserves the explicit disabled preference",
      );
      await second.evaluate(() => {
        const toggle = document.querySelector("#reader-compiler-enabled");
        toggle.checked = true;
        toggle.dispatchEvent(new Event("change"));
      });
      await until(status, (s) => s.workers === 2, "second Worker readiness");
      assert.equal(
        await second.evaluate(() => localStorage.getItem("flow-reader:/:compiler-enabled")),
        "true",
      );
      const legacy = await browser.newPage({ serviceWorkers: "block" });
      const identity = await fetch(origin + "/api/state").then((response) => response.json());
      await legacy.addInitScript((id) => {
        localStorage.setItem(`flow-reader:${id}:compiler-enabled`, "false");
      }, identity.documentID);
      await legacy.goto(origin);
      await legacy.waitForFunction(() =>
        document.querySelector("#reader-document [data-reader-key]"),
      );
      assert.equal(await legacy.locator("#reader-compiler-enabled").isChecked(), false);
      assert.equal(
        await legacy.evaluate(() => localStorage.getItem("flow-reader:/:compiler-enabled")),
        "false",
      );
      assert.equal(
        (await status()).workers,
        2,
        "A migrated disabled choice cannot register another Worker",
      );
      await legacy.close();
      const unavailable = await browser.newPage({ serviceWorkers: "block" });
      unavailable.on("pageerror", (error) => errors.push(error.message));
      await unavailable.route("**/compiler-assets/compiler.js", (route) => route.abort());
      await unavailable.goto(origin);
      await unavailable.locator("#reader-appearance-open").click();
      await unavailable.locator("#reader-compiler-diagnostics > summary").click();
      await unavailable.waitForFunction(() =>
        document
          .querySelector("#reader-diagnostic-result")
          .textContent.includes("준비하지 못했습니다"),
      );
      assert.equal(await unavailable.locator('[data-diagnostic="quick"]').isDisabled(), true);
      assert.equal((await status()).workers, 2, "failed initialization cannot offer capacity");
      await unavailable.close();
      // Hold the first result, terminate its page, then let the other device take its lease.
      let heldPage;
      let releaseResult;
      let heldResolve;
      const held = new Promise((resolve) => {
        heldResolve = resolve;
      });
      const gate = new Promise((resolve) => {
        releaseResult = resolve;
      });
      for (const page of [first, second]) {
        await page.route("**/api/compiler/result", async (route) => {
          if (!heldPage) {
            heldPage = page;
            heldResolve();
            await gate;
          }
          await route.continue().catch(() => {});
        });
      }
      await writeFile(entry, `Reassigned shared output ${engine}.\n`);
      const reassigned = compile();
      await held;
      const leased = await status();
      assert.equal(leased.jobs.length, 1);
      // Pagehide disposes computation and releases the server lease.
      await heldPage.evaluate(() => window.dispatchEvent(new PageTransitionEvent("pagehide")));
      releaseResult();
      const survivor = heldPage === first ? second : first;
      const adopted = await reassigned;
      assert.equal(adopted.report.contentGatePassed, true);
      assert.equal((await status()).fallbacks, after.fallbacks);
      await survivor.waitForFunction(() =>
        document.querySelector("#reader-document").textContent.includes("Reassigned shared output"),
      );
      const manifest = await survivor.evaluate(() => fetch("api/manifest").then((r) => r.json()));
      assert.equal(manifest.revision, adopted.revision);

      // In-flight outputs cannot publish over a later external source edit.
      let resume;
      let capturedResolve;
      const captured = new Promise((resolve) => {
        capturedResolve = resolve;
      });
      const pending = new Promise((resolve) => {
        resume = resolve;
      });
      await survivor.unroute("**/api/compiler/result");
      let intercepted = false;
      await survivor.route("**/api/compiler/result", async (route) => {
        if (!intercepted) {
          intercepted = true;
          capturedResolve();
          await pending;
        }
        await route.continue();
      });
      await writeFile(entry, "Candidate before external edit.\n");
      const stale = compile();
      await captured;
      await writeFile(
        entry,
        "#let highlighted(body) = highlight(body)\nExternal Codex edit wins.\n",
      );
      resume();
      const rejected = await stale;
      assert.equal(rejected.report.contentGatePassed, false);
      assert.equal(rejected.revision, adopted.revision);
      await survivor.unroute("**/api/compiler/result");
      assert.equal((await compile()).report.contentGatePassed, true);
      await survivor.waitForFunction(() =>
        document
          .querySelector("#reader-document")
          .textContent.includes("External Codex edit wins."),
      );
      const beforeHighlight = await status();
      const highlighted = await survivor.evaluate(async () => {
        const state = await (await fetch("api/state")).json();
        const block = [...document.querySelectorAll("[data-reader-key]")].find(
          (node) => node.textContent.trim() === "External Codex edit wins.",
        );
        const response = await fetch("api/highlight", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            revision: state.revision,
            fragments: [
              {
                key: block.dataset.readerKey,
                exact: "External Codex edit wins.",
                prefix: "",
                suffix: "",
              },
            ],
          }),
        });
        return response.json();
      });
      assert.equal(highlighted.status, "highlighted");
      assert.ok(
        (await readFile(entry, "utf8")).includes("#highlighted[External Codex edit wins.]"),
      );
      assert.ok(
        (await status()).completed > beforeHighlight.completed,
        "highlight candidates must use WASM",
      );
      await writeFile(entry, await readFile(new URL("fixtures/decorations.typ", import.meta.url)));
      const decorated = await compile();
      assert.equal(decorated.report.contentGatePassed, true);
      const geometry = async (width) => {
        const response = await fetch(origin + "/api/decorations", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            revision: decorated.revision,
            decorations: {
              "decoration-6": { fontSize: 24, ink: "#242c34", fragments: [{ width, height: 25 }] },
            },
          }),
        });
        assert.equal(response.status, 200, await response.clone().text());
        assert.ok((await response.json()).decorations["decoration-6"]);
      };
      const beforeGeometry = await status();
      await geometry(137);
      assert.ok(
        (await status()).completed > beforeGeometry.completed,
        "dynamic geometry must execute on browser",
      );
      await survivor.evaluate(() => window.dispatchEvent(new PageTransitionEvent("pagehide")));
      await until(status, (s) => s.workers === 0, "all Worker leases released");
      await geometry(145);
      assert.ok(
        (await status()).nativeDynamicRequests > 0,
        "offline Worker capacity falls back to native incremental compilation",
      );
      assert.deepEqual(errors, []);
      console.log(
        engine,
        "real Worker adoption, source carriers, pagehide reassignment, competing edits, highlight writes and dynamic rendering passed",
      );
    } finally {
      await browser.close();
    }
  }
} finally {
  service.stdin.end();
  await once(service, "exit");
  lines.close();
  await rm(work, { recursive: true, force: true });
}
