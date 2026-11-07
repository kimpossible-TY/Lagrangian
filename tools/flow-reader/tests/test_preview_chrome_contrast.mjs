import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import postcss from "postcss";

const parse = (path) => postcss.parse(readFileSync(new URL(path, import.meta.url), "utf8"));
const theme = parse("../web/theme.css");
const chrome = parse("../../typst-preview-frontend/src/styles/layout.css");
function rule(tree, selector) {
  let result;
  tree.walkRules(selector, (node) => { if (!result) result = node; });
  assert.ok(result, `Missing ${selector}`);
  return Object.fromEntries(result.nodes.filter((node) => node.type === "decl").map(({ prop, value }) => [prop, value]));
}
function contrast(a, b) {
  const luminance = (hex) => {
    assert.match(hex, /^#[\da-f]{6}$/i);
    const [r, g, b] = [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16) / 255)
      .map((v) => v <= 0.04045 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4);
    return 0.2126 * r + 0.7152 * g + 0.0722 * b;
  };
  const values = [luminance(a), luminance(b)].sort((x, y) => y - x);
  return (values[0] + 0.05) / (values[1] + 0.05);
}
test("preview mirrors Reader tokens in explicit and system themes", () => {
  for (const [source, target] of [[":root", ":root"], [':root[data-theme="dark"]', ':root[data-document-theme="dark"]'], [':root:not([data-theme="light"])', ':root:not([data-document-theme="light"])']]) {
    assert.deepEqual(rule(chrome, target), rule(theme, source));
  }
});
test("preview chrome hover and solid text colors retain contrast", () => {
  const light = rule(chrome, ":root");
  for (const dark of [false, true]) {
    const values = dark ? { ...light, ...rule(chrome, ':root[data-document-theme="dark"]') } : light;
    for (const background of ["--surface", "--wash", "--paper"]) {
      assert.ok(contrast(values["--ink"], values[background]) >= 4.5, `${background} ${dark ? "dark" : "light"}`);
    }
    assert.ok(contrast(values["--review-ink"], values["--surface"]) >= 4.5);
  }
  chrome.walkRules((node) => {
    if (node.selector.includes(":hover")) node.walkDecls("opacity", ({ value }) => assert.equal(value, "1"));
  });
  const toolbar = parse("../../typst-preview-frontend/src/styles/toolbar.css");
  const hover = rule(toolbar, ".typst-page-button:hover, .typst-toolbar-icon:hover");
  assert.equal(hover.color, "var(--ink)");
  assert.equal(hover.background, "var(--wash)");
});
