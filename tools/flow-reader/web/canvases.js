// CeTZ coordinate units adapt before rendering. The browser never scales the
// resulting text to force a fit. A width fit is not a label-collision guarantee.
export class AdaptiveCanvases {
  constructor(article, getRevision, preserve = (change) => change()) {
    this.article = article;
    this.getRevision = getRevision;
    this.preserve = preserve;
    this.sequence = 0;
    this.records = [];
    this.cache = new Map();
    this.resize = new ResizeObserver(() => this.schedule());
    this.resize.observe(article);
  }

  onDocument() {
    this.sequence++;
    this.controller?.abort();
    clearTimeout(this.timer);
    this.intersection?.disconnect();
    for (const record of this.records) record.message.remove();
    this.records = [];
    this.intersection = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          const record = this.records.find((item) => item.node === entry.target);
          if (record) record.visible = entry.isIntersecting;
        }
        this.schedule();
      },
      { rootMargin: "800px 0px" },
    );
    this.sync();
  }

  sync() {
    if (!this.intersection) return;
    this.records = this.records.filter((record) => {
      if (record.node.isConnected) return true;
      this.intersection.unobserve(record.node);
      return false;
    });
    const known = new Set(this.records.map((record) => record.node));
    for (const node of this.article.querySelectorAll("[data-flow-canvas]")) {
      if (known.has(node)) continue;
      const record = { node, id: node.dataset.flowCanvas, visible: false, key: null };
      const message = document.createElement("span");
      message.className = "flow-canvas-status";
      message.textContent = "그림을 화면 폭에 맞추는 중…";
      record.message = message;
      const image = node.querySelector("svg,img");
      const viewBox = image?.getAttribute("viewBox")?.trim().split(/[ ,]+/).map(Number);
      const width = viewBox?.[2] ?? parseFloat(image?.getAttribute("width"));
      const height = viewBox?.[3] ?? parseFloat(image?.getAttribute("height"));
      if (width > 0 && height > 0)
        node.style.setProperty("--flow-canvas-aspect", String(width / height));
      node.dataset.canvasLayout = "pending";
      node.dataset.canvasPlaceholder = "true";
      record.node.append(message);
      this.records.push(record);
      this.intersection.observe(record.node);
    }
    this.schedule();
  }

  schedule() {
    // Width can change while another compiler request is in flight. Keep
    // offscreen and pending drawings bounded before the network worker runs.
    const revision = this.getRevision();
    const fontSize = parseFloat(getComputedStyle(this.article).fontSize);
    for (const record of this.records) {
      if (!record.node.isConnected) continue;
      const width = Math.floor(record.node.getBoundingClientRect().width);
      if (width < 1) continue;
      const key = JSON.stringify([revision, record.id, width, fontSize]);
      if (record.key === key && record.result && record.node.dataset.canvasLayout === "pending") {
        this.apply(record, record.result, key);
        continue;
      }
      if (!record.fitted) continue;
      const placeholder = String(Number(record.node.dataset.canvasWidth) > width + 1);
      if (record.node.dataset.canvasPlaceholder === placeholder) continue;
      this.preserve(() => {
        record.node.dataset.canvasPlaceholder = placeholder;
        if (placeholder === "true") {
          record.node.dataset.canvasLayout = "pending";
          record.message.textContent = "그림을 화면 폭에 맞추는 중…";
        }
      });
    }
    clearTimeout(this.timer);
    this.timer = setTimeout(() => this.render(), 150);
  }

  apply(record, result, key) {
    const parsed = new DOMParser().parseFromString(result.svg, "image/svg+xml");
    if (parsed.querySelector("parsererror")) throw new Error("그림을 읽지 못했습니다.");
    const svg = parsed.documentElement;
    // Compiler output is trusted drawing data, not executable reader content.
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
    this.preserve(() => {
      record.node.replaceChildren(document.importNode(svg, true), record.message);
      record.node.dataset.canvasLayout = result.layout.status;
      record.node.dataset.canvasWidth = result.layout.width;
      record.node.dataset.canvasFont = result.layout.fontSize;
      record.fitted = result.layout.status === "width-fit";
      record.node.dataset.canvasPlaceholder = "false";
      if (result.layout.width > 0 && result.layout.height > 0)
        record.node.style.setProperty(
          "--flow-canvas-aspect",
          String(result.layout.width / result.layout.height),
        );
      record.message.textContent =
        result.layout.status === "width-fit"
          ? ""
          : "이 그림은 고정된 길이 때문에 아직 화면 폭에 맞추지 못했습니다.";
      record.key = key;
      record.result = result;
    });
  }

  async render() {
    if (this.busy) {
      this.again = true;
      return;
    }
    const revision = this.getRevision();
    if (!revision) return;
    const fontSize = parseFloat(getComputedStyle(this.article).fontSize);
    const pending = [];
    for (const record of this.records) {
      if (!record.visible || !record.node.isConnected) continue;
      const width = Math.floor(record.node.getBoundingClientRect().width);
      if (width < 32 || width > 4096) continue;
      const key = JSON.stringify([revision, record.id, width, fontSize]);
      if (record.key === key) {
        if (record.result && record.node.dataset.canvasLayout === "pending")
          this.apply(record, record.result, key);
        continue;
      }
      if (this.cache.has(key)) {
        this.apply(record, this.cache.get(key), key);
      } else {
        this.preserve(() => {
          // Keep a previously fitted drawing while a larger-font result loads.
          // A drawing wider than the new container needs a bounded placeholder.
          if (record.fitted)
            record.node.dataset.canvasPlaceholder = String(
              Number(record.node.dataset.canvasWidth) > width + 1,
            );
          record.node.dataset.canvasLayout = "pending";
          record.message.textContent = "그림을 화면 폭에 맞추는 중…";
        });
        pending.push({ record, key, request: { width, fontSize } });
      }
    }
    if (!pending.length) return;
    this.busy = true;
    const sequence = this.sequence;
    this.controller = new AbortController();
    try {
      for (let start = 0; start < pending.length; start += 32) {
        const batch = pending.slice(start, start + 32);
        const response = await fetch("api/canvases", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            revision,
            canvases: Object.fromEntries(batch.map((item) => [item.record.id, item.request])),
          }),
          signal: this.controller.signal,
        });
        if (!response.ok) throw new Error("그림 배치를 갱신하지 못했습니다. 다시 시도합니다.");
        const result = await response.json();
        if (
          sequence !== this.sequence ||
          revision !== this.getRevision() ||
          result.revision !== revision
        )
          return;
        for (const item of batch) {
          const drawing = result.canvases[item.record.id];
          this.cache.set(item.key, drawing);
          if (!item.record.node.isConnected) continue;
          const currentKey = JSON.stringify([
            revision,
            item.record.id,
            Math.floor(item.record.node.getBoundingClientRect().width),
            parseFloat(getComputedStyle(this.article).fontSize),
          ]);
          if (currentKey === item.key) this.apply(item.record, drawing, item.key);
          else this.again = true;
        }
        while (this.cache.size > 64) this.cache.delete(this.cache.keys().next().value);
      }
    } catch (error) {
      if (error.name !== "AbortError" && sequence === this.sequence) {
        pending.forEach((item) => {
          item.record.message.textContent = error.message;
        });
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
