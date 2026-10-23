import { paintedPathPoint } from "./annotations.js";
export { inkContrast, readableInk } from "../../features/appearance/drawing-theme.js";

import { composeCanvas, canvasGeometry } from "./canvas-layout.js";
export { composeCanvas, overlaps } from "./canvas-layout.js";

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
  constructor(node, preserve, selectionActive, compute = null, changed = () => {}) {
    Object.assign(this, { node, preserve, selectionActive, compute, changed });
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
      this.completed = null;
      this.error = null;
    }
  }

  layout(width, fontSize) {
    if (this.disposed || this.selectionActive()) return false;
    this.prepare(width, fontSize);
    if (this.error) throw this.error;
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
    const signature = JSON.stringify([
      this.key,
      measured.map((label) => [
        label.width,
        label.height,
        label.baseline,
        label.markerWidth,
        label.markerHeight,
      ]),
    ]);
    if (this.signature === signature) return true;
    let ready = false;
    this.preserve(() => {
      const geometry = canvasGeometry(this.model, width, fontSize);
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
      let plan;
      if (this.compute) {
        if (this.completed?.signature === signature) plan = this.completed.plan;
        else {
          if (this.pending) return;
          // Only measured data crosses the Worker boundary, never DOM nodes.
          const labels = measured.map(
            ({ id, source, width, height, baseline, markerWidth, markerHeight, nested }) => ({
              id,
              source,
              width,
              height,
              baseline,
              markerWidth,
              markerHeight,
              nested,
            }),
          );
          const key = this.key;
          this.pending = this.compute([
            { width: this.model.width, height: this.model.height },
            width,
            labels,
            fontSize,
            segmentsOf(this.svg, this.stage, geometry),
          ])
            .then((result) => {
              if (!this.disposed && this.key === key) this.completed = { signature, plan: result };
            })
            .catch((error) => {
              if (!this.disposed && this.key === key && error.name !== "AbortError")
                this.error = error;
            })
            .finally(() => {
              this.pending = null;
              if (!this.disposed && this.node.isConnected) this.changed();
            });
          return;
        }
      } else {
        plan = composeCanvas(
          this.model,
          width,
          measured,
          fontSize,
          segmentsOf(this.svg, this.stage, geometry),
        );
      }
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
      ready = true;
    });
    return ready;
  }

  dispose() {
    this.disposed = true;
    this.completed = null;
  }
}
