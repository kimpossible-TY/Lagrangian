import assert from "node:assert/strict";
import test from "node:test";
import { bubblePosition } from "../web/features/paragraph-chat/geometry.js";

test("summary crosses exactly one third of an empty reading edge and searches nearby rows", () => {
  const geometry = {
    edge: 700,
    width: 240,
    height: 32,
    paragraph: { top: 100, bottom: 180 },
    viewport: { left: 0, right: 1024 },
    obstacles: [{ left: 100, right: 700, top: 100, bottom: 125 }],
  };
  const result = bubblePosition(geometry);
  assert.equal(result.left, 620);
  assert.equal(result.right, 860);
  assert.equal(700 - result.left, 240 / 3);
  assert.equal(result.right - 700, (240 * 2) / 3);
  assert.ok(result.top >= 130);
});

test("summary falls back inline when prose, math or annotations occupy local whitespace", () => {
  const base = {
    edge: 700,
    width: 240,
    height: 32,
    paragraph: { top: 100, bottom: 180 },
    viewport: { left: 0, right: 1024 },
    obstacles: [{ left: 600, right: 1000, top: 0, bottom: 240 }],
  };
  assert.equal(bubblePosition(base), null);
  assert.equal(bubblePosition({ ...base, obstacles: [], viewport: { left: 0, right: 800 } }), null);
});
