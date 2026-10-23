import { logicalTextIndex } from "/rendering/math/identity.js";
import { mathInkNodes } from "/rendering/math/layout.js";
import { inkContrast } from "/rendering/graphics/canvas-labels.js";

const report = { width: innerWidth, checks: [], errors: [], measurements: [] };
const output = document.createElement("script");
output.type = "application/json";
output.id = "native-canvases-report";
const progress = document.createElement("pre");
progress.id = "native-canvases-progress";
progress.style.cssText =
  "white-space:pre-wrap;overflow-wrap:anywhere;font:13px/1.5 monospace;margin:16px";
document.body.append(output, progress);
function publish() {
  report.canvasRequests = requests;
  output.textContent = JSON.stringify(report);
  progress.textContent = JSON.stringify({
    width: report.width,
    active: report.active,
    completed: report.measurements.length,
    checks: report.checks.length,
    errors: report.errors,
  });
}
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
  publish();
}
async function until(condition, name) {
  const deadline = Date.now() + 90000;
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
  await until(
    () => document.querySelector("#reader-document [data-reader-key]"),
    "reading document",
  );
  const manifest = await (await fetch("/api/manifest")).json();
  report.revision = manifest.revision;
  const source = new DOMParser().parseFromString(
    globalThis.nativeCanvasReference ?? (await (await fetch("/document.html")).text()),
    "text/html",
  );
  const original = [...source.querySelectorAll("[data-flow-canvas-model]")];
  check("The canonical source exposes native figure models", original.length > 0);
  const query = new URL(location.href).searchParams;
  if (query.has("audit")) {
    const { attachReport } = await import("/test-report.js");
    attachReport({
      kind: "native-canvases",
      id: "native-canvases-report",
      stateKey: "nativeCanvasesState",
    });
  }
  const start = Number(query.get("start") ?? 0);
  if (!Number.isInteger(start) || start < 0 || start >= original.length)
    throw new Error("Invalid first native figure");
  if (query.get("width"))
    await until(() => innerWidth === Number(query.get("width")), "requested viewport");
  report.width = innerWidth;
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
    for (const before of original.slice(start)) {
      const id = before.dataset.flowCanvas;
      if (query.get("only") && query.get("only") !== id) continue;
      if (query.has("width") && innerWidth !== Number(query.get("width")))
        throw new Error(`Requested viewport changed before ${id}`);
      if (query.get("package") && query.get("package") !== before.dataset.flowCanvasPackage)
        continue;
      report.active = { font, id };
      publish();
      if (!document.querySelector(`[data-flow-canvas="${id}"]`)) {
        const link = document.createElement("a");
        link.href = `#flow-${id}`;
        document.getElementById("reader-document").append(link);
        link.click();
        link.remove();
        await until(() => document.querySelector(`[data-flow-canvas="${id}"]`), `${id} section`);
      }
      let canvas = document.querySelector(`[data-flow-canvas="${id}"]`);
      canvas.scrollIntoView({ block: "start" });
      await until(() => {
        // Section virtualization may replace the node during the scroll.
        // Verify current published content, not a detached pending instance.
        canvas = document.querySelector(`[data-flow-canvas="${id}"]`);
        return (
          canvas?.dataset.canvasLayout === "native-labels" &&
          Number(canvas.dataset.canvasFont) === font &&
          [...canvas.querySelectorAll(".flow-math-view")].every(
            (view) => view.dataset.mathState === "ready",
          )
        );
      }, `${font}px ${id} composed`);
      await new Promise((resolve) => setTimeout(resolve, 300));
      const labels = direct(canvas),
        sourceLabels = direct(before);
      if (
        source.body.textContent.includes("Compact symbol beside a stroke") &&
        before === original.at(-1)
      ) {
        check(
          `${font}px compact y stays beside its stroke without a numbered legend`,
          labels[0].dataset.labelMode === "inline",
        );
        const stroke = canvas.querySelector(".flow-canvas-stage > svg path[stroke]");
        const point = stroke.getPointAtLength(stroke.getTotalLength() / 2);
        const y = point.matrixTransform(stroke.getScreenCTM()).y;
        const box = labels[0].getBoundingClientRect();
        check(
          `${font}px compact y clears the actual painted stroke`,
          box.bottom < y || box.top > y,
        );
      }
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
      const effectiveSize = (node) =>
        parseFloat(getComputedStyle(node).fontSize) *
        Number(node.closest("[data-flow-canvas-label]")?.dataset.labelScale || 1);
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
        .map(effectiveSize);
      const mathSizes = bodies
        .flatMap((body) => [...body.querySelectorAll(".flow-math-view")])
        .map(effectiveSize);
      check(
        `${font}px ${id} preserves the bounded readable label size`,
        [...textSizes, ...mathSizes].every((size) => size >= Math.max(11, font * 0.8) - 0.1),
      );
      check(
        `${font}px ${id} keeps complete legends at full reading size`,
        labels.every(
          (label) =>
            label.dataset.labelMode === "inline" || Number(label.dataset.labelScale || 1) === 1,
        ),
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
      const inlineBoxes = inline.map((label) => label.getBoundingClientRect());
      let strokeCollisions = 0;
      for (const path of geometry.querySelectorAll(
        "path,rect,circle,ellipse,line,polyline,polygon",
      )) {
        if (path.closest("defs") || getComputedStyle(path).stroke === "none") continue;
        const matrix = path.getScreenCTM();
        if (!matrix) continue;
        const length = path.getTotalLength();
        if (length === 0 && getComputedStyle(path).strokeLinecap === "butt") continue;
        const samples = Math.max(
          1,
          Math.min(4096, Math.ceil(length * Math.hypot(matrix.a, matrix.b))),
        );
        const inset = Math.max(0, parseFloat(getComputedStyle(path).strokeWidth) / 2 - 0.2);
        for (let i = 0; i <= samples; i++) {
          const point = path
            .getPointAtLength(Math.max(0.001, (length * i) / samples))
            .matrixTransform(matrix);
          if (
            inlineBoxes.some(
              (box) =>
                point.x > box.left - inset &&
                point.x < box.right + inset &&
                point.y > box.top - inset &&
                point.y < box.bottom + inset,
            )
          ) {
            strokeCollisions++;
            (report.strokeCollisions ??= []).push({
              font,
              id,
              path: path.outerHTML,
              point: { x: point.x, y: point.y },
              boxes: inlineBoxes.map((box) => box.toJSON()),
            });
            break;
          }
        }
      }
      check(
        `${font}px ${id} keeps inline text clear of painted diagram strokes`,
        strokeCollisions === 0,
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
          const scale = Number(view.closest("[data-flow-canvas-label]")?.dataset.labelScale || 1);
          return (
            view.scrollWidth * scale <= rect.width + 1 &&
            mathInkNodes(view).every((ink) =>
              [...ink.getClientRects()].every(
                (box) => !box.width || (box.left >= rect.left - 1 && box.right <= rect.right + 1),
              ),
            )
          );
        });
      check(`${font}px ${id} retains full horizontal mathematical ink`, mathPaint);
      check(
        `${font}px ${id} bounds the whole page`,
        document.documentElement.scrollWidth <= document.documentElement.clientWidth + 1,
      );
      if (query.has("width") && innerWidth !== Number(query.get("width")))
        throw new Error(`Requested viewport changed while composing ${id}`);
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
publish();
