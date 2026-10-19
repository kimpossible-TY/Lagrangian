import { BoundedReviewStore } from "../../../../reader-common/review-strikes/bounded-store.js";
import type { SelectedText, TextFragment } from "../selection/text-selection";

export interface ReviewMark {
  fragments: TextFragment[];
  fingerprints: Record<number, string>;
}

/** Page geometry and invalidation around shared browser-local persistence. */
export class ReviewMarks {
  private store: BoundedReviewStore<ReviewMark>;
  constructor(storage?: Pick<Storage, "getItem" | "setItem">) {
    this.store = new BoundedReviewStore(storage, (id) => `tinymist-review-v1:${id}`, validMark);
  }

  get marks() {
    return this.store.marks;
  }

  setDocument(id: string) {
    this.store.setDocument(id);
  }

  add(selection: SelectedText) {
    return this.store.add({ fragments: selection.fragments, fingerprints: selection.fingerprints });
  }

  undo() {
    this.store.undo();
  }

  clear() {
    this.store.clear();
  }

  /** Virtualized pages are unknown, not changed. */
  reconcile(pages: Map<number, { fingerprint: string }>) {
    this.store.reconcile((mark) =>
      Object.entries(mark.fingerprints).every(([page, fingerprint]) => {
        const current = pages.get(Number(page))?.fingerprint;
        return !current || current === fingerprint;
      }),
    );
  }
}

function validMark(mark: unknown): mark is ReviewMark {
  if (!mark || typeof mark !== "object") return false;
  const value = mark as ReviewMark;
  return (
    Array.isArray(value.fragments) &&
    value.fragments.length > 0 &&
    value.fragments.length <= 256 &&
    !!value.fingerprints &&
    typeof value.fingerprints === "object" &&
    value.fragments.every(
      (fragment) =>
        Number.isInteger(fragment.page) &&
        fragment.page > 0 &&
        [fragment.x, fragment.y, fragment.width, fragment.height].every(Number.isFinite) &&
        fragment.x >= 0 &&
        fragment.y >= 0 &&
        fragment.width > 0 &&
        fragment.height > 0 &&
        typeof value.fingerprints[fragment.page] === "string",
    )
  );
}
