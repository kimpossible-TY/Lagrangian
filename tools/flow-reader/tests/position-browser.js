import { logicalTextIndex } from "/math-identity.js";

const report = { checks: [], errors: [], measurements: [], target: "energy_flux_identity" };
const output = document.createElement("pre");
output.id = "position-report";
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
const target = () => document.getElementById(report.target);
const math = () => target()?.querySelector(".flow-math-view");
function measure(name, expected) {
  const top = target().getBoundingClientRect().top;
  report.measurements.push({
    name,
    top,
    expected,
    width: innerWidth,
    font: document.querySelector("#reader-size").value,
    componentWidth: target().clientWidth,
    componentScroll: target().scrollWidth,
    pageWidth: document.documentElement.clientWidth,
    pageScroll: document.documentElement.scrollWidth,
  });
  check(name, Math.abs(top - expected) <= 3);
}
function nearCanvasesReady() {
  return [...document.querySelectorAll("[data-flow-canvas]")]
    .filter((n) => {
      const r = n.getBoundingClientRect();
      return r.bottom >= -800 && r.top <= innerHeight + 800;
    })
    .every((n) => ![undefined, "pending"].includes(n.dataset.canvasLayout));
}
try {
  await until(() => math(), "actual PDE target");
  await until(() => math().dataset.mathState === "ready", "entry PDE equation");
  await until(nearCanvasesReady, "entry nearby drawings");
  report.measurements.push({
    name: "Target before initial font normalization",
    top: target().getBoundingClientRect().top,
    font: document.querySelector("#reader-size").value,
    anchor: history.state?.readerAnchor,
  });
  check(
    "The PDE entry target is aligned before changing the saved font",
    Math.abs(target().getBoundingClientRect().top - 88) <= 3,
  );
  while (Number(document.querySelector("#reader-size").value) !== 18)
    document
      .querySelector(
        Number(document.querySelector("#reader-size").value) < 18
          ? "#reader-larger"
          : "#reader-smaller",
      )
      .click();
  await until(() => math().dataset.mathState === "ready", "initial PDE equation");
  await until(nearCanvasesReady, "initial nearby drawings");
  report.measurements.push({
    name: "Initial target after composition",
    top: target().getBoundingClientRect().top,
    font: document.querySelector("#reader-size").value,
    anchor: history.state?.readerAnchor,
  });
  check(
    "Direct PDE target navigation stays at the reading reference",
    Math.abs(target().getBoundingClientRect().top - 88) <= 3,
  );
  // Put the equation itself across the Reader's 90px reference line. Merely
  // putting its top at 112px can leave the preceding paragraph as the anchor.
  for (let attempt = 0; attempt < 4; attempt++) {
    window.scrollBy(0, target().getBoundingClientRect().top - 88);
    await new Promise((resolve) => setTimeout(resolve, 200));
    if (Math.abs(target().getBoundingClientRect().top - 88) < 1) break;
  }
  const initial = target().getBoundingClientRect().top;
  const expectedText = logicalTextIndex(math()).text;
  const previous = math().firstElementChild;
  while (Number(document.querySelector("#reader-size").value) < 30)
    document.querySelector("#reader-larger").click();
  await until(
    () => math()?.dataset.mathState === "ready" && math().firstElementChild !== previous,
    "larger PDE equation",
  );
  await until(nearCanvasesReady, "nearby automatic drawings");
  measure("Actual PDE font change preserves the equation's reading position", initial);
  check(
    "The large PDE equation retains every canonical term",
    logicalTextIndex(math()).text === expectedText,
  );
  check(
    "The large PDE equation needs no horizontal movement",
    target().scrollWidth <= target().clientWidth + 1,
  );
  check(
    "Offscreen pending canvases keep the PDE page bounded",
    document.documentElement.scrollWidth <= document.documentElement.clientWidth + 1,
  );
  const beforeResize = target().getBoundingClientRect().top;
  const previousWidth = innerWidth;
  const beforeMath = math().firstElementChild;
  document.body.dataset.positionState = "await-resize";
  output.textContent = JSON.stringify(report, null, 2);
  await until(() => innerWidth !== previousWidth, "external width change", 120000);
  await until(
    () => math()?.dataset.mathState === "ready" && math().firstElementChild !== beforeMath,
    "resized PDE equation",
  );
  await until(nearCanvasesReady, "resized nearby drawings");
  measure("Actual PDE viewport change preserves the equation's position", beforeResize);
  check(
    "Resized PDE mathematics retains canonical text",
    logicalTextIndex(math()).text === expectedText,
  );
  check(
    "Resized PDE mathematics needs no horizontal movement",
    target().scrollWidth <= target().clientWidth + 1,
  );
  check(
    "The resized PDE page stays within the viewport",
    document.documentElement.scrollWidth <= document.documentElement.clientWidth + 1,
  );
  document.body.dataset.positionState = report.errors.length ? "error" : "ready";
} catch (error) {
  report.errors.push(String(error));
  document.body.dataset.positionState = "error";
}
output.textContent = JSON.stringify(report, null, 2);
