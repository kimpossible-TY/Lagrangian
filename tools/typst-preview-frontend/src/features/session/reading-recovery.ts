import {
  captureReferenceOrigin,
  restoreReferenceOrigin,
  type ReferenceOrigin,
} from "../navigation/reference-navigation";
import { previewPages } from "../selection/text-selection";

interface RenderedIdentity {
  document: string;
  revision: string;
}

/** Restore a full-frame replacement only against the same verified visible page. */
export class ReadingRecovery {
  private disposed = false;
  private rendered?: RenderedIdentity;
  private pending?: {
    identity: RenderedIdentity;
    origin: ReferenceOrigin;
    fingerprint: string;
  };
  private navigated = () => {
    this.pending = undefined;
  };

  constructor(
    private scroller: HTMLElement,
    private root: HTMLElement,
  ) {
    for (const event of ["pointerdown", "touchmove", "wheel"]) {
      scroller.addEventListener(event, this.navigated, { passive: true });
    }
    root.ownerDocument.addEventListener("keydown", this.navigated);
  }

  beforeReset() {
    this.pending = undefined;
    if (this.disposed || !this.rendered) return;
    const origin = captureReferenceOrigin(this.scroller, this.root);
    if (!origin) return;
    const page = previewPages(this.root).get(origin.page + 1);
    if (page?.fingerprint) {
      this.pending = { identity: this.rendered, origin, fingerprint: page.fingerprint };
    }
  }

  afterRender(document?: string, revision?: string): boolean {
    if (this.disposed) return false;
    const pending = this.pending;
    this.pending = undefined;
    this.rendered = document && revision ? { document, revision } : undefined;
    if (!pending || !this.rendered || pending.identity.document !== document) return false;
    // Engine revisions are process-local and can repeat after a restart. A
    // matching number alone never proves that old page coordinates still apply.
    // Conversely, an edit elsewhere may change the revision while this page is
    // unchanged. Its text and layout fingerprint remains the required guard.
    const page = previewPages(this.root).get(pending.origin.page + 1);
    if (page?.fingerprint !== pending.fingerprint) return false;
    return restoreReferenceOrigin(pending.origin, this.scroller, this.root);
  }

  dispose() {
    this.disposed = true;
    this.pending = this.rendered = undefined;
    for (const event of ["pointerdown", "touchmove", "wheel"]) {
      this.scroller.removeEventListener(event, this.navigated);
    }
    this.root.ownerDocument.removeEventListener("keydown", this.navigated);
  }
}
