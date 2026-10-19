import { BoundedReviewStore } from "../../reader-common/review-strikes/bounded-store.js";

function validMark(mark) {
  return (
    Array.isArray(mark?.fragments) &&
    mark.fragments.length > 0 &&
    mark.fragments.length <= 32 &&
    mark.fragments.every(
      (part) =>
        typeof part.key === "string" &&
        part.key.length <= 128 &&
        typeof part.text === "string" &&
        part.text.length <= 200000 &&
        Number.isInteger(part.start) &&
        Number.isInteger(part.end) &&
        part.start >= 0 &&
        part.end > part.start &&
        part.end <= part.text.length,
    )
  );
}

/** HTML text validation and invalidation around shared persistence policy. */
export class ReviewMarkStore extends BoundedReviewStore {
  constructor(storage) {
    super(storage, (id) => `flow-reader:${id}:strikes:v1`, validMark);
  }

  add(fragments) {
    return super.add({ fragments });
  }

  reconcile(blocks) {
    super.reconcile((mark) =>
      mark.fragments.every((part) => !blocks.has(part.key) || blocks.get(part.key) === part.text),
    );
  }
}
