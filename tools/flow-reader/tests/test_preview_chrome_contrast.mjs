import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import postcss from "postcss";

const parse = (path) => postcss.parse(readFileSync(new URL(path, import.meta.url), "utf8"));
const theme = parse("../web/theme.css");
const chrome = parse("../../typst-preview-frontend/src/styles/layout.css");
test("preview toolbar uses only the documented inline-width override", () => {
  const toolbar = parse("../../typst-preview-frontend/src/styles/toolbar.css");
  const important = (sheet) => {
    const declarations = [];
    sheet.walkDecls((decl) => { if (decl.important) declarations.push(decl); });
    return declarations;
  };
  assert.deepEqual(important(toolbar), []);
  const overrides = important(chrome);
  assert.equal(overrides.length, 1);
  assert.equal(overrides[0].prop, "width");
  assert.equal(overrides[0].value, "100%");
  assert.equal(overrides[0].parent.selector, "#typst-container.mode-slide #typst-top-toolbar");
  assert.match(overrides[0].prev()?.text ?? "", /inline calc width/);
});
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

test("preview chrome remains legible over composited glass in forced themes", () => {
  const surfaces = [
    ["../../typst-preview-frontend/src/styles/layout.css", "#typst-top-toolbar"],
    ["../../typst-preview-frontend/src/styles/help-panel.css", "#typst-help-panel"],
    ["../../typst-preview-frontend/src/styles/selection-actions.css", ":root .typst-selection-actions"],
  ];
  for (const [path, selector] of surfaces) {
    const sheet = parse(path);
    let glass;
    sheet.walkAtRules("supports", (at) => at.walkRules(selector, (node) => { glass = Object.fromEntries(node.nodes.filter((n) => n.type === "decl").map(({ prop, value }) => [prop, value])); }));
    assert.equal(glass?.background, "var(--glass-fill)", selector);
  }
  const outline = rule(parse("../../typst-preview-frontend/src/styles/outline.css"), ".typst-outline-title, .typst-preview-canvas-page-number");
  assert.equal(outline.color, "var(--ink)");
  const light = rule(chrome, ":root");
  for (const [name, values] of [["forced light", light], ["forced dark", { ...light, ...rule(chrome, ':root[data-document-theme="dark"]') }]]) {
    const match = /^rgb\((\d+) (\d+) (\d+) \/ (\d+)%\)$/.exec(values["--glass-fill"]);
    assert.ok(match);
    const alpha = Number(match[4]) / 100;
    // Include the themed surround and both extremes of content behind translucent chrome.
    for (const backdrop of [values["--paper"], "#000000", "#ffffff"]) {
      const channels = [1, 3, 5].map((i) => parseInt(backdrop.slice(i, i + 2), 16));
      const composite = channels.map((channel, i) => Math.round(Number(match[i + 1]) * alpha + channel * (1 - alpha)));
      const background = `#${composite.map((channel) => channel.toString(16).padStart(2, "0")).join("")}`;
      for (const foreground of ["--ink", "--warning", "--review-ink"]) {
        const ratio = contrast(values[foreground], background);
        assert.ok(ratio >= 4.5, `${name} ${foreground} on glass over ${backdrop}: ${ratio.toFixed(2)}`);
      }
    }
    assert.ok(contrast(values["--ink"], values["--paper"]) >= 4.5, `${name} outline on surround`);
  }
});
