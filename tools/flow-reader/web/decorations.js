// Keep mathematical glyphs semantic. Original Typst callbacks draw only the paint
// around their measured fragments, so line breaking never has to split an image.
import { setLanguage, uiLanguage } from "./language.js";

export class MathDecorations {
  constructor(article, getRevision, changed, preserve) {
    Object.assign(this, { article, getRevision, changed, preserve });
    this.records = new Map();
    this.cache = new Map();
    this.notices = new Map();
    this.sequence = 0;
    // schedule() may retire paint or prepare native geometry. Keep those
    // writes out of ResizeObserver's current notification delivery cycle.
    this.resize = new ResizeObserver(() => {
      cancelAnimationFrame(this.resizeFrame);
      this.resizeFrame = requestAnimationFrame(() => this.schedule());
    });
    this.intersection = new IntersectionObserver(() => this.schedule(), { rootMargin: "1000px" });
    document.fonts.ready.then(() => this.schedule());
    document.fonts.addEventListener("loadingdone", () => this.schedule());
    article.addEventListener("scroll", () => this.schedule(), true);
    window
      .matchMedia("(prefers-color-scheme: dark)")
      .addEventListener("change", () => this.schedule());
  }

  clear() {
    this.sequence++;
    this.controller?.abort();
    clearTimeout(this.timer);
    this.resize.disconnect();
    this.intersection.disconnect();
    for (const record of this.records.values()) this.remove(record);
    this.records.clear();
    for (const notice of this.notices.values()) notice.remove();
    this.notices.clear();
  }

  remove(record) {
    this.clearPaint(record);
    for (const node of record.nodes) {
      this.intersection.unobserve(node);
    }
  }

  clearPaint(record) {
    for (const svg of record.svgs ?? []) svg.remove();
    record.svgs = [];
    for (const node of record.nodes) {
      delete node.dataset.flowAnchor;
    }
    delete record.key;
  }

  sync() {
    const groups = new Map();
    for (const node of this.article.querySelectorAll("[data-flow-decoration]")) {
      if (node.closest("mjx-assistive-mml,.flow-math-stage")) continue;
      const id = node.dataset.flowDecoration;
      if (!groups.has(id)) groups.set(id, []);
      groups.get(id).push(node);
    }
    for (const [id, record] of this.records) {
      const nodes = groups.get(id);
      if (
        !nodes ||
        nodes.length !== record.nodes.length ||
        nodes.some((n, i) => n !== record.nodes[i])
      ) {
        this.remove(record);
        this.records.delete(id);
      }
    }
    for (const [id, nodes] of groups) {
      if (this.records.has(id)) continue;
      this.records.set(id, { id, nodes, svgs: [] });
      for (const node of nodes) this.intersection.observe(node);
    }
    this.resize.disconnect();
    this.resize.observe(this.article);
    for (const record of this.records.values()) {
      for (const node of record.nodes) {
        const surface = this.surface(node);
        surface.classList.add("flow-decoration-surface");
        this.resize.observe(surface);
      }
    }
    this.schedule();
  }

  status() {
    this.preserve(() => {
      for (const [surface, notice] of this.notices) {
        if (!surface.isConnected) {
          notice.remove();
          this.notices.delete(surface);
        } else notice.textContent = "";
      }
      for (const record of this.records.values())
        for (const node of record.nodes) {
          if (node.dataset.decorationState === "ready") continue;
          // Line breaking can leave an empty mark wrapper before its painted
          // fragments. A composed zero-area carrier has no missing decoration.
          const temporary = ["native", "pending"].includes(
            node.closest(".flow-math-view")?.dataset.mathState,
          );
          if (!temporary && ![...node.getClientRects()].some((rect) => rect.width && rect.height))
            continue;
          const surface = this.surface(node);
          if (!surface?.isConnected) continue;
          if (!this.notices.has(surface)) {
            const notice = document.createElement("span");
            notice.className = "flow-decoration-notice";
            setLanguage(notice, uiLanguage());
            notice.setAttribute("role", "status");
            surface.after(notice);
            this.notices.set(surface, notice);
          }
          this.notices.get(surface).textContent =
            node.dataset.decorationState === "error"
              ? "수식 장식을 불러오지 못했습니다. 자동으로 다시 시도합니다."
              : "수식의 강조·밑줄 등 장식을 준비하는 중…";
        }
    });
  }

  surface(node) {
    return (
      node.closest(".flow-equation,.flow-note,p,figcaption") ?? node.closest(".reader-section")
    );
  }

  measure(record) {
    const fragments = record.nodes.flatMap((node, member) => {
      // Explanations can repeat this callback far below its original term.
      // Compose and paint each nearby occurrence independently; an offscreen
      // native copy must not withhold a visible cancellation or emphasis.
      if (["native", "pending"].includes(node.closest(".flow-math-view")?.dataset.mathState))
        return [];
      const surface = this.surface(node);
      const base = surface.getBoundingClientRect();
      return [...node.getClientRects()]
        .filter((r) => r.width && r.height)
        .map((rect) => ({
          node,
          member,
          surface,
          width: rect.width,
          height: rect.height,
          x: rect.left - base.left - surface.clientLeft + surface.scrollLeft,
          y: rect.top - base.top - surface.clientTop + surface.scrollTop,
          visible: rect.bottom > -1000 && rect.top < innerHeight + 1000,
        }))
        .filter((fragment) => fragment.visible);
    });
    if (!fragments.length) return null;
    const round = (n) => Math.round(n * 1000) / 1000;
    const color = getComputedStyle(fragments[0].node).color.match(/[\d.]+/g);
    const ink =
      "#" +
      (color ?? [36, 44, 52])
        .slice(0, 3)
        .map((n) => Math.round(Number(n)).toString(16).padStart(2, "0"))
        .join("");
    const request = {
      fontSize: parseFloat(getComputedStyle(fragments[0].node).fontSize),
      ink,
      fragments: fragments.map((f) => ({ width: round(f.width), height: round(f.height) })),
    };
    const signature = JSON.stringify([this.getRevision(), record.id, request]);
    const key = JSON.stringify([
      signature,
      fragments.map((f) => [f.member, round(f.x), round(f.y)]),
    ]);
    return { request, signature, key, fragments };
  }

  apply(record, drawings, measurement) {
    for (const svg of record.svgs) svg.remove();
    record.svgs = [];
    for (const drawing of drawings) {
      const fragment = measurement.fragments[drawing.fragment];
      const parsed = new DOMParser().parseFromString(drawing.svg, "image/svg+xml");
      if (parsed.querySelector("parsererror")) throw new Error("Invalid decoration SVG");
      const svg = document.importNode(parsed.documentElement, true);
      svg.querySelectorAll("script,foreignObject").forEach((n) => n.remove());
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
      svg.classList.add("flow-decoration-paint");
      svg.dataset.layer = drawing.layer;
      svg.dataset.readerDecorationId = record.id;
      svg.setAttribute("aria-hidden", "true");
      svg.style.left = `${fragment.x + drawing.layout.left}px`;
      svg.style.top = `${fragment.y + drawing.layout.top}px`;
      fragment.surface.append(svg);
      record.svgs.push(svg);
      fragment.node.dataset.decorationState = "ready";
      // The relationship adapter can include the authored stroke/bracket outset.
      fragment.node.dataset.flowAnchor = JSON.stringify(drawing.layout.anchor);
    }
    record.key = measurement.key;
    this.status();
    this.changed();
  }

  schedule() {
    // A previous wide SVG can enlarge Safari's page even while a different
    // compiler request is busy. Retire obsolete paint before the debounce.
    let changed = false;
    for (const record of this.records.values()) {
      if (!record.svgs?.length || record.key === this.measure(record)?.key) continue;
      this.clearPaint(record);
      for (const node of record.nodes) node.dataset.decorationState = "pending";
      changed = true;
    }
    if (changed) this.changed();
    clearTimeout(this.timer);
    this.timer = setTimeout(() => this.render(), 150);
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
      const measurement = this.measure(record);
      if (!measurement || record.key === measurement.key) continue;
      if (this.cache.has(measurement.signature))
        this.apply(record, this.cache.get(measurement.signature), measurement);
      else {
        // Do not leave an underline or cancellation over the wrong symbols
        // while a font/width change waits for a new compiler response.
        const hadPaint = record.svgs?.length;
        this.clearPaint(record);
        if (hadPaint) this.changed();
        for (const node of record.nodes) node.dataset.decorationState = "pending";
        pending.push({ record, measurement });
      }
    }
    this.status();
    if (!pending.length) return;
    this.busy = true;
    const sequence = this.sequence;
    this.controller = new AbortController();
    try {
      for (let start = 0; start < pending.length; start += 32) {
        const batch = pending.slice(start, start + 32);
        const response = await fetch("api/decorations", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          signal: this.controller.signal,
          body: JSON.stringify({
            revision,
            decorations: Object.fromEntries(
              batch.map(({ record, measurement }) => [record.id, measurement.request]),
            ),
          }),
        });
        if (!response.ok) throw new Error("Decoration rendering failed");
        const result = await response.json();
        if (sequence !== this.sequence || result.revision !== this.getRevision()) return;
        for (const { record, measurement } of batch) {
          const drawing = result.decorations[record.id];
          this.cache.set(measurement.signature, drawing);
          if (this.records.get(record.id) !== record) continue;
          const current = this.measure(record);
          if (current?.key === measurement.key) this.apply(record, drawing, current);
          else this.again = true;
        }
        while (this.cache.size > 128) this.cache.delete(this.cache.keys().next().value);
      }
    } catch (error) {
      if (error.name !== "AbortError" && sequence === this.sequence) {
        for (const { record } of pending)
          for (const node of record.nodes) node.dataset.decorationState = "error";
        this.status();
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
