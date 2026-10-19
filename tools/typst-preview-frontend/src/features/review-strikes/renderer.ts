import { ReviewMarks } from "./store";
import { previewPages } from "../selection/text-selection";

/** Paints page-native fragments; shared persistence never interprets coordinates. */
export class ReviewMarkRenderer {
  readonly store: ReviewMarks;
  private layer = document.createElement("div");

  constructor(private root: HTMLElement) {
    let storage: Storage | undefined;
    try {
      storage = window.localStorage;
    } catch {
      // Review controls retain in-memory use.
    }
    this.store = new ReviewMarks(storage);
    this.layer.className = "typst-review-marks";
    this.layer.setAttribute("aria-hidden", "true");
    root.classList.add("typst-review-host");
  }

  repaint() {
    // The renderer owns the first child and initializes an empty container.
    if (this.root.firstElementChild?.tagName !== "svg") return;
    if (!this.layer.isConnected) this.root.appendChild(this.layer);
    const pages = previewPages(this.root);
    this.store.reconcile(pages);
    const host = this.root.getBoundingClientRect();
    const lines: HTMLElement[] = [];
    for (const mark of this.store.marks)
      for (const fragment of mark.fragments) {
        const page = pages.get(fragment.page);
        if (!page?.fingerprint) continue;
        const line = document.createElement("span");
        const sx = page.rect.width / page.width,
          sy = page.rect.height / page.height;
        Object.assign(line.style, {
          left: `${page.rect.left - host.left + fragment.x * sx}px`,
          top: `${page.rect.top - host.top + (fragment.y + fragment.height * 0.5) * sy}px`,
          width: `${fragment.width * sx}px`,
        });
        lines.push(line);
      }
    this.layer.replaceChildren(...lines);
  }

  dispose() {
    this.layer.remove();
    this.root.classList.remove("typst-review-host");
  }
}
