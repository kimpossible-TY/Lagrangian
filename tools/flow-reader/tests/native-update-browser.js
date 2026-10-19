import { logicalTextIndex } from "/rendering/math/identity.js";

const report = { checks: [], errors: [], measurements: [] };
const output = document.createElement("pre");
output.id = "native-update-report";
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
  while (!(await condition())) {
    if (Date.now() > deadline) throw new Error(`Timed out: ${name}`);
    await new Promise((resolve) => setTimeout(resolve, 150));
  }
}
const state = async () => (await fetch("/api/state", { cache: "no-store" })).json();
const query = new URL(location.href).searchParams;
const initialCount = Number(query.get("initial") || 2);
const figures = () =>
  [...document.querySelectorAll("#reader-document [data-flow-canvas-model]")].filter(
    (node) => !query.get("package") || node.dataset.flowCanvasPackage === query.get("package"),
  );
const ready = (node) => node?.dataset.canvasLayout === "native-labels";
const byIdentity = (identity) =>
  figures().filter((node) => node.dataset.flowCanvasIdentity === identity);
const text = (node) => logicalTextIndex(node, { includeNested: true }).text;
const geometry = (node) =>
  node.querySelector(":scope > .flow-canvas-stage > svg:not(.flow-canvas-leaders)");
async function edit(step) {
  if (!query.has("auto-edit")) return;
  const response = await fetch("/api/test-edit", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ step }),
  });
  if (!response.ok) throw new Error(`Owned fixture edit HTTP ${response.status}`);
}
try {
  await until(() => figures().length === initialCount, "initial source");
  while (Number(document.querySelector("#reader-size").value) !== 18)
    document
      .querySelector(
        Number(document.querySelector("#reader-size").value) > 18
          ? "#reader-smaller"
          : "#reader-larger",
      )
      .click();
  await until(
    () => figures().length === initialCount && figures().every(ready),
    "initial surfaces",
  );
  await document.fonts.ready;
  const initial = await state();
  const canvas = figures()[1];
  const identity = canvas.dataset.flowCanvasIdentity;
  const label = canvas.querySelector(".flow-canvas-label-body[data-reader-key]");
  const key = label.dataset.readerKey;
  const expected = text(label);
  check(
    "Different surfaces with the same axis labels have distinct identities",
    byIdentity(identity).length === 1,
  );
  label.scrollIntoView({ block: "start" });
  await until(() => history.state?.readerAnchor?.key === key, "label position");
  const top = label.getBoundingClientRect().top;
  const walker = document.createTreeWalker(label, NodeFilter.SHOW_TEXT);
  let leaf;
  while ((leaf = walker.nextNode())) if (leaf.textContent.trim()) break;
  if (!leaf) throw new Error("No source axis text");
  const range = document.createRange();
  range.selectNodeContents(leaf);
  const selection = window.getSelection();
  selection.removeAllRanges();
  selection.addRange(range);
  const quotation = selection.toString();
  document.body.dataset.nativeUpdateState = "await-edit";
  publish();
  await edit(1);
  let changed;
  await until(
    async () => {
      changed = await state();
      return changed.revision && changed.revision !== initial.revision && !changed.compiling;
    },
    "first accepted edit",
    180000,
  );
  // Allow a complete normal Reader polling interval while the selection stays.
  await new Promise((resolve) => setTimeout(resolve, 3500));
  check(
    "A source update keeps the selected label DOM mounted",
    label.isConnected && figures().length === initialCount,
  );
  check(
    "The exact selected source text survives the deferred update",
    selection.toString() === quotation && quotation === expected,
  );
  selection.removeAllRanges();
  await until(
    () =>
      !canvas.isConnected && byIdentity(identity).length === 1 && ready(byIdentity(identity)[0]),
    "published first edit",
  );
  const next = byIdentity(identity)[0];
  const nextLabel = document.querySelector(`[data-reader-key="${key}"]`);
  const firstLabelTop = nextLabel.getBoundingClientRect().top;
  check("Inserting a preceding surface changes the generated diagram ID", next.id !== canvas.id);
  check(
    "The same axis passage retains its source key and figure",
    next.contains(nextLabel) && text(nextLabel) === expected,
  );
  check(
    "The label reading position survives publication after selection ends",
    Math.abs(firstLabelTop - top) <= 3,
  );
  const located = await (
    await fetch("/api/locate", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ revision: changed.revision, fragments: [{ key, exact: expected }] }),
    })
  ).json();
  check(
    "A repeated axis quotation resolves to its original surface",
    located.locations?.[0]?.state === "located" && located.locations[0].key === key,
  );
  const source = geometry(next);
  const area = source.getBoundingClientRect();
  const labelBoxes = [...next.querySelectorAll("[data-reader-key]")].map((node) =>
    node.getBoundingClientRect(),
  );
  const fraction = [0.15, 0.35, 0.55, 0.75, 0.9].find((value) =>
    labelBoxes.every(
      (box) =>
        box.top > area.top + value * area.height || box.bottom <= area.top + value * area.height,
    ),
  );
  if (fraction === undefined) throw new Error("No geometry reading line");
  window.scrollBy(0, area.top + fraction * area.height - 90);
  await until(
    () =>
      history.state?.readerAnchor?.canvasIdentity === identity &&
      Number.isFinite(history.state.readerAnchor.canvasFraction),
    "geometry source anchor",
  );
  const beforeFraction =
    (90 - source.getBoundingClientRect().top) / source.getBoundingClientRect().height;
  const priorRevision = changed.revision;
  document.body.dataset.nativeUpdateState = "await-second-edit";
  publish();
  await edit(2);
  await until(
    async () => {
      changed = await state();
      return changed.revision && changed.revision !== priorRevision && !changed.compiling;
    },
    "second accepted edit",
    180000,
  );
  await until(
    () => !next.isConnected && byIdentity(identity).length === 1 && ready(byIdentity(identity)[0]),
    "published second edit",
  );
  const finalCanvas = byIdentity(identity)[0];
  const finalGeometry = geometry(finalCanvas).getBoundingClientRect();
  const afterFraction = (90 - finalGeometry.top) / finalGeometry.height;
  report.measurements.push({
    key,
    identity,
    initialCanvas: canvas.id,
    firstCanvas: next.id,
    finalCanvas: finalCanvas.id,
    labelBefore: top,
    labelAfter: firstLabelTop,
    beforeFraction,
    afterFraction,
  });
  check(
    "Geometry restoration rejects the reused ID of another same-label surface",
    finalCanvas.id !== next.id && finalCanvas.dataset.flowCanvasIdentity === identity,
  );
  check(
    "The original source point stays visible after another preceding insertion",
    Math.abs(afterFraction - beforeFraction) < 0.02,
  );
  await until(() => figures().length === initialCount + 2, "all updated surfaces");
  for (const figure of figures()) {
    figure.scrollIntoView({ block: "start" });
    await until(() => ready(figure), "automatic surface composition while reading");
  }
  check(
    "Every updated surface remains composed in continuous reading",
    figures().length === initialCount + 2 && figures().every(ready),
  );
  check(
    "Source updates keep the complete reading page bounded",
    document.documentElement.scrollWidth <= document.documentElement.clientWidth + 1,
  );
  document.body.dataset.nativeUpdateState = report.errors.length ? "error" : "ready";
} catch (error) {
  report.errors.push(String(error));
  document.body.dataset.nativeUpdateState = "error";
}
publish();
