const gap = 4;
const paper = [252, 250, 246];

function luminance(rgb) {
  const linear = rgb.map((value) => {
    const channel = value / 255;
    return channel <= 0.04045 ? channel / 12.92 : ((channel + 0.055) / 1.055) ** 2.4;
  });
  return linear.reduce((sum, value, i) => sum + value * [0.2126, 0.7152, 0.0722][i], 0);
}

export function inkContrast(rgb) {
  const background = luminance(paper),
    foreground = luminance(rgb);
  return (Math.max(background, foreground) + 0.05) / (Math.min(background, foreground) + 0.05);
}

export function readableInk(rgb) {
  if (inkContrast(rgb) >= 4.5) return rgb;
  let low = 0,
    high = 1;
  for (let pass = 0; pass < 20; pass++) {
    const factor = (low + high) / 2;
    if (inkContrast(rgb.map((value) => value * factor)) >= 4.5) low = factor;
    else high = factor;
  }
  return rgb.map((value) => Math.floor(value * low));
}

export function overlaps(a, b, padding = gap) {
  return (
    a.left < b.left + b.width + padding &&
    b.left < a.left + a.width + padding &&
    a.top < b.top + b.height + padding &&
    b.top < a.top + a.height + padding
  );
}

function intersects(a, b, box) {
  let low = 0;
  let high = 1;
  for (const [p, q] of [
    [a.x - b.x, a.x - box.left],
    [b.x - a.x, box.left + box.width - a.x],
    [a.y - b.y, a.y - box.top],
    [b.y - a.y, box.top + box.height - a.y],
  ]) {
    if (p === 0 && q < 0) return false;
    if (p < 0) low = Math.max(low, q / p);
    if (p > 0) high = Math.min(high, q / p);
  }
  return low <= high;
}

// Geometry remains in the authored coordinate system. Only its uniform scale
// changes. Text that cannot occupy its anchor safely has an always-visible
// numbered legend; a leader connects a displaced number to its original point.
export function composeCanvas(model, width, labels, fontSize, segments = []) {
  const scale = Math.max(1, width - 4) / Math.max(1, model.width);
  const pad = Math.ceil(fontSize);
  const geometry = { left: 2, top: pad, width: model.width * scale, height: model.height * scale };
  const occupied = [];
  const placed = new Map();
  let height = geometry.height + 2 * pad;
  const point = (label) => ({
    x: geometry.left + (label.source.left + label.source.width / 2) * scale,
    y: geometry.top + (label.source.top + label.source.height / 2) * scale,
  });
  const hits = (box) => segments.some(([a, b]) => intersects(a, b, box));
  const valid = (box, strokes = true) =>
    box.left >= 0 &&
    box.left + box.width <= width &&
    box.top >= 0 &&
    box.top + box.height <= height &&
    !occupied.some((other) => overlaps(box, other)) &&
    (!strokes || !hits(box));
  const sorted = [...labels].sort((a, b) => a.width * a.height - b.width * b.height);
  for (const label of sorted) {
    const anchor = point(label);
    const box = {
      left:
        anchor.x -
        (label.source.align === "end"
          ? label.width
          : label.source.align === "start"
            ? 0
            : label.width / 2),
      top:
        anchor.y -
        (label.source.baseline && Number.isFinite(label.baseline)
          ? label.baseline
          : label.height / 2),
      width: label.width,
      height: label.height,
    };
    if (!label.nested && label.height <= 3 * fontSize && valid(box)) {
      occupied.push(box);
      placed.set(label.id, { ...box, id: label.id, mode: "inline", anchor });
    }
  }
  for (const label of labels) {
    if (placed.has(label.id)) continue;
    const anchor = point(label);
    const w = Math.min(width, label.markerWidth);
    const h = label.markerHeight;
    const origin = {
      left: Math.max(0, Math.min(width - w, anchor.x - w / 2)),
      top: Math.max(0, anchor.y - h / 2),
      width: w,
      height: h,
    };
    const candidates = [origin];
    for (let ring = 1; ring <= 8; ring++) {
      for (const [x, y] of [
        [0, -1],
        [0, 1],
        [-1, 0],
        [1, 0],
        [-1, -1],
        [1, -1],
        [-1, 1],
        [1, 1],
      ])
        candidates.push({
          ...origin,
          left: origin.left + (x * ring * (w + gap)) / 2,
          top: origin.top + (y * ring * (h + gap)) / 2,
        });
    }
    let box = candidates.find((candidate) => valid(candidate));
    if (!box) {
      // A new row is preferable to a smaller badge, clipping, or hidden text.
      box = { left: 0, top: height + gap, width: w, height: h };
      height = box.top + h;
    }
    occupied.push(box);
    placed.set(label.id, { ...box, id: label.id, mode: "legend", anchor });
  }
  return { width, height, geometry, labels: labels.map((label) => placed.get(label.id)) };
}

function segmentsOf(svg, stage, geometry) {
  const rect = stage.getBoundingClientRect();
  const segments = [];
  for (const path of svg.querySelectorAll("path,rect,circle,ellipse,line,polyline,polygon")) {
    if (path.closest("defs") || getComputedStyle(path).stroke === "none") continue;
    const matrix = path.getScreenCTM();
    if (!matrix) continue;
    const length = path.getTotalLength();
    const count = Math.min(
      512,
      Math.max(1, Math.ceil((length * geometry.width) / svg.viewBox.baseVal.width / 3)),
    );
    let previous;
    for (let i = 0; i <= count; i++) {
      const transformed = path.getPointAtLength((length * i) / count).matrixTransform(matrix);
      const current = { x: transformed.x - rect.left, y: transformed.y - rect.top };
      if (previous) segments.push([previous, current]);
      previous = current;
    }
  }
  return segments;
}

export class NativeCanvasLabels {
  constructor(node, preserve, selectionActive) {
    Object.assign(this, { node, preserve, selectionActive });
    this.model = JSON.parse(node.dataset.flowCanvasModel);
    this.stage = node.querySelector(":scope > .flow-canvas-stage");
    this.svg = this.stage.querySelector(":scope > svg");
    this.labels = [...node.querySelectorAll("[data-flow-canvas-label]")]
      .filter((label) => label.closest("[data-flow-canvas]") === node)
      .map((label) => ({
        node: label,
        id: label.dataset.flowCanvasLabel,
        body: label.querySelector(":scope > .flow-canvas-label-body"),
        number: label.querySelector(":scope > .flow-canvas-label-number"),
      }));
    if (this.model.version !== 1 || !this.svg || this.labels.length !== this.model.labels.length)
      throw new Error("그림의 라벨 정보를 읽지 못했습니다.");
    for (const [i, label] of this.labels.entries()) {
      if (!this.model.labels[i].baseline) continue;
      const probe = document.createElement("span");
      probe.setAttribute("aria-hidden", "true");
      probe.style.cssText =
        "display:inline-block;width:0;height:0;padding:0;margin:0;vertical-align:baseline";
      label.body.prepend(probe);
      label.baselineProbe = probe;
    }
    for (const raster of this.svg.querySelectorAll("[data-flow-raster-layer] > svg")) {
      // The original pixel data fills the unchanged source viewBox. Its nested
      // Typst frame's em sizes must not scale again with the reading font.
      raster.style.width = "100%";
      raster.style.height = "100%";
    }
    this.overlay = document.createElementNS("http://www.w3.org/2000/svg", "svg");
    this.overlay.classList.add("flow-canvas-leaders");
    this.overlay.setAttribute("aria-hidden", "true");
    this.overlay.style.width = "0px";
    this.overlay.style.height = "0px";
    this.markers = document.createElement("div");
    this.markers.className = "flow-canvas-markers";
    this.markers.setAttribute("aria-hidden", "true");
    this.stage.append(this.overlay, this.markers);
    const calibration = this.model.width / this.svg.viewBox.baseVal.width;
    for (const path of this.svg.querySelectorAll(
      "path,rect,circle,ellipse,line,polyline,polygon",
    )) {
      if (path.closest("defs")) continue;
      const style = getComputedStyle(path);
      if (style.stroke === "none") continue;
      const value = parseFloat(style.strokeWidth) * calibration;
      if (!Number.isFinite(value)) continue;
      path.dataset.canvasSourceStroke = value;
      path.style.strokeWidth = `${value}px`;
      path.setAttribute("vector-effect", "non-scaling-stroke");
    }
  }

  floor(fontSize) {
    for (const label of this.labels) {
      for (const element of label.body.querySelectorAll("*")) {
        if (
          element.namespaceURI !== "http://www.w3.org/1999/xhtml" ||
          element.closest("math,svg,mjx-assistive-mml")
        )
          continue;
        if (element.closest("[data-flow-canvas]") !== this.node) continue;
        const style = getComputedStyle(element);
        if (!element.closest(".flow-math-view") && parseFloat(style.fontSize) < fontSize - 0.1)
          element.style.fontSize = "1em";
        const match = style.color.match(/^rgba?\(([^)]+)\)$/);
        if (match) {
          const channels = match[1].split(/[, /]+/).map(Number);
          const alpha = channels[3] ?? 1;
          const rgb = channels
            .slice(0, 3)
            .map((value, i) => value * alpha + paper[i] * (1 - alpha));
          const ink = readableInk(rgb);
          if (ink.some((value, i) => value !== rgb[i])) {
            element.dataset.canvasSourceColor ??= style.color;
            element.style.color = `rgb(${ink.join(",")})`;
          }
        }
      }
    }
  }

  prepare(width, fontSize) {
    if (this.selectionActive()) return;
    const key = JSON.stringify([width, fontSize]);
    if (this.key !== key) {
      this.preserve(() => {
        this.floor(fontSize);
        for (const label of this.labels) {
          label.node.dataset.labelMode = "flow";
          label.node.style.cssText = "";
          label.body.style.width = "";
        }
        this.markers.replaceChildren();
        this.overlay.replaceChildren();
        this.overlay.style.width = "0px";
        this.overlay.style.height = "0px";
        this.node.dataset.canvasLayout = "pending";
      });
      this.key = key;
      this.signature = null;
    }
  }

  layout(width, fontSize) {
    if (this.selectionActive()) return false;
    this.prepare(width, fontSize);
    // Source labels use the common mathematical renderer. Wait for its actual
    // measured boxes instead of introducing a second formula renderer here.
    if (
      this.labels.some(({ body }) =>
        [...body.querySelectorAll(".flow-math-view")].some(
          (view) =>
            view.closest("[data-flow-canvas]") === this.node &&
            !["ready", "overflow"].includes(view.dataset.mathState),
        ),
      )
    )
      return false;
    const paintNodes = [...this.node.querySelectorAll(".flow-math-view")].map(
      (view) => view.firstElementChild,
    );
    if (
      !this.paintNodes ||
      paintNodes.some((node, i) => node !== this.paintNodes[i]) ||
      paintNodes.length !== this.paintNodes.length
    ) {
      this.floor(fontSize);
      this.paintNodes = paintNodes;
    }
    const measured = this.labels.map((label, i) => {
      const body = label.body.getBoundingClientRect();
      const number = label.number.getBoundingClientRect();
      if (number.width > 0 && number.height > 0) {
        label.markerWidth = number.width;
        label.markerHeight = number.height;
      }
      return {
        ...label,
        source: this.model.labels[i],
        width: body.width,
        height: body.height,
        baseline: label.baselineProbe
          ? label.baselineProbe.getBoundingClientRect().top - body.top
          : undefined,
        markerWidth: label.markerWidth || Math.max(1.5 * fontSize, String(i + 1).length * fontSize),
        markerHeight: label.markerHeight || 1.6 * fontSize,
        nested: Boolean(label.body.querySelector("[data-flow-canvas]")),
      };
    });
    const signature = JSON.stringify(measured.map((label) => [label.width, label.height]));
    if (this.signature === signature) return true;
    this.preserve(() => {
      const preliminary = composeCanvas(this.model, width, measured, fontSize);
      const geometry = preliminary.geometry;
      Object.assign(this.svg.style, {
        position: "absolute",
        left: `${geometry.left}px`,
        top: `${geometry.top}px`,
        width: `${geometry.width}px`,
        height: `${geometry.height}px`,
        maxWidth: "none",
        margin: "0",
        overflow: "visible",
      });
      const plan = composeCanvas(
        this.model,
        width,
        measured,
        fontSize,
        segmentsOf(this.svg, this.stage, geometry),
      );
      this.stage.style.height = `${plan.height}px`;
      this.overlay.setAttribute("viewBox", `0 0 ${width} ${plan.height}`);
      this.overlay.style.width = `${width}px`;
      this.overlay.style.height = `${plan.height}px`;
      this.overlay.replaceChildren();
      this.markers.replaceChildren();
      for (const placement of plan.labels) {
        const label = measured.find((item) => item.id === placement.id);
        label.node.dataset.labelMode = placement.mode;
        label.node.dataset.labelWide = String(
          label.width + label.markerWidth + fontSize * 0.4 > width,
        );
        label.body.style.width = `${label.width}px`;
        if (placement.mode === "inline") {
          Object.assign(label.node.style, {
            left: `${placement.left}px`,
            top: `${placement.top}px`,
            width: `${placement.width}px`,
          });
        } else {
          label.node.style.cssText = "";
          const marker = label.number.cloneNode(true);
          Object.assign(marker.style, {
            position: "absolute",
            left: `${placement.left}px`,
            top: `${placement.top}px`,
            width: `${placement.width}px`,
            height: `${placement.height}px`,
          });
          this.markers.append(marker);
          const end = {
            x: Math.max(
              placement.left,
              Math.min(placement.left + placement.width, placement.anchor.x),
            ),
            y: Math.max(
              placement.top,
              Math.min(placement.top + placement.height, placement.anchor.y),
            ),
          };
          if (Math.hypot(end.x - placement.anchor.x, end.y - placement.anchor.y) > 2) {
            const line = document.createElementNS(this.overlay.namespaceURI, "path");
            line.setAttribute(
              "d",
              `M ${placement.anchor.x} ${placement.anchor.y} L ${end.x} ${end.y}`,
            );
            this.overlay.append(line);
            const dot = document.createElementNS(this.overlay.namespaceURI, "circle");
            dot.setAttribute("cx", placement.anchor.x);
            dot.setAttribute("cy", placement.anchor.y);
            dot.setAttribute("r", "2");
            this.overlay.append(dot);
          }
        }
      }
      this.node.dataset.canvasLayout = "native-labels";
      this.node.dataset.canvasPlaceholder = "false";
      this.node.dataset.canvasWidth = width;
      this.node.dataset.canvasFont = fontSize;
      this.node.dataset.canvasLegendCount = plan.labels.filter(
        (item) => item.mode === "legend",
      ).length;
      this.signature = signature;
      this.plan = plan;
    });
    return true;
  }
}
