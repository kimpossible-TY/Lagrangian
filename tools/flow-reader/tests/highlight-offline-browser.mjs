// Real offline shell + durable intent + Python source validation and lost-response replay.
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { once } from "node:events";
import { mkdir, mkdtemp, readFile, rm, writeFile, access } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createInterface } from "node:readline";
import { fileURLToPath } from "node:url";

const playwright = await import(process.env.FLOW_READER_PLAYWRIGHT_MODULE || "playwright");
assert.ok(process.env.FLOW_READER_PACKAGES, "Set FLOW_READER_PACKAGES");
const work = await mkdtemp(join(tmpdir(), "flow-offline-highlight-"));
const root = fileURLToPath(new URL("../", import.meta.url));
await mkdir(join(work, "source"));
const entry = join(work, "source/main.typ");
const original =
  "#let highlighted(body) = highlight(body)\nFirst offline passage.\n\nSecond pending passage.\n\nNew selection remains active.\n";
await writeFile(entry, original);
const service = spawn(
  "python3",
  [
    "-u",
    "-c",
    `
from pathlib import Path
from http.server import ThreadingHTTPServer
import os, sys, threading
from flow_reader.compiler.project import Project
from flow_reader.server.state import ReaderState
from flow_reader.server.http import handler_for
root = Path(sys.argv[1])
project = Project(root / 'source', Path('main.typ'), Path(os.environ['FLOW_READER_PACKAGES']))
state = ReaderState(project, root / 'output', '', False)
state.compile()
assert state.revision, state.report
class Handler(handler_for(state)):
    def handle(self):
        if (root / 'disconnected').exists():
            return
        super().handle()
    def respond(self, *args, **kwargs):
        if self.path == '/api/highlight' and (root / 'lose-ack').exists():
            (root / 'lost-result').write_bytes(args[0])
            (root / 'lose-ack').unlink()
            (root / 'disconnected').write_text('Lost after the authoritative source write')
            return
        return super().respond(*args, **kwargs)
server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
threading.Thread(target=server.serve_forever, daemon=True).start()
print(server.server_port, flush=True)
try:
    for line in sys.stdin:
        state.compile()
        print(state.revision, flush=True)
finally:
    state.close()
    server.shutdown()
    server.server_close()
`,
    work,
  ],
  { env: { ...process.env, PYTHONPATH: root }, stdio: ["pipe", "pipe", "inherit"] },
);
const lines = createInterface({ input: service.stdout });
async function until(read, test, description) {
  const deadline = Date.now() + 60000;
  let value;
  while (Date.now() < deadline) {
    value = await read();
    if (test(value)) return value;
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  throw new Error(`Timed out: ${description}: ${JSON.stringify(value)}`);
}
try {
  const [port] = await once(lines, "line");
  const origin = `http://127.0.0.1:${port}/`;
  const compile = async () => {
    const done = once(lines, "line");
    service.stdin.write("compile\n");
    return (await done)[0];
  };
  for (const engine of (process.env.FLOW_READER_BROWSER_ENGINES || "chromium,webkit").split(",")) {
    await writeFile(entry, original);
    await compile();
    const browser = await playwright[engine].launch({
      headless: true,
      ...(engine === "chromium" ? { channel: "chrome" } : {}),
    });
    try {
      const page = await browser.newPage({ viewport: { width: 390, height: 844 } });
      const errors = [];
      page.on("pageerror", (error) => errors.push(error.message));
      const records = () =>
        page.evaluate(() =>
          Object.keys(localStorage)
            .filter((key) => key.startsWith("flow-reader:highlight-intents:v1:"))
            .map((key) => JSON.parse(localStorage.getItem(key))),
        );
      const select = async (text) => {
        await page.evaluate((text) => {
          const paragraph = [...document.querySelectorAll("[data-reader-key]")].find(
            (node) => node.textContent.trim() === text,
          );
          if (!paragraph) throw new Error("Selection paragraph missing");
          const range = document.createRange();
          range.selectNodeContents(paragraph);
          const selection = getSelection();
          selection.removeAllRanges();
          selection.addRange(range);
          document.dispatchEvent(new Event("selectionchange"));
        }, text);
        await page.locator("#reader-source-highlight").waitFor({ state: "visible" });
      };
      const ready = async () => {
        await page.waitForSelector("[data-reader-key]");
        await page.evaluate(() => navigator.serviceWorker.ready);
        await page.waitForFunction(() => navigator.serviceWorker.controller !== null);
        await page.waitForFunction(() =>
          document.querySelector("#reader-offline-status").textContent.includes("오프라인에서도"),
        );
      };
      const disconnect = async () => {
        await writeFile(join(work, "disconnected"), "offline");
        await page.reload();
        await page.waitForSelector("[data-reader-key]");
        await page.waitForFunction(
          () => document.querySelector("#reader-status").dataset.state === "offline",
        );
      };
      const reconnect = async () => {
        await rm(join(work, "disconnected"), { force: true });
        await page.evaluate(() => window.dispatchEvent(new Event("online")));
      };
      await page.goto(origin);
      await ready();
      await disconnect();
      await select("First offline passage.");
      await page.locator("#reader-source-highlight").click();
      await until(
        records,
        (items) => items.length === 1 && items[0].state === "pending",
        "offline intent persisted",
      );
      const queued = (await records())[0];
      assert.equal(await readFile(entry, "utf8"), original);
      await page.reload();
      await page.waitForSelector("[data-reader-key]");
      assert.equal((await records())[0].request.requestID, queued.request.requestID);
      await select("New selection remains active.");
      await reconnect();
      await until(
        () => readFile(entry, "utf8"),
        (text) => text.includes("#highlighted[First offline passage.]"),
        "queued highlight saved",
      );
      await until(records, (items) => items.length === 0, "acknowledged request removed");
      assert.equal(
        await page.evaluate(() => getSelection().toString().trim()),
        "New selection remains active.",
      );
      await page.evaluate(() => getSelection().removeAllRanges());
      await compile();
      await page.reload();
      await ready();

      // An actual source write succeeds but the response connection is dropped.
      await writeFile(join(work, "lose-ack"), "drop response");
      await select("Second pending passage.");
      await page.locator("#reader-source-highlight").click();
      await until(
        () =>
          access(join(work, "disconnected")).then(
            () => true,
            () => false,
          ),
        Boolean,
        "lost acknowledgment",
      );
      await until(records, (items) => items.length === 1, "uncertain transport keeps request");
      const lost = (await records())[0].request.requestID;
      const saved = await readFile(entry, "utf8");
      assert.ok(
        saved.includes("#highlighted[Second pending passage.]"),
        JSON.stringify({
          response: await readFile(join(work, "lost-result"), "utf8"),
          source: saved,
        }),
      );
      await compile();
      await page.reload();
      await page.waitForSelector("[data-reader-key]");
      assert.equal((await records())[0].request.requestID, lost);
      await reconnect();
      await until(records, (items) => items.length === 0, "durable receipt replayed after reload");
      assert.equal(await readFile(entry, "utf8"), saved);
      await page.reload();
      await ready();

      // An offline request cannot overwrite an external Codex edit.
      await disconnect();
      await select("New selection remains active.");
      await page.locator("#reader-source-highlight").click();
      await until(records, (items) => items.length === 1, "conflicting intent persisted");
      const external = saved.replace(
        "New selection remains active.",
        "Codex changed this paragraph.",
      );
      await writeFile(entry, external);
      await compile();
      await reconnect();
      await until(records, (items) => items[0]?.state === "rejected", "stale request rejected");
      assert.equal((await records())[0].result.status, "stale");
      assert.equal(await readFile(entry, "utf8"), external);
      assert.match(
        await page.locator("#reader-highlight-queue-status").textContent(),
        /확인이 필요한/,
      );
      assert.deepEqual(errors, []);
      console.log(
        engine,
        "offline reload/replay, lost acknowledgment, newer selection and conflicting source edit passed",
      );
    } finally {
      await rm(join(work, "disconnected"), { force: true });
      await browser.close();
    }
  }
} finally {
  service.stdin.end();
  await once(service, "exit");
  lines.close();
  await rm(work, { recursive: true, force: true });
}
