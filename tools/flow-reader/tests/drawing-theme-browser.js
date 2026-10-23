import {
  DrawingTheme,
  drawingBackground,
  inkContrast,
  parseColor,
} from "../web/features/appearance/drawing-theme.js";

const article = document.querySelector("#reader-document");
const original = () =>
  [...article.querySelectorAll("svg,svg *")]
    .filter((node) => !node.closest("[data-live-tests]"))
    .map((node) =>
      ["d", "points", "viewBox", "fill", "stroke", "color", "mask", "href", "stop-color"].map(
        (key) => node.getAttribute(key),
      ),
    );
const source = original();
const liveTemplate = document.querySelector("#live-drawing").cloneNode(true);
let liveStage = 0;
const drawingTheme = new DrawingTheme(article);
let refreshCount = 0;
const refresh = drawingTheme.refresh.bind(drawingTheme);
drawingTheme.refresh = () => {
  refreshCount++;
  refresh();
};
const frame = () => new Promise(requestAnimationFrame);
const histories = new Map();
const liveHistories = new Map();

function changeSource(svg, stage) {
  const node = (name) => svg.querySelector(`[data-paint="${name}"]`);
  if (stage === 2) {
    node("attribute-fill").setAttribute("fill", "url(#gradient)");
    node("attribute-stroke").setAttribute("stroke", "none");
    node("attribute-color").setAttribute("color", "#000000");
    node("style-fill").style.fill = "none";
    node("style-stroke").style.stroke = "currentColor";
    node("style-color").style.color = "#000000";
    node("important-stroke").style.setProperty("stroke", "currentColor", "important");
    node("html-color").style.color = "#000000";
    node("native-label").style.color = "#000000";
    node("mathcolor").setAttribute("mathcolor", "#000000");
  } else if (stage === 3) {
    node("attribute-fill").removeAttribute("fill");
    node("attribute-stroke").removeAttribute("stroke");
    node("attribute-color").removeAttribute("color");
    node("style-fill").style.removeProperty("fill");
    node("style-stroke").style.removeProperty("stroke");
    node("style-color").style.removeProperty("color");
    node("important-stroke").style.removeProperty("stroke");
    node("html-color").style.removeProperty("color");
    node("native-label").style.removeProperty("color");
    node("mathcolor").removeAttribute("mathcolor");
  } else {
    const fill = stage === 1 ? "#f0ebf8" : "#f0f5ff";
    const ink = stage === 1 ? "#c84031" : "#3157c8";
    node("attribute-fill").setAttribute("fill", fill);
    node("attribute-stroke").setAttribute("stroke", ink);
    node("attribute-color").setAttribute("color", ink);
    node("style-fill").style.fill = fill;
    node("style-stroke").style.stroke = ink;
    node("style-color").style.color = ink;
    node("important-stroke").style.setProperty("stroke", ink, "important");
    node("html-color").style.color = ink;
    node("native-label").style.color = ink;
    node("mathcolor").setAttribute("mathcolor", ink);
  }
}

function freshReference(id) {
  const reference = liveTemplate.cloneNode(true);
  reference.id = id;
  changeSource(reference, liveStage);
  return reference;
}

async function mutatePaint() {
  document.body.dataset.audit = "pending";
  liveStage = (liveStage + 1) % 5;
  const drawing = document.querySelector("#live-drawing");
  drawing.remove();
  changeSource(drawing, liveStage);
  // Removed descendants can still appear in the observer's queued records.
  await frame();
  document.querySelector("#live-comparison").prepend(drawing);
  document.querySelector("#live-reference").replaceChildren(freshReference("reference-drawing"));
  // Clone after the source update has received its presentation paint. The clone
  // must recover those sources when mounted on the page's different background.
  await frame();
  await frame();
  const clone = document.querySelector("#live-drawing").cloneNode(true);
  clone.id = "live-clone";
  document
    .querySelector("#late-live-drawing")
    .replaceChildren(clone, freshReference("reference-clone"));
  await audit();
}

async function audit() {
  document.body.dataset.audit = "pending";
  await frame();
  await frame();
  const checks = [],
    errors = [];
  const check = (name, condition) => {
    checks.push(name);
    if (!condition) errors.push(name);
  };
  let settledFrames = 0,
    lastRefresh = refreshCount;
  for (let pass = 0; pass < 10 && settledFrames < 3; pass++) {
    await frame();
    settledFrames = refreshCount === lastRefresh ? settledFrames + 1 : 0;
    lastRefresh = refreshCount;
  }
  check("Drawing paint observer settles after external updates", settledFrames === 3);
  const color = (selector, property) =>
    parseColor(getComputedStyle(document.querySelector(selector))[property]);
  const near = (a, b) => a.every((value, i) => Math.abs(value - b[i]) < 1);
  const background = drawingBackground(document.querySelector(".flow-canvas").parentElement);
  check(
    "Semantic mannot term colors remain readable",
    inkContrast(
      color("#marked-math", "color"),
      drawingBackground(document.querySelector("#marked-math")),
    ) >= 4.5,
  );
  check("SVG paper matches its enclosing callout", near(color("#paper", "fill"), background));
  check(
    "Native label paper matches the same callout",
    near(color(".flow-canvas-label-body", "backgroundColor"), background),
  );
  check(
    "Native text remains readable",
    inkContrast(color("#native-label", "color"), background) >= 4.5,
  );
  check(
    "Colored label remains readable",
    inkContrast(color("#colored-label", "color"), background) >= 4.5,
  );
  check(
    "Original black axis remains visible",
    inkContrast(color("#axis", "stroke"), background) >= 3,
  );
  check("Colored arrow remains visible", inkContrast(color("#blue", "stroke"), background) >= 3);
  check(
    "Inherited symbol glyph retains its colored use ink",
    inkContrast(color("#colored-glyph", "fill"), background) >= 4.5,
  );
  check(
    "Inherited pale glyph ink remains readable rather than becoming paper",
    inkContrast(color("#pale-glyph-group use", "fill"), background) >= 4.5,
  );
  for (const [blueId, redId, property] of [
    ["colored-glyph", "red-glyph", "fill"],
    ["inherited-blue-glyph", "inherited-red-glyph", "fill"],
    ["current-blue-glyph", "current-red-glyph", "color"],
  ]) {
    check(
      `${blueId} and ${redId} retain distinct per-use colors`,
      !near(color(`#${blueId}`, property), color(`#${redId}`, property)),
    );
    for (const id of [blueId, redId])
      check(`${id} remains readable`, inkContrast(color(`#${id}`, property), background) >= 4.5);
  }
  check(
    "Symbol inherited/currentColor paths keep instance paint",
    ["#glyph path", "#inherited-glyph path", "#current-glyph path"].every(
      (selector) => !document.querySelector(selector).style.fill,
    ),
  );
  check(
    "Explicit reusable defs ink remains visible",
    inkContrast(color("#reusable-ink", "fill"), background) >= 3,
  );
  const cells = ["blue-cell", "purple-cell", "gray-cell", "alpha-cell"];
  for (const id of cells) {
    const fill = color(`#${id}`, "fill");
    check(`${id} remains a subtle surface wash`, inkContrast(fill, background) < 1.5);
    check(
      `${id} permits readable label ink`,
      inkContrast(color("#native-label", "color"), fill) >= 4.5,
    );
  }
  const blue = color("#blue-cell", "fill"),
    purple = color("#purple-cell", "fill");
  const tint = (rgb) => rgb.map((value, i) => value - background[i]);
  const blueTint = tint(blue),
    purpleTint = tint(purple);
  check("Blue cell tint is retained", blueTint[2] > blueTint[0] && blueTint[2] > blueTint[1]);
  check(
    "Purple cell tint is retained",
    purpleTint[0] > purpleTint[1] && purpleTint[2] > purpleTint[1],
  );
  check("Authored cell alpha is retained", color("#alpha-cell", "fill")[3] === 0.7);
  for (const id of ["oklab-cell", "oklab-alpha-cell"]) {
    check(
      `${id} receives subtle theme shading`,
      inkContrast(color(`#${id}`, "fill"), background) < 1.5,
    );
  }
  check("Authored Oklab alpha is retained", color("#oklab-alpha-cell", "fill")[3] === 0.7);
  check(
    "Text sharing a group does not change its inherited surface fill",
    near(color("#plain-inherited-cell", "fill"), color("#mixed-inherited-cell", "fill")) &&
      inkContrast(color("#mixed-inherited-cell", "fill"), background) < 1.5,
  );
  check(
    "Inherited group text remains readable over its sibling surface",
    inkContrast(color("#mixed-inherited-text", "fill"), color("#mixed-inherited-cell", "fill")) >=
      4.5,
  );
  for (const id of ["attribute-current-ink", "style-current-ink"]) {
    check(
      `${id} adapts fixed currentColor to visible vector ink`,
      inkContrast(color(`#${id}`, "stroke"), background) >= 3,
    );
  }
  check(
    "Fixed currentColor text remains readable",
    inkContrast(color("#current-text", "fill"), background) >= 4.5,
  );
  check(
    "A pale stroke still receives foreground contrast",
    inkContrast(color("#pale-stroke", "stroke"), background) >= 3,
  );
  check(
    "SVG masks retain white coverage and black holes",
    near(color("#mask-paper", "fill"), [255, 255, 255]) &&
      near(color("#mask-hole", "fill"), [0, 0, 0]),
  );
  check(
    "Gradient paint remains an SVG resource",
    /url\(/.test(getComputedStyle(document.querySelector("#gradient-box")).fill),
  );
  check(
    "mannot underlay retains readable formula ink",
    inkContrast(color("#marked-math", "color"), color("#underlay", "fill")) >= 4.5,
  );
  check(
    "SVG roots and relationship frames are transparent",
    ["svg", ".flow-canvas", ".flow-graphic-frame"].every((selector) =>
      [...document.querySelectorAll(selector)].every(
        (node) => getComputedStyle(node).backgroundColor === "rgba(0, 0, 0, 0)",
      ),
    ),
  );
  check(
    "Authored geometry, paint attributes, masks and references are intact",
    JSON.stringify(original().slice(0, source.length)) === JSON.stringify(source),
  );
  const late = document.querySelector("#late-ink");
  if (late) {
    check(
      "Late asynchronous paint receives the current appearance",
      inkContrast(
        parseColor(getComputedStyle(late).stroke),
        drawingBackground(late.closest("svg").parentElement),
      ) >= 3,
    );
    check(
      "Cloned paint uses its original color on a different background",
      near(color("#late-paper", "fill"), drawingBackground(late.closest("svg").parentElement)),
    );
    check(
      "Cloned cell shading remains subtle on a different background",
      inkContrast(
        color("#late-cell", "fill"),
        drawingBackground(late.closest("svg").parentElement),
      ) < 1.5,
    );
  }
  const livePaints = [
    ["attribute-fill", "fill"],
    ["style-fill", "fill"],
    ["attribute-stroke", "stroke"],
    ["style-stroke", "stroke"],
    ["attribute-current", "stroke"],
    ["style-current", "stroke"],
    ["important-stroke", "stroke"],
    ["html-current", "stroke"],
    ["native-label", "color"],
    ["mathcolor", "color"],
  ];
  for (const [activeId, referenceId] of [
    ["live-drawing", "reference-drawing"],
    ["live-clone", "reference-clone"],
  ]) {
    const active = document.getElementById(activeId);
    if (!active) continue;
    const reference = document.getElementById(referenceId);
    for (const [name, property] of livePaints) {
      const activeNode = active.querySelector(`[data-paint="${name}"]`);
      const referenceNode = reference.querySelector(`[data-paint="${name}"]`);
      const actual = getComputedStyle(activeNode)[property];
      const expected = getComputedStyle(referenceNode)[property];
      const actualRgb = parseColor(actual),
        expectedRgb = parseColor(expected);
      check(
        `${activeId} stage ${liveStage} ${name} matches freshly mounted authored paint`,
        actualRgb && expectedRgb ? near(actualRgb, expectedRgb) : actual === expected,
      );
    }
    check(
      `${activeId} keeps current authored paint attributes`,
      [...active.querySelectorAll("[data-paint]")].every((node) => {
        const expected = reference.querySelector(`[data-paint="${node.dataset.paint}"]`);
        return ["fill", "stroke", "color", "mathcolor"].every(
          (property) => node.getAttribute(property) === expected.getAttribute(property),
        );
      }),
    );
    check(
      `${activeId} keeps authored inline paint priority`,
      active
        .querySelector('[data-paint="important-stroke"]')
        .style.getPropertyPriority("stroke") === (liveStage === 3 ? "" : "important"),
    );
  }
  const theme = document.documentElement.dataset.theme;
  const livePalette = JSON.stringify(
    livePaints.map(
      ([name, property]) =>
        getComputedStyle(document.querySelector(`#live-drawing [data-paint="${name}"]`))[property],
    ),
  );
  const liveHistoryKey = `${theme}:${liveStage}`;
  if (liveHistories.has(liveHistoryKey))
    check(
      "Authored paint updates stay stable through repeated theme changes",
      liveHistories.get(liveHistoryKey) === livePalette,
    );
  liveHistories.set(liveHistoryKey, livePalette);
  const palette = JSON.stringify([
    color("#paper", "fill"),
    color("#axis", "stroke"),
    color("#native-label", "color"),
    color("#colored-label", "color"),
    ...cells.map((id) => color(`#${id}`, "fill")),
  ]);
  if (histories.has(theme))
    check(
      "Returning to a theme does not accumulate color changes",
      histories.get(theme) === palette,
    );
  histories.set(theme, palette);
  document.querySelector("#report").textContent = JSON.stringify(
    { theme, liveStage, checks, errors },
    null,
    2,
  );
  document.body.dataset.audit = errors.length ? "error" : "ready";
  document.body.dataset.auditTheme = theme;
  document.body.dataset.auditStage = liveStage;
}
document.querySelector("#reader-theme").addEventListener("change", audit);
document.querySelector("#mutate").addEventListener("click", () => void mutatePaint());
document.querySelector("#late").addEventListener("click", () => {
  const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
  svg.setAttribute("viewBox", "0 0 240 110");
  svg.setAttribute("width", "240");
  svg.setAttribute("height", "110");
  for (const [source, id] of [
    ["paper", "late-paper"],
    ["axis", "late-ink"],
    ["blue-cell", "late-cell"],
  ]) {
    const copy = document.getElementById(source).cloneNode(true);
    copy.id = id;
    svg.append(copy);
  }
  document.querySelector("#late-drawing").replaceChildren(svg);
  void audit();
});
document.querySelector("#live-reference").replaceChildren(freshReference("reference-drawing"));
void audit();
