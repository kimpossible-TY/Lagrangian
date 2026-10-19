import { logicalTextIndex } from "/rendering/math/identity.js";

const report = { checks: [], errors: [], phases: [] };
const output = document.createElement("pre");
output.id = "routing-report";
output.style.cssText = "white-space:pre-wrap;font:13px/1.5 monospace;margin:16px";
document.body.append(output);
const show = () => (output.textContent = JSON.stringify(report, null, 2));
function check(name, condition) {
  report.checks.push(name);
  if (!condition) report.errors.push(name);
  show();
}
async function until(condition, name, timeout = 30000) {
  const deadline = Date.now() + timeout;
  while (!condition()) {
    if (Date.now() > deadline) throw new Error(`Timed out: ${name}`);
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
}
try {
  await until(
    () => document.querySelector('#jacobi-routing .flow-math-view[data-math-state="ready"]'),
    "first mathematical composition",
  );
  const view = document.querySelector("#jacobi-routing .flow-math-view");
  const source = new DOMParser().parseFromString(
    await (await fetch("/document.html")).text(),
    "text/html",
  );
  const canonical = logicalTextIndex(source.querySelector("#jacobi-routing math")).text;
  for (const size of [18, 30]) {
    const before = view.firstElementChild;
    const oldSize = Number(document.querySelector("#reader-size").value);
    while (Number(document.querySelector("#reader-size").value) > size)
      document.querySelector("#reader-smaller").click();
    while (Number(document.querySelector("#reader-size").value) < size)
      document.querySelector("#reader-larger").click();
    if (size !== oldSize)
      await until(
        () => view.firstElementChild !== before && view.dataset.mathState === "ready",
        "font composition",
      );
    view.scrollIntoView({ block: "center" });
    await until(
      () =>
        document.querySelector('.flow-graphic-status[data-graphic-state="ready"]') &&
        JSON.parse(
          document
            .querySelector(".flow-graphic-overlay")
            ?.getAttribute("data-flow-graphic-layout") ?? "null",
        )?.fontSize === size,
      "collision-free original CeTZ relationships",
      60000,
    );
    const svg = document.querySelector(".flow-graphic-overlay");
    const layout = JSON.parse(svg.getAttribute("data-flow-graphic-layout"));
    const connectors = layout.connectors;
    check(
      `Named endpoints survive at ${size}px`,
      connectors.length === 2 &&
        connectors[0].start.tag === "local-scope-annotations-2-d_dh" &&
        connectors[0].end.tag === "local-scope-annotations-2-det_A" &&
        connectors[1].end.tag === "local-scope-annotations-2-bracket",
    );
    if (size === 18)
      check(
        `A colliding connector is recomposed at ${size}px`,
        connectors.some((c) => c.routed),
      );
    check(`The completed drawing matches the ${size}px reading font`, layout.fontSize === size);
    check(`All mathematical text survives at ${size}px`, logicalTextIndex(view).text === canonical);
    check(
      `Equations and connections fit the body at ${size}px`,
      view.scrollWidth <= view.clientWidth + 1 &&
        layout.left >= -1 &&
        layout.left + layout.width <= layout.sceneWidth + 1,
    );
    check(
      `Original two colored arrows retain their CeTZ marks at ${size}px`,
      svg.querySelectorAll('path[stroke="#ff4136"]').length === 2 &&
        svg.querySelectorAll('path[stroke="#0074d9"]').length === 2,
    );
    const state = document.querySelector(".flow-graphic-status");
    check(
      `No text or label collisions remain at ${size}px`,
      state.dataset.graphicCollisions === '{"labels":0,"paths":0}',
    );
    report.phases.push({
      size,
      layout,
      state: state.dataset.graphicState,
      collisions: state.dataset.graphicCollisions,
    });
  }
  await new Promise((resolve) => setTimeout(resolve, 750));
  check(
    "The completed layout remains stable after observer callbacks",
    document.querySelector(".flow-graphic-status")?.dataset.graphicState === "ready",
  );
  const requests = performance
    .getEntriesByType("resource")
    .filter((e) => new URL(e.name).pathname === "/api/graphics");
  check("Bounded route retries settle without a compile loop", requests.length <= 8);
  report.graphicRequests = requests.length;
  report.width = innerWidth;
  document.body.dataset.routingState = report.errors.length ? "error" : "ready";
} catch (error) {
  report.errors.push(String(error));
  document.body.dataset.routingState = "error";
}
show();
