import assert from "node:assert/strict";
import test from "node:test";
import { drawingPaint, inkContrast, parseColor, readableInk } from "../web/drawing-theme.js";

const dark = [27, 28, 30],
  light = [250, 249, 246];
const softInk = [230, 228, 223],
  darkInk = [41, 40, 36];

test("labels and colored vector ink remain readable on both reading surfaces", () => {
  for (const background of [
    dark,
    light,
    [37, 45, 42],
    [238, 241, 236],
    [153, 153, 153],
    [120, 120, 120],
  ]) {
    for (const source of [
      [0, 0, 0],
      [255, 255, 255],
      [48, 80, 240],
      [224, 48, 48],
      [57, 204, 204],
    ]) {
      const original = [...source];
      assert.ok(inkContrast(readableInk(source, background), background) >= 4.5);
      const ink =
        inkContrast(darkInk, background) > inkContrast(softInk, background) ? darkInk : softInk;
      assert.ok(inkContrast(drawingPaint(source, background, ink), background) >= 3);
      assert.deepEqual(source, original);
    }
  }
});

test("neutral drawing ink and opaque paper follow the surrounding surface", () => {
  for (const [background, ink] of [
    [dark, softInk],
    [light, darkInk],
  ]) {
    assert.deepEqual(drawingPaint([0, 0, 0], background, ink), ink);
    assert.deepEqual(drawingPaint([255, 255, 255], background, ink, { paper: true }), background);
    assert.deepEqual(drawingPaint([255, 255, 255, 0.7], background, ink, { paper: true }), [
      ...background,
      0.7,
    ]);
    assert.deepEqual(drawingPaint([255, 255, 255], background, ink), ink);
    assert.deepEqual(drawingPaint([252, 250, 246], background, ink, { paper: true }), background);
  }
});

test("mannot filled underlays retain legible mathematical ink", () => {
  for (const [background, ink] of [
    [dark, softInk],
    [light, darkInk],
  ]) {
    for (const color of [
      [255, 255, 128],
      [49, 87, 200],
      [150, 200, 150],
    ]) {
      const fill = drawingPaint(color, background, ink, { underlay: true });
      assert.ok(inkContrast(ink, fill) >= 4.5, JSON.stringify({ ink, fill }));
    }
  }
});

test("already readable colors retain their exact channels and transparency", () => {
  const source = [230, 228, 223, 0.9];
  assert.equal(readableInk(source, dark), source);
  assert.deepEqual(parseColor("rgba(230, 228, 223, 0.9)"), source);
  assert.deepEqual(parseColor("rgb(230 228 223 / 0.9)"), source);
  assert.deepEqual(parseColor("#1b1c1e"), dark);
  assert.deepEqual(parseColor("color(srgb 0.5 1 0 / 0.2)"), [127.5, 255, 0, 0.2]);
  for (const paint of ["none", "url(#gradient)", "currentColor"])
    assert.equal(parseColor(paint), null);
});
