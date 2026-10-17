// Relationships use the original equation nodes in the continuous body.
// Original CeTZ programs are evaluated against the actual marked term geometry.
import { visualFragments } from "./math-identity.js";
import { mathInkNodes } from "./math-layout.js";
import { routeConnections } from "./connector-routing.js";

export function paintedPathPoint(path, distance, length, linecap = "butt") {
  if (length > 0) {
    // Typst may begin with an isolated `M 0 0` before the real subpath. SVG's
    // zero-distance sample can return that unpainted origin. A positive offset
    // reaches the actual stroke, including its cap to subpixel precision.
    return path.getPointAtLength(Math.max(Math.min(0.001, length / 2), distance));
  }
  if (!["round", "square"].includes(linecap)) return null;
  const box = path.getBBox();
  const point = path.ownerSVGElement.createSVGPoint();
  point.x = box.x;
  point.y = box.y;
  return point;
}

function spanFor(records) {
  const roots = [
    ...new Set(
      records.flatMap((record) =>
        record.nodes.map(
          (node) =>
            node.closest(".flow-equation") ?? node.closest("p") ?? node.closest("math") ?? node,
        ),
      ),
    ),
  ];
  let parent = roots[0].parentElement;
  while (!roots.every((node) => parent.contains(node))) parent = parent.parentElement;
  const children = [...parent.childNodes];
  const indices = roots.map((node) => {
    while (node.parentNode !== parent) node = node.parentNode;
    return children.indexOf(node);
  });
  const first = children[Math.min(...indices)];
  const last = children[Math.max(...indices)];
  const range = document.createRange();
  range.setStartBefore(first);
  range.setEndAfter(last);
  return { records, first, last, range };
}

function overlaps(a, b) {
  return a.left < b.right && b.left < a.right && a.top < b.bottom && b.top < a.bottom;
}

function textInk(record) {
  const body = record.scene.body;
  const ink = [];
  const walker = document.createTreeWalker(body, NodeFilter.SHOW_TEXT, {
    acceptNode(node) {
      return node.textContent.trim() &&
        !node.parentElement.closest(
          "svg,script,style,mjx-assistive-mml,.flow-math-stage,mjx-c,mjx-utext,mjx-stretchy-v,mjx-stretchy-h",
        )
        ? NodeFilter.FILTER_ACCEPT
        : NodeFilter.FILTER_REJECT;
    },
  });
  for (let node = walker.nextNode(); node; node = walker.nextNode()) {
    const range = document.createRange();
    range.selectNodeContents(node);
    const tag = node.parentElement.closest("[data-flow-mark]")?.dataset.flowMark ?? null;
    const target = record.nodes.some((mark) =>
      visualFragments(mark).some((fragment) => fragment.contains(node)),
    );
    for (const rect of range.getClientRects()) {
      if (rect.width && rect.height) ink.push({ rect, target, tag });
    }
  }
  // A text Range spans the font's entire ascent/descent, including empty space
  // above and below a CHTML glyph. Its own measured surface follows the actual
  // mathematical paint and leaves real channels between derivation rows.
  for (const node of mathInkNodes(body)) {
    if (node.closest(".flow-math-stage")) continue;
    if (node.localName === "svg" && !node.closest(".flow-math-view")) continue;
    const target = record.nodes.some((mark) =>
      visualFragments(mark).some((fragment) => fragment.contains(node)),
    );
    const tag = node.closest("[data-flow-mark]")?.dataset.flowMark ?? null;
    for (const rect of node.getClientRects())
      if (rect.width && rect.height) ink.push({ rect, target, tag });
  }
  return ink;
}

function collisions(record, layout, measurement) {
  const ink = textInk(record);
  const origin = record.scene.body.getBoundingClientRect();
  const labels = layout.labels ?? [];
  let labelHits = 0;
  for (const label of labels) {
    const left = origin.left + measurement.x + label.left;
    const top = origin.top + measurement.y + label.top;
    const rect = { left, top, right: left + label.width, bottom: top + label.height };
    if (ink.some((item) => overlaps(rect, item.rect))) labelHits++;
  }
  let pathHits = 0;
  const obstacles = ink.filter((item) => !item.target).map((item) => item.rect);
  for (const path of record.svg.querySelectorAll("path[stroke]")) {
    if (path.closest("defs,symbol") || path.getAttribute("stroke") === "none") continue;
    const matrix = path.getScreenCTM();
    if (!matrix) continue;
    const length = path.getTotalLength();
    const scale = Math.max(Math.hypot(matrix.a, matrix.b), Math.hypot(matrix.c, matrix.d));
    const samples = Math.min(2000, Math.max(1, Math.ceil((length * scale) / 2)));
    const style = getComputedStyle(path);
    const radius = Math.max(0.5, (parseFloat(style.strokeWidth) * scale) / 2);
    for (let i = 0; i <= samples; i++) {
      const sample = paintedPathPoint(path, (length * i) / samples, length, style.strokeLinecap);
      if (!sample) continue;
      const point = sample.matrixTransform(matrix);
      if (
        obstacles.some(
          (rect) =>
            point.x + radius > rect.left &&
            point.x - radius < rect.right &&
            point.y + radius > rect.top &&
            point.y - radius < rect.bottom,
        )
      ) {
        pathHits++;
        break;
      }
    }
  }
  return { labels: labelHits, paths: pathHits };
}

function inlineGeometry(record, width) {
  const svg = record.svg;
  const matrix = svg.getScreenCTM();
  if (!matrix) throw new Error("관계 그림의 크기를 측정하지 못했습니다.");
  const inverse = matrix.inverse();
  const points = [];
  for (const shape of svg.querySelectorAll(
    "path,rect,circle,ellipse,line,polyline,polygon,use,text",
  )) {
    if (shape.closest("defs,symbol")) continue;
    const style = getComputedStyle(shape);
    if (
      style.display === "none" ||
      Number(style.opacity) === 0 ||
      (style.stroke === "none" && style.fill === "none")
    )
      continue;
    const transform = shape.getScreenCTM();
    if (!transform) continue;
    const box = shape.getBBox();
    for (const [x, y] of [
      [box.x, box.y],
      [box.x + box.width, box.y],
      [box.x, box.y + box.height],
      [box.x + box.width, box.y + box.height],
    ]) {
      const point = new DOMPoint(x, y).matrixTransform(transform).matrixTransform(inverse);
      points.push(point);
    }
    if (style.stroke !== "none") {
      const stroke =
        parseFloat(style.strokeWidth) *
        Math.max(Math.hypot(transform.a, transform.b), Math.hypot(transform.c, transform.d));
      shape.style.strokeWidth = `${stroke}px`;
      shape.setAttribute("vector-effect", "non-scaling-stroke");
    }
  }
  if (!points.length) throw new Error("관계 그림의 선을 찾지 못했습니다.");
  const left = Math.min(...points.map((point) => point.x)) - 4;
  const top = Math.min(...points.map((point) => point.y)) - 4;
  const sourceWidth = Math.max(...points.map((point) => point.x)) - left + 4;
  const sourceHeight = Math.max(...points.map((point) => point.y)) - top + 4;
  svg.setAttribute("viewBox", `${left} ${top} ${sourceWidth} ${sourceHeight}`);
  Object.assign(svg.style, {
    position: "relative",
    left: "0",
    top: "0",
    width: `${width}px`,
    height: `${(width * sourceHeight) / sourceWidth}px`,
    maxWidth: "100%",
  });
  const rail = document.createElement("div");
  rail.className = "flow-graphic-inline";
  rail.append(svg);
  record.scene.frame.append(rail);
  record.rail = rail;
}

export class GraphicalAnnotations {
  constructor(article, getRevision, preserve) {
    Object.assign(this, { article, getRevision, preserve });
    this.records = new Map();
    this.scenes = new Set();
    this.cache = new Map();
    this.sequence = 0;
    this.resize = new ResizeObserver(() => this.schedule());
    this.intersection = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          for (const scene of this.scenes) {
            if (scene.node === entry.target) scene.visible = entry.isIntersecting;
          }
        }
        this.schedule();
      },
      { rootMargin: "1200px 0px" },
    );
    document.fonts.ready.then(() => this.schedule());
    document.fonts.addEventListener("loadingdone", () => this.schedule());
    article.addEventListener("scroll", () => this.schedule(), true);
  }

  register(id, tags, nodes, note) {
    if (nodes.some((node) => !node)) throw new Error(`Missing target for ${id}`);
    note.className = "flow-graphic-status";
    note.dataset.graphicId = id;
    note.setAttribute("role", "status");
    note.textContent = "수식의 관계 그림을 준비하는 중…";
    this.records.set(id, { id, tags, nodes, note, key: null });
  }

  prepare(root) {
    let groups = [...this.records.values()]
      .filter((record) => root.contains(record.nodes[0]))
      .map((record) => spanFor([record]));
    // Merge overlapping spans before moving nodes, including nested callouts.
    for (let changed = true; changed; ) {
      changed = false;
      outer: for (let i = 0; i < groups.length; i++) {
        for (let j = i + 1; j < groups.length; j++) {
          if (
            groups[i].range.intersectsNode(groups[j].first) ||
            groups[j].range.intersectsNode(groups[i].first)
          ) {
            groups[i] = spanFor([...groups[i].records, ...groups[j].records]);
            groups.splice(j, 1);
            changed = true;
            break outer;
          }
        }
      }
    }
    for (const group of groups) {
      const node = document.createElement("div");
      node.className = "flow-graphic-scene";
      const frame = document.createElement("div");
      frame.className = "flow-graphic-frame";
      const body = document.createElement("div");
      body.className = "flow-graphic-body";
      group.first.before(node);
      for (let child = group.first; child; ) {
        const next = child.nextSibling;
        body.append(child);
        if (child === group.last) break;
        child = next;
      }
      frame.append(body);
      node.append(frame);
      const scene = { node, frame, body, records: group.records, visible: false };
      for (const record of group.records) {
        record.scene = scene;
        node.append(record.note);
      }
      this.scenes.add(scene);
    }
    for (const group of root.querySelectorAll(".flow-notes")) {
      if (!group.querySelector(".flow-note")) group.remove();
    }
  }

  clear() {
    this.sequence++;
    this.controller?.abort();
    clearTimeout(this.timer);
    this.resize.disconnect();
    this.intersection.disconnect();
    this.scenes.clear();
    this.records.clear();
  }

  sync() {
    for (const scene of this.scenes) {
      if (!scene.node.isConnected) {
        this.intersection.unobserve(scene.node);
        this.resize.unobserve(scene.body);
        this.scenes.delete(scene);
        for (const record of scene.records) {
          if (this.records.get(record.id) === record) this.records.delete(record.id);
        }
      } else if (!scene.observed) {
        scene.observed = true;
        this.intersection.observe(scene.node);
        this.resize.observe(scene.body);
      }
    }
    this.schedule();
  }

  schedule() {
    // Invalid overlays must not widen the page while render() is busy or waits
    // for mathematical composition. Hidden SVGs still have overflow geometry.
    for (const record of this.records.values()) {
      if (!record.svg?.isConnected) continue;
      const temporary = record.nodes.some((source) =>
        visualFragments(source).some((node) =>
          ["native", "pending"].includes(node.closest(".flow-math-view")?.dataset.mathState),
        ),
      );
      if (!temporary && record.key === this.measure(record)?.key) continue;
      this.preserve(() => {
        record.svg.remove();
        record.rail?.remove();
        record.rail = null;
        record.key = null;
        record.note.dataset.graphicState = "pending";
        record.note.textContent = "수식의 관계 그림을 준비하는 중…";
      });
    }
    clearTimeout(this.timer);
    this.timer = setTimeout(() => this.render(), 200);
  }

  ink(record) {
    return textInk(record);
  }

  measure(record) {
    const rect = record.scene.body.getBoundingClientRect();
    const groups = record.nodes.map((source) =>
      visualFragments(source).flatMap((node) =>
        [...node.getClientRects()]
          .filter((r) => r.width && r.height)
          .map((rect) => {
            if (!node.dataset.flowAnchor) return rect;
            const anchor = JSON.parse(node.dataset.flowAnchor);
            const left = rect.left + anchor.left,
              top = rect.top + anchor.top;
            return {
              left,
              top,
              right: left + anchor.width,
              bottom: top + anchor.height,
              width: anchor.width,
              height: anchor.height,
            };
          }),
      ),
    );
    if (groups.some((fragments) => !fragments.length)) return null;
    const bounds = groups.flat();
    const x = Math.min(0, ...bounds.map((item) => item.left - rect.left));
    const y = Math.min(0, ...bounds.map((item) => item.top - rect.top));
    const width = Math.max(rect.width, ...bounds.map((item) => item.right - rect.left)) - x;
    const height = Math.max(rect.height, ...bounds.map((item) => item.bottom - rect.top)) - y;
    if (width < 1 || height < 1 || width > 30000 || height > 30000) return null;
    const round = (value) => Math.round(value * 1000) / 1000;
    const geometry = {
      width: round(width),
      height: round(height),
      fontSize: parseFloat(getComputedStyle(this.article).fontSize),
      markers: Object.fromEntries(
        record.tags.map((tag, index) => [
          tag,
          {
            fragments: groups[index].map((bounds) => ({
              x: round(bounds.left - rect.left - x),
              y: round(bounds.top - rect.top - y),
              width: round(bounds.width),
              height: round(bounds.height),
            })),
          },
        ]),
      ),
    };
    const ink = this.ink(record).map(({ rect: item, tag }) => ({
      left: round(item.left - rect.left - x),
      top: round(item.top - rect.top - y),
      right: round(item.right - rect.left - x),
      bottom: round(item.bottom - rect.top - y),
      tag,
    }));
    const baseKey = JSON.stringify([
      this.getRevision(),
      record.id,
      geometry,
      round(x),
      round(y),
      ink,
    ]);
    if (record.routeKey === baseKey && record.routes) geometry.routes = record.routes;
    const signature = JSON.stringify([this.getRevision(), record.id, geometry]);
    return {
      geometry,
      signature,
      x,
      y,
      width: rect.width,
      height: rect.height,
      ink,
      baseKey,
      key: JSON.stringify([
        signature,
        baseKey,
        round(x),
        round(y),
        round(rect.width),
        round(rect.height),
      ]),
    };
  }

  apply(record, source, measurement) {
    const parsed = new DOMParser().parseFromString(source, "image/svg+xml");
    if (parsed.querySelector("parsererror")) throw new Error("관계 그림을 읽지 못했습니다.");
    const svg = parsed.documentElement;
    svg.querySelectorAll("script,foreignObject").forEach((node) => node.remove());
    for (const node of [svg, ...svg.querySelectorAll("*")]) {
      for (const attribute of [...node.attributes]) {
        if (
          /^on/i.test(attribute.name) ||
          (/^(href|src|xlink:href)$/i.test(attribute.name) &&
            /^\s*javascript:/i.test(attribute.value))
        )
          node.removeAttribute(attribute.name);
      }
    }
    const layout = JSON.parse(svg.getAttribute("data-flow-graphic-layout"));
    const left = layout.left + measurement.x;
    const top = layout.top + measurement.y;
    svg.classList.add("flow-graphic-overlay");
    svg.setAttribute("role", "img");
    svg.setAttribute("aria-label", "표시된 수식 항 사이의 관계 그림");
    svg.dataset.graphicId = record.id;
    svg.style.left = `${left}px`;
    svg.style.top = `${top}px`;
    const overflow = left < -1 || left + layout.width > measurement.width + 1;
    this.preserve(() => {
      record.svg?.remove();
      record.rail?.remove();
      record.rail = null;
      record.svg = document.importNode(svg, true);
      record.scene.body.append(record.svg);
      record.bounds = {
        top: Math.max(0, -top) + 4,
        bottom: Math.max(0, top + layout.height - measurement.height) + 4,
      };
      record.scene.frame.style.paddingTop = `${Math.max(...record.scene.records.map((item) => item.bounds?.top ?? 0))}px`;
      record.scene.frame.style.paddingBottom = `${Math.max(...record.scene.records.map((item) => item.bounds?.bottom ?? 0))}px`;
      let hits = collisions(record, layout, measurement);
      const floating =
        !layout.connectors?.length &&
        !layout.labels?.length &&
        !record.svg.querySelector("symbol,use,text") &&
        (overflow || hits.labels || hits.paths);
      if (floating) {
        // Numeric offsets do not identify a destination term. Preserve their
        // vector drawing in the continuous flow rather than invent endpoints
        // or let it cover reflowed mathematics. Named connections stay anchored.
        inlineGeometry(record, measurement.width);
        record.bounds = { top: 4, bottom: 4 };
        record.scene.frame.style.paddingTop = `${Math.max(...record.scene.records.map((item) => item.bounds?.top ?? 0))}px`;
        record.scene.frame.style.paddingBottom = `${Math.max(...record.scene.records.map((item) => item.bounds?.bottom ?? 0))}px`;
        hits = collisions(record, layout, measurement);
      }
      const plan = routeConnections(
        layout.connectors ?? [],
        measurement.ink,
        measurement.geometry,
        (layout.labels ?? []).map((label) => ({
          left: label.left,
          top: label.top,
          right: label.left + label.width,
          bottom: label.top + label.height,
        })),
      );
      const collision = hits.labels + hits.paths > 0 || plan.unresolved.length > 0;
      record.note.dataset.graphicCollisions = JSON.stringify(hits);
      record.note.dataset.graphicUnrouted = JSON.stringify(plan.unresolved);
      record.note.dataset.graphicMode = floating ? "inline" : "anchored";
      record.note.textContent =
        overflow && !floating
          ? "수식과 관계 그림의 폭 조정이 아직 필요합니다."
          : collision
            ? "관계선 또는 설명이 본문과 겹쳐 배치 조정이 필요합니다."
            : "";
      record.note.dataset.graphicState =
        overflow && !floating ? "overflow" : collision ? "collision" : "ready";
      record.key = measurement.key;
      if (layout.connectors?.length) {
        const attempts = record.routeKey === measurement.baseKey ? (record.routeAttempts ?? 0) : 0;
        const routes = {
          ...(record.routeKey === measurement.baseKey ? record.routes : {}),
          ...plan.routes,
        };
        if (
          attempts < 2 &&
          Object.keys(routes).length &&
          JSON.stringify(routes) !== JSON.stringify(measurement.geometry.routes)
        ) {
          record.routeKey = measurement.baseKey;
          record.routes = routes;
          record.routeAttempts = attempts + 1;
          record.key = null;
          record.note.dataset.graphicState = "pending";
          record.note.textContent = "관계선이 글자와 겹치지 않도록 배치하는 중…";
          this.schedule();
        }
      }
      // Measure the compiler's paint to route it, but do not cover readable
      // mathematics with a candidate awaiting its automatic replacement.
      record.svg.style.visibility = record.note.dataset.graphicState === "pending" ? "hidden" : "";
    });
  }

  async render() {
    if (this.busy) {
      this.again = true;
      return;
    }
    const revision = this.getRevision();
    if (!revision) return;
    const pending = [];
    for (const record of this.records.values()) {
      if (!record.scene?.visible || !record.scene.node.isConnected) continue;
      // Initial MathML will shortly be replaced. Do not spend a full compiler
      // request on geometry already known to be temporary.
      if (
        record.nodes.some((source) =>
          visualFragments(source).some((node) =>
            ["native", "pending"].includes(node.closest(".flow-math-view")?.dataset.mathState),
          ),
        )
      )
        continue;
      const measurement = this.measure(record);
      if (!measurement) {
        record.note.textContent = "관계 그림의 배치 범위를 확인해야 합니다.";
        record.note.dataset.graphicState = "unsupported";
        continue;
      }
      if (record.key === measurement.key) continue;
      record.svg?.remove();
      if (this.cache.has(measurement.signature)) {
        this.apply(record, this.cache.get(measurement.signature), measurement);
      } else {
        record.note.dataset.graphicState = "pending";
        record.note.textContent = "수식의 관계 그림을 준비하는 중…";
        pending.push({ record, measurement });
      }
    }
    if (!pending.length) return;
    this.busy = true;
    const sequence = this.sequence;
    this.controller = new AbortController();
    try {
      for (let start = 0; start < pending.length; start += 32) {
        const batch = pending.slice(start, start + 32);
        const response = await fetch("api/graphics", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            revision,
            graphs: Object.fromEntries(
              batch.map(({ record, measurement }) => [record.id, measurement.geometry]),
            ),
          }),
          signal: this.controller.signal,
        });
        if (!response.ok)
          throw new Error("관계 그림을 갱신하지 못했습니다. 자동으로 다시 시도합니다.");
        const result = await response.json();
        if (sequence !== this.sequence || result.revision !== this.getRevision()) return;
        for (const { record, measurement } of batch) {
          const source = result.graphics[record.id];
          this.cache.set(measurement.signature, source);
          if (!record.scene.node.isConnected) continue;
          const current = this.measure(record);
          if (current?.key === measurement.key) this.apply(record, source, current);
          else this.again = true;
        }
        while (this.cache.size > 64) this.cache.delete(this.cache.keys().next().value);
      }
    } catch (error) {
      if (error.name !== "AbortError" && sequence === this.sequence) {
        for (const { record } of pending) {
          record.note.textContent = error.message;
          record.note.dataset.graphicState = "error";
        }
        this.timer = setTimeout(() => this.render(), 5000);
      }
    } finally {
      this.busy = false;
      if (this.again || sequence !== this.sequence) {
        this.again = false;
        this.schedule();
      }
    }
  }
}

export function namespaceClone(root, prefix) {
  const nodes = [root, ...root.querySelectorAll("[id]")];
  const ids = new Map();
  for (const node of nodes) {
    if (node.id) {
      ids.set(node.id, prefix + node.id);
      node.id = prefix + node.id;
    }
  }
  for (const node of [root, ...root.querySelectorAll("*")]) {
    for (const attribute of [...node.attributes]) {
      let value = attribute.value;
      if (attribute.localName === "href" && value.startsWith("#") && ids.has(value.slice(1))) {
        value = "#" + ids.get(value.slice(1));
      }
      value = value.replace(/url\(#([^)]*)\)/g, (whole, id) =>
        ids.has(id) ? `url(#${ids.get(id)})` : whole,
      );
      if (value !== attribute.value)
        node.setAttributeNS(attribute.namespaceURI, attribute.name, value);
    }
  }
  return root;
}
