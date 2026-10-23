import { OptimisticHighlights } from "../../reader-common/source-highlight/optimistic.js";
import { logicalTextIndex, rangesFor } from "../../rendering/math/identity.js";
import { sourceHighlightSnapshot } from "./controller.js";

/** Semantic offsets are resolved again after reflow, without changing document text. */
export class SourceHighlightRenderer {
  constructor(article) {
    this.article = article;
    this.layer = document.createElement("div");
    this.layer.className = "reader-optimistic-highlights";
    this.layer.setAttribute("aria-hidden", "true");
    this.highlights = new OptimisticHighlights((selections) => this.paint(selections));
    this.resize = new ResizeObserver(() => this.highlights.repaint());
    this.resize.observe(article);
  }

  onDocument(manifest) {
    this.highlights.onDocument(sourceHighlightSnapshot(manifest));
  }

  paint(selections) {
    if (!selections.length) {
      this.layer.remove();
      return;
    }
    const host = this.article.getBoundingClientRect();
    const blocks = new Map(
      [...this.article.querySelectorAll("[data-reader-key]")].map((node) => [
        node.dataset.readerKey,
        logicalTextIndex(node),
      ]),
    );
    const marks = [];
    for (const selected of selections)
      for (const part of selected) {
        const index = blocks.get(part.key);
        if (!index || index.text.slice(part.start, part.end) !== part.exact) continue;
        for (const range of rangesFor(index, part.start, part.end))
          for (const rect of range.getClientRects()) {
            if (rect.width <= 0 || rect.height <= 0) continue;
            const mark = document.createElement("span");
            Object.assign(mark.style, {
              left: `${rect.left - host.left}px`,
              top: `${rect.top - host.top}px`,
              width: `${rect.width}px`,
              height: `${rect.height}px`,
            });
            marks.push(mark);
          }
      }
    this.layer.replaceChildren(...marks);
    if (!this.layer.isConnected) this.article.append(this.layer);
  }

  dispose() {
    this.resize.disconnect();
    this.highlights.dispose();
  }
}
