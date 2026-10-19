import assert from "node:assert/strict";
import test from "node:test";
import { paintedPathPoint } from "../web/rendering/graphics/annotations.js";

test("an isolated SVG move cannot create a phantom stroke before the painted subpath", () => {
  const path = {
    getPointAtLength: (distance) => (distance === 0 ? { x: 0, y: 0 } : { x: 40 + distance, y: 20 }),
  };
  const point = paintedPathPoint(path, 0, 80);
  assert.ok(point.x >= 40 && point.x < 40.01);
  assert.equal(point.y, 20);
  assert.deepEqual(paintedPathPoint(path, 80, 80), { x: 120, y: 20 });
});

test("a subpixel path still samples inside its painted length", () => {
  const path = { getPointAtLength: (distance) => ({ distance }) };
  const point = paintedPathPoint(path, 0, 0.0001);
  assert.ok(point.distance > 0 && point.distance < 0.0001);
});

test("a move-only butt-cap path does not claim painted ink", () => {
  assert.equal(paintedPathPoint({}, 0, 0), null);
});

test("a zero-length round or square stroke retains its actual painted point", () => {
  const path = {
    getBBox: () => ({ x: 40, y: 60 }),
    ownerSVGElement: { createSVGPoint: () => ({}) },
  };
  assert.deepEqual(paintedPathPoint(path, 0, 0, "round"), { x: 40, y: 60 });
  assert.deepEqual(paintedPathPoint(path, 0, 0, "square"), { x: 40, y: 60 });
});
