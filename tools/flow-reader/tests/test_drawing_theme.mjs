import assert from "node:assert/strict";
import test from "node:test";
import {
  drawingPaint,
  inkContrast,
  parseColor,
  readableInk,
} from "../web/features/appearance/drawing-theme.js";

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

test("pale CeTZ cell fills retain subtle shading and color in either appearance", () => {
  for (const [background, ink] of [
    [light, darkInk],
    [dark, softInk],
    [[238, 241, 236], darkInk],
    [[37, 45, 42], softInk],
  ]) {
    for (const source of [
      [240, 245, 255],
      [240, 235, 248],
      [239, 239, 239],
      [220, 220, 220, 0.7],
    ]) {
      const original = [...source];
      const fill = drawingPaint(source, background, ink, { paper: true });
      assert.ok(inkContrast(fill, background) < 1.5, JSON.stringify({ source, fill }));
      assert.ok(inkContrast(ink, fill) >= 4.5, JSON.stringify({ ink, fill }));
      assert.ok(fill.every(Number.isFinite));
      assert.equal(fill[3], source[3]);
      assert.deepEqual(source, original);
    }
    const blue = drawingPaint([240, 245, 255], background, ink, { paper: true });
    const purple = drawingPaint([240, 235, 248], background, ink, { paper: true });
    const tint = (rgb) => rgb.map((value, i) => value - background[i]);
    const blueTint = tint(blue),
      purpleTint = tint(purple);
    assert.ok(blueTint[2] > blueTint[0] && blueTint[2] > blueTint[1]);
    assert.ok(purpleTint[0] > purpleTint[1] && purpleTint[2] > purpleTint[1]);
    assert.notDeepEqual(blue, purple);
    // The same authored color still needs foreground contrast for glyphs/lines.
    assert.ok(inkContrast(drawingPaint([240, 245, 255], background, ink), background) >= 3);
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
