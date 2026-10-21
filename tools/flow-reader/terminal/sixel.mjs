// Native SIXEL output for Chromium viewport screenshots; no external image tool.
import { inflateSync } from "node:zlib";

const ESC = "\x1b";
const signature = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);

function paeth(left, above, upperLeft) {
  const prediction = left + above - upperLeft;
  const a = Math.abs(prediction - left);
  const b = Math.abs(prediction - above);
  const c = Math.abs(prediction - upperLeft);
  return a <= b && a <= c ? left : b <= c ? above : upperLeft;
}

// Chromium emits noninterlaced, 8-bit RGB/RGBA. Reject other PNG formats rather
// than silently misreading pixels; dimensions also bound zlib's output allocation.
function screenshotPixels(png) {
  if (!png.subarray(0, 8).equals(signature)) throw new Error("Invalid screenshot PNG");
  let width;
  let height;
  let channels;
  let ended = false;
  const compressed = [];
  for (let offset = 8; offset + 12 <= png.length; ) {
    const length = png.readUInt32BE(offset);
    const end = offset + 12 + length;
    if (end > png.length) throw new Error("Truncated screenshot PNG");
    const type = png.toString("ascii", offset + 4, offset + 8);
    const data = png.subarray(offset + 8, end - 4);
    if (offset === 8 && type !== "IHDR") throw new Error("Missing PNG header");
    if (type === "IHDR") {
      if (
        offset !== 8 ||
        length !== 13 ||
        data[8] !== 8 ||
        ![2, 6].includes(data[9]) ||
        data[10] !== 0 ||
        data[11] !== 0 ||
        data[12] !== 0
      )
        throw new Error("SIXEL requires a noninterlaced 8-bit RGB/RGBA screenshot PNG");
      width = data.readUInt32BE(0);
      height = data.readUInt32BE(4);
      channels = data[9] === 6 ? 4 : 3;
      if (!width || !height || width > 32768 || height > 32768 || width * height > 16777216)
        throw new Error("Screenshot PNG dimensions exceed the SIXEL frame limit");
    } else if (type === "IDAT") compressed.push(data);
    else if (type === "IEND") {
      ended = true;
      break;
    }
    offset = end;
  }
  if (!ended || !compressed.length) throw new Error("Incomplete screenshot PNG");
  const stride = width * channels;
  const expected = (stride + 1) * height;
  const raw = inflateSync(Buffer.concat(compressed), { maxOutputLength: expected });
  if (raw.length !== expected) throw new Error("Invalid screenshot PNG pixel length");
  const pixels = Buffer.alloc(stride * height);
  for (let y = 0; y < height; y++) {
    const filter = raw[y * (stride + 1)];
    if (filter > 4) throw new Error("Invalid screenshot PNG row filter");
    for (let x = 0; x < stride; x++) {
      const offset = y * stride + x;
      const left = x >= channels ? pixels[offset - channels] : 0;
      const above = y ? pixels[offset - stride] : 0;
      const upperLeft = y && x >= channels ? pixels[offset - stride - channels] : 0;
      const predictor =
        filter === 0
          ? 0
          : filter === 1
            ? left
            : filter === 2
              ? above
              : filter === 3
                ? Math.floor((left + above) / 2)
                : paeth(left, above, upperLeft);
      pixels[offset] = raw[y * (stride + 1) + x + 1] + predictor;
    }
  }
  return { pixels, width, height, channels };
}

function colorBox(entries) {
  let weight = 0;
  const mean = [0, 0, 0];
  for (const entry of entries) {
    weight += entry.count;
    for (let channel = 0; channel < 3; channel++) mean[channel] += entry.rgb[channel] * entry.count;
  }
  for (let channel = 0; channel < 3; channel++) mean[channel] /= weight;
  const variance = [0, 0, 0];
  for (const entry of entries)
    for (let channel = 0; channel < 3; channel++)
      variance[channel] += (entry.rgb[channel] - mean[channel]) ** 2 * entry.count;
  const axis = variance.indexOf(Math.max(...variance));
  return { entries, mean, weight, axis, score: entries.length > 1 ? variance[axis] : 0 };
}

function screenshotColors(pixels, channels) {
  // A bounded 5-bit histogram retains actual pixel means. A fixed six-level RGB
  // cube merged the green/blue channels of gold highlights, turning them red.
  const bins = 1 << 15;
  const counts = new Uint32Array(bins);
  const sums = Array.from({ length: 3 }, () => new Uint32Array(bins));
  const colors = new Uint16Array(pixels.length / channels);
  for (let index = 0; index < colors.length; index++) {
    const offset = index * channels;
    const alpha = channels === 4 ? pixels[offset + 3] / 255 : 1;
    const background = 255 * (1 - alpha);
    const red = Math.round(pixels[offset] * alpha + background);
    const green = Math.round(pixels[offset + 1] * alpha + background);
    const blue = Math.round(pixels[offset + 2] * alpha + background);
    if (red === green && green === blue) {
      colors[index] = bins + Math.round((red * 39) / 255);
      continue;
    }
    const bin = ((red >> 3) << 10) | ((green >> 3) << 5) | (blue >> 3);
    colors[index] = bin;
    counts[bin]++;
    sums[0][bin] += red;
    sums[1][bin] += green;
    sums[2][bin] += blue;
  }
  const entries = [];
  for (let bin = 0; bin < bins; bin++)
    if (counts[bin])
      entries.push({ bin, count: counts[bin], rgb: sums.map((sum) => sum[bin] / counts[bin]) });
  const boxes = entries.length ? [colorBox(entries)] : [];
  while (boxes.length && boxes.length < 216) {
    let largest = 0;
    for (let index = 1; index < boxes.length; index++)
      if (boxes[index].score > boxes[largest].score) largest = index;
    const box = boxes[largest];
    if (!box.score) break;
    box.entries.sort((a, b) => a.rgb[box.axis] - b.rgb[box.axis]);
    let split = 0;
    let weight = 0;
    while (split < box.entries.length - 1 && weight < box.weight / 2)
      weight += box.entries[split++].count;
    boxes.splice(
      largest,
      1,
      colorBox(box.entries.slice(0, split)),
      colorBox(box.entries.slice(split)),
    );
  }
  const palette = Array.from({ length: 256 }, (_, index) =>
    index >= 216 ? Array(3).fill(Math.round(((index - 216) * 100) / 39)) : null,
  );
  const lookup = new Uint8Array(bins);
  boxes.forEach((box, index) => {
    palette[index] = box.mean.map((channel) => Math.round((channel * 100) / 255));
    for (const entry of box.entries) lookup[entry.bin] = index;
  });
  for (let index = 0; index < colors.length; index++) {
    const bin = colors[index];
    colors[index] = bin >= bins ? 216 + bin - bins : lookup[bin];
  }
  return { colors, palette };
}

function runs(plane, end) {
  const result = [];
  for (let x = 0; x < end; ) {
    const value = plane[x];
    let next = x + 1;
    while (next < end && plane[next] === value) next++;
    const character = String.fromCharCode(63 + value);
    const count = next - x;
    result.push(count >= 4 ? `!${count}${character}` : character.repeat(count));
    x = next;
  }
  return result.join("");
}

export function sixelSequence(png) {
  const { pixels, width, height, channels } = screenshotPixels(png);
  const { colors, palette } = screenshotColors(pixels, channels);
  const used = new Set(colors);
  // P2=1 leaves unpainted bits transparent. Every actual pixel is painted,
  // including the background; the last partial band cannot erase the status row.
  const result = [`${ESC}[H${ESC}P0;1;0q"1;1;${width};${height}`];
  for (const color of used) result.push(`#${color};2;${palette[color].join(";")}`);
  for (let y = 0; y < height; y += 6) {
    const planes = new Map();
    for (let bit = 0; bit < 6 && y + bit < height; bit++) {
      for (let x = 0; x < width; x++) {
        const color = colors[(y + bit) * width + x];
        let plane = planes.get(color);
        if (!plane) {
          plane = new Uint8Array(width);
          planes.set(color, plane);
        }
        plane[x] |= 1 << bit;
      }
    }
    let first = true;
    for (const [color, plane] of planes) {
      let end = width;
      while (end && !plane[end - 1]) end--;
      if (!first) result.push("$");
      result.push(`#${color}${runs(plane, end)}`);
      first = false;
    }
    if (y + 6 < height) result.push("-");
  }
  result.push(`${ESC}\\`);
  return result.join("");
}
