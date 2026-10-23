// Exercise real SVG paint and repeated/cloned themes in Chromium and WebKit.
// Optional FLOW_READER_DRAWING_DOCUMENT verifies the photographed compiled figure.
import assert from "node:assert/strict";
import { once } from "node:events";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { createServer } from "node:http";

const playwright = await import(process.env.FLOW_READER_PLAYWRIGHT_MODULE || "playwright");
const web = new URL("../web/", import.meta.url);
const assets = JSON.parse(await readFile(new URL("assets.json", web), "utf8"));
const routes = new Map([
  ["/tests/drawing-theme.html", new URL("drawing-theme.html", import.meta.url)],
  ["/tests/drawing-theme-browser.js", new URL("drawing-theme-browser.js", import.meta.url)],
  ...Object.entries(assets).map(([route, path]) => [`/web/${route}`, new URL(path, web)]),
]);
const compiled = process.env.FLOW_READER_DRAWING_DOCUMENT
  ? await readFile(process.env.FLOW_READER_DRAWING_DOCUMENT, "utf8")
  : null;
const screenshots = process.env.FLOW_READER_DRAWING_SCREENSHOTS;
if (screenshots) await mkdir(screenshots, { recursive: true });
const server = createServer(async (request, response) => {
  const file = routes.get(new URL(request.url, "http://localhost").pathname);
  if (!file) return response.writeHead(404).end();
  response.writeHead(200, {
    "Content-Type": file.pathname.endsWith(".js")
      ? "text/javascript"
      : file.pathname.endsWith(".css")
        ? "text/css"
        : "text/html",
  });
  response.end(await readFile(file));
});
server.listen(0, "127.0.0.1");
await once(server, "listening");
const url = `http://127.0.0.1:${server.address().port}/tests/drawing-theme.html`;

try {
  for (const engine of ["chromium", "webkit"]) {
    const browser = await playwright[engine].launch({
      headless: true,
      ...(engine === "chromium" ? { channel: "chrome" } : {}),
    });
    try {
      const page = await browser.newPage({ viewport: { width: 390, height: 844 } });
      const errors = [];
      page.on("pageerror", (error) => errors.push(error.message));
      await page.goto(url);
      let scenarios = 0;
      const compiledChecks = [];
      const cases = ["light", "dark", "light", "dark", "light"].map((theme) => ({
        theme,
        stage: 0,
      }));
      for (const stage of [1, 2, 3, 4])
        for (const theme of ["dark", "light", "dark"]) cases.push({ theme, stage });
      let currentStage = 0;
      for (const { theme, stage } of cases) {
        if (stage !== currentStage) {
          await page.click("#mutate");
          currentStage = stage;
          await page.waitForFunction(
            (stage) =>
              Number(document.body.dataset.auditStage) === stage &&
              document.body.dataset.audit !== "pending",
            stage,
          );
        }
        await page.selectOption("#reader-theme", theme);
        await page.waitForFunction(
          ({ theme, stage }) =>
            document.body.dataset.auditTheme === theme &&
            Number(document.body.dataset.auditStage) === stage &&
            document.body.dataset.audit !== "pending",
          { theme, stage },
        );
        if (scenarios === 1) {
          await page.click("#late");
          await page.waitForFunction(() => document.body.dataset.audit !== "pending");
        }
        const audit = JSON.parse(await page.locator("#report").textContent());
        assert.deepEqual(
          audit.errors,
          [],
          `${engine}/${theme}/stage ${stage}: ${JSON.stringify(audit)}`,
        );
        if (compiled) {
          const documentPaint = await page.evaluate(async (source) => {
            const { drawingBackground, drawingPaint, inkContrast, parseColor } = await import(
              "../web/features/appearance/drawing-theme.js"
            );
            const doc = new DOMParser().parseFromString(source, "text/html");
            let host = document.querySelector("#compiled-drawing");
            if (!host) {
              const caption = [...doc.querySelectorAll("figcaption")].find((node) =>
                node.textContent.includes("Successive reflections change orientation and sign"),
              );
              if (!caption) throw new Error("Photographed CeTZ figure is missing");
              host = document.createElement("div");
              host.id = "compiled-drawing";
              host.append(
                document.importNode(caption.closest("figure").querySelector("svg"), true),
              );
              document.querySelector("#reader-document").append(host);
            }
            const sourceFigures = [...doc.querySelectorAll("svg")].filter((svg) =>
              svg.querySelector('[fill^="oklab("]'),
            );
            let oklabHost = document.querySelector("#compiled-oklab");
            if (!oklabHost) {
              oklabHost = document.createElement("div");
              oklabHost.id = "compiled-oklab";
              for (const [index, svg] of sourceFigures.entries()) {
                const figure = document.createElement("figure");
                const caption = document.createElement("figcaption");
                caption.textContent = `Compiled Oklab figure ${index + 1}`;
                figure.append(document.importNode(svg, true), caption);
                oklabHost.append(figure);
              }
              document.querySelector("#reader-document").append(oklabHost);
            }
            await new Promise(requestAnimationFrame);
            await new Promise(requestAnimationFrame);
            const background = drawingBackground(host);
            const cells = [...host.querySelectorAll('[fill="#f0f5ff"],[fill="#f0ebf8"]')].map(
              (node) => {
                const fill = parseColor(getComputedStyle(node).fill);
                return {
                  source: node.getAttribute("fill"),
                  fill,
                  contrast: inkContrast(fill, background),
                };
              },
            );
            const oklab = [],
              foreground = [],
              figures = [];
            for (const [index, svg] of [...oklabHost.querySelectorAll("svg")].entries()) {
              const sourceSvg = sourceFigures[index];
              const originalNodes = [sourceSvg, ...sourceSvg.querySelectorAll("*")];
              const nodes = [svg, ...svg.querySelectorAll("*")];
              const paintBackground = drawingBackground(svg.parentElement);
              const ink = parseColor(getComputedStyle(svg).color);
              const fills = [...svg.querySelectorAll('[fill^="oklab("]')];
              for (const node of fills) {
                const authored = parseColor(node.getAttribute("fill"));
                const actual = parseColor(getComputedStyle(node).fill);
                const expected = drawingPaint(authored, paintBackground, ink, { paper: true });
                oklab.push({
                  source: node.getAttribute("fill"),
                  sourceRgb: authored,
                  actual,
                  expected: expected.slice(0, 3).map(Math.round),
                  converted: Boolean(node.style.fill),
                  alphaPreserved: (actual[3] ?? 1) === (authored[3] ?? 1),
                });
              }
              for (const node of svg.querySelectorAll("use,text,tspan,textPath,[stroke]")) {
                if (node.closest("defs,mask,clipPath,symbol")) continue;
                const glyph = node.matches("use,text,tspan,textPath");
                const color = parseColor(getComputedStyle(node)[glyph ? "fill" : "stroke"]);
                if (!color || (color[3] ?? 1) !== 1) continue;
                foreground.push({ glyph, contrast: inkContrast(color, paintBackground) });
              }
              const resources = "mask,clipPath,linearGradient,radialGradient,pattern";
              figures.push({
                fills: fills.length,
                sourceShades: new Set(fills.map((node) => node.getAttribute("fill"))).size,
                outputShades: new Set(fills.map((node) => getComputedStyle(node).fill)).size,
                attributesPreserved:
                  originalNodes.length === nodes.length &&
                  originalNodes.every((node, i) =>
                    [...node.attributes].every(
                      ({ name, value }) =>
                        name === "style" || nodes[i].getAttribute(name) === value,
                    ),
                  ),
                resourcesPreserved: [...sourceSvg.querySelectorAll(resources)].every(
                  (node, i) => node.outerHTML === svg.querySelectorAll(resources)[i].outerHTML,
                ),
              });
            }
            return { cells, oklab, foreground, figures };
          }, compiled);
          assert.equal(
            documentPaint.cells.length,
            10,
            `${engine}/${theme}: all photographed cell fills`,
          );
          assert.ok(
            documentPaint.cells.every((cell) => cell.contrast < 1.5),
            JSON.stringify(documentPaint.cells),
          );
          assert.equal(
            documentPaint.figures.length,
            4,
            `${engine}/${theme}: all compiled Oklab figures`,
          );
          assert.equal(
            documentPaint.oklab.length,
            34,
            `${engine}/${theme}: all compiled Oklab fills`,
          );
          assert.ok(
            documentPaint.oklab.every(
              (fill) =>
                fill.converted &&
                fill.alphaPreserved &&
                fill.expected.every((value, i) => Math.abs(value - fill.actual[i]) < 1),
            ),
            JSON.stringify(documentPaint.oklab),
          );
          assert.ok(
            documentPaint.figures.every(
              (figure) =>
                figure.attributesPreserved &&
                figure.resourcesPreserved &&
                (figure.sourceShades < 2 || figure.outputShades >= 2),
            ),
            JSON.stringify(documentPaint.figures),
          );
          assert.ok(
            documentPaint.foreground.length > 0 &&
              documentPaint.foreground.every((ink) => ink.contrast >= (ink.glyph ? 4.5 : 3)),
            JSON.stringify(documentPaint.foreground),
          );
          if (screenshots && scenarios < 2) {
            await page.locator("#compiled-oklab").screenshot({
              path: `${screenshots}/${engine}-${theme}-compiled-oklab.png`,
              style: ".reader-toolbar { visibility: hidden !important; }",
            });
            compiledChecks.push({ theme, ...documentPaint });
          }
          if (scenarios < 2)
            console.log(
              `${engine}/${theme}: ${JSON.stringify({ figures: documentPaint.figures, glyphs: documentPaint.foreground.filter((ink) => ink.glyph).length, vectors: documentPaint.foreground.filter((ink) => !ink.glyph).length })}`,
            );
        }
        if (screenshots && scenarios < 2)
          await page.screenshot({ path: `${screenshots}/${engine}-${theme}.png`, fullPage: true });
        scenarios++;
      }
      assert.deepEqual(errors, [], `${engine}: browser errors`);
      if (screenshots && compiled)
        await writeFile(
          `${screenshots}/${engine}-compiled-colors.json`,
          JSON.stringify(compiledChecks, null, 2),
        );
      console.log(
        `PASS ${engine}: ${scenarios} Oklab, inherited paint, currentColor, authored updates, shading, glyph, alpha, resource and clone/theme scenarios${compiled ? "; all 10 photographed CeTZ cells and 34 Oklab fills across 4 compiled figures" : ""}`,
      );
    } finally {
      await browser.close();
    }
  }
} finally {
  await new Promise((resolve) => server.close(resolve));
}
