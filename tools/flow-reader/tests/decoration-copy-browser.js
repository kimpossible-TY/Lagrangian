import { logicalTextIndex } from "/rendering/math/identity.js";

const report = { width: innerWidth, checks: [], errors: [], measurements: [] };
const output = document.createElement("script");
output.id = "decoration-copy-report";
output.type = "application/json";
document.body.append(output);
const publish = () => (output.textContent = JSON.stringify(report));
function check(name, condition) {
  report.checks.push(name);
  if (!condition) report.errors.push(name);
  publish();
}
async function until(condition, name, timeout = 20000) {
  const deadline = Date.now() + timeout;
  while (!condition()) {
    if (Date.now() > deadline) throw new Error(`Timed out: ${name}`);
    await new Promise((resolve) => setTimeout(resolve, 40));
  }
}
function targets() {
  const nodes = [...document.querySelectorAll("[data-flow-decoration]")].filter(
    (node) =>
      node.querySelector("[data-flow-cancel]") &&
      !node.closest("mjx-assistive-mml,.flow-math-stage"),
  );
  return {
    source: nodes.find((node) => !node.closest(".flow-note-targets")),
    copy: nodes.find((node) => node.closest(".flow-note-targets")),
  };
}
function state(node) {
  const view = node?.closest(".flow-math-view");
  return {
    math: view?.dataset.mathState,
    decoration: node?.dataset.decorationState,
    rect: node?.getBoundingClientRect().toJSON(),
    paint: node?.closest(".flow-equation,.flow-note")?.querySelectorAll(".flow-decoration-paint")
      .length,
    text: view && logicalTextIndex(view, { includeNested: true }).text,
    term: node && logicalTextIndex(node, { includeNested: true }).text,
    enclosure: Boolean(
      view?.querySelector('mjx-assistive-mml menclose[notation="updiagonalstrike"]'),
    ),
  };
}
try {
  const query = new URL(location.href).searchParams;
  if (query.has("audit")) {
    const { attachReport } = await import("/test-report.js");
    attachReport({ kind: "decorations", id: output.id, stateKey: "decorationCopyState" });
  }
  if (query.has("width"))
    await until(() => innerWidth === Number(query.get("width")), "requested viewport");
  report.width = innerWidth;
  await until(() => targets().source, "original cancellation");
  report.revision = (await (await fetch("/api/manifest")).json()).revision;
  const fonts = query.get("fonts")?.split(",").map(Number) ?? [13, 30];
  for (const font of fonts) {
    while (Number(document.querySelector("#reader-size").value) !== font)
      document
        .querySelector(
          Number(document.querySelector("#reader-size").value) < font
            ? "#reader-larger"
            : "#reader-smaller",
        )
        .click();
    targets().source.scrollIntoView({ block: "start" });
    await until(() => state(targets().source).math === "ready", "original mathematics");
    report.active = { font, source: state(targets().source), copy: state(targets().copy) };
    publish();
    check(
      `${font}px source is visible without an automatically cloned explanation`,
      state(targets().source).rect.top < innerHeight && !targets().copy,
    );
    await until(
      () => state(targets().source).decoration === "ready",
      "visible original cancellation",
    );
    const original = state(targets().source);
    check(`${font}px cancellation is painted without opening its annotation`, original.paint > 0);
    check(`${font}px source retains assistive cancellation notation`, original.enclosure);
    report.measurements.push({
      font,
      phase: "source",
      source: original,
      copy: state(targets().copy),
    });
    const target = targets().source.closest("[data-reader-note]");
    const note = document.getElementById(target.dataset.readerNote.split(" ")[0]);
    await until(() => target.dataset.noteInteractive === "true", "annotation activation");
    target.dispatchEvent(new MouseEvent("click", { bubbles: true }));
    await until(() => note.dataset.open === "true", "authored explanation");
    check(
      `${font}px opening the explanation preserves the original cancellation and semantic term`,
      state(targets().source).paint > 0 &&
        state(targets().source).term === original.term &&
        !note.querySelector(".flow-note-targets") &&
        note.textContent.includes("The cancellation"),
    );
    note.querySelector(".flow-note-close").click();
    report.measurements.push({ font, phase: "annotation", source: state(targets().source) });
    publish();
  }
  delete report.active;
  document.body.dataset.decorationCopyState = report.errors.length ? "error" : "ready";
} catch (error) {
  report.errors.push(String(error));
  report.active = {
    ...report.active,
    source: state(targets().source),
    copy: state(targets().copy),
  };
  document.body.dataset.decorationCopyState = "error";
}
publish();
