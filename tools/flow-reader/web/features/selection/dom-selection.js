import { logicalTextIndex, selectedIntervals } from "../../rendering/math/identity.js";
import { sourceSegments } from "./source-segments.js";

const excluded = "svg,script,style,nav,.flow-notes,.reader-chat,[data-flow-targets]";
export const textIndex = logicalTextIndex;

function insideSurrogatePair(text, offset) {
  const before = text.charCodeAt(offset - 1);
  const after = text.charCodeAt(offset);
  return before >= 0xd800 && before <= 0xdbff && after >= 0xdc00 && after <= 0xdfff;
}

/** Resolve browser ranges to semantic blocks without exposing DOM state to shared policy. */
export function selectedReaderText(article, manifest, range) {
  const fragments = [];
  for (const block of article.querySelectorAll("[data-reader-key]")) {
    if (block.closest(excluded) || !range.intersectsNode(block)) continue;
    const index = textIndex(block);
    for (const [rangeStart, rangeEnd] of selectedIntervals(index, range)) {
      const start = insideSurrogatePair(index.text, rangeStart) ? rangeStart - 1 : rangeStart;
      const end = insideSurrogatePair(index.text, rangeEnd) ? rangeEnd + 1 : rangeEnd;
      let before = Math.max(0, start - 64);
      let after = Math.min(index.text.length, end + 64);
      if (insideSurrogatePair(index.text, before)) before++;
      if (insideSurrogatePair(index.text, after)) after--;
      fragments.push({
        key: block.dataset.readerKey,
        exact: index.text.slice(start, end),
        prefix: index.text.slice(before, start).trim(),
        suffix: index.text.slice(end, after).trim(),
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
