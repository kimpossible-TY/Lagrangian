import test from "node:test";
import assert from "node:assert/strict";
import { deflateSync } from "node:zlib";
import { sixelSequence } from "../terminal/sixel.mjs";

function chunk(type, data) {
  const body = Buffer.concat([Buffer.from(type), data]);
  let crc = 0xffffffff;
  for (const byte of body) {
    crc ^= byte;
    for (let bit = 0; bit < 8; bit++) crc = (crc >>> 1) ^ (crc & 1 ? 0xedb88320 : 0);
  }
  const result = Buffer.alloc(data.length + 12);
  result.writeUInt32BE(data.length);
  body.copy(result, 4);
  result.writeUInt32BE((crc ^ 0xffffffff) >>> 0, result.length - 4);
  return result;
}

function png(width, height, pixels, channels = 4, filter = 0) {
  const header = Buffer.alloc(13);
  header.writeUInt32BE(width);
  header.writeUInt32BE(height, 4);
  header[8] = 8;
  header[9] = channels === 4 ? 6 : 2;
  const stride = width * channels;
  const raw = Buffer.alloc((stride + 1) * height);
  for (let y = 0; y < height; y++) {
    raw[y * (stride + 1)] = filter;
    for (let x = 0; x < stride; x++) {
      const index = y * stride + x;
      const left = x >= channels ? pixels[index - channels] : 0;
      const above = y ? pixels[index - stride] : 0;
      const upperLeft = y && x >= channels ? pixels[index - stride - channels] : 0;
      const distances = [left, above, upperLeft].map((value) =>
        Math.abs(left + above - upperLeft - value),
      );
      const paeth = [left, above, upperLeft][distances.indexOf(Math.min(...distances))];
      const predictor = [0, left, above, Math.floor((left + above) / 2), paeth][filter];
      raw[y * (stride + 1) + x + 1] = pixels[index] - predictor;
    }
  }
  return Buffer.concat([
    Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]),
    chunk("IHDR", header),
    chunk("IDAT", deflateSync(raw)),
    chunk("IEND", Buffer.alloc(0)),
  ]);
}

// Independent small SIXEL interpreter: verify actual reconstructed pixels,
// including color planes, runs, band advances and the partial final band.
function decodeSixel(output) {
  const prefix = '\x1b[H\x1bP0;1;0q"1;1;';
  assert.ok(output.startsWith(prefix));
  assert.ok(output.endsWith("\x1b\\"));
  const data = output.slice(prefix.length, -2);
  const dimensions = data.match(/^(\d+);(\d+)/);
  const width = Number(dimensions[1]);
  const height = Number(dimensions[2]);
  const pixels = Array(width * height).fill(null);
  const palette = new Map();
  let x = 0;
  let y = 0;
  let color;
  const paint = (character, count) => {
    const bits = character.charCodeAt(0) - 63;
    for (let column = 0; column < count; column++, x++) {
      assert.ok(x < width);
      for (let bit = 0; bit < 6; bit++)
        if (bits & (1 << bit)) {
          assert.ok(y + bit < height, "frame must not paint below its final row");
          pixels[(y + bit) * width + x] = palette.get(color);
        }
    }
  };
  for (let index = dimensions[0].length; index < data.length; ) {
    const character = data[index++];
    if (character === "#") {
      const definition = data.slice(index).match(/^(\d+)(?:;2;(\d+);(\d+);(\d+))?/);
      color = Number(definition[1]);
      if (definition[2] !== undefined)
        palette.set(
          color,
          definition.slice(2).map((value) => Math.round(Number(value) * 2.55)),
        );
      index += definition[0].length;
    } else if (character === "!") {
      const repeat = data.slice(index).match(/^(\d+)([?-~])/);
      paint(repeat[2], Number(repeat[1]));
      index += repeat[0].length;
    } else if (character === "$") x = 0;
    else if (character === "-") {
      x = 0;
      y += 6;
    } else paint(character, 1);
  }
  assert.ok(pixels.every(Boolean), "every frame pixel, including its background, must be painted");
  return { width, height, pixels };
}

test("SIXEL reconstructs RGB/RGBA screenshot pixels for every PNG row filter", () => {
  const samples = [
    [0, 0, 0],
    [255, 255, 255],
    [255, 0, 0],
    [0, 255, 0],
    [0, 0, 255],
    [128, 128, 128],
    [51, 153, 204],
  ];
  for (const channels of [3, 4])
    for (let filter = 0; filter < 5; filter++) {
      const pixels = [];
      const expected = [];
      for (let index = 0; index < 11 * 8; index++) {
        const sample = samples[index % samples.length];
        pixels.push(...sample, ...(channels === 4 ? [255] : []));
        expected.push(sample);
      }
      const actual = decodeSixel(sixelSequence(png(11, 8, pixels, channels, filter)));
      assert.equal(actual.width, 11);
      assert.equal(actual.height, 8);
      for (let index = 0; index < expected.length; index++)
        for (let channel = 0; channel < 3; channel++)
          assert.ok(Math.abs(actual.pixels[index][channel] - expected[index][channel]) <= 3);
    }
});

test("SIXEL composites alpha onto white and compresses repeated columns", () => {
  const transparent = png(1, 1, [255, 0, 0, 0]);
  assert.deepEqual(decodeSixel(sixelSequence(transparent)).pixels, [[255, 255, 255]]);
  const frame = sixelSequence(
    png(80, 7, Array.from({ length: 80 * 7 }, () => [255, 0, 0, 255]).flat()),
  );
  assert.ok(frame.includes("!80~"));
  assert.ok(frame.includes("!80@"));
  assert.ok(frame.length < 150);
  assert.ok(decodeSixel(frame).pixels.every((pixel) => pixel.join() === "255,0,0"));
});

test("SIXEL rejects truncated, unsupported and oversized screenshots before drawing", () => {
  assert.throws(() => sixelSequence(Buffer.from("PNG")), /Invalid screenshot/);
  const valid = png(1, 1, [255, 0, 0, 255]);
  assert.throws(() => sixelSequence(valid.subarray(0, -4)), /Incomplete|Truncated/);
  const unsupported = Buffer.from(valid);
  unsupported[24] = 16;
  assert.throws(() => sixelSequence(unsupported), /8-bit/);
  const enormous = Buffer.from(valid);
  enormous.writeUInt32BE(32769, 16);
  assert.throws(() => sixelSequence(enormous), /dimensions/);
});
