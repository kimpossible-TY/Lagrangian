// Canonical-text geometry belongs to the HTML renderer.
import { logicalTextIndex, rangesFor } from "../../rendering/math/identity.js";
import { ReviewMarkStore } from "./store.js";

export class ReaderReviewMarks {
  constructor(article, changed) {
    this.article = article;
    this.changed = changed;
    let storage;
    try {
      storage = localStorage;
    } catch {
      /* Memory still works. */
    }
    this.store = new ReviewMarkStore(storage);
    this.layer = document.createElement("div");
    this.layer.className = "reader-review-marks";
    this.layer.setAttribute("aria-hidden", "true");
    article.classList.add("reader-review-host");
    this.resize = new ResizeObserver(() => this.schedule());
    this.resize.observe(article);
    this.resized = () => this.schedule();
    window.addEventListener("resize", this.resized);
    this.storageChanged = (event) => {
      if (event.key !== this.store.key && event.key !== null) return;
      const id = this.documentID;
      this.store.key = null;
      this.store.setDocument(id);
      this.repaint();
      this.changed();
    };
    window.addEventListener("storage", this.storageChanged);
  }

  onDocument(id) {
    this.documentID = id;
    this.store.setDocument(id);
    this.schedule();
  }

  add(fragments) {
    const nodes = new Map(
      [...this.article.querySelectorAll("[data-reader-key]")].map((node) => [
        node.dataset.readerKey,
        node,
      ]),
    );
    const parts = fragments.map((part) => {
      const block = nodes.get(part.key);
      if (!block) return null;
      const text = logicalTextIndex(block).text;
      if (text.slice(part.start, part.end) !== part.exact) return null;
      return { key: part.key, text, start: part.start, end: part.end };
    });
    if (parts.some((part) => !part) || !this.store.add(parts)) return false;
    this.repaint();
    return true;
  }

  schedule() {
    if (this.disposed || this.frame) return;
    this.frame = requestAnimationFrame(() => {
      this.frame = null;
      this.repaint();
    });
  }

  repaint() {
    if (!this.layer.isConnected) this.article.append(this.layer);
    const blocks = new Map(
      [...this.article.querySelectorAll("[data-reader-key]")].map((node) => [
        node.dataset.readerKey,
        logicalTextIndex(node),
      ]),
    );
    this.store.reconcile(new Map([...blocks].map(([key, index]) => [key, index.text])));
    const host = this.article.getBoundingClientRect();
    const lines = [];
    for (const mark of this.store.marks)
      for (const part of mark.fragments) {
        const index = blocks.get(part.key);
        if (!index || index.text !== part.text) continue;
        for (const range of rangesFor(index, part.start, part.end))
          for (const rect of range.getClientRects()) {
            if (rect.width <= 0 || rect.height <= 0) continue;
            const line = document.createElement("span");
            Object.assign(line.style, {
              left: `${rect.left - host.left}px`,
              top: `${rect.top - host.top + rect.height / 2}px`,
              width: `${rect.width}px`,
            });
            lines.push(line);
          }
      }
    this.layer.replaceChildren(...lines);
    this.changed();
  }
  dispose() {
    this.disposed = true;
    if (this.frame) cancelAnimationFrame(this.frame);
    this.resize.disconnect();
    window.removeEventListener("resize", this.resized);
    window.removeEventListener("storage", this.storageChanged);
    this.layer.remove();
    this.article.classList.remove("reader-review-host");
  }
}
