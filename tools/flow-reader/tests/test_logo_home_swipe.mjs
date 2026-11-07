import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { logoHomeURL, logoGesture } from "../web/features/navigation/logo-home-swipe.js";

const down = (width = 200) => logoGesture(null, { type: "down", pointerId: 1, isPrimary: true, button: 0, x: 0, y: 0, width });
const update = (state, type, x, y) => logoGesture(state, { type, pointerId: 1, x, y });

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

test("hold, release, and movement transitions are exclusive", () => {
  assert.equal(logoGesture(down(), { type: "hold" }).action, "home");
  assert.equal(update(down(), "up", 0, 0).action, null);
  const moved = update(down(), "move", 11, 0);
  assert.equal(moved.phase, "swiping");
  assert.equal(logoGesture(moved, { type: "hold" }).action, null);
  const held = logoGesture(down(), { type: "hold" });
  assert.equal(update(update(held, "move", 80, 0), "up", 80, 0).action, null);
  assert.equal(update(moved, "up", 80, 0).action, "home");
});

test("swipe thresholds and cancellation", () => {
  assert.equal(update(down(), "up", 59, 0).action, null);
  assert.equal(update(down(), "up", 60, 0).action, "home");
  assert.equal(update(down(100), "up", 40, 19).action, "home");
  assert.equal(update(down(100), "up", 40, 20).action, null);
  assert.equal(update(update(down(), "move", -11, 0), "up", 80, 0).action, null);
  assert.equal(update(update(down(), "move", 5, 12), "up", 80, 0).action, null);
  assert.equal(update(logoGesture(down(), { type: "cancel", pointerId: 1 }), "up", 80, 0).action, null);
  assert.equal(update(logoGesture(down(), { type: "down", pointerId: 2 }), "up", 80, 0).action, null);
  assert.equal(logoGesture(null, { type: "down", isPrimary: false, button: 0 }), null);
});

test("only shared document routes provide a Homepage", () => {
  assert.equal(logoHomeURL("/d/abc/"), "/");
  assert.equal(logoHomeURL("/"), null);
  assert.equal(logoHomeURL("/p/abc/"), null);
});
