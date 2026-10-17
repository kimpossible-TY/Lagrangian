// Transport sections form one reading flow. Only distant, unselected sections
// are parked; their measured height preserves the surrounding scroll geometry.
export class ContinuousSections {
  constructor(article, { fetchSection, prepare, changed, anchor, restore }) {
    Object.assign(this, { article, fetchSection, prepare, changed, anchor, restore });
    this.generation = 0;
    this.entries = new Map();
    this.resize = new ResizeObserver(() => this.schedule());
    this.resize.observe(article);
    window.addEventListener("scroll", () => this.schedule(), { passive: true });
    window.addEventListener("resize", () => this.schedule());
    window.addEventListener("online", () => {
      this.retry = {};
      for (const entry of this.entries.values()) entry.retryAt = 0;
      this.schedule();
    });
    document.addEventListener("selectionchange", () => this.schedule());
  }

  reset(manifest, section, html) {
    this.generation++;
    this.controller?.abort();
    this.controller = new AbortController();
    this.observer?.disconnect();
    clearTimeout(this.timer);
    this.running = null;
    this.manifest = manifest;
    this.retry = {};
    this.entries.clear();
    this.first = this.last = manifest.sections.findIndex((item) => item.id === section);
    this.before = this.boundary("before");
    this.after = this.boundary("after");
    const entry = this.create(this.first, html);
    this.article.replaceChildren(this.before, entry.node, this.after);
    this.observer = new IntersectionObserver(() => this.schedule(), {
      rootMargin: "1200px 0px",
    });
    this.observer.observe(this.before);
    this.observer.observe(this.after);
    this.observer.observe(entry.node);
    this.updateBoundaries();
  }

  boundary(direction) {
    const node = document.createElement("div");
    node.className = "reader-continuation";
    node.dataset.direction = direction;
    node.setAttribute("role", "status");
    return node;
  }

  updateBoundaries() {
    this.before.hidden = this.first === 0;
    this.after.hidden = this.last === this.manifest.sections.length - 1;
    if (!this.retry.before) this.before.textContent = "앞의 내용을 불러오는 중…";
    if (!this.retry.after) this.after.textContent = "이어지는 내용을 불러오는 중…";
  }

  create(index, html) {
    const section = this.manifest.sections[index].id;
    const node = document.createElement("section");
    node.className = "reader-section";
    node.dataset.readerSection = section;
    node.append(this.prepare(html, section));
    node.dataset.sectionState = "ready";
    const entry = { index, node, ready: true, retryAt: 0 };
    this.entries.set(index, entry);
    return entry;
  }

  schedule(delay = 80) {
    clearTimeout(this.timer);
    this.timer = setTimeout(() => this.pump(), delay);
  }

  near(node, margin = 1200) {
    if (node.hidden) return false;
    const rect = node.getBoundingClientRect();
    return rect.bottom >= -margin && rect.top <= window.innerHeight + margin;
  }

  mutate(action) {
    // Capture at application time: the reader may have scrolled while fetching.
    const anchor = this.anchor();
    action();
    this.changed();
    this.restore(anchor);
  }

  async extend(direction, generation) {
    const index = direction === "before" ? this.first - 1 : this.last + 1;
    if (index < 0 || index >= this.manifest.sections.length) return false;
    const boundary = this[direction];
    if (!this.near(boundary) || (this.retry[direction] ?? 0) > Date.now()) return false;
    try {
      const html = await this.fetchSection(
        this.manifest,
        this.manifest.sections[index].id,
        this.controller.signal,
      );
      if (this.generation !== generation) return false;
      this.retry[direction] = 0;
      this.mutate(() => {
        const entry = this.create(index, html);
        if (direction === "before") {
          this.before.after(entry.node);
          this.first = index;
        } else {
          this.after.before(entry.node);
          this.last = index;
        }
        this.observer.observe(entry.node);
        this.updateBoundaries();
      });
      return true;
    } catch (error) {
      if (this.generation === generation && error.name !== "AbortError") {
        boundary.textContent = "내용을 불러오지 못했습니다. 연결 후 자동으로 다시 시도합니다.";
        this.retry[direction] = Date.now() + 5000;
      }
      return false;
    }
  }

  async restoreEntry(entry, generation) {
    if (entry.ready || !this.near(entry.node) || entry.retryAt > Date.now()) return false;
    try {
      const html = await this.fetchSection(
        this.manifest,
        this.manifest.sections[entry.index].id,
        this.controller.signal,
      );
      if (this.generation !== generation) return false;
      this.mutate(() => {
        entry.node.replaceChildren(this.prepare(html, entry.node.dataset.readerSection));
        entry.node.style.removeProperty("height");
        entry.node.removeAttribute("aria-busy");
        entry.node.dataset.sectionState = "ready";
        entry.ready = true;
        entry.retryAt = 0;
      });
      return true;
    } catch (error) {
      if (this.generation === generation && error.name !== "AbortError") {
        entry.node.firstElementChild.textContent =
          "내용을 불러오지 못했습니다. 연결 후 자동으로 다시 시도합니다.";
        entry.retryAt = Date.now() + 5000;
      }
      return false;
    }
  }

  protected(node) {
    if (document.querySelector("dialog[open]") || node.contains(document.activeElement))
      return true;
    const selection = window.getSelection();
    for (let index = 0; selection && index < selection.rangeCount; index++) {
      if (!selection.isCollapsed && selection.getRangeAt(index).intersectsNode(node)) return true;
    }
    return false;
  }

  park() {
    const ready = [...this.entries.values()].filter((entry) => entry.ready);
    const candidates = ready
      .filter((entry) => !this.near(entry.node, 1800) && !this.protected(entry.node))
      .sort((a, b) => {
        const distance = (entry) =>
          Math.abs(entry.node.getBoundingClientRect().top - innerHeight / 2);
        return distance(b) - distance(a);
      });
    const remove = candidates.slice(0, Math.max(0, ready.length - 6));
    if (!remove.length) return;
    this.mutate(() => {
      for (const entry of remove) {
        const height = entry.node.getBoundingClientRect().height;
        const message = document.createElement("div");
        message.className = "reader-continuation";
        message.textContent = "이 부분을 다시 불러오는 중…";
        entry.node.style.height = `${height}px`;
        entry.node.replaceChildren(message);
        entry.node.dataset.sectionState = "parked";
        entry.node.setAttribute("aria-busy", "true");
        entry.ready = false;
      }
    });
  }

  async pump() {
    if (!this.manifest || this.running === this.generation) return;
    const generation = this.generation;
    this.running = generation;
    let changed = false;
    try {
      // Restore visible parked content before extending either edge.
      for (const entry of this.entries.values()) {
        changed = (await this.restoreEntry(entry, generation)) || changed;
        if (this.generation !== generation) return;
      }
      changed = (await this.extend("before", generation)) || changed;
      if (this.generation !== generation) return;
      changed = (await this.extend("after", generation)) || changed;
      if (this.generation !== generation) return;
      this.park();
    } finally {
      if (this.generation === generation) {
        this.running = null;
        // Short documents may need more than one neighbor to fill the viewport.
        // Failures use automatic retry and never require a next/retry click.
        this.schedule(changed ? 80 : 5000);
      }
    }
  }
}
