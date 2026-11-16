import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import postcss from "postcss";

const home = postcss.parse(readFileSync(new URL("../web/home/home.css", import.meta.url), "utf8"));
const theme = postcss.parse(readFileSync(new URL("../web/theme.css", import.meta.url), "utf8"));

function declarations(rule) {
  return Object.fromEntries(
    rule.nodes.filter((node) => node.type === "decl").map(({ prop, value }) => [prop, value]),
  );
}

function tokens(selector) {
  const rule = theme.nodes
    .flatMap((node) => (node.type === "atrule" ? node.nodes : [node]))
    .find((node) => node.type === "rule" && node.selector === selector);
  assert.ok(rule, `Missing theme selector ${selector}`);
  return declarations(rule);
}

function resolve(value, values, seen = new Set()) {
  const mix = /^color-mix\(in srgb, (var\(--[\w-]+\)) ([\d.]+)%, (var\(--[\w-]+\))\)$/.exec(value);
  if (mix) {
    const first = resolve(mix[1], values, new Set(seen));
    const second = resolve(mix[3], values, new Set(seen));
    const weight = Number(mix[2]) / 100;
    assert.ok(weight >= 0 && weight <= 1);
    return (
      "#" +
      [1, 3, 5]
        .map((offset) =>
          Math.round(
            parseInt(first.slice(offset, offset + 2), 16) * weight +
              parseInt(second.slice(offset, offset + 2), 16) * (1 - weight),
          )
            .toString(16)
            .padStart(2, "0"),
        )
        .join("")
    );
  }
  const match = /^var\((--[\w-]+)\)$/.exec(value);
  if (!match) return value;
  assert.ok(!seen.has(match[1]), `Circular token ${match[1]}`);
  assert.ok(values[match[1]], `Missing token ${match[1]}`);
  seen.add(match[1]);
  return resolve(values[match[1]], values, seen);
}

function luminance(hex) {
  assert.match(hex, /^#[\da-f]{6}$/i, `Expected an opaque hex color, got ${hex}`);
  const channels = [1, 3, 5]
    .map((offset) => parseInt(hex.slice(offset, offset + 2), 16) / 255)
    .map((value) => (value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4));
  return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2];
}

function contrast(first, second) {
  const lightness = [luminance(first), luminance(second)].sort((a, b) => b - a);
  return (lightness[0] + 0.05) / (lightness[1] + 0.05);
}

// Explicit selector/inheritance mappings for this Home stylesheet, not a CSS
// cascade or browser/shadow-DOM simulator. Every color comes from a declaration.
function style(selector, root = home, required = true) {
  const rules = root.nodes.filter(
    (entry) => entry.type === "rule" && entry.selectors.includes(selector),
  );
  if (required) assert.ok(rules.length, `Missing Home rule: ${selector}`);
  return Object.assign({}, ...rules.map(declarations));
}
function background(paint, parent) {
  const value = paint["background-color"] || paint.background;
  return !value || value === "transparent" ? parent : value;
}
function foreground(paint, parent) {
  return !paint.color || paint.color === "inherit" ? parent : paint.color;
}
function edge(paint, property = "border") {
  const value = paint[property + "-color"] || paint[property];
  const color = /var\(--[\w-]+\)|#[\da-f]{6}\b|currentColor/.exec(value || "")?.[0];
  assert.ok(color, `Missing visible ${property} color: ${value}`);
  return color;
}
function palettes(root = home) {
  const light = tokens(":root");
  const support = root.nodes.find(
    (entry) =>
      entry.type === "atrule" && entry.name === "supports" && entry.params.includes("color-mix"),
  );
  assert.ok(support, "Home control edge requires a supported-color branch");
  const enhanced = style("body", support)["--home-control-edge"];
  assert.ok(enhanced);
  const base = style("body", root);
  return Object.entries({
    light,
    "explicit dark": { ...light, ...tokens(':root[data-theme="dark"]') },
    "system dark": { ...light, ...tokens(':root:not([data-theme="light"])') },
  }).flatMap(([name, values]) => [
    [name + " fallback", { ...values, ...base }],
    [name + " color-mix", { ...values, ...base, "--home-control-edge": enhanced }],
  ]);
}
function pair(label, color, fill, values, threshold) {
  assert.ok(color && fill, `Missing paint for ${label}`);
  const ratio = contrast(resolve(color, values), resolve(fill, values));
  assert.ok(ratio >= threshold, `${label}: ${ratio.toFixed(2)}:1 < ${threshold}:1`);
}
function surfaces(root) {
  const body = style("body", root);
  const page = background(body);
  return {
    ink: body.color,
    page,
    document: background(style(".document-card.item", root), page),
    dialog: background(style("dialog", root), page),
    inset: background(style(".connection-state", root), page),
    search: background(style(".search", root), page),
    menu: background(style("wa-dropdown::part(menu)", root), page),
  };
}
function verifyPlaceholder(root = home) {
  const surface = surfaces(root);
  const input = style(".search input", root);
  const paint = style(".search input::placeholder", root);
  for (const [name, values] of palettes(root))
    pair(name + " search placeholder", paint.color, background(input, surface.search), values, 4.5);
}
function verifyText(root = home) {
  const surface = surfaces(root);
  const base = style(".document-status", root);
  const selectors = new Set([".document-status"]);
  root.nodes
    .filter((entry) => entry.type === "rule")
    .forEach((rule) => {
      for (const selector of rule.selectors)
        if (/^\.document-status\[data-state="[^"]+"\]$/.test(selector)) selectors.add(selector);
    });
  for (const [name, values] of palettes(root)) {
    for (const selector of selectors) {
      const paint = { ...base, ...style(selector, root) };
      pair(
        name + " " + selector,
        foreground(paint, surface.ink),
        background(paint, surface.document),
        values,
        4.5,
      );
    }
    const feedback = style(".feedback", root);
    const inventory = { ...feedback, ...style("#inventory-message:not(:empty)", root) };
    for (const [selector, paint, parent] of [
      ["#document-count", style("#document-count", root), surface.page],
      [".feedback", feedback, surface.document],
      ["#inventory-message:not(:empty)", inventory, surface.page],
      [
        '#inventory-message[data-error]:not([data-error=""])',
        { ...inventory, ...style('#inventory-message[data-error]:not([data-error=""])', root) },
        surface.page,
      ],
    ]) {
      const fill = background(paint, parent);
      pair(name + " " + selector, foreground(paint, surface.ink), fill, values, 4.5);
    }
    const title = { ...style(".reader-link", root), ...style("h3 .reader-link", root) };
    pair(
      name + " document title",
      foreground(title, surface.ink),
      background(title, surface.document),
      values,
      4.5,
    );
  }
}
function verifyPressed(root = home) {
  for (const selector of [
    "button:active:not(:disabled)",
    "a:active",
    "summary:active",
    "wa-dropdown-item:active:not([disabled])",
  ]) {
    const paint = style(selector, root);
    assert.ok(paint.color && paint.background, selector + " needs an explicit paint pair");
    for (const [name, values] of palettes(root))
      pair(name + " " + selector, paint.color, paint.background, values, 4.5);
  }
}
function verifyEdges(root = home) {
  const surface = surfaces(root);
  const controlContexts = [
    ["button", [], [surface.page, surface.dialog, surface.inset]],
    ["button", ["#settings-open"], [surface.page]],
    ["button", [".alternatives-trigger"], [surface.document]],
    ["input", [], [surface.dialog]],
    ["select", [], [surface.dialog]],
    [".search", [], [surface.page]],
    ["wa-dropdown::part(menu)", [], [surface.page, surface.document]],
    [".skip", [], [surface.page]],
  ];
  for (const [selector, overrides, adjacent] of controlContexts) {
    const paint = Object.assign(
      {},
      selector === ".skip" ? style("a", root) : {},
      style(selector, root),
      ...overrides.map((s) => style(s, root)),
    );
    const color = edge(paint);
    for (const [name, values] of palettes(root)) {
      for (const parent of adjacent) {
        const fill = background(paint, parent);
        const ink = foreground(paint, surface.ink);
        pair(
          name + " " + selector + " inside border",
          color === "currentColor" ? ink : color,
          fill,
          values,
          3,
        );
        pair(
          name + " " + selector + " outside border",
          color === "currentColor" ? ink : color,
          parent,
          values,
          3,
        );
        pair(name + " " + selector + " resting text", ink, fill, values, 4.5);
      }
    }
  }
  // The search input intentionally delegates its edge and ring to the label.
  assert.equal(style(".search input", root).border, "0");
  assert.equal(style(".search input", root).background, "transparent");
  assert.equal(style(".search input:focus-visible", root).outline, "none");
  for (const [selector, adjacent] of [
    [
      ":focus-visible",
      [surface.page, surface.document, surface.dialog, surface.inset, surface.menu],
    ],
    ["#documents:focus", [surface.page]],
    ["#connection:focus", [surface.dialog]],
    [".search:focus-within", [surface.page]],
  ]) {
    const paint = style(selector, root);
    const color = edge(paint, "outline");
    for (const [name, values] of palettes(root))
      for (const fill of adjacent) pair(name + " " + selector, color, fill, values, 3);
  }
  // Read the Home-owned shadow-component paint bindings, not a guessed palette.
  const menu = style("wa-dropdown", root);
  for (const [name, values] of palettes(root)) {
    pair(name + " menu text", menu["--wa-color-text-normal"], surface.menu, values, 4.5);
    pair(
      name + " focused menu text",
      menu["--wa-color-text-normal"],
      menu["--wa-color-neutral-fill-normal"],
      values,
      4.5,
    );
    const ring = edge({ outline: menu["--wa-focus-ring"] }, "outline");
    for (const fill of [surface.menu, menu["--wa-color-neutral-fill-normal"]])
      pair(name + " menu focus ring", ring, fill, values, 3);
  }
}

test("Homepage hover declarations retain text contrast on their solid fills", () => {
  const hoverRules = [];
  home.walkRules((rule) => {
    if (rule.selector.includes(":hover")) hoverRules.push(rule);
  });
  for (const rule of hoverRules)
    rule.walkDecls("opacity", ({ value }) => {
      assert.match(value, /^(?:1(?:\.0+)?|100%)$/, rule.selector + " obscures hover text");
    });
  const colors = hoverRules.filter((rule) =>
    rule.nodes.some(
      (node) =>
        node.type === "decl" && ["color", "background", "background-color"].includes(node.prop),
    ),
  );
  assert.equal(colors.length, 1, "Review all Home hover paint overrides");
  assert.deepEqual(colors[0].selectors, [
    "button:hover:not(:disabled)",
    "a:hover",
    "summary:hover",
  ]);
  const paint = declarations(colors[0]);
  assert.ok(paint.color && paint.background && paint["text-decoration"]);
  for (const [name, values] of palettes())
    pair(name + " hover", paint.color, paint.background, values, 4.5);
});
test("search placeholder uses its actual input and search surface", () => verifyPlaceholder());
test("pressed controls and status declarations retain text contrast", () => {
  verifyPressed();
  verifyText();
});
test("actual control borders and focus declarations contrast with adjacent surfaces", () =>
  verifyEdges());

test("low-contrast declaration mutations are rejected without changing product files", () => {
  const source = home.toString();
  for (const [name, pattern, replacement, verify] of [
    [
      "search border",
      /(\.search\s*\{[^}]*?border: 1px solid )var\(--home-control-edge\)/,
      "$1var(--line)",
      verifyEdges,
    ],
    [
      "ready status",
      /(\.document-status\[data-state="ready"\]\s*\{\s*color:) var\(--accent\);/,
      "$1 #fffefa;",
      verifyText,
    ],
    [
      "pressed text",
      /(wa-dropdown-item:active:not\(\[disabled\]\)\s*\{\s*background:) var\(--wash\);/,
      "$1 var(--ink);",
      verifyPressed,
    ],
    [
      "placeholder",
      /(\.search input::placeholder\s*\{\s*color:) var\(--muted\);/,
      "$1 #fffefa;",
      verifyPlaceholder,
    ],
  ]) {
    const changed = source.replace(pattern, replacement);
    assert.notEqual(changed, source, name + " mutation must change the fixture");
    assert.throws(
      () => verify(postcss.parse(changed)),
      /:1 </,
      name + " must fail numerical contrast",
    );
  }
});
