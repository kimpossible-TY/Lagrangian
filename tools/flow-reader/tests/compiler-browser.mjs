/* global compilerTest */
// Real WASM Worker contracts; optional frozen PDE corpus benchmark uses the same worker.
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { once } from "node:events";
import { readFile, writeFile } from "node:fs/promises";
import { createServer } from "node:http";
import { resolve, join } from "node:path";

const playwright = await import(process.env.FLOW_READER_PLAYWRIGHT_MODULE || "playwright");
const assets = resolve(process.env.FLOW_COMPILER_ASSETS || "dist/reader-compiler");
const manifest = JSON.parse(await readFile(join(assets, "manifest.json")));
const web = new URL("../web/", import.meta.url);
const corpus = process.env.FLOW_COMPILER_CORPUS && resolve(process.env.FLOW_COMPILER_CORPUS);
const blob = (path, content) => ({
  path,
  data: Buffer.from(content).toString("base64"),
  sha256: createHash("sha256").update(content).digest("hex"),
});
const snapshot = {
  schemaVersion: 1,
  identity: "test",
  engine: manifest.engine,
  target: "html",
  entry: "/workspace/main.typ",
  inputs: {},
  timestamp: 1760000000,
  fonts: [],
  files: [
    blob("/workspace/main.typ", '#include "part.typ"'),
    blob("/workspace/part.typ", "First $x^2$."),
  ],
};
const server = createServer(async (request, response) => {
  try {
    const path = new URL(request.url, "http://localhost").pathname;
    let content,
      type = "text/javascript";
    if (path === "/") {
      content = "<!doctype html><title>Compiler benchmark</title>";
      type = "text/html";
    } else if (path === "/compiler/worker.js" || path === "/compiler/runtime.js")
      content = await readFile(new URL(path.slice(1), web));
    else if (["/compiler.js", "/compiler_bg.wasm"].includes(path)) {
      content = await readFile(join(assets, path.slice(1)));
      if (path.endsWith(".wasm")) type = "application/wasm";
    } else if (corpus && path === "/snapshot.json") {
      content = await readFile(join(corpus, "snapshot.json"));
      type = "application/json";
    } else if (
      corpus &&
      request.method === "POST" &&
      /^\/result-(chromium|webkit)-\d+\.html$/.test(path)
    ) {
      const chunks = [];
      let size = 0;
      for await (const chunk of request) {
        size += chunk.length;
        if (size > 64 * 1024 * 1024) throw new Error("Oversized result");
        chunks.push(chunk);
      }
      await writeFile(join(corpus, path.slice(1)), Buffer.concat(chunks));
      content = "ok";
      type = "text/plain";
    } else {
      response.writeHead(404).end();
      return;
    }
    response.writeHead(200, { "Content-Type": type });
    response.end(content);
  } catch (error) {
    response.writeHead(500).end(String(error));
  }
});
server.listen(0, "127.0.0.1");
await once(server, "listening");
try {
  for (const engine of (process.env.FLOW_READER_BROWSER_ENGINES || "chromium,webkit").split(",")) {
    const browser = await playwright[engine].launch({
      headless: true,
      ...(engine === "chromium" && process.env.FLOW_READER_CHROMIUM_CHANNEL
        ? { channel: process.env.FLOW_READER_CHROMIUM_CHANNEL }
        : {}),
    });
    try {
      const page = await browser.newPage();
      await page.goto(`http://127.0.0.1:${server.address().port}/`);
      await page.evaluate(() => {
        const worker = new Worker("compiler/worker.js", { type: "module" });
        let id = 0;
        const pending = new Map();
        worker.onmessage = ({ data }) => {
          const done = pending.get(data.id);
          pending.delete(data.id);
          if (done) data.error ? done.reject(new Error(data.error)) : done.resolve(data);
        };
        worker.onerror = (error) => {
          for (const done of pending.values()) done.reject(new Error(error.message));
          pending.clear();
        };
        globalThis.compilerTest = {
          worker,
          request(body) {
            return new Promise((resolve, reject) => {
              const ticket = ++id;
              const timeout = setTimeout(() => {
                worker.terminate();
                reject(new Error("Worker deadline exceeded"));
              }, 300000);
              pending.set(ticket, {
                resolve: (result) => {
                  clearTimeout(timeout);
                  resolve(result);
                },
                reject: (error) => {
                  clearTimeout(timeout);
                  reject(error);
                },
              });
              worker.postMessage({ ...body, id: ticket });
            });
          },
        };
      });
      const init = await page.evaluate(
        (engine) =>
          compilerTest.request({
            type: "init",
            engine,
            moduleURL: "/compiler.js",
            wasmURL: "/compiler_bg.wasm",
          }),
        manifest.engine,
      );
      assert.equal(init.ready, true);
      const compile = (snapshot) =>
        page.evaluate(async (snapshot) => {
          const result = await compilerTest.request({ type: "compile", snapshot });
          return {
            ...result,
            artifact: undefined,
            text: new TextDecoder().decode(result.artifact),
          };
        }, snapshot);
      if (!corpus) {
        const first = await compile(snapshot);
        assert.equal(first.returncode, 0, first.stderr);
        assert.match(first.text, /First/);
        assert.ok(first.dependencies.includes("/workspace/part.typ"));
        const edited = structuredClone(snapshot);
        edited.files[1] = blob("/workspace/part.typ", "Second.");
        assert.match((await compile(edited)).text, /Second/);
        edited.files.pop();
        assert.notEqual((await compile(edited)).returncode, 0);
        edited.files.push(blob("/workspace/part.typ", "Restored."));
        edited.target = "pdf";
        const pdf = await compile(edited);
        assert.equal(pdf.returncode, 0, pdf.stderr);
        assert.ok(pdf.text.startsWith("%PDF"));
        console.log(
          engine,
          "Worker HTML/PDF, incremental edit, missing-input and restore passed",
          init,
        );
      }
      if (corpus) {
        const metadata = JSON.parse(await readFile(join(corpus, "corpus.json")));
        assert.equal(metadata.engine, manifest.engine, "Corpus must identify this compiler build");
        const results = { engine, init, corpus: metadata, runs: [] };
        await page.evaluate(async () => {
          compilerTest.snapshot = await (await fetch("snapshot.json")).json();
        });
        try {
          for (let run = 0; run < Number(process.env.FLOW_COMPILER_ROUNDS || 6); run++) {
            let watchdog;
            const deadline = new Promise((_, reject) => {
              watchdog = setTimeout(() => {
                reject(new Error("Browser process exceeded the external 300s compile deadline"));
                void browser.close();
              }, 300000);
            });
            let measured;
            try {
              measured = await Promise.race([
                deadline,
                page.evaluate(
                  async ({ entry, engine, run }) => {
                    const snapshot = structuredClone(compilerTest.snapshot);
                    const index = snapshot.files.findIndex((file) => file.path === entry);
                    if (index < 0) throw new Error("Benchmark entry missing");
                    if (run) {
                      const edited =
                        atob(snapshot.files[index].data) + `\n\nBrowser benchmark edit ${run}.\n`;
                      const bytes = Uint8Array.from(edited, (c) => c.charCodeAt(0));
                      const hash = [...new Uint8Array(await crypto.subtle.digest("SHA-256", bytes))]
                        .map((v) => v.toString(16).padStart(2, "0"))
                        .join("");
                      snapshot.files[index] = { path: entry, sha256: hash, data: btoa(edited) };
                    }
                    const started = performance.now();
                    const result = await compilerTest.request({ type: "compile", snapshot });
                    const totalMs = performance.now() - started;
                    if (result.returncode) throw new Error(result.stderr);
                    const transferStarted = performance.now();
                    const saved = await fetch(`result-${engine}-${run}.html`, {
                      method: "POST",
                      body: result.artifact,
                    });
                    if (!saved.ok) throw new Error("Could not save benchmark artifact");
                    return {
                      ...result.metrics,
                      totalMs,
                      outputTransferMs: performance.now() - transferStarted,
                      bytes: result.artifact.byteLength,
                      diagnostics: result.stderr,
                      userAgent: navigator.userAgent,
                      hardwareConcurrency: navigator.hardwareConcurrency,
                    };
                  },
                  { entry: metadata.entry, engine, run },
                ),
              ]);
            } finally {
              clearTimeout(watchdog);
            }
            results.runs.push(measured);
            // Persist evidence after each run, including when a later Worker dies.
            await writeFile(
              join(corpus, `measurements-${engine}.json`),
              JSON.stringify(results, null, 2) + "\n",
            );
            console.log(engine, "PDE run", run, measured);
          }
        } catch (error) {
          results.error = String(error);
          await writeFile(
            join(corpus, `measurements-${engine}.json`),
            JSON.stringify(results, null, 2) + "\n",
          );
          throw error;
        }
      }
      await page.evaluate(() => compilerTest.worker.terminate());
    } finally {
      await browser.close();
    }
  }
} finally {
  server.close();
  await once(server, "close");
}
