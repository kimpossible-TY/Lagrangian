const clamp = (value, maximum = 1) => Math.max(0, Math.min(maximum, value));

function component(value, percentScale) {
  if (value === "none") return 0;
  const match = value?.match(/^([+-]?(?:\d*\.\d+|\d+)(?:e[+-]?\d+)?)(%)?$/i);
  if (!match) return NaN;
  return match[2] ? (Number(match[1]) / 100) * percentScale : Number(match[1]);
}

function hue(value) {
  if (value === "none") return 0;
  const match = value?.match(/^([+-]?(?:\d*\.\d+|\d+)(?:e[+-]?\d+)?)(deg|grad|rad|turn)?$/i);
  if (!match) return NaN;
  const degrees = Number(match[1]) * ({ grad: 0.9, rad: 180 / Math.PI, turn: 360 }[match[2]] ?? 1);
  return ((degrees % 360) * Math.PI) / 180;
}

function functionChannels(body, legacy) {
  if (body.includes(",")) {
    if (!legacy || body.includes("/")) return null;
    const values = body.split(",").map((value) => value.trim());
    return [3, 4].includes(values.length) ? values : null;
  }
  const parts = body.split("/");
  if (parts.length > 2) return null;
  const channels = parts[0].trim().split(/\s+/);
  if (channels.length !== 3) return null;
  return parts.length === 2 ? [...channels, parts[1].trim()] : channels;
}

const multiply = (matrix, vector) =>
  matrix.map((row) => row.reduce((sum, value, i) => sum + value * vector[i], 0));

function oklabToRGB(channels) {
  const [lightness] = channels;
  if (lightness <= 0 || lightness >= 1) return Array(3).fill(clamp(lightness) * 255);
  // CSS Color 4 OKLab -> LMS -> linear sRGB, combining its XYZ matrices.
  // https://www.w3.org/TR/css-color-4/#color-conversion-code
  const lms = multiply(
    [
      [1, 0.3963377773761749, 0.2158037573099136],
      [1, -0.1055613458156586, -0.0638541728258133],
      [1, -0.0894841775298119, -1.2914855480194092],
    ],
    channels,
  ).map((value) => value ** 3);
  return multiply(
    [
      [4.076741636075958, -3.3077115392580616, 0.2309699031821043],
      [-1.2684379732850317, 2.6097573492876887, -0.34131937600265727],
      [-0.004196076138675564, -0.7034186179359363, 1.7076146940746117],
    ],
    lms,
  ).map((value) => 255 * (value <= 0.0031308 ? 12.92 * value : 1.055 * value ** (1 / 2.4) - 0.055));
}

// Resolve the numeric formats produced by computed styles and Typst's SVG
// exporter. Symbolic paints (currentColor, resource URLs, variables) stay with
// the drawing adapter, which can resolve their inheritance in the actual DOM.
export function parseColor(value) {
  if (typeof value !== "string") return null;
  const color = value.trim().toLowerCase();
  if (color === "transparent") return [0, 0, 0, 0];
  if (/^#(?:[\da-f]{3,4}|[\da-f]{6}|[\da-f]{8})$/.test(color)) {
    const hex = color.length < 6 ? color.slice(1).replace(/./g, "$&$&") : color.slice(1);
    return hex.match(/../g).map((channel, i) => parseInt(channel, 16) / (i === 3 ? 255 : 1));
  }
  const match = color.match(/^(rgb|rgba|oklab|oklch|color)\(([^()]*)\)$/);
  if (!match) return null;
  const format = match[1];
  let body = match[2];
  if (format === "color") {
    const srgb = body.match(/^srgb\s+(.+)$/);
    if (!srgb) return null;
    body = srgb[1];
  }
  const values = functionChannels(body, format === "rgb" || format === "rgba");
  if (!values) return null;
  const alpha = values.length === 4 ? component(values[3], 1) : undefined;
  let rgb;
  if (format === "oklab" || format === "oklch") {
    const lightness = component(values[0], 1);
    const second = component(values[1], 0.4);
    const third = format === "oklch" ? hue(values[2]) : component(values[2], 0.4);
    const lab =
      format === "oklch"
        ? [lightness, Math.max(0, second) * Math.cos(third), Math.max(0, second) * Math.sin(third)]
        : [lightness, second, third];
    if (!lab.every(Number.isFinite)) return null;
    rgb = oklabToRGB(lab);
  } else {
    rgb = values
      .slice(0, 3)
      .map((channel) =>
        format === "color" ? component(channel, 1) * 255 : component(channel, 255),
      );
  }
  if (!rgb.every(Number.isFinite) || (alpha !== undefined && !Number.isFinite(alpha))) return null;
  const result = rgb.map((channel) => clamp(channel, 255));
  return alpha === undefined ? result : [...result, clamp(alpha)];
}
