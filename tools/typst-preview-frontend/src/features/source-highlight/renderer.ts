import { OptimisticHighlights } from "../../../../reader-common/source-highlight/optimistic.js";
import { previewPages, type SelectedText } from "../selection/text-selection";

/** Temporary fragments stay in page units and require the original text layout. */
export class SourceHighlightRenderer {
  readonly highlights = new OptimisticHighlights<SelectedText>((selections) =>
    this.paint(selections),
  );
  private layer = document.createElement("div");

  constructor(private root: HTMLElement) {
    this.layer.className = "reader-optimistic-highlights";
    this.layer.setAttribute("aria-hidden", "true");
  }

  private paint(selections: SelectedText[]) {
    if (!selections.length) {
      this.layer.remove();
      return;
    }
    const pages = previewPages(this.root);
    const host = this.root.getBoundingClientRect();
    const marks: HTMLElement[] = [];
    for (const selected of selections)
      for (const fragment of selected.fragments) {
        const page = pages.get(fragment.page);
        if (!page || page.fingerprint !== selected.fingerprints[fragment.page]) continue;
        const mark = document.createElement("span");
        const sx = page.rect.width / page.width;
        const sy = page.rect.height / page.height;
        Object.assign(mark.style, {
          left: `${page.rect.left - host.left + fragment.x * sx}px`,
          top: `${page.rect.top - host.top + fragment.y * sy}px`,
          width: `${fragment.width * sx}px`,
          height: `${fragment.height * sy}px`,
        });
        marks.push(mark);
      }
    this.layer.replaceChildren(...marks);
    if (!this.layer.isConnected) this.root.appendChild(this.layer);
  }

  dispose() {
    this.highlights.dispose();
  }
}
