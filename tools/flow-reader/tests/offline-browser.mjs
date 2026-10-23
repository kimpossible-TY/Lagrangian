// Real compiler, HTTP server, Service Worker and offline restart in an isolated project.
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { once } from "node:events";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createInterface } from "node:readline";
import { fileURLToPath } from "node:url";

const playwright = await import(process.env.FLOW_READER_PLAYWRIGHT_MODULE || "playwright");
assert.ok(process.env.FLOW_READER_PACKAGES, "Set FLOW_READER_PACKAGES");
const root = fileURLToPath(new URL("../", import.meta.url));
const work = await mkdtemp(join(tmpdir(), "flow-offline-"));
const source = (revision) =>
  Array.from(
    { length: 170 },
    (_, i) =>
      `Paragraph ${i}, ${revision}. Offline reading keeps mathematics $x^2 + y^2$ available.\n\n`,
  ).join("");
await writeFile(join(work, "main.typ"), source("first"));
const script = `
from pathlib import Path
from http.server import ThreadingHTTPServer
import os, sys, threading
from flow_reader.compiler.project import Project
from flow_reader.server.state import ReaderState
from flow_reader.server.http import handler_for
root = Path(sys.argv[1])
project = Project(root, Path('main.typ'), Path(os.environ['FLOW_READER_PACKAGES']), compiler=os.environ.get('FLOW_READER_TYPST', 'typst'))
state = ReaderState(project, root / 'output', '', False)
state.compile()
assert state.revision, state.report
class Handler(handler_for(state)):
    def handle(self):
        if (root / 'disconnected').exists():
            return
        super().handle()
server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
threading.Thread(target=server.serve_forever, daemon=True).start()
print(server.server_port, flush=True)
try:
    for line in sys.stdin:
        state.compile()
        print(state.revision, flush=True)
finally:
    server.shutdown()
    state.close()
`;
const service = spawn("python3", ["-u", "-c", script, work], {
  env: { ...process.env, PYTHONPATH: root },
  stdio: ["pipe", "pipe", "inherit"],
});
const lines = createInterface({ input: service.stdout });
try {
  const [port] = await once(lines, "line");
  assert.match(port, /^\d+$/);
  const url = `http://127.0.0.1:${port}/`;
  for (const engine of (process.env.FLOW_READER_BROWSER_ENGINES || "webkit").split(",")) {
    await writeFile(join(work, "main.typ"), source("first"));
    const reset = once(lines, "line");
    service.stdin.write("compile\n");
    await reset;
    const browser = await playwright[engine].launch({
      headless: true,
      ...(engine === "chromium" && process.env.FLOW_READER_CHROMIUM_CHANNEL
        ? { channel: process.env.FLOW_READER_CHROMIUM_CHANNEL }
        : {}),
    });
    try {
      const context = await browser.newContext({ viewport: { width: 390, height: 844 } });
      const page = await context.newPage();
      const errors = [];
      // Playwright WebKit's offline emulation fails navigation before SW dispatch.
      // Drop actual server connections for WebKit; Chrome also exercises navigator.offline.
      const disconnect = async (value) => {
        if (engine === "webkit") {
          if (value) await writeFile(join(work, "disconnected"), "");
          else await rm(join(work, "disconnected"), { force: true });
        } else await context.setOffline(value);
      };
      page.on("pageerror", (error) => errors.push(error.message));
      await page.goto(url);
      await page.waitForSelector("mjx-container", { timeout: 60000 });
      await page.evaluate(() => navigator.serviceWorker.ready);
      await page.waitForFunction(
        () =>
          document.querySelector("#reader-offline-status").textContent.includes("오프라인에서도"),
        null,
        { timeout: 60000 },
      );
      await page.evaluate(() => navigator.serviceWorker.ready);
      await page.waitForFunction(() => navigator.serviceWorker.controller !== null);
      await disconnect(true);
      await page.reload();
      await page.waitForSelector("mjx-container", { timeout: 30000 }).catch(async (error) => {
        console.error(
          await page.evaluate(async () => ({
            status: document.querySelector("#reader-status")?.textContent,
            body: document.querySelector("#reader-document")?.innerHTML.slice(0, 500),
            controller: navigator.serviceWorker.controller?.scriptURL,
            caches: await caches.keys(),
            state: await fetch("api/state")
              .then((r) => r.text())
              .catch(String),
          })),
          errors,
        );
        throw error;
      });
      await page.waitForFunction(
        () => document.querySelector("#reader-status").dataset.state === "offline",
      );
      assert.match(await page.locator("#reader-document").innerText(), /first/);
      // The second section was never mounted before the offline restart.
      const cached = await page.evaluate(async () => {
        const state = await (await fetch("api/state")).json();
        const manifest = await (await fetch(`api/manifest?revision=${state.revision}`)).json();
        const last = manifest.sections.at(-1).id;
        const section = await (
          await fetch(`api/sections/${last}?revision=${state.revision}`)
        ).text();
        return { sections: manifest.sections.length, section };
      });
      assert.ok(cached.sections > 1);
      assert.match(cached.section, /Paragraph 169/);
      await writeFile(join(work, "main.typ"), source("second"));
      const compiled = once(lines, "line");
      service.stdin.write("compile\n");
      const [newRevision] = await compiled;
      await disconnect(false);
      await page.evaluate(() => window.dispatchEvent(new Event("online")));
      await page.waitForFunction(
        () => document.querySelector("#reader-document").textContent.includes("second"),
        null,
        { timeout: 30000 },
      );
      // This WebKit build resolves waitForFunction(async () => false) immediately.
      // Await actual CacheStorage values in Node before disconnecting the server.
      const deadline = Date.now() + 30000;
      let cachedRevision;
      while (Date.now() < deadline) {
        cachedRevision = await page.evaluate(async () => {
          const meta = (await caches.keys()).find((name) => name.endsWith(":meta"));
          if (!meta) return null;
          const cache = await caches.open(meta);
          const keys = await cache.keys();
          if (!keys.length) return null;
          const pointer = await (await cache.match(keys[0])).json();
          return JSON.parse(pointer.identity)[1];
        });
        if (cachedRevision === newRevision) break;
        await new Promise((resolve) => setTimeout(resolve, 100));
      }
      assert.equal(cachedRevision, newRevision, "New accepted snapshot was committed");
      await disconnect(true);
      await page.reload();
      await page
        .waitForFunction(() =>
          document.querySelector("#reader-document").textContent.includes("second"),
        )
        .catch(async (error) => {
          console.error(
            "offline second",
            await page.evaluate(async () => {
              const names = await caches.keys();
              const cache = await caches.open(names.find((name) => name.endsWith(":meta")));
              const keys = await cache.keys();
              const pointer = keys.length ? await (await cache.match(keys[0])).json() : null;
              const current = pointer ? await caches.open(pointer.current) : null;
              return {
                names,
                pointer,
                entries: current ? (await current.keys()).map((k) => k.url) : [],
                status: document.querySelector("#reader-status").textContent,
                body: document.querySelector("#reader-document").textContent.slice(0, 200),
              };
            }),
            errors,
          );
          throw error;
        });
      assert.deepEqual(errors, []);
      console.log(
        `${engine}: PWA installation, complete snapshot, offline math/reload and reconnect passed`,
      );
      await disconnect(false);
      await context.close();
    } finally {
      await browser.close();
    }
  }
} finally {
  lines.close();
  service.stdin.end();
  service.kill("SIGTERM");
  await once(service, "exit");
  await rm(work, { recursive: true, force: true });
}
