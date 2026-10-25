// A touch selection inside composed mathematics starts on one painted glyph.
// Snap that boundary to the complete expression so the visible selection,
// source actions and copied text all refer to the same mathematical unit.
const excluded = "mjx-assistive-mml,.flow-math-stage";

export function mathSelectionUnit(point) {
  const node = point?.nodeType === 1 ? point : point?.parentElement;
  if (!node || node.closest(excluded)) return null;
  // The view owns the logical expression. A split derivation lives inside that
  // view, so the whole expression remains one selectable unit.
  return node.closest(".flow-math-view") ?? node.closest("math") ?? null;
}

function selectionUnits(article) {
  return [...article.querySelectorAll(".flow-math-view,math")].filter(
    (unit) =>
      !unit.closest(excluded) && !unit.parentElement?.closest(".flow-math-view,math"),
  );
}

/** Expand only boundaries that fall inside a mathematical expression. */
export function snapRangeToMath(range, article) {
  if (!range || range.collapsed) return false;
  let startUnit = null;
  let endUnit = null;
  for (const unit of selectionUnits(article)) {
    if (!range.intersectsNode(unit)) continue;
    const contents = document.createRange();
    contents.selectNodeContents(unit);
    const inside = (node, offset) => {
      try {
        return contents.comparePoint(node, offset) === 0;
      } catch {
        return false;
      }
    };
    if (!startUnit && inside(range.startContainer, range.startOffset)) startUnit = unit;
    if (!endUnit && inside(range.endContainer, range.endOffset)) endUnit = unit;
    if (startUnit === unit && endUnit === unit) break;
  }
  if (!startUnit && !endUnit) return false;
  if (startUnit) range.setStart(startUnit, 0);
  if (endUnit) range.setEnd(endUnit, endUnit.childNodes.length);
  return true;
}
