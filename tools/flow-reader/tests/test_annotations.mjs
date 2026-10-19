import assert from "node:assert/strict";
import test from "node:test";
import {
  shortAnnotation,
  sideAnnotations,
  popoverPosition,
  labelPosition,
} from "../web/annotations.js";

test("short labels find free space above preceding mathematical lines", () => {
  const target = { left: 100, right: 300, top: 140 };
  const size = { width: 50, height: 20 };
  const bounds = { left: 16, right: 374, top: 30 };
  const ink = [{ left: 16, right: 374, top: 100, bottom: 130 }];
  const box = labelPosition(target, size, bounds, ink);
  assert.deepEqual(box, { left: 175, right: 225, top: 74, bottom: 94 });
  const occupied = [...ink, { left: 160, right: 240, top: 70, bottom: 95 }];
  const next = labelPosition(target, size, bounds, occupied);
  assert.ok(next.right <= 157 || next.left >= 243 || next.bottom <= 67);
  assert.ok(next.top >= bounds.top);
});

test("short labels search horizontal gaps and reject insufficient physical space", () => {
  const target = { left: 90, right: 290, top: 100 };
  const size = { width: 50, height: 20 };
  const bounds = { left: 16, right: 374, top: 60 };
  const ink = [
    { left: 16, right: 110, top: 65, bottom: 95 },
    { left: 175, right: 374, top: 65, bottom: 95 },
  ];
  const box = labelPosition(target, size, bounds, ink);
  assert.ok(box.left >= 113 && box.right <= 172);
  assert.equal(labelPosition(target, { width: 400, height: 20 }, bounds, []), null);
  assert.equal(
    labelPosition(target, size, bounds, [{ left: 16, right: 374, top: 60, bottom: 100 }]),
    null,
  );
});

test("short names count graphemes and words, while rich and explanatory notes open", () => {
  for (const name of ["kernel", "heat kernel", "경계 조건", "e\u0301".repeat(24)])
    assert.equal(shortAnnotation(name), true, name);
  for (const name of ["", "a b c d", "k".repeat(25), "An explanation of the sign."])
    assert.equal(shortAnnotation(name), false, name);
  assert.equal(shortAnnotation("kernel", true), false);
});

test("side notes need both landscape proportions and real space at the reading font", () => {
  const wide = { width: 1280, height: 800, articleRight: 900, fontSize: 18 };
  assert.equal(sideAnnotations(wide), true);
  assert.equal(sideAnnotations({ ...wide, height: 1400 }), false);
  assert.equal(sideAnnotations({ ...wide, width: 900 }), false);
  assert.equal(sideAnnotations({ ...wide, articleRight: 1100 }), false);
  assert.equal(sideAnnotations({ ...wide, fontSize: 30 }), false);
});

test("popovers stay within viewport edges and use the space above or below a term", () => {
  const viewport = { top: 80, bottom: 800, left: 12, right: 378 };
  const size = { width: 300, height: 160 };
  const above = popoverPosition({ top: 400, bottom: 430, left: 20, right: 70 }, size, viewport);
  assert.equal(above.left, 12);
  assert.equal(above.top, 230);
  assert.equal(above.side, "above");
  const below = popoverPosition({ top: 85, bottom: 110, left: 330, right: 370 }, size, viewport);
  assert.equal(below.left, 78);
  assert.equal(below.top, 120);
  assert.equal(below.side, "below");
  const tall = popoverPosition(
    { top: 400, bottom: 430, left: 120, right: 200 },
    { width: 300, height: 1000 },
    viewport,
  );
  assert.ok(tall.top >= viewport.top);
  assert.ok(tall.top + tall.maxHeight <= viewport.bottom);
});
