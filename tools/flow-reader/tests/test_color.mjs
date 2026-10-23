import assert from "node:assert/strict";
import test from "node:test";
import { parseColor } from "../web/features/appearance/color.js";

const approximately = (actual, expected, tolerance = 0.02) => {
  assert.equal(actual?.length, expected.length);
  for (let i = 0; i < expected.length; i++)
    assert.ok(Math.abs(actual[i] - expected[i]) <= tolerance, JSON.stringify({ actual, expected }));
};

test("numeric sRGB colors retain channels, percentages, and alpha", () => {
  assert.deepEqual(parseColor("rgba(230, 228, 223, 0.9)"), [230, 228, 223, 0.9]);
  assert.deepEqual(parseColor("rgb(230 228 223 / 90%)"), [230, 228, 223, 0.9]);
  assert.deepEqual(parseColor("RGB(100% 50% 0%)"), [255, 127.5, 0]);
  assert.deepEqual(parseColor("color(srgb 0.5 1 0 / 0.2)"), [127.5, 255, 0, 0.2]);
  assert.deepEqual(parseColor("color(srgb 50% 100% 0% / 20%)"), [127.5, 255, 0, 0.2]);
  assert.deepEqual(parseColor("#1b1c1e"), [27, 28, 30]);
  assert.deepEqual(parseColor("#0f08"), [0, 255, 0, 136 / 255]);
  assert.deepEqual(parseColor("#1b1c1e80"), [27, 28, 30, 128 / 255]);
  assert.deepEqual(parseColor("transparent"), [0, 0, 0, 0]);
});

test("Typst Oklab fills convert to sRGB while preserving the tint and alpha", () => {
  // Independently checked against Chromium/WebKit's sRGB canvas conversion.
  approximately(parseColor("oklab(95% 0.00001 0.00004)"), [238.306, 238.292, 238.264]);
  approximately(parseColor("oklab(0.95 1e-5 4e-5 / 0.7)"), [238.306, 238.292, 238.264, 0.7]);
  approximately(parseColor("oklab(0.627955 0.224863 0.125846)"), [255, 0, 0]);
  approximately(parseColor("oklab(0.86644 -0.233888 0.179498)"), [0, 255, 0]);
  approximately(parseColor("oklab(0.452014 -0.032457 -0.311528)"), [0, 0, 255]);
  approximately(parseColor("oklab(60% 10% -25% / 40%)"), parseColor("oklab(.6 .04 -.1 / .4)"));
});

test("Oklch hue units and missing channels resolve consistently", () => {
  const expected = parseColor("oklab(.7 0 .1 / .5)");
  for (const angle of ["90", "90deg", "100grad", "1.5707963267948966rad", ".25turn", "450deg"])
    approximately(parseColor(`oklch(70% 25% ${angle} / 50%)`), expected);
  approximately(parseColor("oklab(.5 none none)"), [99.086, 99.086, 99.086]);
  approximately(parseColor("oklch(.5 -0.1 none)"), parseColor("oklab(.5 0 0)"));
});

test("the contrast pipeline only receives finite bounded paint channels", () => {
  assert.deepEqual(parseColor("rgb(-10 300 0 / 200%)"), [0, 255, 0, 1]);
  assert.deepEqual(parseColor("oklab(0 .2 -.1 / -1)"), [0, 0, 0, 0]);
  assert.deepEqual(parseColor("oklab(1 -.2 .1)"), [255, 255, 255]);
  for (const color of ["oklab(.7 1 -.8)", "oklch(.7 2 -30)", "color(srgb -1 2 0)"])
    assert.ok(
      parseColor(color).every(
        (channel) => Number.isFinite(channel) && channel >= 0 && channel <= 255,
      ),
    );
  for (const color of [
    null,
    undefined,
    123,
    "",
    "none",
    "url(#gradient)",
    "currentColor",
    "var(--ink)",
    "rgb(1 2)",
    "rgb(1 2 3 4)",
    "rgb(1,,3)",
    "rgb(1 2 3 /)",
    "rgb(1, 2, 3 / .5)",
    "oklab(.5, 0, 0)",
    "oklab(.5 0 NaN)",
    "oklab(.5 1e999 0)",
    "oklch(.5 .1 90%)",
    "color(srgb 1 0)",
    "color(unknown 1 0 0)",
    "oklab(calc(.5) 0 0)",
  ])
    assert.equal(parseColor(color), null, String(color));
});
