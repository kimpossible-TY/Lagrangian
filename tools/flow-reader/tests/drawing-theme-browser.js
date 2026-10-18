import { DrawingTheme, drawingBackground, inkContrast, parseColor } from "../web/drawing-theme.js";

const article = document.querySelector("#reader-document");
const original = () =>
  [...article.querySelectorAll("svg,svg *")].map((node) =>
    ["d", "points", "viewBox", "fill", "stroke", "mask", "href", "stop-color"].map((key) =>
      node.getAttribute(key),
    ),
  );
const source = original();
new DrawingTheme(article);
const frame = () => new Promise(requestAnimationFrame);
const histories = new Map();

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
  }
  const theme = document.documentElement.dataset.theme;
  const palette = JSON.stringify([
    color("#paper", "fill"),
    color("#axis", "stroke"),
    color("#native-label", "color"),
    color("#colored-label", "color"),
  ]);
  if (histories.has(theme))
    check(
      "Returning to a theme does not accumulate color changes",
      histories.get(theme) === palette,
    );
  histories.set(theme, palette);
  document.querySelector("#report").textContent = JSON.stringify(
    { theme, checks, errors },
    null,
    2,
  );
  document.body.dataset.audit = errors.length ? "error" : "ready";
  document.body.dataset.auditTheme = theme;
}
document.querySelector("#reader-theme").addEventListener("change", audit);
document.querySelector("#late").addEventListener("click", () => {
  const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
  svg.setAttribute("viewBox", "0 0 240 110");
  svg.setAttribute("width", "240");
  svg.setAttribute("height", "110");
  for (const [source, id] of [
    ["paper", "late-paper"],
    ["axis", "late-ink"],
  ]) {
    const copy = document.getElementById(source).cloneNode(true);
    copy.id = id;
    svg.append(copy);
  }
  document.querySelector("#late-drawing").replaceChildren(svg);
  void audit();
});
void audit();
