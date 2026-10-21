import { paintedPathPoint } from "./annotations.js";
export { inkContrast, readableInk } from "../../features/appearance/drawing-theme.js";

const gap = 4;

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

// Sampled strokes are local obstacles. Query only cells touched by a candidate
// instead of scanning every segment for every alternative label position.
function strokeCollision(segments, cellSize) {
  const cells = new Map();
  const bounds = (box) => [
    Math.floor(box.left / cellSize),
    Math.floor(box.top / cellSize),
    Math.floor((box.left + box.width) / cellSize),
    Math.floor((box.top + box.height) / cellSize),
  ];
  for (const [a, b, clearance = 0] of segments) {
    const edge = {
      a,
      b,
      clearance,
      left: Math.min(a.x, b.x) - clearance,
      top: Math.min(a.y, b.y) - clearance,
      width: Math.abs(a.x - b.x) + 2 * clearance,
      height: Math.abs(a.y - b.y) + 2 * clearance,
    };
    const [left, top, right, bottom] = bounds(edge);
    for (let x = left; x <= right; x++)
      for (let y = top; y <= bottom; y++) {
        const key = `${x},${y}`;
        if (!cells.has(key)) cells.set(key, []);
        cells.get(key).push(edge);
      }
  }
  const cache = new Map();
  return (box) => {
    const key = `${box.left},${box.top},${box.width},${box.height}`;
    if (cache.has(key)) return cache.get(key);
    const [left, top, right, bottom] = bounds(box);
    const seen = new Set();
    for (let x = left; x <= right; x++)
      for (let y = top; y <= bottom; y++) {
        for (const edge of cells.get(`${x},${y}`) || []) {
          if (seen.has(edge)) continue;
          seen.add(edge);
          const { a, b, clearance } = edge;
          if (
            intersects(a, b, {
              left: box.left - clearance,
              top: box.top - clearance,
              width: box.width + 2 * clearance,
              height: box.height + 2 * clearance,
            })
          ) {
            cache.set(key, true);
            return true;
          }
        }
      }
    cache.set(key, false);
    return false;
  };
}

function labelBox(label, anchor) {
  return {
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
}

// Geometry remains in the authored coordinate system. Only its uniform scale
// changes. Text that cannot occupy its anchor safely has an always-visible
// numbered legend; a leader connects a displaced number to its original point.
export function composeCanvas(model, width, labels, fontSize, segments = []) {
  const scale = Math.max(1, width - 4) / Math.max(1, model.width);
  const pad = Math.ceil(1.5 * fontSize);
  const geometry = { left: 2, top: pad, width: model.width * scale, height: model.height * scale };
  const occupied = [];
  const placed = new Map();
  let height = geometry.height + 2 * pad;
  const point = (label) => ({
    x: geometry.left + (label.source.left + label.source.width / 2) * scale,
    y: geometry.top + (label.source.top + label.source.height / 2) * scale,
  });
  const hits = strokeCollision(segments, Math.max(24, 2 * fontSize));
  const valid = (box, strokes = true) =>
    box.left >= 0 &&
    box.left + box.width <= width &&
    box.top >= 0 &&
    box.top + box.height <= height &&
    !occupied.some((other) => overlaps(box, other)) &&
    (!strokes || !hits(box));
  const sorted = [...labels].sort((a, b) => a.width * a.height - b.width * b.height);
  // Preserve small coordinate symbols before larger nearby descriptions use
  // their limited anchor space. This is priority, never an eligibility cutoff.
  const compact = (label) => label.width <= 3 * fontSize && label.height <= 2 * fontSize;
  for (const group of [sorted.filter(compact), sorted.filter((label) => !compact(label))]) {
    for (const label of group) {
      const anchor = point(label);
      const box = labelBox(label, anchor);
      if (!label.nested && valid(box)) {
        occupied.push(box);
        placed.set(label.id, { ...box, id: label.id, mode: "inline", anchor });
      }
    }
    // Keep safe authored placements, then allocate nearby space to the labels
    // with the fewest available positions. Width alone is not a reason to number
    // a short formula or a two-line name. All candidates use measured text boxes.
    // Keep the largest fitting size for each compact label; legends and larger
    // descriptions retain the reading size. Never trade readability for a fit.
    const minimum = Math.min(1, Math.max(0.8, 11 / fontSize));
    const scales = group.every(compact)
      ? [...new Set([1, 0.95, 0.9, 0.85, minimum].filter((value) => value >= minimum))]
      : [1];
    const pending = group
      .filter(
        (label) =>
          !placed.has(label.id) && !label.nested && label.width <= width && label.height <= height,
      )
      .map((label) => {
        const anchor = point(label);
        const radius = Math.min(
          width / 4,
          Math.max(2 * fontSize, Math.min(4 * fontSize, Math.max(label.width, label.height) / 2)),
        );
        return { label, anchor, radius };
      });
    const leader = (box, anchor) => [
      anchor,
      {
        x: Math.max(box.left, Math.min(box.left + box.width, anchor.x)),
        y: Math.max(box.top, Math.min(box.top + box.height, anchor.y)),
      },
    ];
    const connected = (box, anchor) => {
      const [a, b] = leader(box, anchor);
      return (
        // A moved neighbor must leave other source anchors reachable.
        labels.every((other) => {
          const source = point(other);
          return (
            (source.x === anchor.x && source.y === anchor.y) ||
            source.x < box.left ||
            source.x > box.left + box.width ||
            source.y < box.top ||
            source.y > box.top + box.height
          );
        }) &&
        occupied.every((other) => !intersects(a, b, other)) &&
        [...placed.values()].every((other) => {
          const [start, end] = leader(other, other.anchor);
          return !intersects(start, end, box);
        })
      );
    };
    while (pending.length) {
      const choices = pending
        .map((entry) => {
          const { label, radius, anchor } = entry;
          for (const labelScale of scales) {
            const origin = labelBox(
              {
                ...label,
                width: label.width * labelScale,
                height: label.height * labelScale,
                baseline: label.baseline * labelScale,
              },
              anchor,
            );
            const candidates = [
              {
                ...origin,
                left: Math.max(0, Math.min(width - origin.width, origin.left)),
                top: Math.max(0, Math.min(height - origin.height, origin.top)),
              },
            ];
            for (let distance = fontSize / 4; distance <= radius + 0.01; distance += fontSize / 4) {
              for (let angle = 0; angle < 32; angle++) {
                const theta = (angle * Math.PI) / 16;
                candidates.push({
                  ...origin,
                  left: origin.left + Math.cos(theta) * distance,
                  top: origin.top + Math.sin(theta) * distance,
                });
              }
            }
            // Include the exact clearance around occupied boxes, rather than hoping
            // a coarse angular sample happens to land in a narrow gap.
            for (const other of occupied) {
              for (const left of [
                origin.left,
                other.left - origin.width - gap,
                other.left + other.width + gap,
              ]) {
                for (const top of [
                  origin.top,
                  other.top - origin.height - gap,
                  other.top + other.height + gap,
                ])
                  candidates.push({ ...origin, left, top });
              }
            }
            const distance = (box) => Math.hypot(box.left - origin.left, box.top - origin.top);
            const unique = new Map(
              candidates.map((box) => {
                const bounded = {
                  ...box,
                  left: Math.max(0, Math.min(width - box.width, box.left)),
                  top: Math.max(0, Math.min(height - box.height, box.top)),
                };
                return [`${bounded.left.toFixed(2)},${bounded.top.toFixed(2)}`, bounded];
              }),
            );
            const available = [...unique.values()]
              .filter(
                (box) => distance(box) <= radius + 0.01 && valid(box) && connected(box, anchor),
              )
              .sort((a, b) => distance(a) - distance(b));
            if (available.length) return { entry, available, labelScale };
          }
          return { entry, available: [] };
        })
        .filter(({ available }) => available.length);
      if (!choices.length) break;
      choices.sort((a, b) => a.available.length - b.available.length);
      const {
        entry,
        labelScale,
        available: [box],
      } = choices[0];
      occupied.push(box);
      placed.set(entry.label.id, {
        ...box,
        id: entry.label.id,
        mode: "inline",
        labelScale,
        anchor: entry.anchor,
      });
      pending.splice(pending.indexOf(entry), 1);
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
    const style = getComputedStyle(path);
    if (path.closest("defs") || style.stroke === "none") continue;
    const matrix = path.getScreenCTM();
    if (!matrix) continue;
    const length = path.getTotalLength();
    const count = Math.min(
      4096,
      Math.max(1, Math.ceil((length * geometry.width) / svg.viewBox.baseVal.width)),
    );
    let previous;
    for (let i = 0; i <= count; i++) {
      const sample = paintedPathPoint(path, (length * i) / count, length, style.strokeLinecap);
      if (!sample) continue;
      const transformed = sample.matrixTransform(matrix);
      const current = { x: transformed.x - rect.left, y: transformed.y - rect.top };
      if (previous)
        segments.push([previous, current, Math.max(1, parseFloat(style.strokeWidth) / 2 + 0.5)]);
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
          delete label.node.dataset.labelScale;
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
      // DOM rectangles include the previous presentation transform. Recover the
      // natural layout dimensions, quantized to CSS layout precision, so retries
      // never compound the reduction or oscillate on floating-point noise.
      const natural = (value) =>
        Math.round((value / Number(label.node.dataset.labelScale || 1)) * 64) / 64;
      const number = label.number.getBoundingClientRect();
      if (number.width > 0 && number.height > 0) {
        label.markerWidth = number.width;
        label.markerHeight = number.height;
      }
      return {
        ...label,
        source: this.model.labels[i],
        width: natural(body.width),
        height: natural(body.height),
        baseline: label.baselineProbe
          ? natural(label.baselineProbe.getBoundingClientRect().top - body.top)
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
      // Retire placeholder CSS before sampling: it overrides the SVG's planned
      // top/width and would test collisions against a different coordinate plane.
      this.node.dataset.canvasLayout = "native-labels";
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
        label.node.dataset.labelScale = String(placement.labelScale || 1);
        label.node.dataset.labelWide = String(
          label.width + label.markerWidth + fontSize * 0.4 > width,
        );
        label.body.style.width = `${label.width}px`;
        if (placement.mode === "inline") {
          Object.assign(label.node.style, {
            left: `${placement.left}px`,
            top: `${placement.top}px`,
            width: `${label.width}px`,
            transformOrigin: "top left",
            transform: `scale(${placement.labelScale || 1})`,
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
        }
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
