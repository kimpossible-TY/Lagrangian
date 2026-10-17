import assert from "node:assert/strict";
import test from "node:test";
import { mathOverflow } from "../web/math-layout.js";

function rect(left, right) {
  return { left, right, width: right - left, height: 20 };
}
function node(bounds, stretch = null, assistive = false) {
  return {
    closest: (selector) => (selector === "mjx-assistive-mml" ? assistive : stretch),
    getClientRects: () => [bounds],
  };
}
function surface(nodes, scrollWidth = 100) {
  return {
    clientWidth: 100,
    scrollWidth,
    getBoundingClientRect: () => rect(0, 100),
    querySelectorAll: () => nodes,
  };
}

test("a stretched operator's stenciled glyph pieces do not create false horizontal overflow", () => {
  const bar = node(rect(20, 90));
  bar.closest = (selector) => (selector === "mjx-assistive-mml" ? null : bar);
  const pieces = [node(rect(20, 130), bar), node(rect(70, 160), bar)];
  const assistive = node(rect(-1000, 1000), null, true);
  assert.deepEqual(mathOverflow(surface([bar, ...pieces, assistive])), { left: 0, right: 0 });
});

test("real operator extents and indivisible layout width remain failed geometry", () => {
  const bar = node(rect(-3, 115));
  bar.closest = (selector) => (selector === "mjx-assistive-mml" ? null : bar);
  assert.deepEqual(mathOverflow(surface([bar])), { left: 3, right: 15 });
  assert.deepEqual(mathOverflow(surface([node(rect(0, 90))], 140)), { left: 0, right: 40 });
});
