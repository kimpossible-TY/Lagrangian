import { logicalTextIndex } from "/math-identity.js";
import { mathOverflow } from "/math-layout.js";
import { inkContrast } from "/canvas-labels.js";

const report = { width: innerWidth, checks: [], errors: [], measurements: [] };
const output = document.createElement("pre");
output.id = "native-canvases-report";
output.style.cssText =
  "white-space:pre-wrap;overflow-wrap:anywhere;font:13px/1.5 monospace;margin:16px";
document.body.append(output);
const sourceOf = (body) => logicalTextIndex(body, { includeNested: true }).text;
const direct = (canvas) =>
  [...canvas.querySelectorAll("[data-flow-canvas-label]")].filter(
    (label) => label.closest("[data-flow-canvas]") === canvas,
  );
let requests = 0;
const normalFetch = window.fetch;
window.fetch = (...args) => {
  if (String(args[0]).endsWith("api/canvases")) requests++;
  return normalFetch(...args);
};
function check(name, condition) {
  report.checks.push(name);
  if (!condition) report.errors.push(name);
  output.textContent = JSON.stringify(report, null, 2);
}
async function until(condition, name) {
  const deadline = Date.now() + 45000;
  while (!condition()) {
    if (Date.now() > deadline) throw new Error(`Timed out: ${name}`);
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
}
function overlaps(a, b) {
  return (
    Math.min(a.right, b.right) - Math.max(a.left, b.left) > 1 &&
    Math.min(a.bottom, b.bottom) - Math.max(a.top, b.top) > 1
  );
}
try {
  await until(() => document.querySelector("[data-flow-canvas-model]"), "native source");
  const source = new DOMParser().parseFromString(
    await (await fetch("/document.html")).text(),
    "text/html",
  );
  const original = [...source.querySelectorAll("[data-flow-canvas-model]")];
  const query = new URL(location.href).searchParams;
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
    for (const before of original) {
      const id = before.dataset.flowCanvas;
      if (query.get("only") && query.get("only") !== id) continue;
      if (query.get("package") && query.get("package") !== before.dataset.flowCanvasPackage)
        continue;
      if (!document.querySelector(`[data-flow-canvas="${id}"]`)) {
        location.hash = `#flow-${id}`;
        await until(() => document.querySelector(`[data-flow-canvas="${id}"]`), `${id} section`);
      }
      const canvas = document.querySelector(`[data-flow-canvas="${id}"]`);
      canvas.scrollIntoView({ block: "start" });
      await until(
        () =>
          canvas.dataset.canvasLayout === "native-labels" &&
          Number(canvas.dataset.canvasFont) === font &&
          [...canvas.querySelectorAll(".flow-math-view")].every(
            (view) => view.dataset.mathState === "ready",
          ),
        `${font}px ${id} composed`,
      );
      await new Promise((resolve) => setTimeout(resolve, 300));
      const labels = direct(canvas),
        sourceLabels = direct(before);
      if (
        source.body.textContent.includes(
          "Small, inherited, large, and automatically scaled labels",
        ) &&
        id === "canvas-3"
      ) {
        const widths = labels.map(
          (label) =>
            label.querySelector(":scope > .flow-canvas-label-body").getBoundingClientRect().width,
        );
        check(
          `${font}px explicit tiny text, math and auto-scale match their readable controls`,
          Math.abs(widths[0] - widths[1]) <= 1 &&
            Math.abs(widths[2] - widths[3]) <= 1 &&
            Math.abs(widths[5] - widths[1]) <= 1,
        );
        check(
          `${font}px deliberately larger text and mathematics remain larger`,
          widths[4] > widths[1] && widths[6] > widths[3],
        );
      }
      check(
        `${font}px ${id} retains every semantic label`,
        labels.length === sourceLabels.length &&
          labels.every(
            (label, i) =>
              sourceOf(label.querySelector(":scope > .flow-canvas-label-body")) ===
              sourceOf(sourceLabels[i].querySelector(":scope > .flow-canvas-label-body")),
          ),
      );
      const bounds = canvas.getBoundingClientRect();
      const bodies = labels.map((label) => label.querySelector(":scope > .flow-canvas-label-body"));
      check(
        `${font}px ${id} keeps every complete label in the reading body`,
        bodies.every(
          (body) =>
            getComputedStyle(body).display !== "none" &&
            body.getBoundingClientRect().height > 0 &&
            body.getBoundingClientRect().left >= bounds.left - 1 &&
            body.getBoundingClientRect().right <= bounds.right + 1 &&
            body.scrollWidth <= body.clientWidth + 1,
        ),
      );
      const textSizes = bodies
        .flatMap((body) => [body, ...body.querySelectorAll("*")])
        .filter(
          (node) =>
            node.namespaceURI === "http://www.w3.org/1999/xhtml" &&
            !node.closest(
              "svg,math,.flow-math-view,.flow-canvas-label-number,.flow-canvas-status",
            ) &&
            [...node.childNodes].some(
              (child) => child.nodeType === Node.TEXT_NODE && child.textContent.trim(),
            ),
        )
        .map((node) => parseFloat(getComputedStyle(node).fontSize));
      const mathSizes = bodies
        .flatMap((body) => [...body.querySelectorAll(".flow-math-view")])
        .map((node) => parseFloat(getComputedStyle(node).fontSize));
      check(
        `${font}px ${id} preserves a reading-size font floor`,
        [...textSizes, ...mathSizes].every((size) => size >= font - 0.1),
      );
      const markers = [
        ...canvas.querySelectorAll(":scope > .flow-canvas-stage > .flow-canvas-markers > *"),
      ];
      check(
        `${font}px ${id} retains readable diagram numbers`,
        markers.every((node) => parseFloat(getComputedStyle(node).fontSize) >= font - 0.1),
      );
      const painted = bodies
        .flatMap((body) => [...body.querySelectorAll("*")])
        .filter(
          (node) =>
            node.namespaceURI === "http://www.w3.org/1999/xhtml" &&
            !node.closest("svg,mjx-assistive-mml,.flow-math-stage") &&
            (node.matches("mjx-c,mjx-utext,[data-flow-token]") ||
              [...node.childNodes].some(
                (child) => child.nodeType === Node.TEXT_NODE && child.textContent.trim(),
              )),
        );
      const contrasts = painted.map((node) => {
        const match = getComputedStyle(node).color.match(/^rgba?\(([^)]+)\)$/);
        return match
          ? inkContrast(
              match[1]
                .split(/[, /]+/)
                .slice(0, 3)
                .map(Number),
            )
          : 0;
      });
      check(
        `${font}px ${id} keeps label ink readable against its paper`,
        contrasts.every((value) => value >= 4.49),
      );
      const inline = labels.filter((label) => label.dataset.labelMode === "inline");
      const boxes = [...markers, ...inline].map((node) => node.getBoundingClientRect());
      check(
        `${font}px ${id} separates readable labels and numbered markers`,
        boxes.every(
          (box, i) =>
            box.left >= bounds.left - 1 &&
            box.right <= bounds.right + 1 &&
            boxes.slice(i + 1).every((other) => !overlaps(box, other)),
        ),
      );
      const legends = labels.filter((label) => label.dataset.labelMode === "legend");
      check(
        `${font}px ${id} maps each visible legend to its diagram number`,
        legends.length === markers.length &&
          legends.every((label) =>
            markers.some(
              (marker) =>
                marker.textContent ===
                label.querySelector(":scope > .flow-canvas-label-number").textContent,
            ),
          ),
      );
      const geometry = canvas.querySelector(
        ":scope > .flow-canvas-stage > svg:not(.flow-canvas-leaders)",
      );
      check(
        `${font}px ${id} retains visible vector geometry without baked label glyphs`,
        !geometry.querySelector("symbol,use") &&
          geometry.getBoundingClientRect().width <= bounds.width + 1 &&
          getComputedStyle(
            canvas.querySelector(":scope > .flow-canvas-stage > .flow-canvas-leaders"),
          ).backgroundColor === "rgba(0, 0, 0, 0)",
      );
      check(
        `${font}px ${id} retains physical stroke thickness across geometry scale`,
        [...geometry.querySelectorAll("[data-canvas-source-stroke]")].every(
          (path) =>
            Math.abs(
              parseFloat(getComputedStyle(path).strokeWidth) -
                Number(path.dataset.canvasSourceStroke),
            ) < 0.01 && getComputedStyle(path).vectorEffect === "non-scaling-stroke",
        ),
      );
      const mathPaint = bodies
        .flatMap((body) => [...body.querySelectorAll(".flow-math-view")])
        .every((view) => {
          const parent = view.closest(".flow-canvas-label-body");
          const rect = parent.getBoundingClientRect();
          const overflow = mathOverflow(view, { width: rect.width, left: rect.left });
          return Math.max(overflow.left, overflow.right) <= 1;
        });
      check(`${font}px ${id} retains full horizontal mathematical ink`, mathPaint);
      check(
        `${font}px ${id} bounds the whole page`,
        document.documentElement.scrollWidth <= document.documentElement.clientWidth + 1,
      );
      report.measurements.push({
        font,
        id,
        labels: labels.length,
        legends: legends.length,
        width: bounds.width,
        height: bounds.height,
        page: [document.documentElement.clientWidth, document.documentElement.scrollWidth],
        textSizes,
        mathSizes,
      });
    }
  }
  check("Native figure resizing requires no compiler canvas requests", requests === 0);
  document.body.dataset.nativeCanvasesState = report.errors.length ? "error" : "ready";
} catch (error) {
  report.errors.push(String(error));
  document.body.dataset.nativeCanvasesState = "error";
}
output.textContent = JSON.stringify(report, null, 2);
