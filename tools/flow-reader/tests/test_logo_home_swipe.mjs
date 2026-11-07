import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { logoHomeURL, logoSwipe } from "../web/features/navigation/logo-home-swipe.js";

const down = (width = 200) => logoSwipe(null, { type: "down", pointerId: 1, isPrimary: true, button: 0, x: 0, y: 0, width });
const update = (state, type, x, y) => logoSwipe(state, { type, pointerId: 1, x, y });

test("logo touch-action follows the toolbar control rule", () => {
  const css = readFileSync(new URL("../web/reader.css", import.meta.url), "utf8").replace(/\/\*[\s\S]*?\*\//g, "");
  const rules = Array.from(css.matchAll(/([^{}]+)\{([^{}]*)\}/g), ([, selector, declarations]) => ({
    selector: selector.trim(),
    touchAction: Array.from(declarations.matchAll(/(?:^|;)\s*touch-action\s*:\s*([^;]+)\s*(?=;|$)/g), (match) => match[1].trim()).at(-1),
  })).filter((rule) => rule.touchAction);
  const toolbar = rules.findIndex((rule) => rule.selector.includes(".reader-toolbar :is(button, a)"));
  const brand = rules.filter((rule) => /\.reader-brand\b/.test(rule.selector));
  assert.ok(toolbar >= 0);
  assert.equal(rules[toolbar].touchAction, "manipulation");
  assert.ok(rules.indexOf(brand.at(-1)) > toolbar);
  assert.equal(brand.at(-1)?.touchAction, "pan-y");
  assert.match(brand.at(-1).selector, /\.reader-brand\s+svg\b/);
});

test("threshold and horizontal direction", () => {
  assert.equal(update(down(), "up", 59, 0).complete, false);
  assert.equal(update(down(), "up", 60, 0).complete, true);
  assert.equal(update(down(100), "up", 40, 19).complete, true);
  assert.equal(update(down(100), "up", 40, 20).complete, false);
  assert.equal(update(update(down(), "move", -11, 0), "up", 80, 0).complete, false);
  assert.equal(update(update(down(), "move", 5, 12), "up", 80, 0).complete, false);
});

test("cancellation and multiple pointers cannot complete", () => {
  assert.equal(update(logoSwipe(down(), { type: "cancel", pointerId: 1 }), "up", 80, 0).complete, false);
  assert.equal(update(logoSwipe(down(), { type: "down", pointerId: 2 }), "up", 80, 0).complete, false);
  assert.equal(logoSwipe(null, { type: "down", isPrimary: false, button: 0 }), null);
  assert.equal(logoSwipe(null, { type: "down", isPrimary: true, button: 2 }), null);
});

test("only shared document routes provide a Homepage", () => {
  assert.equal(logoHomeURL("/d/abc/"), "/");
  assert.equal(logoHomeURL("/"), null);
  assert.equal(logoHomeURL("/p/abc/"), null);
});
