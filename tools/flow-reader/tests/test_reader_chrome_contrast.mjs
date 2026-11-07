import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import postcss from "postcss";

const css = postcss.parse(readFileSync(new URL("../web/reader.css", import.meta.url), "utf8"));
const theme = postcss.parse(readFileSync(new URL("../web/theme.css", import.meta.url), "utf8"));

function declarations(rule) {
  return Object.fromEntries(rule.nodes.filter((node) => node.type === "decl").map(({ prop, value }) => [prop, value]));
}
function tokens(selector) {
  const rule = theme.nodes.flatMap((node) => node.type === "atrule" ? node.nodes : [node])
    .find((node) => node.type === "rule" && node.selector === selector);
  assert.ok(rule, `Missing theme selector ${selector}`);
  return declarations(rule);
}
function resolve(value, values, seen = new Set()) {
  const match = /^var\((--[\w-]+)\)$/.exec(value);
  if (!match) return value;
  assert.ok(!seen.has(match[1]) && values[match[1]], `Invalid token ${match[1]}`);
  seen.add(match[1]);
  return resolve(values[match[1]], values, seen);
}
function rgb(hex) {
  assert.match(hex, /^#[\da-f]{6}$/i);
  return [1, 3, 5].map((offset) => parseInt(hex.slice(offset, offset + 2), 16));
}
function luminance(channels) {
  const linear = channels.map((channel) => channel / 255)
    .map((value) => value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4);
  return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2];
}
function contrast(a, b) {
  const [light, dark] = [luminance(a), luminance(b)].sort((x, y) => y - x);
  return (light + 0.05) / (dark + 0.05);
}
function ruleWith(selector, parent) {
  let found;
  css.walkRules((rule) => {
    if (rule.selectors.includes(selector) && (!parent || rule.parent.params?.includes(parent))) found = rule;
  });
  assert.ok(found, `Missing ${selector} in ${parent || "stylesheet"}`);
  return declarations(found);
}

test("Reader chrome control colors remain legible in themes and material fallbacks", () => {
  const hover = ruleWith("#reader-outline a:hover", "hover: hover");
  assert.equal(hover.color, "var(--color-text)");
  assert.equal(hover.background, "var(--color-tint)");
  for (const selector of [".reader-toolbar", ".reader-drawer-panel", "#reader-appearance-panel"]) {
    assert.equal(ruleWith(selector, "backdrop-filter").background, "var(--glass-fill)");
    assert.equal(ruleWith(selector, "prefers-reduced-transparency").background, "var(--glass-solid)");
  }
  for (const selector of [".reader-toolbar button:hover:not(:disabled)",
    ".reader-drawer-panel button:hover:not(:disabled)",
    "#reader-appearance-panel button:hover:not(:disabled)", "#reader-appearance-panel summary:hover"]) {
    assert.deepEqual(ruleWith(selector, "hover: hover"), hover);
  }
  const light = tokens(":root");
  const themes = {
    light,
    "explicit dark": { ...light, ...tokens(':root[data-theme="dark"]') },
    "system dark": { ...light, ...tokens(':root:not([data-theme="light"])') },
  };
  for (const [name, values] of Object.entries(themes)) {
    const ink = rgb(resolve("var(--color-text)", values));
    for (const background of ["--color-tint", "--glass-solid", "--color-page"]) {
      const ratio = contrast(ink, rgb(resolve(`var(${background})`, values)));
      assert.ok(ratio >= 4.5, `${name}, ${background}: ${ratio.toFixed(2)}:1`);
    }
    for (const [foreground, background] of [["--muted", "--paper"], ["--muted", "--surface"], ["--accent", "--wash"],
      ["--accent", "--surface"], ["--warning", "--surface"]]) {
      const ratio = contrast(rgb(resolve(`var(${foreground})`, values)), rgb(resolve(`var(${background})`, values)));
      assert.ok(ratio >= 4.5, `${name}, ${foreground} on ${background}: ${ratio.toFixed(2)}:1`);
    }
    const fill = resolve("var(--glass-fill)", values);
    const match = /^rgb\((\d+) (\d+) (\d+) \/ (\d+)%\)$/.exec(fill);
    assert.ok(match, `Expected glass color, got ${fill}`);
    const alpha = Number(match[4]) / 100;
    // Test both extreme backdrops; channel compositing is monotonic between them.
    for (const backdrop of [0, 255]) {
      const composite = match.slice(1, 4).map((channel) => Number(channel) * alpha + backdrop * (1 - alpha));
      const ratio = contrast(ink, composite);
      assert.ok(ratio >= 4.5, `${name}, glass over ${backdrop}: ${ratio.toFixed(2)}:1`);
    }
  }
});
