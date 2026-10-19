// Browser-local mathematics, selection holds and stale composition in both engines.
import assert from "node:assert/strict";
import { once } from "node:events";
import { readFile } from "node:fs/promises";
import { createServer } from "node:http";

const playwright = await import(process.env.FLOW_READER_PLAYWRIGHT_MODULE || "playwright");
const web = new URL("../web/", import.meta.url);
const assets = JSON.parse(await readFile(new URL("assets.json", web), "utf8"));
const vendor = "vendor/mathjax-4.1.3/";
const manifest = JSON.parse(await readFile(new URL(vendor + "manifest.json", web), "utf8"));
for (const file of Object.keys(manifest.files)) assets[vendor + file] = vendor + file;
const shell = `<!doctype html><html lang="en"><head>
  <link rel="stylesheet" href="/reader.css"></head><body>
  <article id="reader-document" style="width:280px;margin:16px;font-size:18px"></article>
  <script type="module">
    import { ResponsiveMath } from "/rendering/math/renderer.js";
    const article = document.querySelector("article");
    const fixture = globalThis.fixture = { changes: 0 };
    const renderer = fixture.renderer = new ResponsiveMath(article, {
      preserve: change => change(), changed: () => fixture.changes++,
      selectionActive: () => !getSelection().isCollapsed,
    });
    fixture.populate = variable => {
      renderer.clear();
      article.innerHTML = '<p id="select">Keep this reading selection.</p>' +
        '<math display="block"><mrow><mfrac><mi>' + variable +
        '</mi><mn>2</mn></mfrac><mo>+</mo><mi>y</mi><mo>=</mo><mn>1</mn></mrow></math>';
      renderer.prepare(article);
      renderer.sync();
    };
    fixture.populate("x");
  </script></body></html>`;
const server = createServer(async (request, response) => {
  const route = new URL(request.url, "http://fixture.test").pathname.slice(1);
  if (!route) {
    response.writeHead(200, { "Content-Type": "text/html" });
    return response.end(shell);
  }
  const file = assets[route];
  if (!file) {
    response.writeHead(404);
    return response.end("Not found");
  }
  const type = route.endsWith(".js")
    ? "text/javascript"
    : route.endsWith(".css")
      ? "text/css"
      : route.endsWith(".woff2")
        ? "font/woff2"
        : "application/octet-stream";
  response.writeHead(200, { "Content-Type": type });
  response.end(await readFile(new URL(file, web)));
});
server.listen(0, "127.0.0.1");
await once(server, "listening");

try {
  for (const engine of ["chromium", "webkit"]) {
    const browser = await playwright[engine].launch({
      headless: true,
      ...(engine === "chromium" && process.env.FLOW_READER_CHROMIUM_CHANNEL
        ? { channel: process.env.FLOW_READER_CHROMIUM_CHANNEL }
        : {}),
    });
    try {
      const page = await browser.newPage({ viewport: { width: 390, height: 844 }, hasTouch: true });
      const errors = [];
      const apiRequests = [];
      page.on("pageerror", (error) => errors.push(error.message));
      page.on("request", (request) => {
        if (new URL(request.url()).pathname.startsWith("/api/")) apiRequests.push(request.url());
      });
      const ready = () =>
        page.waitForFunction(() => {
          const record = [...(globalThis.fixture?.renderer.records ?? [])][0];
          return record?.view.dataset.mathState === "ready";
        });
      await page.goto(`http://127.0.0.1:${server.address().port}/`);
      await ready();
      const before = await page.evaluate(() => {
        const range = document.createRange();
        range.selectNodeContents(document.querySelector("#select"));
        getSelection().addRange(range);
        document.querySelector("article").style.width = "190px";
        return [...fixture.renderer.records][0].key;
      });
      await page.waitForTimeout(350);
      assert.equal(await page.evaluate(() => [...fixture.renderer.records][0].key), before);
      assert.equal(
        await page.evaluate(() => getSelection().toString()),
        "Keep this reading selection.",
      );
      await page.evaluate(() => getSelection().removeAllRanges());
      await ready();
      assert.notEqual(await page.evaluate(() => [...fixture.renderer.records][0].key), before);

      // Hold a real MathJax candidate while the section is replaced. New work
      // must wait, and that old candidate must never replace the new expression.
      await page.evaluate(() => {
        const renderer = fixture.renderer;
        fixture.originalCandidate = renderer.candidate;
        renderer.candidate = async function (...args) {
          fixture.candidates = (fixture.candidates ?? 0) + 1;
          const result = await fixture.originalCandidate.apply(this, args);
          fixture.waiting = true;
          await new Promise((resolve) => (fixture.release = resolve));
          return result;
        };
        document.querySelector("article").style.fontSize = "24px";
      });
      await page.waitForFunction(() => fixture.waiting);
      await page.evaluate(() => fixture.renderer.render());
      assert.equal(await page.evaluate(() => fixture.candidates), 1);
      await page.evaluate(() => {
        fixture.renderer.candidate = fixture.originalCandidate;
        fixture.populate("z");
        fixture.release();
      });
      await ready();
      assert.equal((await page.locator("mjx-mi").first().textContent()).normalize("NFKC"), "z");
      await page.evaluate(() => fixture.renderer.dispose());
      const changes = await page.evaluate(() => fixture.changes);
      await page.evaluate(() => {
        document.querySelector("article").style.width = "220px";
        dispatchEvent(new Event("resize"));
      });
      await page.waitForTimeout(350);
      assert.equal(await page.evaluate(() => fixture.changes), changes);
      assert.deepEqual(apiRequests, [], "Math reflow must stay in the browser");
      assert.deepEqual(errors, []);
      console.log(
        `${engine}: local math reflow, selection hold, stale composition and disposal passed`,
      );
    } finally {
      await browser.close();
    }
  }
} finally {
  server.close();
  await once(server, "close");
}
