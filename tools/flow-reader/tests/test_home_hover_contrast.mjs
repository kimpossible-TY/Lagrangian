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

test("Homepage control hover colors retain text contrast in every theme and material mode", () => {
  const hoverRules = [];
  home.walkRules((rule) => {
    if (rule.selector.includes(":hover")) hoverRules.push(rule);
  });
  for (const rule of hoverRules) {
    rule.walkDecls("opacity", ({ value }) => {
      assert.match(
        value,
        /^(?:1(?:\.0+)?|100%)$/,
        `${rule.selector} reduces or obscures hover opacity`,
      );
    });
  }

  const controls = ["button:hover:not(:disabled)", "a:hover", "summary:hover"];
  const colorRules = hoverRules.filter((rule) =>
    rule.nodes.some(
      (node) =>
        node.type === "decl" && ["color", "background", "background-color"].includes(node.prop),
    ),
  );
  assert.equal(colorRules.length, 1, "Review all hover color overrides in this contract");
  const rule = colorRules[0];
  assert.deepEqual(rule.selectors, controls);
  const hover = declarations(rule);
  assert.ok(hover.color && hover.background, "Hover text and background must both be explicit");
  assert.ok(hover["text-decoration"], "Hover must provide visible feedback");

  const light = tokens(":root");
  const themes = {
    light,
    "explicit dark": { ...light, ...tokens(':root[data-theme="dark"]') },
    "system dark": { ...light, ...tokens(':root:not([data-theme="light"])') },
  };
  for (const [name, values] of Object.entries(themes)) {
    // Opaque control backgrounds have the same computed pair over glass and solid cards.
    for (const material of ["glass", "solid fallback"]) {
      for (const control of [
        "primary button",
        "secondary button",
        "text-button",
        "reader-link",
        "secondary reader-link",
      ]) {
        const foreground = resolve(hover.color, values);
        const background = resolve(hover.background, values);
        const ratio = contrast(foreground, background);
        assert.ok(ratio >= 4.5, `${name}, ${material}, ${control}: ${ratio.toFixed(2)}:1`);
      }
    }
  }
});

test("search placeholder follows theme contrast in light and dark modes", () => {
  const rule = home.nodes.find(
    (entry) => entry.type === "rule" && entry.selector === ".search input::placeholder",
  );
  assert.ok(rule);
  const color = declarations(rule).color;
  const light = tokens(":root");
  for (const values of [
    light,
    { ...light, ...tokens(':root[data-theme="dark"]') },
    { ...light, ...tokens(':root:not([data-theme="light"])') },
  ]) {
    assert.ok(contrast(resolve(color, values), resolve("var(--surface)", values)) >= 4.5);
  }
});

test("pressed controls and truthful status text retain contrast on solid surfaces", (t) => {
  const pressed = home.nodes.find(
    (entry) => entry.type === "rule" && entry.selectors.includes("a:active"),
  );
  assert.ok(pressed, "Pressed links need an explicit text/background pair");
  const paint = declarations(pressed);
  assert.ok(paint.color && paint.background);
  const light = tokens(":root");
  for (const [name, values] of Object.entries({
    light,
    "explicit dark": { ...light, ...tokens(':root[data-theme="dark"]') },
    "system dark": { ...light, ...tokens(':root:not([data-theme="light"])') },
  })) {
    const ratio = contrast(resolve(paint.color, values), resolve(paint.background, values));
    assert.ok(ratio >= 4.5, `${name} pressed text: ${ratio.toFixed(2)}:1`);
    for (const foreground of ["--ink", "--muted", "--accent", "--warning"]) {
      for (const background of ["--paper", "--surface", "--wash"]) {
        const actual = contrast(
          resolve(`var(${foreground})`, values),
          resolve(`var(${background})`, values),
        );
        assert.ok(actual >= 4.5, `${name} ${foreground}/${background}: ${actual.toFixed(2)}:1`);
      }
    }
    t.diagnostic(`${name} pressed text: ${ratio.toFixed(2)}:1`);
  }
});

test("control edges and focus remain distinguishable with mixed-color support or fallback", (t) => {
  const body = home.nodes.find((entry) => entry.type === "rule" && entry.selector === "body");
  const fallback = declarations(body)["--home-control-edge"];
  const support = home.nodes.find(
    (entry) =>
      entry.type === "atrule" && entry.name === "supports" && entry.params.includes("color-mix"),
  );
  assert.ok(support);
  const enhanced = declarations(support.nodes.find((entry) => entry.selector === "body"))[
    "--home-control-edge"
  ];
  assert.ok(fallback && enhanced, "Controls require an opaque fallback and an enhanced edge");
  const focus = home.nodes.find(
    (entry) => entry.type === "rule" && entry.selectors.includes(".search:focus-within"),
  );
  const focusColor = /var\(--[\w-]+\)/.exec(declarations(focus).outline)?.[0];
  assert.ok(focusColor);
  const light = tokens(":root");
  for (const [name, values] of Object.entries({
    light,
    "explicit dark": { ...light, ...tokens(':root[data-theme="dark"]') },
    "system dark": { ...light, ...tokens(':root:not([data-theme="light"])') },
  })) {
    let minimum = Infinity;
    for (const foreground of [fallback, enhanced, focusColor]) {
      for (const background of ["--paper", "--surface", "--wash"]) {
        const ratio = contrast(resolve(foreground, values), resolve(`var(${background})`, values));
        assert.ok(ratio >= 3, `${name} ${foreground}/${background}: ${ratio.toFixed(2)}:1`);
        minimum = Math.min(minimum, ratio);
      }
    }
    t.diagnostic(`${name} minimum control edge/focus: ${minimum.toFixed(2)}:1`);
  }
});
