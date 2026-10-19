import { logicalTextIndex, selectedIntervals } from "../../rendering/math/identity.js";
import { sourceSegments } from "./source-segments.js";

const excluded = "svg,script,style,nav,.flow-notes,[data-flow-targets]";
export const textIndex = logicalTextIndex;

/** Resolve browser ranges to semantic blocks without exposing DOM state to shared policy. */
export function selectedReaderText(article, manifest, selection) {
  const range = selection.getRangeAt(0);
  const fragments = [];
  for (const block of article.querySelectorAll("[data-reader-key]")) {
    if (block.closest(excluded) || !range.intersectsNode(block)) continue;
    const index = textIndex(block);
    for (const [start, end] of selectedIntervals(index, range)) {
      fragments.push({
        key: block.dataset.readerKey,
        exact: index.text.slice(start, end),
        prefix: index.text.slice(Math.max(0, start - 64), start).trim(),
        suffix: index.text.slice(end, end + 64).trim(),
        start,
        end,
        revision: manifest.revision,
        service: manifest.service,
        segments: sourceSegments(index, start, end),
      });
    }
  }
  return fragments.length ? fragments : null;
}
