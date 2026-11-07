/** Side presentation requires real spare space, with a wider threshold on entry. */
export function panelPosition({ edge, anchor, viewport, side = false }) {
  const left = edge + 24;
  const available = viewport.right - 12 - left;
  if (available < 360 + (side ? 0 : 24)) return null;
  const width = Math.min(420, available);
  return { left, right: left + width, top: anchor.top, width };
}

/** Search bounded local whitespace; preserve a valid prior vertical offset. */
export function localPanelPosition({ edge, anchor, viewport, height, obstacles, previous }) {
  if (viewport.right < 960) return null;
  const width = Math.min(420, (viewport.right - 12 - edge) * 1.5);
  if (width < 360) return null;
  const left = edge - width / 3;
  const tops = [anchor.top, ...obstacles.flatMap((ink) => [ink.bottom + 8, ink.top - height - 8])];
  tops.sort((a, b) => Math.abs(a - anchor.top) - Math.abs(b - anchor.top));
  if (Number.isFinite(previous)) tops.unshift(anchor.top + previous);
  for (const top of new Set(tops)) {
    if (Math.abs(top - anchor.top) > 160) continue;
    const box = { left, right: left + width, top, bottom: top + height, width };
    if (!overlapsInk(box, obstacles)) return box;
  }
  return null;
}

export function overlapsInk(box, obstacles) {
  return obstacles.some((ink) =>
    box.left < ink.right + 8 && box.right > ink.left - 8 &&
    box.top < ink.bottom + 8 && box.bottom > ink.top - 8,
  );
}

export function documentInk(article) {
  const rectangles = [];
  const excluded = ".reader-chat,svg,script,style,mjx-assistive-mml,.flow-math-stage,[hidden]";
  const walker = document.createTreeWalker(article, NodeFilter.SHOW_TEXT);
  for (let node = walker.nextNode(); node; node = walker.nextNode()) {
    if (!node.data.trim() || node.parentElement.closest(excluded)) continue;
    const range = document.createRange();
    range.selectNodeContents(node);
    rectangles.push(...range.getClientRects());
  }
  for (const node of article.querySelectorAll(
    ".flow-math-view,math,.flow-equation-number,.flow-note,img,figure,table,.flow-canvas-view",
  )) {
    if (!node.closest(excluded)) rectangles.push(...node.getClientRects());
  }
  return rectangles.filter((box) => box.width > 0 && box.height > 0);
}
