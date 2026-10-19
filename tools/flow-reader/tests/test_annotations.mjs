import assert from "node:assert/strict";
import test from "node:test";
import { shortAnnotation, sideAnnotations, popoverPosition } from "../web/annotations.js";

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
