// A graphical annotation is evaluated by CeTZ at measured DOM term positions.
// The original programs, curve directions, labels and units remain authoritative.
export class GraphicalAnnotations {
  constructor(dialog, getRevision) {
    this.dialog = dialog;
    this.getRevision = getRevision;
    this.records = new Map();
    this.sequence = 0;
    dialog.addEventListener("close", () => this.stop());
  }

  register(id, tags, nodes) {
    if (nodes.some((node) => !node)) throw new Error(`Missing target for ${id}`);
    this.records.set(id, { tags, nodes });
  }

  clear() {
    this.stop();
    this.records.clear();
  }

  prune() {
    for (const [id, record] of this.records) {
      if (record.nodes.some((node) => !node.isConnected)) this.records.delete(id);
    }
  }

  stop() {
    this.observer?.disconnect();
    this.controller?.abort();
    clearTimeout(this.timer);
    this.sequence++;
  }

  async show(id) {
    const record = this.records.get(id);
    if (!record) return;
    this.stop();
    const sequence = this.sequence;
    const revision = this.getRevision();
    const body = this.dialog.querySelector("#reader-note-body");
    const title = document.createElement("h2");
    title.textContent = "수식의 관계";
    const status = document.createElement("p");
    status.className = "flow-graphic-status";
    status.setAttribute("role", "status");
    status.textContent = "관계 그림을 준비하고 있습니다…";
    const scroll = document.createElement("div");
    scroll.className = "flow-graphic-scroll";
    const scene = document.createElement("div");
    scene.className = "flow-graphic-scene";
    scene.dataset.graphicId = id;
    const roots = [
      ...new Set(
        record.nodes.map(
          (node) =>
            node.closest(".flow-equation") ?? node.closest("p") ?? node.closest("math") ?? node,
        ),
      ),
    ].sort((a, b) => (a.compareDocumentPosition(b) & Node.DOCUMENT_POSITION_FOLLOWING ? -1 : 1));
    for (const root of roots) {
      const clone = root.cloneNode(true);
      namespaceClone(clone, `reader-scene-${sequence}-`);
      clone.querySelectorAll("[data-reader-note]").forEach((node) => {
        node.removeAttribute("data-reader-note");
        node.removeAttribute("tabindex");
        node.removeAttribute("role");
        node.removeAttribute("aria-haspopup");
      });
      scene.append(clone);
    }
    scroll.append(scene);
    body.replaceChildren(title, status, scroll);
    if (!this.dialog.open) this.dialog.showModal();
    await document.fonts.ready;
    await new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)));
    if (this.sequence !== sequence) return;

    let lastGeometry;
    const render = async () => {
      if (this.sequence !== sequence || !this.dialog.open) return;
      const rect = scene.getBoundingClientRect();
      const markers = {};
      for (const tag of record.tags) {
        const mark = scene.querySelector(`[data-flow-mark="${CSS.escape(tag)}"]`);
        if (!mark) {
          status.textContent = "연결된 수식 항을 찾을 수 없습니다.";
          return;
        }
        const bounds = mark.getBoundingClientRect();
        markers[tag] = {
          x: bounds.x - rect.x,
          y: bounds.y - rect.y,
          width: bounds.width,
          height: bounds.height,
        };
      }
      const geometry = { width: rect.width, height: rect.height, markers };
      if (lastGeometry === undefined) {
        const bounds = Object.values(markers);
        const left = Math.min(...bounds.map((mark) => mark.x));
        const right = Math.max(...bounds.map((mark) => mark.x + mark.width));
        scroll.scrollLeft =
          right - left < scroll.clientWidth - 48
            ? (left + right - scroll.clientWidth) / 2
            : left - 24;
      }
      const signature = JSON.stringify(geometry);
      if (lastGeometry === signature) return;
      lastGeometry = signature;
      this.controller?.abort();
      this.controller = new AbortController();
      scene.dataset.renderState = "pending";
      scene.querySelector(".flow-graphic-overlay")?.remove();
      status.textContent = "관계 그림을 준비하고 있습니다…";
      try {
        const response = await fetch("api/graphics", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ revision, graphs: { [id]: geometry } }),
          signal: this.controller.signal,
        });
        if (response.status === 409)
          throw new Error("문서가 변경되었습니다. 닫은 뒤 다시 열어 주세요.");
        if (!response.ok) throw new Error("관계 그림을 만들지 못했습니다. 다시 열어 주세요.");
        const result = await response.json();
        if (
          this.sequence !== sequence ||
          this.getRevision() !== result.revision ||
          lastGeometry !== signature
        )
          return;
        const parsed = new DOMParser().parseFromString(result.graphics[id], "image/svg+xml");
        if (parsed.querySelector("parsererror")) throw new Error("관계 그림을 읽지 못했습니다.");
        const svg = parsed.documentElement;
        svg.classList.add("flow-graphic-overlay");
        svg.setAttribute("aria-label", "표시된 수식 항 사이의 관계 그림");
        scene.append(document.importNode(svg, true));
        scene.dataset.renderState = "ready";
        status.textContent = "좌우로 이동해 전체 수식과 관계선을 볼 수 있습니다.";
      } catch (error) {
        if (error.name !== "AbortError" && this.sequence === sequence) {
          scene.dataset.renderState = "error";
          status.textContent = error.message;
        }
      }
    };
    this.observer = new ResizeObserver(() => {
      clearTimeout(this.timer);
      this.timer = setTimeout(render, 200);
    });
    this.observer.observe(scene);
    render();
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
