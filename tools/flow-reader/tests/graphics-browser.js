const report = { width: innerWidth, checks: [], errors: [], measurements: [] };
const compilerPaint = new Map();
const normalFetch = window.fetch;
window.fetch = async (...args) => {
  const response = await normalFetch(...args);
  if (String(args[0]).endsWith("api/graphics") && response.ok) {
    const result = await response.clone().json();
    for (const [id, source] of Object.entries(result.graphics)) compilerPaint.set(id, source);
  }
  return response;
};
function paintSignature(svg) {
  return JSON.stringify(
    [...svg.querySelectorAll("path")].map((path) => {
      const transforms = [];
      for (let node = path; node && node !== svg; node = node.parentElement)
        transforms.push(node.getAttribute("transform"));
      return [
        path.getAttribute("d"),
        path.getAttribute("stroke"),
        path.getAttribute("fill"),
        transforms,
      ];
    }),
  );
}
const output = document.createElement("pre");
output.id = "graphics-report";
output.style.cssText =
  "white-space:pre-wrap;overflow-wrap:anywhere;font:13px/1.5 monospace;margin:16px";
document.body.append(output);
const publish = () => (output.textContent = JSON.stringify(report, null, 2));
function check(name, condition) {
  report.checks.push(name);
  if (!condition) report.errors.push(name);
  publish();
}
async function until(condition, name, timeout = 300000) {
  const deadline = Date.now() + timeout;
  while (!condition()) {
    if (Date.now() > deadline) throw new Error(`Timed out: ${name}`);
    await new Promise((resolve) => setTimeout(resolve, 150));
  }
}
try {
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
        return [...parsed.querySelectorAll("[data-flow-graphic]")].map((note) => {
          const tags = JSON.parse(note.dataset.flowTargets);
          const mark = [...parsed.querySelectorAll("[data-flow-mark]")].find(
            (node) => node.dataset.flowMark === tags[0],
          );
          return {
            id: note.dataset.flowGraphic,
            tags,
            anchor: mark?.closest("[data-reader-key]")?.id,
          };
        });
      }),
    )
  ).flat();
  check(
    "Every source relationship exposes its original target tags and reading anchor",
    targets.length > 0 && targets.every((target) => target.anchor),
  );
  const query = new URL(location.href).searchParams;
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
    for (const target of targets) {
      if (query.get("only") && query.get("only") !== target.id) continue;
      if (!document.getElementById(target.anchor)) location.hash = target.anchor;
      await until(() => document.getElementById(target.anchor), `${target.id} section`);
      document.getElementById(target.anchor).scrollIntoView({ block: "start" });
      const note = () =>
        document.querySelector(`.flow-graphic-status[data-graphic-id="${target.id}"]`);
      await until(() => note(), `${target.id} scene`);
      const scene = note().closest(".flow-graphic-scene");
      await until(
        () =>
          [...scene.querySelectorAll(".flow-math-view")].every((view) =>
            ["ready", "overflow", "error"].includes(view.dataset.mathState),
          ),
        `${target.id} native math`,
      );
      await until(
        () => ["ready", "collision", "overflow"].includes(note().dataset.graphicState),
        `${target.id} automatic geometry`,
      );
      const svg = scene.querySelector(`svg.flow-graphic-overlay[data-graphic-id="${target.id}"]`);
      const collisions = JSON.parse(note().dataset.graphicCollisions || "{}");
      const unrouted = JSON.parse(note().dataset.graphicUnrouted || "[]");
      const prefix = `${font}px ${target.id}`;
      check(
        `${prefix} composes its complete source mathematics at the reading width`,
        [...scene.querySelectorAll(".flow-math-view")].every(
          (view) => view.dataset.mathState === "ready",
        ),
      );
      check(
        `${prefix} composes its relationship automatically`,
        note().dataset.graphicState === "ready" && Boolean(svg),
      );
      check(
        `${prefix} preserves every native marked target`,
        target.tags.every((tag) =>
          [...scene.querySelectorAll("[data-flow-mark]")].some(
            (node) => node.dataset.flowMark === tag,
          ),
        ),
      );
      check(
        `${prefix} avoids label and path collisions with mathematical ink`,
        (collisions.labels ?? 0) === 0 && (collisions.paths ?? 0) === 0 && unrouted.length === 0,
      );
      check(
        `${prefix} keeps vectors separate from native mathematical glyphs`,
        svg && svg.querySelectorAll("path").length > 0 && !svg.querySelector("symbol,use,text"),
      );
      const sourcePaint = compilerPaint.get(target.id);
      check(
        `${prefix} retains every compiler path, arrowhead and authored transform`,
        sourcePaint &&
          svg &&
          paintSignature(svg) ===
            paintSignature(
              new DOMParser().parseFromString(sourcePaint, "image/svg+xml").documentElement,
            ),
      );
      check(
        `${prefix} stays bounded without horizontal movement`,
        scene.scrollWidth <= scene.clientWidth + 1 &&
          document.documentElement.scrollWidth <= document.documentElement.clientWidth + 1,
      );
      report.measurements.push({
        font,
        id: target.id,
        targets: target.tags.length,
        state: note().dataset.graphicState,
        mode: note().dataset.graphicMode,
        viewport: innerWidth,
        collisions,
        unrouted,
        scene: [scene.clientWidth, scene.scrollWidth],
      });
      publish();
    }
  }
  document.body.dataset.graphicsState = report.errors.length ? "error" : "ready";
} catch (error) {
  report.errors.push(String(error));
  document.body.dataset.graphicsState = "error";
}
publish();
