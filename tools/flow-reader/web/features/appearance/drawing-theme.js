import { parseColor } from "./color.js";
export { parseColor } from "./color.js";

// Adapt drawing paint, never geometry, raster pixels, or semantic mathematics.
const lightPaper = [252, 250, 246];

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
  if (paper && !underlay && inkContrast(rgb, lightPaper) < minimum) {
    // Pale filled areas encode shading, rather than foreground ink. Recover
    // their pigment and coverage over white, then apply that wash to the actual
    // surface. Requiring foreground contrast here turns CeTZ cell tints black.
    const coverage = 1 - Math.min(...rgb.slice(0, 3)) / 255;
    const pigment = rgb.slice(0, 3).map((value) => 255 - (255 - value) / coverage);
    const color = neutralInk(pigment) ? ink : readableInk(pigment, background, minimum);
    const result = mix(background, color, coverage);
    return rgb.length > 3 ? [...result, rgb[3]] : result;
  }
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
  restorePaint(element, "color");
  delete element.dataset.readerSourceColor;
  delete element.dataset.canvasSourceColor;
  const original = element.style.color || element.getAttribute("mathcolor");
  if (!original || /^(inherit|currentcolor|var\()/i.test(original)) return;
  element.dataset.readerSourceColor = parseColor(original)
    ? original
    : getComputedStyle(element).color;
  const source = parseColor(element.dataset.readerSourceColor);
  if (!source) return;
  const background = drawingBackground(element);
  const ink = parseColor(getComputedStyle(element).getPropertyValue("--ink").trim()) ?? [
    41, 40, 36,
  ];
  if (element.closest(".flow-canvas-label-body"))
    element.dataset.canvasSourceColor = element.dataset.readerSourceColor;
  presentDrawingPaint(element, "color", drawingPaint(source, background, ink, { minimum: 4.5 }));
}

const paintProperties = ["fill", "stroke"];
const paintKey = (property) => property[0].toUpperCase() + property.slice(1);

function restorePaint(node, property) {
  const key = paintKey(property);
  const presentation = node.dataset[`readerPaint${key}`];
  if (presentation === undefined) return;
  // An edited inline value/priority belongs to the author. Otherwise remove
  // only our override before resolving current attributes and inheritance.
  if (
    node.style.getPropertyValue(property) === presentation &&
    node.style.getPropertyPriority(property) === node.dataset[`readerPaintPriority${key}`]
  ) {
    const original = node.dataset[`readerInline${key}`];
    if (original) node.style.setProperty(property, original, node.dataset[`readerPriority${key}`]);
    else node.style.removeProperty(property);
  }
  delete node.dataset[`readerPaint${key}`];
  delete node.dataset[`readerPaintPriority${key}`];
  delete node.dataset[`readerInline${key}`];
  delete node.dataset[`readerPriority${key}`];
  delete node.dataset[`readerSource${property}`];
}

function restoreDrawingPaint(svg) {
  for (const node of [svg, ...svg.querySelectorAll("*")])
    for (const property of [...paintProperties, "color"]) restorePaint(node, property);
}

function presentDrawingPaint(node, property, value) {
  const key = paintKey(property);
  if (node.dataset[`readerPaint${key}`] === undefined) {
    node.dataset[`readerInline${key}`] = node.style.getPropertyValue(property);
    node.dataset[`readerPriority${key}`] = node.style.getPropertyPriority(property);
  }
  node.style.setProperty(property, css(value), node.dataset[`readerPriority${key}`]);
  // Store CSSOM's serialization so clones can recognize our own presentation.
  node.dataset[`readerPaint${key}`] = node.style.getPropertyValue(property);
  node.dataset[`readerPaintPriority${key}`] = node.style.getPropertyPriority(property);
}

function definitionPaint(node, definition, property) {
  for (let parent = node; parent; parent = parent.parentElement) {
    const value = parent.style[property] || parent.getAttribute(property);
    if (value && !/^(inherit|unset)$/i.test(value))
      return !/^(currentcolor|context-fill|context-stroke|var\()/i.test(value);
    if (parent === definition) break;
  }
  return false;
}

export class DrawingTheme {
  constructor(article) {
    this.article = article;
    this.sources = new WeakMap();
    this.content = new MutationObserver((changes) => {
      this.invalidate(changes);
      this.schedule();
    });
    this.observeContent();
    this.appearance = new MutationObserver(() => {
      // Authored currentColor/variables can inherit a different palette after
      // surrounding HTML text has adapted to the new appearance.
      for (const svg of article.querySelectorAll("svg")) this.sources.delete(svg);
      this.schedule();
    });
    this.appearance.observe(document.documentElement, {
      attributes: true,
      attributeFilter: ["data-theme"],
    });
    this.schedule();
  }

  observeContent() {
    this.content.observe(this.article, {
      childList: true,
      subtree: true,
      attributes: true,
      attributeFilter: ["fill", "stroke", "color", "style", "class", "mathcolor"],
    });
  }

  invalidate(changes) {
    for (const change of changes) {
      let svg = change.target.closest?.("svg");
      if (svg) {
        for (
          let parent = svg.parentElement?.closest("svg");
          parent;
          parent = svg.parentElement?.closest("svg")
        )
          svg = parent;
        this.sources.delete(svg);
      } else if (change.type === "attributes") {
        // An enclosing color/class can change the SVG's inherited source paint.
        for (const child of change.target.querySelectorAll("svg")) this.sources.delete(child);
      }
    }
  }

  schedule() {
    if (this.frame) return;
    this.frame = requestAnimationFrame(() => {
      this.frame = null;
      this.refresh();
    });
  }

  refresh() {
    this.invalidate(this.content.takeRecords());
    // Presentation writes must not look like new authored paint. JavaScript
    // runs this refresh synchronously; queued authored mutations were read above.
    this.content.disconnect();
    try {
      for (const canvas of this.article.querySelectorAll("[data-flow-canvas-model]"))
        prepareCanvasSurface(canvas);
      for (const element of this.article.querySelectorAll("[style],[mathcolor]"))
        if (element.style.color || element.hasAttribute("mathcolor")) adaptTextColor(element);
      for (const svg of this.article.querySelectorAll("svg")) {
        if (svg.parentElement.closest("svg") || svg.closest(".flow-math-stage,mjx-assistive-mml"))
          continue;
        this.paint(svg);
      }
    } finally {
      this.observeContent();
    }
  }

  paint(svg) {
    let source = this.sources.get(svg);
    if (!source) {
      restoreDrawingPaint(svg);
      const paints = [];
      for (const node of svg.querySelectorAll(
        "path,rect,circle,ellipse,line,polyline,polygon,text,tspan,textPath,use",
      )) {
        // Mask/clip colors encode coverage, not visible paint.
        if (node.closest("mask,clipPath,pattern")) continue;
        const symbol = node.closest("symbol");
        const definition = node.closest("symbol,defs");
        const style = getComputedStyle(node);
        for (const property of paintProperties) {
          // An unpainted glyph path must inherit from each <use> instance.
          if (definition && !definitionPaint(node, definition, property)) continue;
          const color = style[property];
          const rgb = parseColor(color);
          if (!rgb) continue;
          node.dataset[`readerSource${property}`] = color;
          paints.push({
            node,
            property,
            rgb,
            glyph: Boolean(symbol || node.matches("use,text,tspan,textPath")),
          });
        }
        if (node.localName === "use") {
          // Symbolic definition paint resolves currentColor in each instance,
          // not in the hidden definition's unrelated color context.
          const rgb = parseColor(style.color);
          if (rgb) paints.push({ node, property: "color", rgb, glyph: true });
        }
      }
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
    for (const { node, property, rgb, glyph } of source.paints) {
      const value = drawingPaint(rgb, background, ink, {
        underlay: property === "fill" && svg.dataset.layer === "under",
        paper: property === "fill" && !glyph,
        minimum: property !== "stroke" && glyph ? 4.5 : 3,
      });
      presentDrawingPaint(node, property, value);
    }
    source.signature = signature;
  }
}
