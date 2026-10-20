import assert from "node:assert/strict";
import test from "node:test";
import {
  composeCanvas,
  overlaps,
  inkContrast,
  readableInk,
} from "../web/rendering/graphics/canvas-labels.js";

function label(id, x, y, width = 40, height = 28) {
  return {
    id: String(id),
    width,
    height,
    markerWidth: 30,
    markerHeight: 30,
    source: { left: x - 4, top: y - 4, width: 8, height: 8 },
  };
}

test("low-contrast authored colors retain channel proportions at readable ink contrast", () => {
  for (const rgb of [
    [170, 170, 170],
    [57, 204, 204],
    [46, 204, 64],
    [255, 65, 54],
    [245, 166, 35],
  ]) {
    const ink = readableInk(rgb);
    assert.ok(inkContrast(ink) >= 4.5);
    for (let i = 0; i < 3; i++) assert.ok(Math.abs(ink[i] / rgb[i] - ink[0] / rgb[0]) < 0.03);
    assert.ok(ink.every((value, i) => value <= rgb[i]));
  }
  const dark = [36, 44, 52];
  assert.equal(readableInk(dark), dark);
});

test("uniform geometry and original label coordinates survive narrow composition", () => {
  const model = { width: 600, height: 200 };
  const labels = [label(0, 200, 100), label(1, 400, 100)];
  const original = structuredClone(labels);
  const result = composeCanvas(model, 273, labels, 18);
  assert.deepEqual(labels, original);
  assert.equal(result.labels.length, 2);
  assert.ok(Math.abs(result.geometry.width / result.geometry.height - 3) < 1e-10);
  assert.ok(Math.abs(result.labels[0].anchor.x - (2 + (200 * 269) / 600)) < 1e-10);
  assert.equal(result.labels[0].mode, "inline");
});

test("SVG text anchors retain their exact source point and measured baseline", () => {
  const source = {
    ...label(0, 80, 50, 40, 32),
    source: { left: 80, top: 50, width: 0, height: 0, align: "end", baseline: true },
    baseline: 24,
  };
  const result = composeCanvas({ width: 200, height: 100 }, 204, [source], 18);
  const placed = result.labels[0];
  assert.equal(placed.mode, "inline");
  assert.equal(placed.anchor.x, 82);
  assert.equal(placed.anchor.y, 68);
  assert.equal(placed.left + placed.width, placed.anchor.x);
  assert.equal(placed.top + source.baseline, placed.anchor.y);
  assert.deepEqual(source.source, {
    left: 80,
    top: 50,
    width: 0,
    height: 0,
    align: "end",
    baseline: true,
  });
});

test("a small authored diagram uses the reading width without scaling its native label", () => {
  const source = label(0, 50, 25, 40, 28);
  const before = structuredClone(source);
  const result = composeCanvas({ width: 100, height: 50 }, 304, [source], 18);
  assert.equal(result.geometry.width, 300);
  assert.equal(result.geometry.height, 150);
  assert.equal(result.labels[0].width, 40);
  assert.equal(result.labels[0].height, 28);
  assert.equal(result.labels[0].anchor.x, 152);
  assert.deepEqual(source, before);
});

test("crowded labels retain readable badges and complete continuous legends", () => {
  const labels = Array.from({ length: 26 }, (_, i) => label(i, 300, 80, 220, 90));
  const result = composeCanvas({ width: 600, height: 160 }, 210, labels, 30);
  assert.equal(result.labels.length, labels.length);
  assert.ok(result.labels.every((item) => item.mode === "legend"));
  for (const [i, box] of result.labels.entries()) {
    assert.equal(box.width, 30);
    assert.equal(box.height, 30);
    assert.ok(box.left >= 0 && box.left + box.width <= 210);
    assert.ok(box.top >= 0 && box.top + box.height <= result.height);
    assert.ok(result.labels.slice(i + 1).every((other) => !overlaps(box, other)));
  }
});

test("a stroke crossing a label reserves a legend without changing its anchor", () => {
  const labels = [label(0, 100, 80, 80)];
  const clear = composeCanvas({ width: 200, height: 160 }, 204, labels, 18);
  const anchor = clear.labels[0].anchor;
  const crossed = composeCanvas({ width: 200, height: 160 }, 204, labels, 18, [
    [
      { x: 0, y: anchor.y },
      { x: 204, y: anchor.y },
    ],
  ]);
  assert.equal(clear.labels[0].mode, "inline");
  assert.equal(crossed.labels[0].mode, "legend");
  assert.deepEqual(crossed.labels[0].anchor, anchor);
  const distant = composeCanvas({ width: 200, height: 160 }, 204, labels, 18, [
    [
      { x: 0, y: 0 },
      { x: 204, y: 0 },
    ],
  ]);
  assert.equal(distant.labels[0].mode, "inline");
});

test("long or nested labels stay in the body with their full measured text size", () => {
  const nested = { ...label(0, 50, 60), nested: true };
  const wide = label(1, 150, 60, 300, 30);
  const result = composeCanvas({ width: 200, height: 160 }, 204, [nested, wide], 18);
  assert.deepEqual(
    result.labels.map((item) => item.mode),
    ["legend", "legend"],
  );
  assert.equal(wide.width, 300);
});

test("compact axis symbols use nearby free space at the measured reading size", () => {
  for (const font of [13, 18, 30]) {
    const symbol = label("y", 100, 80, font * 0.7, font * 1.2);
    const model = { width: 200, height: 160 };
    const original = composeCanvas(model, 204, [symbol], font).labels[0];
    const segments = [
      [
        { x: 0, y: original.anchor.y },
        { x: 204, y: original.anchor.y },
      ],
    ];
    const moved = composeCanvas(model, 204, [symbol], font, segments).labels[0];
    assert.equal(moved.mode, "inline");
    assert.equal(moved.width, symbol.width);
    assert.equal(moved.height, symbol.height);
    assert.deepEqual(moved.anchor, original.anchor);
    assert.ok(moved.top + moved.height < moved.anchor.y || moved.top > moved.anchor.y);
    assert.ok(Math.hypot(moved.left - original.left, moved.top - original.top) <= font);
  }
});

test("compact labels retain numbered fallback when nearby space is obstructed", () => {
  const symbol = label("y", 100, 80, 12, 20);
  const segments = Array.from({ length: 81 }, (_, i) => [
    { x: 0, y: 60 + i },
    { x: 204, y: 60 + i },
  ]);
  const result = composeCanvas({ width: 200, height: 160 }, 204, [symbol], 18, segments);
  assert.equal(result.labels[0].mode, "legend");
});

test("nearby placement preserves exact labels, bounds, and deterministic recomposition", () => {
  const labels = [label("y", 5, 60, 18, 24), label("x", 32, 60, 18, 24)];
  for (const width of [204, 304]) {
    const model = { width: 200, height: 160 };
    const plan = composeCanvas(model, width, labels, 18);
    assert.ok(plan.labels.every((box) => box.mode === "inline"));
    assert.ok(plan.labels.every((box) => box.left >= 0 && box.left + box.width <= width));
    assert.ok(!overlaps(...plan.labels));
    const exact = composeCanvas(model, width, [labels[1]], 18).labels[0];
    assert.deepEqual(plan.labels[1], exact);
    assert.deepEqual(composeCanvas(model, width, labels, 18), plan);
  }
});
