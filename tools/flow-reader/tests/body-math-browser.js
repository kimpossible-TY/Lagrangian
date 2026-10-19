import { ResponsiveMath } from "/rendering/math/renderer.js";
import { logicalTextIndex } from "/rendering/math/identity.js";
import { mathOverflow } from "/rendering/math/layout.js";

// Observe the real renderer without changing its viewport eligibility, budgets,
// scheduling or publication. Scroll uncomposed passages into the normal margin;
// already current, nearby expressions need no additional scroll or render.
let renderer;
const measure = ResponsiveMath.prototype.measure;
ResponsiveMath.prototype.measure = function (record) {
  if (this.article.id === "reader-document") renderer = this;
  return measure.call(this, record);
};
const report = { width: innerWidth, checks: 0, errors: [], sections: [], failures: [] };
const notice = ResponsiveMath.prototype.notice;
if (new URL(location.href).searchParams.has("trace")) {
  ResponsiveMath.prototype.notice = function (record, message) {
    const snapshot = () => {
      const measurement = this.measure(record);
      return (
        measurement && {
          measurement,
          bounds: mathOverflow(record.view, measurement),
          rect: record.view.getBoundingClientRect().toJSON(),
          wrapper: record.view.parentElement.getBoundingClientRect().toJSON(),
        }
      );
    };
    const before = record.view.dataset.mathState === "overflow" && snapshot();
    notice.call(this, record, message);
    if (before) {
      report.trace ??= [];
      report.trace.push({ text: text(record.template), before, after: snapshot() });
    }
  };
}
const output = document.createElement("script");
output.type = "application/json";
output.id = "body-math-report";
const progress = document.createElement("pre");
progress.id = "body-math-progress";
progress.style.cssText =
  "white-space:pre-wrap;overflow-wrap:anywhere;font:13px/1.5 monospace;margin:16px";
document.body.append(output, progress);
const publish = () => {
  // Thousands of diagnostic strings must not become part of the laid-out
  // reading page or its accessibility tree while scrolling the real content.
  output.textContent = JSON.stringify(report);
  progress.textContent = JSON.stringify(
    {
      width: report.width,
      active: report.active,
      sections: report.sections.length,
      checks: report.checks,
      errors: report.errors,
      failures: report.failures.length,
    },
    null,
    2,
  );
};
function check(name, condition) {
  report.checks++;
  if (!condition) report.errors.push(name);
}
async function until(condition, name, timeout = 90000) {
  const deadline = Date.now() + timeout;
  while (!condition()) {
    if (Date.now() > deadline) throw new Error(`Timed out: ${name}`);
    await new Promise((resolve) => setTimeout(resolve, 40));
  }
}
const text = (node) => logicalTextIndex(node, { includeNested: true }).text;
try {
  const query = new URL(location.href).searchParams;
  report.dynamicPaint = !query.has("math-only");
  if (query.has("audit")) {
    const { attachReport } = await import("/test-report.js");
    attachReport({ kind: "body-math", id: "body-math-report", stateKey: "bodyMathState" });
  }
  if (query.get("width"))
    await until(() => innerWidth === Number(query.get("width")), "requested viewport");
  report.width = innerWidth;
  await until(() => renderer && document.querySelector("[data-reader-key]"), "Reader body");
  const manifest = await (await fetch("/api/manifest")).json();
  report.revision = manifest.revision;
  const sections = await Promise.all(
    manifest.sections.map(async (section) => {
      const source = new DOMParser().parseFromString(
        await (await fetch(`/api/sections/${section.id}?revision=${manifest.revision}`)).text(),
        "text/html",
      );
      return { id: section.id, anchor: source.querySelector("[data-reader-key]")?.id };
    }),
  );
  check(
    "Every transport section has an ordinary reading anchor",
    sections.every((s) => s.anchor),
  );
  const fonts = query.get("fonts") ? query.get("fonts").split(",").map(Number) : [18, 30];
  const start = Number(query.get("start") ?? 0);
  const end = Number(query.get("end") ?? sections.length);
  if (!Number.isInteger(start) || start < 0 || start >= sections.length)
    throw new Error("Invalid first transport section");
  if (!Number.isInteger(end) || end <= start || end > sections.length)
    throw new Error("Invalid last transport section");
  for (const font of fonts) {
    while (Number(document.querySelector("#reader-size").value) !== font)
      document
        .querySelector(
          Number(document.querySelector("#reader-size").value) < font
            ? "#reader-larger"
            : "#reader-smaller",
        )
        .click();
    for (const section of sections.slice(start, end)) {
      // Exercise the Reader's actual link handler. A direct location.hash write
      // inherits history state and can restore an older saved reading anchor.
      const link = document.createElement("a");
      link.href = `#${section.anchor}`;
      document.getElementById("reader-document").append(link);
      link.click();
      link.remove();
      await until(
        () =>
          document.getElementById(section.anchor) &&
          document.getElementById("reader-document").getAttribute("aria-busy") === "false",
        `${section.id} mounted`,
      );
      await new Promise(requestAnimationFrame);
      document.getElementById(section.anchor).scrollIntoView({ block: "start" });
      const root = document.getElementById(section.anchor).closest("[data-reader-section]");
      const records = [...renderer.records].filter(
        ({ view }) =>
          root.contains(view) &&
          !view.closest("table,[data-flow-canvas-model],.flow-graphic-scene"),
      );
      const checksBefore = report.checks;
      const errorsBefore = report.errors.length;
      const bodyViews = [...root.querySelectorAll(".flow-math-view")].filter(
        (view) => !view.closest("table,[data-flow-canvas-model],.flow-graphic-scene"),
      );
      check(
        `${font}px ${section.id} audits every body expression`,
        records.length === bodyViews.length,
      );
      const stats = {
        font,
        viewport: innerWidth,
        section: section.id,
        expressions: records.length,
        widths: [],
        fontSizes: [],
        ready: 0,
        scrolls: 0,
        alreadyCurrent: 0,
        decoratedExpressions: 0,
      };
      const widths = new Set();
      const sizes = new Set();
      for (const [index, record] of records.entries()) {
        report.active = { font, section: section.id, expression: index + 1 };
        const expected = text(record.template);
        // The Reader preserves its 90px reading reference. Centering a short
        // passage can leave that reference inside a preceding, expanding
        // formula; align the audited passage with the reference instead.
        const current = () => {
          if (!record.view.isConnected) throw new Error("Audited passage was replaced");
          const measurement = renderer.measure(record);
          return (
            measurement &&
            (record.view.dataset.mathState === "error" ||
              (record.key === measurement.key &&
                ["ready", "overflow"].includes(record.view.dataset.mathState)))
          );
        };
        if (current()) stats.alreadyCurrent++;
        else {
          stats.scrolls++;
          record.view.scrollIntoView({ block: "start" });
          await new Promise(requestAnimationFrame);
          renderer.schedule(0);
          await until(current, `${font}px ${section.id} expression ${index + 1}`);
        }
        const measurement = renderer.measure(record);
        const bounds = mathOverflow(record.view, measurement);
        const prefix = `${font}px ${section.id} expression ${index + 1}`;
        widths.add(Math.round(measurement.width * 100) / 100);
        sizes.add(measurement.fontSize);
        check(
          `${prefix} publishes complete native mathematics`,
          record.view.dataset.mathState === "ready",
        );
        check(`${prefix} retains its canonical source`, text(record.view) === expected);
        check(`${prefix} bounds all horizontal ink`, Math.max(bounds.left, bounds.right) <= 1);
        if (record.view.dataset.mathState === "ready") stats.ready++;
        else
          report.failures.push({
            ...stats,
            index: index + 1,
            text: expected,
            anchor: record.view.closest("[data-reader-key]")?.id,
            state: record.view.dataset.mathState,
            width: measurement.width,
            bounds,
            notice: record.notice?.textContent,
          });
        const decorations = () =>
          [...record.view.querySelectorAll("[data-flow-decoration]")].filter(
            (node) => !node.closest("mjx-assistive-mml"),
          );
        if (report.dynamicPaint && decorations().length) {
          stats.decoratedExpressions++;
          // The decoration margin is narrower than the math prefetch margin.
          // Read the marked passage itself before requiring its original paint.
          record.view.scrollIntoView({ block: "start" });
          await new Promise(requestAnimationFrame);
          await until(
            () =>
              current() &&
              decorations().every(
                (node) =>
                  node.dataset.decorationState === "error" ||
                  (node.dataset.decorationState === "ready" && node.dataset.flowAnchor),
              ),
            `${prefix} original decoration paint`,
            300000,
          );
          check(
            `${prefix} paints every visible emphasis or cancellation without visiting a copy`,
            decorations().every(
              (node) => node.dataset.decorationState === "ready" && node.dataset.flowAnchor,
            ),
          );
        }
        if ((index + 1) % 32 === 0) publish();
      }
      stats.widths = [...widths].sort((a, b) => a - b);
      stats.fontSizes = [...sizes].sort((a, b) => a - b);
      check(
        `${font}px ${section.id} retains its requested viewport`,
        !query.has("width") || innerWidth === Number(query.get("width")),
      );
      check(
        `${font}px ${section.id} keeps the whole reading page bounded`,
        document.documentElement.scrollWidth <= document.documentElement.clientWidth + 1,
      );
      stats.checks = report.checks - checksBefore;
      stats.errors = report.errors.length - errorsBefore;
      report.sections.push(stats);
      publish();
    }
  }
  document.body.dataset.bodyMathState = report.errors.length ? "error" : "ready";
  delete report.active;
} catch (error) {
  report.errors.push(String(error));
  document.body.dataset.bodyMathState = "error";
} finally {
  ResponsiveMath.prototype.measure = measure;
  ResponsiveMath.prototype.notice = notice;
}
publish();
