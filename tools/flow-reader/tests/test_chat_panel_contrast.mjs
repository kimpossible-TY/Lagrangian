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

test("Chat colors and hover remain legible across themes and materials", () => {
  const hover = ruleWith(".reader-chat button:hover:not(:disabled)", "hover: hover");
  assert.equal(hover.color, "var(--color-text)");
  assert.equal(hover.background, "var(--color-tint)");
  css.walkRules((rule) => {
    if (rule.selector.includes(".reader-chat") && rule.selector.includes(":hover")) {
      rule.walkDecls("opacity", () => assert.fail(`Hover opacity in ${rule.selector}`));
    }
  });
  for (const selector of [".reader-chat-heading", ".reader-chat-composer"]) {
    assert.equal(ruleWith(selector, "backdrop-filter").background, "var(--glass-fill)");
    assert.equal(ruleWith(selector, "prefers-reduced-transparency").background, "var(--glass-solid)");
  }
  const light = tokens(":root");
  const themes = { light, dark: { ...light, ...tokens(':root[data-theme="dark"]') },
    system: { ...light, ...tokens(':root:not([data-theme="light"])') } };
  for (const [name, values] of Object.entries(themes)) {
    for (const [foreground, background] of [["--color-text", "--color-tint"],
      ["--color-text", "--color-surface"], ["--color-text", "--color-page"],
      ["--color-subtle", "--color-surface"], ["--color-subtle", "--color-page"],
      ["--warning", "--color-page"], ["--color-action", "--color-page"],
      ["--color-surface", "--color-action"]]) {
      const ratio = contrast(rgb(resolve(`var(${foreground})`, values)), rgb(resolve(`var(${background})`, values)));
      assert.ok(ratio >= 4.5, `${name}, ${foreground} on ${background}: ${ratio.toFixed(2)}:1`);
    }
    const match = /^rgb\((\d+) (\d+) (\d+) \/ (\d+)%\)$/.exec(resolve("var(--glass-fill)", values));
    assert.ok(match);
    for (const backdrop of [0, 255]) {
      const alpha = Number(match[4]) / 100;
      const composite = match.slice(1, 4).map((channel) => Number(channel) * alpha + backdrop * (1 - alpha));
      for (const foreground of ["--color-text"]) {
        const ratio = contrast(rgb(resolve(`var(${foreground})`, values)), composite);
        assert.ok(ratio >= 4.5, `${name}, ${foreground} glass over ${backdrop}: ${ratio.toFixed(2)}:1`);
      }
    }
  }
});
