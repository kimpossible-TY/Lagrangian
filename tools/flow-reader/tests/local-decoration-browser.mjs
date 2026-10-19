// Real compiler + Reader shell: local request elimination and Typst SVG parity.
// Set FLOW_READER_PACKAGES and FLOW_READER_PLAYWRIGHT_MODULE as for other fixtures.
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { createInterface } from "node:readline";
import { once } from "node:events";

const playwright = await import(process.env.FLOW_READER_PLAYWRIGHT_MODULE || "playwright");
assert.ok(process.env.FLOW_READER_PACKAGES, "Set FLOW_READER_PACKAGES");
const output = await mkdtemp(`${tmpdir()}/flow-local-decoration-`);
const service = spawn(
  process.env.PYTHON || "python3",
  [
    new URL("../serve.py", import.meta.url).pathname,
    "--root",
    new URL("fixtures/", import.meta.url).pathname,
    "--entry",
    "local-decoration-paint.typ",
    "--package-path",
    process.env.FLOW_READER_PACKAGES,
    "--output",
    output,
    "--original-url",
    "https://example.invalid/paged",
    ...(process.env.FLOW_READER_TYPST ? ["--compiler", process.env.FLOW_READER_TYPST] : []),
  ],
  { stdio: ["ignore", "pipe", "pipe"] },
);
let log = "";
service.stderr.on("data", (value) => {
  log += value;
});
const lines = createInterface({ input: service.stdout });
try {
  const [line] = await once(lines, "line");
  const origin = JSON.parse(line).url;
  for (const engine of ["chromium", "webkit"]) {
    const browser = await playwright[engine].launch({
      headless: true,
      ...(engine === "chromium" ? { channel: "chrome" } : {}),
    });
    try {
      const page = await browser.newPage({ viewport: { width: 320, height: 740 } });
      const requests = [],
        errors = [];
      page.on("pageerror", (error) => errors.push(error.message));
      page.on("request", (request) => {
        if (request.url().endsWith("/api/decorations"))
          requests.push(Object.keys(request.postDataJSON().decorations));
      });
      await page.goto(origin);
      await page.waitForFunction(
        () => document.querySelectorAll(".flow-math-view[data-math-state=ready]").length === 10,
      );
      const revision = (await (await page.request.get(`${origin}api/manifest`)).json()).revision;
      const canonicalText = () =>
        page.evaluate(async () => {
          const { logicalTextIndex } = await import("/rendering/math/identity.js");
          return [...document.querySelectorAll(".flow-math-view")].map(
            (node) => logicalTextIndex(node, { includeNested: true }).text,
          );
        });
      const canonical = await canonicalText();
      // Compare explicit local primitives with the still-supported original
      // server callback at two reading fonts and two fragment shapes.
      for (const fontSize of [13, 30]) {
        const request = {
          fontSize,
          ink: "#aabbcc",
          fragments: [
            { width: 100, height: 30 },
            { width: 60, height: 25 },
          ],
        };
        const decorations = Object.fromEntries(
          [1, 2, 3, 4, 5].map((i) => [`decoration-${i}`, request]),
        );
        const response = await page.request.post(`${origin}api/decorations`, {
          data: { revision, decorations },
        });
        assert.ok(response.ok(), await response.text());
        const { decorations: reference } = await response.json();
        const parity = await page.evaluate(
          async ({ request, reference }) => {
            const { localDecorationPaint } = await import("/rendering/math/decoration-paint.js");
            const host = document.createElement("div");
            host.style.cssText = "position:fixed;left:-10000px;top:0";
            document.body.append(host);
            const geometry = (source) => {
              host.innerHTML = source;
              return [...host.querySelectorAll("path,rect")].map((shape) => {
                const m = shape.getCTM(),
                  box = shape.getBBox();
                const point = (x, y) => {
                  const p = new DOMPoint(x, y).matrixTransform(m);
                  return [p.x, p.y];
                };
                const line =
                  shape.localName === "path" &&
                  shape.getAttribute("fill") === "none" &&
                  !/[zZ]/.test(shape.getAttribute("d"));
                const corners = [
                  [box.x, box.y],
                  [box.x + box.width, box.y],
                  [box.x, box.y + box.height],
                  [box.x + box.width, box.y + box.height],
                ].map(([x, y]) => point(x, y));
                return {
                  fill: shape.getAttribute("fill"),
                  stroke: shape.getAttribute("stroke") || "none",
                  thickness:
                    (Number(shape.getAttribute("stroke-width")) || 0) * Math.hypot(m.a, m.b),
                  box: [
                    Math.min(...corners.map((p) => p[0])),
                    Math.min(...corners.map((p) => p[1])),
                    Math.max(...corners.map((p) => p[0])),
                    Math.max(...corners.map((p) => p[1])),
                  ],
                  ends: line
                    ? [0, shape.getTotalLength()].flatMap((distance) => {
                        const p = shape.getPointAtLength(distance);
                        return point(p.x, p.y);
                      })
                    : null,
                };
              });
            };
            const results = [];
            try {
              for (const [id, drawings] of Object.entries(reference)) {
                const node = document.querySelector(
                  `.flow-math-view [data-flow-decoration="${id}"]`,
                );
                const local = localDecorationPaint({ nodes: [node] }, request);
                for (const drawing of drawings) {
                  const candidate = local[drawing.fragment];
                  results.push({
                    id,
                    fragment: drawing.fragment,
                    local: { layout: candidate.layout, shapes: geometry(candidate.svg) },
                    server: { layout: drawing.layout, shapes: geometry(drawing.svg) },
                  });
                }
              }
            } finally {
              host.remove();
            }
            return results;
          },
          { request, reference },
        );
        const close = (a, b, context) => {
          if (typeof a === "number") assert.ok(Math.abs(a - b) < 0.005, `${context}: ${a} != ${b}`);
          else if (a && typeof a === "object") {
            assert.deepEqual(Object.keys(a), Object.keys(b), context);
            for (const key of Object.keys(a)) close(a[key], b[key], `${context}.${key}`);
          } else assert.equal(a, b, context);
        };
        for (const result of parity)
          close(
            result.local,
            result.server,
            `${engine}/${fontSize}/${result.id}/${result.fragment}`,
          );
      }
      for (const [width, font] of [
        [320, 30],
        [768, 18],
        [390, 13],
      ]) {
        await page.setViewportSize({ width, height: 1000 });
        await page.evaluate((font) => {
          while (+document.querySelector("#reader-size").value !== font)
            document
              .querySelector(
                +document.querySelector("#reader-size").value < font
                  ? "#reader-larger"
                  : "#reader-smaller",
              )
              .click();
        }, font);
        await page.waitForTimeout(300);
        for (let id = 1; id <= 10; id++) {
          await page.evaluate((id) => {
            const node = [
              ...document.querySelectorAll(`[data-flow-decoration="decoration-${id}"]`),
            ].find((node) => !node.closest("mjx-assistive-mml,.flow-math-stage"));
            node.closest(".flow-math-view").scrollIntoView({ block: "center" });
          }, id);
          await page.waitForFunction((id) => {
            const nodes = [
              ...document.querySelectorAll(
                `.flow-math-view [data-flow-decoration="decoration-${id}"]`,
              ),
            ].filter(
              (node) =>
                !node.closest("mjx-assistive-mml,.flow-math-stage") &&
                node.getBoundingClientRect().width,
            );
            return nodes.length && nodes.every((node) => node.dataset.decorationState === "ready");
          }, id);
        }
      }
      assert.ok(requests.length, "Unsupported callbacks must retain server rendering");
      assert.ok(
        requests.flat().every((id) => +id.split("-")[1] > 5),
        JSON.stringify(requests),
      );
      await page.emulateMedia({ colorScheme: "dark" });
      await page.waitForTimeout(350);
      assert.ok(
        requests.flat().every((id) => +id.split("-")[1] > 5),
        "Theme uses local primitives too",
      );
      assert.deepEqual(await canonicalText(), canonical);
      assert.deepEqual(errors, []);
      console.log(
        `PASS ${engine}: Typst paint parity, reflow, theme, semantic text; ${requests.length} fallback requests, zero supported requests`,
      );
      await page.close();
    } finally {
      await browser.close();
    }
  }
} catch (error) {
  console.error(log.slice(-4000));
  throw error;
} finally {
  lines.close();
  service.kill("SIGTERM");
  if (service.exitCode === null) await once(service, "exit");
  await rm(output, { recursive: true, force: true });
}
