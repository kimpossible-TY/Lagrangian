// Adapt drawing paint, never geometry, raster pixels, or semantic mathematics.
const lightPaper = [252, 250, 246];

export function parseColor(value) {
  if (/^#[\da-f]{6}$/i.test(value))
    return [1, 3, 5].map((offset) => parseInt(value.slice(offset, offset + 2), 16));
  const match = value?.match(/^rgba?\(([^)]+)\)$/);
  const srgb = value?.match(/^color\(srgb\s+([^)]+)\)$/);
  const channels = (match?.[1] ?? srgb?.[1])
    ?.trim()
    .split(/[, /]+/)
    .map(Number);
  if (!channels || ![3, 4].includes(channels.length) || !channels.every(Number.isFinite))
    return null;
  return srgb ? channels.map((channel, i) => (i < 3 ? channel * 255 : channel)) : channels;
}

function luminance(rgb) {
  const linear = rgb.slice(0, 3).map((value) => {
    const channel = value / 255;
    return channel <= 0.04045 ? channel / 12.92 : ((channel + 0.055) / 1.055) ** 2.4;
  });
  return linear.reduce((sum, value, i) => sum + value * [0.2126, 0.7152, 0.0722][i], 0);
}

export function inkContrast(rgb, background = lightPaper) {
  const a = luminance(rgb),
    b = luminance(background);
  return (Math.max(a, b) + 0.05) / (Math.min(a, b) + 0.05);
}

const mix = (a, b, amount) => a.slice(0, 3).map((value, i) => value + (b[i] - value) * amount);
const composite = (rgb, background) => mix(background, rgb, rgb[3] ?? 1);
const css = (rgb) =>
  `rgb(${rgb.slice(0, 3).map(Math.round).join(" ")}${rgb[3] === undefined ? "" : ` / ${rgb[3]}`})`;
const neutralInk = (rgb) =>
  (Math.max(...rgb.slice(0, 3)) < 100 || Math.min(...rgb.slice(0, 3)) > 200) &&
  Math.max(...rgb.slice(0, 3)) - Math.min(...rgb.slice(0, 3)) < 20;

export function readableInk(rgb, background = lightPaper, minimum = 4.5) {
  if (inkContrast(composite(rgb, background), background) >= minimum) return rgb;
  const target =
    inkContrast([255, 255, 255], background) > inkContrast([0, 0, 0], background)
      ? [255, 255, 255]
      : [0, 0, 0];
  let low = 0,
    high = 1;
  for (let pass = 0; pass < 20; pass++) {
    const amount = (low + high) / 2;
    const candidate = [...mix(rgb, target, amount), rgb[3] ?? 1];
    if (inkContrast(composite(candidate, background), background) >= minimum) high = amount;
    else low = amount;
  }
  // Round toward the contrast endpoint rather than back below the threshold.
  const result = mix(rgb, target, high).map(target[0] ? Math.ceil : Math.floor);
  return rgb.length > 3 ? [...result, rgb[3]] : result;
}

export function drawingPaint(
  rgb,
  background,
  ink,
  { underlay = false, paper = false, minimum = 3 } = {},
) {
  if (
    paper &&
    rgb.slice(0, 3).every((value) => value >= 240) &&
    Math.max(...rgb.slice(0, 3)) - Math.min(...rgb.slice(0, 3)) < 12
  )
    return rgb.length > 3 ? [...background, rgb[3]] : background;
  if (!underlay) {
    if (neutralInk(rgb))
      return readableInk(
        rgb.length > 3 ? [...ink.slice(0, 3), rgb[3]] : ink.slice(0, 3),
        background,
        minimum,
      );
    return readableInk(rgb, background, minimum);
  }
  // A filled mannot underlay must keep the mathematical glyphs legible.
  if (inkContrast(ink, composite(rgb, background)) >= 4.5) return rgb;
  let low = 0,
    high = 1;
  for (let pass = 0; pass < 20; pass++) {
    const amount = (low + high) / 2;
    if (
      inkContrast(ink, composite([...mix(rgb, background, amount), rgb[3] ?? 1], background)) >= 4.5
    )
      high = amount;
    else low = amount;
  }
  const result = mix(rgb, background, high).map((value, i) =>
    background[i] > rgb[i] ? Math.ceil(value) : Math.floor(value),
  );
  return rgb.length > 3 ? [...result, rgb[3]] : result;
}

export function drawingBackground(node) {
  const layers = [];
  for (let parent = node; parent; parent = parent.parentElement) {
    const color = parseColor(getComputedStyle(parent).backgroundColor);
    if (!color || color[3] === 0) continue;
    layers.push(color);
    if ((color[3] ?? 1) === 1) break;
  }
  return layers.reverse().reduce((background, color) => composite(color, background), lightPaper);
}

function prepareCanvasSurface(canvas, background = drawingBackground(canvas.parentElement)) {
  canvas.style.setProperty("--drawing-surface", css(background));
}

function adaptTextColor(element) {
  if (element.closest("svg,mjx-assistive-mml,.flow-math-stage")) return;
  const original =
    element.dataset.readerSourceColor ??
    element.dataset.canvasSourceColor ??
    (element.style.color || element.getAttribute("mathcolor"));
  if (!original || /^(inherit|currentcolor|var\()/i.test(original)) return;
  element.dataset.readerSourceColor ??= parseColor(original)
    ? original
    : getComputedStyle(element).color;
  const source = parseColor(element.dataset.readerSourceColor);
  if (!source) return;
  const background = drawingBackground(element);
  const ink = parseColor(getComputedStyle(element).getPropertyValue("--ink").trim()) ?? [
    41, 40, 36,
  ];
  if (element.closest(".flow-canvas-label-body"))
    element.dataset.canvasSourceColor ??= element.dataset.readerSourceColor;
  element.style.color = css(drawingPaint(source, background, ink, { minimum: 4.5 }));
}

export class DrawingTheme {
  constructor(article) {
    this.article = article;
    this.sources = new WeakMap();
    this.content = new MutationObserver((changes) => {
      for (const change of changes) {
        const svg = change.target.closest?.("svg");
        if (svg) this.sources.delete(svg);
      }
      this.schedule();
    });
    this.content.observe(article, { childList: true, subtree: true });
    this.appearance = new MutationObserver(() => this.schedule());
    this.appearance.observe(document.documentElement, {
      attributes: true,
      attributeFilter: ["data-theme"],
    });
    this.schedule();
  }

  schedule() {
    if (this.frame) return;
    this.frame = requestAnimationFrame(() => {
      this.frame = null;
      this.refresh();
    });
  }

  refresh() {
    for (const canvas of this.article.querySelectorAll("[data-flow-canvas-model]"))
      prepareCanvasSurface(canvas);
    for (const element of this.article.querySelectorAll("[style],[mathcolor]"))
      if (element.style.color || element.hasAttribute("mathcolor")) adaptTextColor(element);
    for (const svg of this.article.querySelectorAll("svg")) {
      if (svg.parentElement.closest("svg") || svg.closest(".flow-math-stage,mjx-assistive-mml"))
        continue;
      this.paint(svg);
    }
  }

  paint(svg) {
    let source = this.sources.get(svg);
    if (!source) {
      const paints = [];
      for (const node of [svg, ...svg.querySelectorAll("[fill],[stroke],[style]")]) {
        // Mask/clip colors encode coverage, not visible paint.
        if (node.closest("mask,clipPath")) continue;
        for (const property of ["fill", "stroke"]) {
          const original =
            node.dataset[`readerSource${property}`] ??
            (node.style[property] || node.getAttribute(property));
          if (!original || /^(none|currentcolor|context-fill|context-stroke|url\()/i.test(original))
            continue;
          const color = node.dataset[`readerSource${property}`] ?? getComputedStyle(node)[property];
          const rgb = parseColor(color);
          if (!rgb) continue;
          // Keep originals through clones and repeat theme changes; authored
          // attributes remain intact, including SVG paths and arrow geometry.
          node.dataset[`readerSource${property}`] = color;
          paints.push({ node, property, rgb });
        }
      }
      if (!svg.hasAttribute("fill") && !svg.style.fill) svg.style.fill = "currentColor";
      source = { paints };
      this.sources.set(svg, source);
    }
    const background = drawingBackground(svg.parentElement);
    const term =
      svg.dataset.readerDecorationId &&
      [...svg.parentElement.querySelectorAll("[data-flow-decoration]")].find(
        (node) =>
          node.dataset.flowDecoration === svg.dataset.readerDecorationId &&
          !node.closest("mjx-assistive-mml,.flow-math-stage"),
      );
    const ink = parseColor(getComputedStyle(term || svg).color) ?? [41, 40, 36];
    const signature = JSON.stringify([background, ink]);
    if (signature === source.signature) return;
    for (const { node, property, rgb } of source.paints) {
      const value = drawingPaint(rgb, background, ink, {
        underlay: property === "fill" && svg.dataset.layer === "under",
        paper:
          property === "fill" &&
          !node.closest("symbol") &&
          !["use", "text", "tspan"].includes(node.localName),
        minimum:
          property === "fill" &&
          (node.closest("symbol") ||
            node.matches("use,text,tspan") ||
            node.querySelector("use,text"))
            ? 4.5
            : 3,
      });
      node.style[property] = css(value);
    }
    source.signature = signature;
  }
}
