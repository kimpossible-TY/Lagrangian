import { ResponsiveMath } from "/math-renderer.js";
import { logicalTextIndex } from "/math-identity.js";
import { mathOverflow } from "/math-layout.js";

// Observe the real renderer without changing its viewport eligibility, budgets,
// scheduling or publication. Scroll each body passage into the normal margin.
let renderer;
const measure = ResponsiveMath.prototype.measure;
ResponsiveMath.prototype.measure = function (record) {
  if (this.article.id === "reader-document") renderer = this;
  return measure.call(this, record);
};
const report = { width: innerWidth, checks: [], errors: [], sections: [], failures: [] };
const output = document.createElement("pre");
output.id = "body-math-report";
output.style.cssText =
  "white-space:pre-wrap;overflow-wrap:anywhere;font:13px/1.5 monospace;margin:16px";
document.body.append(output);
const publish = () => (output.textContent = JSON.stringify(report, null, 2));
function check(name, condition) {
  report.checks.push(name);
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
  if (query.get("width"))
    await until(() => innerWidth === Number(query.get("width")), "requested viewport");
  report.width = innerWidth;
  await until(() => renderer && document.querySelector("[data-reader-key]"), "Reader body");
  const manifest = await (await fetch("/api/manifest")).json();
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
  for (const font of fonts) {
    while (Number(document.querySelector("#reader-size").value) !== font)
      document
        .querySelector(
          Number(document.querySelector("#reader-size").value) < font
            ? "#reader-larger"
            : "#reader-smaller",
        )
        .click();
    for (const section of sections) {
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
      const stats = {
        font,
        section: section.id,
        expressions: records.length,
        widths: [],
        fontSizes: [],
        ready: 0,
      };
      const widths = new Set();
      const sizes = new Set();
      for (const [index, record] of records.entries()) {
        report.active = { font, section: section.id, expression: index + 1 };
        const expected = text(record.template);
        record.view.scrollIntoView({ block: "center" });
        renderer.schedule(0);
        await until(
          () => {
            if (!record.view.isConnected) throw new Error("Audited passage was replaced");
            const current = renderer.measure(record);
            return (
              current &&
              (record.view.dataset.mathState === "error" ||
                (record.key === current.key &&
                  ["ready", "overflow"].includes(record.view.dataset.mathState)))
            );
          },
          `${font}px ${section.id} expression ${index + 1}`,
        );
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
        if ((index + 1) % 32 === 0) publish();
      }
      stats.widths = [...widths].sort((a, b) => a - b);
      stats.fontSizes = [...sizes].sort((a, b) => a - b);
      report.sections.push(stats);
      check(
        `${font}px ${section.id} keeps the whole reading page bounded`,
        document.documentElement.scrollWidth <= document.documentElement.clientWidth + 1,
      );
      publish();
    }
  }
  document.body.dataset.bodyMathState = report.errors.length ? "error" : "ready";
  delete report.active;
} catch (error) {
  report.errors.push(String(error));
  document.body.dataset.bodyMathState = "error";
}
publish();
