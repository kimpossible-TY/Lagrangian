import { AdaptiveCanvases } from "/rendering/graphics/canvases.js";

const report = { checks: [], errors: [], measurements: [], requests: [] };
const shrinking = new URLSearchParams(location.search).has("shrink");
const output = document.createElement("pre");
output.id = "canvas-loading-report";
output.style.cssText =
  "white-space:pre-wrap;overflow-wrap:anywhere;font:13px/1.5 monospace;margin:16px";
document.body.append(output);
const originalFetch = window.fetch;
let release;
let gate = new Promise((resolve) => {
  release = resolve;
});
const finished = [];
window.fetch = async (url, options) => {
  if (!String(url).endsWith("api/canvases")) return originalFetch(url, options);
  const request = JSON.parse(options.body);
  report.requests.push(request);
  await gate;
  const response = await originalFetch(url, options);
  finished.push(request);
  return response;
};
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
function pause() {
  gate = new Promise((resolve) => {
    release = resolve;
  });
}
function ready() {
  return [...document.querySelectorAll("[data-flow-canvas]")].every(
    (n) => n.dataset.canvasLayout === "width-fit",
  );
}
const paragraph = () => document.getElementById("reading-position");
function position(name, expected) {
  const top = paragraph().getBoundingClientRect().top;
  report.measurements.push({
    name,
    top,
    expected,
    width: innerWidth,
    font: document.querySelector("#reader-size").value,
  });
  check(name, Math.abs(top - expected) <= 2);
}
async function failedFit() {
  const state = await (await originalFetch("/api/state")).json();
  const response = await originalFetch("/api/canvases", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      revision: state.revision,
      canvases: { "canvas-2": { width: 32, fontSize: 30 } },
    }),
  });
  const result = (await response.json()).canvases["canvas-2"];
  const host = document.createElement("div");
  host.className = "flow-drawing flow-canvas";
  host.style.cssText = "position:fixed;left:-100000px;top:0;width:200px";
  host.dataset.canvasPlaceholder = "true";
  host.setAttribute("aria-hidden", "true");
  host.inert = true;
  document.body.append(host);
  const renderer = new AdaptiveCanvases(host, () => state.revision);
  try {
    const message = document.createElement("span");
    renderer.apply({ node: host, message }, result, "failure-test");
    check(
      "An impossible fit retains the complete drawing and a diagnostic",
      result.layout.status === "overflow" &&
        host.dataset.canvasPlaceholder === "false" &&
        getComputedStyle(host.querySelector("svg")).display !== "none" &&
        message.textContent.length > 0,
    );
  } finally {
    renderer.resize.disconnect();
    clearTimeout(renderer.timer);
    host.remove();
  }
}
try {
  await until(() => paragraph(), "initial source");
  while (Number(document.querySelector("#reader-size").value) > 13)
    document.querySelector("#reader-smaller").click();
  await until(() => report.requests.length > 0, "initial automatic request");
  if (report.requests.some((r) => Object.values(r.canvases).some((v) => v.fontSize !== 13)))
    throw new Error("Fixture setup did not start the first drawing request at 13px");
  const drawings = [...document.querySelectorAll("[data-flow-canvas]")];
  check(
    "Unadapted drawings reserve bounded placeholders",
    drawings.length === 2 &&
      drawings.every(
        (n) => n.dataset.canvasPlaceholder === "true" && n.getBoundingClientRect().height > 30,
      ),
  );
  check(
    "Pending originals cannot widen the page",
    document.documentElement.scrollWidth <= document.documentElement.clientWidth + 1,
  );
  check(
    "The original source drawing waits for automatic replacement",
    drawings.every((n) => getComputedStyle(n.querySelector("svg,img")).display === "none"),
  );
  paragraph().scrollIntoView({ block: "start" });
  window.scrollBy(0, paragraph().getBoundingClientRect().top - 90);
  await new Promise((resolve) => setTimeout(resolve, 180));
  const initial = paragraph().getBoundingClientRect().top;
  release();
  await until(ready, "initial fitted drawings");
  position("Initial drawing publication preserves the reading paragraph", initial);
  check(
    "Fitted drawings appear automatically at full label size",
    drawings.every(
      (n) =>
        n.dataset.canvasPlaceholder === "false" &&
        n.querySelector("svg") &&
        Number(n.dataset.canvasFont) === 13,
    ),
  );
  check(
    "The fitted page needs no horizontal movement",
    document.documentElement.scrollWidth <= document.documentElement.clientWidth + 1,
  );
  pause();
  const fontRequests = report.requests.length;
  const beforeFont = paragraph().getBoundingClientRect().top;
  while (Number(document.querySelector("#reader-size").value) < 30)
    document.querySelector("#reader-larger").click();
  await until(
    () =>
      report.requests
        .slice(fontRequests)
        .some((r) => Object.values(r.canvases).some((v) => v.fontSize === 30)),
    "larger-font request",
  );
  position("Rapid reading-size changes preserve the paragraph", beforeFont);
  check(
    "A fitted drawing remains visible while larger labels load",
    drawings.every(
      (n) =>
        n.dataset.canvasPlaceholder === "false" &&
        getComputedStyle(n.querySelector("svg")).display !== "none",
    ),
  );
  if (!shrinking) {
    release();
    await until(
      () => ready() && drawings.every((n) => Number(n.dataset.canvasFont) === 30),
      "larger fitted labels",
    );
    position("Larger drawing publication preserves the paragraph", beforeFont);
  }
  const beforeResize = paragraph().getBoundingClientRect().top;
  const oldWidth = innerWidth;
  document.body.dataset.canvasLoadingState = "await-resize";
  output.textContent = JSON.stringify(report, null, 2);
  await until(() => innerWidth !== oldWidth, "external viewport change", 120000);
  if (shrinking) {
    await until(
      () => drawings.every((n) => n.dataset.canvasPlaceholder === "true"),
      "narrowing during the pending font request",
    );
    check(
      "A narrower viewport stays bounded during an in-flight font request",
      document.documentElement.scrollWidth <= document.documentElement.clientWidth + 1,
    );
    release();
  }
  const width = Math.floor(drawings[0].getBoundingClientRect().width);
  await until(
    () =>
      ready() &&
      drawings.every((n) => Number(n.dataset.canvasFont) === 30) &&
      finished.some((r) =>
        Object.values(r.canvases).some((v) => v.width === width && v.fontSize === 30),
      ),
    "resized drawings",
  );
  if (shrinking)
    check(
      "Only drawings for the current width can publish",
      drawings.every((n) => Number(n.dataset.canvasWidth) <= n.clientWidth + 1),
    );
  position("Viewport change and drawing publication preserve the paragraph", beforeResize);
  check(
    "The resized page has no horizontal overflow",
    document.documentElement.scrollWidth <= document.documentElement.clientWidth + 1,
  );
  if (new URLSearchParams(location.search).has("back")) {
    pause();
    const wide = innerWidth;
    const beforeBack = paragraph().getBoundingClientRect().top;
    const count = finished.length;
    const requests = report.requests.length;
    document.body.dataset.canvasLoadingState = "await-narrow";
    // Use a third width: the initial width already has a valid cached result.
    await until(
      () => innerWidth < wide && innerWidth !== oldWidth,
      "uncached narrower viewport",
      120000,
    );
    await until(
      () => drawings.every((n) => n.dataset.canvasPlaceholder === "true"),
      "narrower pending drawing",
    );
    await until(() => report.requests.length > requests, "delayed narrower request");
    check(
      "A width-only pending request cannot widen the page",
      document.documentElement.scrollWidth <= document.documentElement.clientWidth + 1,
    );
    document.body.dataset.canvasLoadingState = "await-return";
    await until(() => innerWidth === wide, "return to accepted width", 120000);
    await until(ready, "cached accepted drawing while an obsolete request waits");
    check(
      "Returning to an accepted width restores the drawing before the old response",
      finished.length === count && drawings.every((n) => n.dataset.canvasPlaceholder === "false"),
    );
    release();
    await until(() => finished.length > count, "obsolete width response");
    await new Promise((resolve) => setTimeout(resolve, 300));
    check(
      "An obsolete narrower response cannot replace the restored drawing",
      ready() && drawings.every((n) => Number(n.dataset.canvasWidth) <= n.clientWidth + 1),
    );
    position("Width round trips retain the reading paragraph", beforeBack);
  }
  await failedFit();
  document.body.dataset.canvasLoadingState = report.errors.length ? "error" : "ready";
} catch (error) {
  report.errors.push(String(error));
  document.body.dataset.canvasLoadingState = "error";
} finally {
  release();
  window.fetch = originalFetch;
}
output.textContent = JSON.stringify(report, null, 2);
