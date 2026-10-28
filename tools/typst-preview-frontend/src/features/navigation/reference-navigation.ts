import { ReferenceReturn } from "../../../../reader-common/navigation/reference-return.js";

export interface ReferenceOrigin {
  page: number;
  x: number;
  y: number;
  /** The point's vertical position within the scrollport before navigation. */
  viewportY?: number;
}

/** Capture the viewport relative to a page, independent of preview scale. */
export function captureReferenceOrigin(
  scroller: HTMLElement,
  root: HTMLElement,
  viewportY = 0,
): ReferenceOrigin | undefined {
  const viewport = scroller.getBoundingClientRect();
  const referenceY = viewport.top + (Number.isFinite(viewportY) ? viewportY : 0);
  let nearest: { origin: ReferenceOrigin; distance: number } | undefined;
  for (const page of root.querySelectorAll<SVGRectElement>(".typst-page-inner")) {
    const rect = page.getBoundingClientRect();
    const pageNumber = Number(page.getAttribute("data-page-number"));
    if (rect.width <= 0 || rect.height <= 0 || !Number.isSafeInteger(pageNumber)) continue;
    const distance = Math.max(rect.top - referenceY, referenceY - rect.bottom, 0);
    if (!nearest || distance < nearest.distance) {
      nearest = {
        origin: {
          page: pageNumber,
          x: (viewport.left - rect.left) / rect.width,
          y: (referenceY - rect.top) / rect.height,
          viewportY: Number.isFinite(viewportY) ? viewportY : 0,
        },
        distance,
      };
    }
  }
  return nearest?.origin;
}

/** Restore directly, including when the originating page is currently virtual. */
export function restoreReferenceOrigin(
  origin: ReferenceOrigin,
  scroller: HTMLElement,
  root: HTMLElement,
): boolean {
  const page = root.querySelector<SVGRectElement>(
    `.typst-page-inner[data-page-number="${origin.page}"]`,
  );
  if (!page) return false;
  const rect = page.getBoundingClientRect();
  if (rect.width <= 0 || rect.height <= 0) return false;
  const viewport = scroller.getBoundingClientRect();
  const viewportY = Number.isFinite(origin.viewportY) ? origin.viewportY! : 0;
  scroller.scrollTo({
    top: scroller.scrollTop + rect.top - viewport.top + origin.y * rect.height - viewportY,
    left: scroller.scrollLeft + rect.left - viewport.left + origin.x * rect.width,
    behavior: "instant",
  });
  return true;
}

/** The global renderer callback is used by internal links, not editor jumps. */
export class ReferenceNavigation {
  private references: ReferenceReturn<ReferenceOrigin>;
  private button = document.createElement("button");
  private previous = window.handleTypstLocation;
  private navigate: Window["handleTypstLocation"];
  private restoring?: { value: string; priority: string };
  private frame?: number;

  constructor(
    private scroller: HTMLElement,
    root: HTMLElement,
    actions: HTMLElement,
    onNavigate: () => void,
    onRestore: () => void,
  ) {
    this.button.type = "button";
    this.button.className = "typst-reference-back";
    this.button.textContent = navigator.language.startsWith("ko")
      ? "참조 위치로 돌아가기"
      : "Back to reference";
    this.references = new ReferenceReturn(this.button, (origin) => {
      // Populating a virtual page can otherwise make browser scroll anchoring
      // shift the viewport immediately after our explicit return.
      if (!this.restoring) {
        this.restoring = {
          value: scroller.style.getPropertyValue("overflow-anchor"),
          priority: scroller.style.getPropertyPriority("overflow-anchor"),
        };
      }
      scroller.style.setProperty("overflow-anchor", "none");
      if (restoreReferenceOrigin(origin, scroller, root)) onRestore();
      else this.finishRestore();
      this.references.consume(origin);
    });
    actions.appendChild(this.button);
    this.navigate = (element, page, x, y, targetViewportY) => {
      let destinationY = targetViewportY;
      if (
        root.contains(element) &&
        Number.isSafeInteger(page) &&
        page >= 1 &&
        Number.isFinite(x) &&
        Number.isFinite(y) &&
        root.querySelector(`.typst-page-inner[data-page-number="${page - 1}"]`)
      ) {
        const viewportY =
          element.getBoundingClientRect().top - scroller.getBoundingClientRect().top;
        destinationY = viewportY;
        const origin = captureReferenceOrigin(scroller, root, viewportY);
        if (origin) {
          this.finishRestore();
          this.references.remember(origin);
          onNavigate();
        }
      }
      this.previous(element, page, x, y, destinationY);
    };
    window.handleTypstLocation = this.navigate;
  }

  afterRender(): void {
    if (this.restoring && this.frame === undefined) {
      this.frame = requestAnimationFrame(() => this.finishRestore());
    }
  }

  private finishRestore(): void {
    if (this.frame !== undefined) cancelAnimationFrame(this.frame);
    this.frame = undefined;
    if (!this.restoring) return;
    if (this.restoring.value) {
      this.scroller.style.setProperty(
        "overflow-anchor",
        this.restoring.value,
        this.restoring.priority,
      );
    } else {
      this.scroller.style.removeProperty("overflow-anchor");
    }
    this.restoring = undefined;
  }

  dispose(): void {
    this.finishRestore();
    if (window.handleTypstLocation === this.navigate) {
      window.handleTypstLocation = this.previous;
    }
    this.references.dispose();
    this.button.remove();
  }
}
