import { logicalTextIndex } from "/math-identity.js";
import { mathOverflow } from "/math-layout.js";
import { prepareResponsiveTables } from "/tables.js";

const report = { width: innerWidth, checks: [], errors: [], measurements: [] };
const output = document.createElement("pre");
output.id = "tables-report";
output.style.cssText =
  "white-space:pre-wrap;overflow-wrap:anywhere;font:13px/1.5 monospace;margin:16px";
document.body.append(output);
const publish = () => (output.textContent = JSON.stringify(report, null, 2));
function check(name, condition) {
  report.checks.push(name);
  if (!condition) report.errors.push(name);
  publish();
}
async function until(condition, name, timeout = 90000) {
  const deadline = Date.now() + timeout;
  while (!condition()) {
    if (Date.now() > deadline) throw new Error(`Timed out: ${name}`);
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
}
const text = (node) => logicalTextIndex(node, { includeNested: true }).text;
try {
  const query = new URL(location.href).searchParams;
  if (query.get("width"))
    await until(() => innerWidth === Number(query.get("width")), "requested viewport");
  report.width = innerWidth;
  const sample = new DOMParser().parseFromString(
    '<table><thead><tr><th colspan="2">Group</th></tr><tr><th>Left</th><th>Right</th></tr></thead><tbody><tr><td rowspan="2">A</td><td><math><mi>x</mi></math></td></tr><tr><td>C</td></tr></tbody></table>',
    "text/html",
  );
  const before = sample.querySelector("table").textContent;
  const originalMath = sample.querySelector("math");
  prepareResponsiveTables(sample.body);
  const last = sample.querySelector("tbody tr:last-child td");
  check(
    "Table reflow retains every original text and mathematical node",
    sample.querySelector("table").textContent === before &&
      sample.querySelector("math") === originalMath &&
      sample.querySelectorAll("math").length === 1,
  );
  check(
    "Merged cells retain their source spans and logical columns",
    sample.querySelector("tbody td").rowSpan === 2 &&
      last.getAttribute("aria-colindex") === "2" &&
      sample.querySelector("th").colSpan === 2,
  );
  check(
    "A spanned column keeps both original header associations",
    last.getAttribute("headers").split(" ").length === 2 &&
      last.dataset.readerColumnLabel === "Group / Right",
  );
  const plain = new DOMParser().parseFromString(
    "<table><tr><td>1</td><td>2</td></tr><tr><td>3</td><td>4</td></tr></table>",
    "text/html",
  );
  prepareResponsiveTables(plain.body);
  check(
    "Unheaded data stays data with positional hints",
    plain.querySelector("table").dataset.readerTableHeaders === "none" &&
      plain.querySelectorAll('[role="columnheader"]').length === 0 &&
      plain.querySelector("td").dataset.readerColumnLabel === "열 1",
  );
  await until(
    () => document.querySelector("#reader-document [data-reader-key]"),
    "reading document",
  );
  const manifest = await (await fetch("/api/manifest")).json();
  const targets = (
    await Promise.all(
      manifest.sections.map(async (section) => {
        const html = await (
          await fetch(`/api/sections/${section.id}?revision=${manifest.revision}`)
        ).text();
        const parsed = new DOMParser().parseFromString(html, "text/html");
        return [...parsed.querySelectorAll("table")].map((table) => ({
          anchor: table.querySelector("td[id],th[id]")?.id,
          text: text(table),
          cells: [...table.rows].flatMap((row) => [...row.cells]).map((cell) => text(cell)),
          math: table.querySelectorAll("math").length,
        }));
      }),
    )
  ).flat();
  check(
    "All source tables expose a native reading anchor",
    targets.length > 0 && targets.every((target) => target.anchor),
  );
  for (const font of [18, 30]) {
    while (Number(document.querySelector("#reader-size").value) !== font)
      document
        .querySelector(
          Number(document.querySelector("#reader-size").value) < font
            ? "#reader-larger"
            : "#reader-smaller",
        )
        .click();
    for (const [index, target] of targets.entries()) {
      if (!document.getElementById(target.anchor)) location.hash = target.anchor;
      await until(() => document.getElementById(target.anchor), `table ${index + 1} section`);
      const table = document.getElementById(target.anchor).closest("table");
      const cells = [...table.rows].flatMap((row) => [...row.cells]);
      const prefix = `${font}px table ${index + 1}`;
      check(
        `${prefix} keeps its source cell count and semantic table`,
        cells.length === target.cells.length && table.getAttribute("role") === "table",
      );
      for (const [c, cell] of cells.entries()) {
        cell.scrollIntoView({ block: "start" });
        await until(
          () =>
            [...cell.querySelectorAll(".flow-math-view")].every(
              (view) => view.dataset.mathState === "ready",
            ),
          `${prefix} cell ${c + 1} math`,
        );
        check(
          `${prefix} cell ${c + 1} retains exact logical source`,
          text(cell) === target.cells[c],
        );
        check(
          `${prefix} cell ${c + 1} needs no horizontal movement`,
          cell.scrollWidth <= cell.clientWidth + 1 &&
            parseFloat(getComputedStyle(cell).fontSize) >= font - 0.1,
        );
        const rect = cell.getBoundingClientRect(),
          style = getComputedStyle(cell);
        const width =
          cell.clientWidth - parseFloat(style.paddingLeft) - parseFloat(style.paddingRight);
        const left = rect.left + cell.clientLeft + parseFloat(style.paddingLeft);
        check(
          `${prefix} cell ${c + 1} retains all mathematical ink`,
          [...cell.querySelectorAll(".flow-math-view")].every((view) => {
            const bounds = mathOverflow(view, { width, left });
            return Math.max(bounds.left, bounds.right) <= 1;
          }),
        );
      }
      check(
        `${prefix} keeps the complete original table source order`,
        text(table) === target.text,
      );
      check(
        `${prefix} does not clone source mathematical expressions`,
        table.querySelectorAll(".flow-math-view").length === target.math,
      );
      check(
        `${prefix} exposes every column association without a reveal action`,
        [...table.querySelectorAll('[role="cell"]')].every(
          (cell) => cell.dataset.readerColumnLabel && cell.getAttribute("headers"),
        ),
      );
      check(
        `${prefix} stays bounded in the continuous page`,
        table.scrollWidth <= table.clientWidth + 1 &&
          document.documentElement.scrollWidth <= document.documentElement.clientWidth + 1,
      );
      report.measurements.push({
        font,
        index: index + 1,
        cells: cells.length,
        math: target.math,
        width: table.clientWidth,
        scroll: table.scrollWidth,
      });
    }
  }
  document.body.dataset.tablesState = report.errors.length ? "error" : "ready";
} catch (error) {
  report.errors.push(String(error));
  document.body.dataset.tablesState = "error";
}
publish();
