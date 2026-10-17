import { logicalTextIndex } from "/math-identity.js";

const report = { width: innerWidth, checks: [], errors: [], measurements: [] };
const output = document.createElement("pre");
output.id = "native-position-report";
output.style.cssText =
  "white-space:pre-wrap;overflow-wrap:anywhere;font:13px/1.5 monospace;margin:16px";
document.body.append(output);
function check(name, condition) {
  report.checks.push(name);
  if (!condition) report.errors.push(name);
  output.textContent = JSON.stringify(report, null, 2);
}
async function until(condition, name, timeout = 45000) {
  const deadline = Date.now() + timeout;
  while (!condition()) {
    if (Date.now() > deadline) throw new Error(`Timed out: ${name}`);
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
}
const font = () => Number(document.querySelector("#reader-size").value);
function setFont(size) {
  while (font() !== size)
    document.querySelector(font() < size ? "#reader-larger" : "#reader-smaller").click();
}
const text = (node) => logicalTextIndex(node, { includeNested: true }).text;
const ready = (canvas, size) =>
  canvas.dataset.canvasLayout === "native-labels" &&
  Number(canvas.dataset.canvasFont) === size &&
  [...canvas.querySelectorAll(".flow-math-view")].every(
    (view) => view.dataset.mathState === "ready",
  );
try {
  const id = new URL(location.href).searchParams.get("canvas") || "canvas-5";
  await until(() => document.querySelector("[data-flow-canvas-model]"), "document");
  if (!document.querySelector(`[data-flow-canvas="${id}"]`)) location.hash = `#flow-${id}`;
  await until(() => document.querySelector(`[data-flow-canvas="${id}"]`), "chosen canvas");
  const canvas = document.querySelector(`[data-flow-canvas="${id}"]`);
  setFont(18);
  canvas.scrollIntoView({ block: "start" });
  await until(() => ready(canvas, 18), "initial drawing");
  const target = [...canvas.querySelectorAll("[data-reader-key]")]
    .filter(
      (node) =>
        node.closest(".flow-canvas-label-body") &&
        !node.querySelector("[data-reader-key]") &&
        node.closest("[data-flow-canvas-label]")?.dataset.labelMode === "legend" &&
        text(node).length > 25,
    )
    .sort((a, b) => text(b).length - text(a).length)[0];
  if (!target) throw new Error("No keyed legend passage");
  const expected = text(target),
    key = target.dataset.readerKey;
  target.scrollIntoView({ block: "start" });
  await until(() => history.state?.readerAnchor?.key === key, "saved label anchor");
  const before = target.getBoundingClientRect().top;
  setFont(30);
  await until(() => ready(canvas, 30), "large-font drawing");
  await new Promise((resolve) => setTimeout(resolve, 400));
  const after = target.getBoundingClientRect().top;
  report.measurements.push({ phase: "font", key, before, after });
  check(
    "A label passage keeps its source text and reading position through font changes",
    text(target) === expected && Math.abs(after - before) <= 3,
  );
  check("The restored label uses its own reading key", history.state?.readerAnchor?.key === key);
  const geometry = canvas.querySelector(
    ":scope > .flow-canvas-stage > svg:not(.flow-canvas-leaders)",
  );
  const area = geometry.getBoundingClientRect();
  const boxes = [...canvas.querySelectorAll("[data-reader-key]")].map((node) =>
    node.getBoundingClientRect(),
  );
  const fraction = [0.15, 0.35, 0.55, 0.75, 0.9].find((f) =>
    boxes.every(
      (box) => box.top > area.top + area.height * f || box.bottom <= area.top + area.height * f,
    ),
  );
  if (fraction === undefined) throw new Error("No unobscured geometry reading line");
  window.scrollBy(0, area.top + area.height * fraction - 90);
  await until(
    () =>
      history.state?.readerAnchor?.canvas === canvas.id &&
      Math.abs(history.state.readerAnchor.canvasFraction - fraction) < 0.01,
    "geometry anchor",
  );
  report.measurements.push({
    phase: "geometry-before-font",
    fraction,
    actual: (90 - geometry.getBoundingClientRect().top) / geometry.getBoundingClientRect().height,
    anchor: history.state.readerAnchor,
  });
  setFont(18);
  await until(() => ready(canvas, 18), "geometry font return");
  await new Promise((resolve) => setTimeout(resolve, 400));
  const restored = geometry.getBoundingClientRect();
  const currentFraction = (90 - restored.top) / restored.height;
  report.measurements.push({ phase: "geometry", before: fraction, after: currentFraction });
  check(
    "Reading the geometry preserves its source point through a font change",
    Math.abs(currentFraction - fraction) < 0.02,
  );
  target.scrollIntoView({ block: "start" });
  await until(() => history.state?.readerAnchor?.key === key, "label before width change");
  const top = target.getBoundingClientRect().top;
  const originalWidth = innerWidth;
  document.body.dataset.nativePositionState = "await-resize";
  await until(
    () =>
      innerWidth !== originalWidth &&
      canvas.dataset.canvasLayout === "native-labels" &&
      Number(canvas.dataset.canvasWidth) === Math.floor(canvas.getBoundingClientRect().width),
    "width change",
    180000,
  );
  await new Promise((resolve) => setTimeout(resolve, 500));
  const finalTop = target.getBoundingClientRect().top;
  report.measurements.push({ phase: "width", before: top, after: finalTop, width: innerWidth });
  check(
    "A label passage remains anchored after the viewport width changes",
    Math.abs(finalTop - top) <= 3,
  );
  check("The source label remains the same after rotation", text(target) === expected);
  check(
    "The complete resized reading page stays bounded",
    document.documentElement.scrollWidth <= document.documentElement.clientWidth + 1,
  );
  document.body.dataset.nativePositionState = report.errors.length ? "error" : "ready";
} catch (error) {
  report.errors.push(String(error));
  document.body.dataset.nativePositionState = "error";
}
output.textContent = JSON.stringify(report, null, 2);
