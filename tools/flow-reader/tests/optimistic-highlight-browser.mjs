// Real DOM geometry and delayed acknowledgments; compiler correctness has separate fixtures.
// FLOW_READER_PLAYWRIGHT_MODULE=/path/to/playwright/index.mjs node <this file>
import assert from "node:assert/strict";
import { mkdir, readFile } from "node:fs/promises";
import { createServer } from "node:http";
import { fileURLToPath } from "node:url";
import { build } from "esbuild";

const playwright = await import(process.env.FLOW_READER_PLAYWRIGHT_MODULE || "playwright");
const root = new URL("../../../", import.meta.url);
const web = new URL("tools/flow-reader/web/", root);
const assets = JSON.parse(await readFile(new URL("assets.json", web), "utf8"));
const shell = await readFile(new URL("index.html", web), "utf8");
const text =
  "Selected words span several lines and remain visible while source verification compiles.";
const bundle = await build({
  stdin: {
    resolveDir: fileURLToPath(root),
    contents: `
      import { ReaderSelectionActions } from './tools/flow-reader/web/features/selection/controller.js';
      import { SelectionActions } from './tools/typst-preview-frontend/src/features/selection/actions.ts';
      const article = document.querySelector('#reader-document');
      const paged = location.search.includes('paged');
      const text = ${JSON.stringify(text)};
      let revision = 'r1';
      const manifest = () => ({documentID: 'fixture', revision, service: {pid: 17}});
      const content = (saved = false) => '<p data-reader-key="body">' + (saved ? '<mark>' : '') + text + (saved ? '</mark>' : '') + '</p><p>Unselected text remains unchanged.</p>';
      if (paged) {
        article.innerHTML = '<svg width="0" height="0"></svg><div class="typst-page" data-page-number="0"><div class="typst-page-inner" data-page-number="0" data-page-width="320" data-page-height="440"><span class="line"><span class="tsel">' + text + '</span></span><p>Unselected text remains unchanged.</p></div></div>';
      } else article.innerHTML = content();
      const actions = paged
        ? new SelectionActions(article, () => true, () => revision)
        : new ReaderSelectionActions(article, { editorServer: 'fixture-editor' });
      const publish = (next, saved = false) => {
        revision = next;
        if (paged) actions.setDocument('fixture', revision);
        else { article.innerHTML = content(saved); actions.onDocument(manifest(), 'body'); }
      };
      publish('r1');
      if (paged) actions.setEnabled(true);
      window.fixture = {
        article, actions, publish,
        select() {
          const node = article.querySelector(paged ? '.tsel' : '[data-reader-key]').firstChild;
          const range = document.createRange(); range.selectNodeContents(node);
          getSelection().removeAllRanges(); getSelection().addRange(range);
          document.dispatchEvent(new Event('selectionchange'));
          if (!paged) actions.capture();
        },
        submit() { document.querySelector(paged ? '.typst-selection-actions button' : '#reader-source-highlight').click(); },
        settle(status) { actions.highlightFinished(status); },
        reflow() { if (paged) article.dispatchEvent(new Event('typst-text-layout')); else actions.repaint(); },
      };
    `,
  },
  bundle: true,
  format: "esm",
  write: false,
});
let response;
let requestBody;
const server = createServer(async (request, result) => {
  try {
    const path = new URL(request.url, "http://localhost").pathname.slice(1);
    if (path === "api/highlight") {
      const chunks = [];
      for await (const chunk of request) chunks.push(chunk);
      requestBody = JSON.parse(Buffer.concat(chunks));
      response = result;
      return;
    }
    let body;
    let type = "text/html";
    if (!path) {
      body = shell
        .replace('src="reader.js"', 'src="window.fixture.js"')
        .replace(
          "</head>",
          '<link rel="stylesheet" href="paged.css"><style>#reader-document { font-size: 18px; padding: 20px; max-width: 800px; } .typst-page-inner { width: 320px; min-height: 440px; } .line { display: inline; }</style></head>',
        );
    } else if (path === "window.fixture.js") {
      body = bundle.outputFiles[0].contents;
      type = "text/javascript";
    } else if (path === "paged.css") {
      body = await readFile(
        new URL("tools/typst-preview-frontend/src/styles/selection-actions.css", root),
      );
      type = "text/css";
    } else if (assets[path]) {
      body = await readFile(new URL(assets[path], web));
      type = path.endsWith(".css") ? "text/css" : path.endsWith(".js") ? "text/javascript" : type;
    }
    result.writeHead(body === undefined ? 404 : 200, { "Content-Type": type });
    result.end(body);
  } catch (error) {
    result.writeHead(500).end(String(error));
  }
});
await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
const url = `http://127.0.0.1:${server.address().port}/`;
const reply = (status) => {
  response.writeHead(200, { "Content-Type": "application/json" });
  response.end(JSON.stringify({ status }));
  response = undefined;
};

async function verify(browser, paged, theme, engine) {
  const page = await browser.newPage({ viewport: { width: 390, height: 844 } });
  const errors = [];
  page.on("pageerror", (error) => errors.push(error.message));
  await page.goto(url + (paged ? "?paged" : ""));
  await page.waitForFunction(() => window.fixture);
  await page.evaluate((theme) => (document.documentElement.dataset.theme = theme), theme);
  const marks = page.locator(".reader-optimistic-highlights span");
  const submit = async () => {
    await page.evaluate(() => {
      window.fixture.select();
      window.fixture.submit();
    });
    await page.waitForFunction(() => document.querySelector(".reader-optimistic-highlights span"));
    if (!paged) {
      await page.waitForFunction(() =>
        document.querySelector('#reader-selection[aria-busy="true"]'),
      );
      assert.equal(requestBody.editorServer, "fixture-editor");
    }
  };
  await submit();
  assert.equal(await page.evaluate(() => getSelection().isCollapsed), true);
  assert.equal(
    await page.locator("#reader-document").textContent(),
    text + "Unselected text remains unchanged.",
  );
  const before = await marks.first().boundingBox();
  assert.ok(before.width > 0 && before.height > 0);
  await page.evaluate(() => {
    if (location.search) {
      const page = window.fixture.article.querySelector(".typst-page");
      page.style.transform = "scale(1.2)";
      page.style.transformOrigin = "top left";
    } else {
      window.fixture.article.style.fontSize = "26px";
      window.fixture.article.style.width = "290px";
    }
    window.fixture.reflow();
  });
  await page.waitForFunction(
    (minimum) =>
      [...document.querySelectorAll(".reader-optimistic-highlights span")].some(
        (node) => parseFloat(node.style.height) > minimum,
      ),
    paged ? before.height * 1.1 : 25,
  );
  assert.ok((await marks.count()) > 1, "wrapped selection retains multiple highlight fragments");
  assert.equal(
    await page.evaluate(() =>
      document.querySelector(".reader-optimistic-highlights").getAttribute("aria-hidden"),
    ),
    "true",
  );
  assert.equal(
    await page.evaluate(
      () => getComputedStyle(document.querySelector(".reader-optimistic-highlights")).pointerEvents,
    ),
    "none",
  );
  if (process.env.FLOW_READER_HIGHLIGHT_EVIDENCE) {
    await mkdir(process.env.FLOW_READER_HIGHLIGHT_EVIDENCE, { recursive: true });
    await page.screenshot({
      path: `${process.env.FLOW_READER_HIGHLIGHT_EVIDENCE}/${engine}-${paged ? "paged" : "html"}-${theme}.png`,
    });
  }
  if (paged) await page.evaluate(() => window.fixture.settle("highlighted"));
  else {
    reply("highlighted");
    await page.waitForFunction(() => !window.fixture.actions.source.pending);
  }
  assert.ok(await marks.count(), "write success must retain paint until accepted publication");
  await page.evaluate(() => window.fixture.publish("r2", true));
  assert.equal(await marks.count(), 0);
  if (!paged) assert.equal(await page.locator("#reader-document mark").textContent(), text);

  await page.evaluate(() => window.fixture.publish("r3"));
  await submit();
  if (paged) await page.evaluate(() => window.fixture.settle("unsupported"));
  else {
    reply("unsupported");
    await page.waitForFunction(() => !window.fixture.actions.source.pending);
  }
  assert.equal(await marks.count(), 0, "rejection rolls back temporary paint");
  if (!paged)
    assert.equal(await page.evaluate(() => window.fixture.actions.selection[0].exact), text);
  await submit();
  await page.evaluate(() => window.fixture.publish("r4"));
  if (paged) await page.evaluate(() => window.fixture.settle("highlighted"));
  else {
    reply("highlighted");
    await page.waitForFunction(() => !window.fixture.actions.source.pending);
  }
  assert.equal(await marks.count(), 0, "late success never restores superseded paint");
  await page.evaluate(() => window.fixture.actions.dispose());
  assert.equal(await page.locator(".reader-optimistic-highlights").count(), 0);
  assert.deepEqual(errors, []);
  await page.close();
}

try {
  for (const engine of ["chromium", "webkit"]) {
    const browser = await playwright[engine].launch(
      engine === "chromium"
        ? {
            executablePath:
              process.env.FLOW_READER_CHROME ||
              "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
          }
        : {},
    );
    try {
      for (const paged of [false, true])
        for (const theme of ["light", "dark"]) {
          await verify(browser, paged, theme, engine);
          console.log(
            `${engine} ${paged ? "paged" : "HTML/terminal"} ${theme}: immediate paint, reflow, accepted replacement, rejection and stale response passed`,
          );
        }
    } finally {
      await browser.close();
    }
  }
} finally {
  response?.end();
  server.closeAllConnections();
  await new Promise((resolve) => server.close(resolve));
}
