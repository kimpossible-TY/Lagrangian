/** Find actual empty ink space near the paragraph at the exact one-third crossing. */
export function bubblePosition({ edge, width, height, paragraph, viewport, obstacles }) {
  const left = edge - width / 3;
  const right = edge + (2 * width) / 3;
  if (viewport.right - right < 12 || left < viewport.left + 12) return null;
  const near = { top: paragraph.top - 12, bottom: paragraph.bottom + 48 };
  const candidates = [
    ...new Set([
      paragraph.top,
      paragraph.bottom - height,
      ...obstacles.flatMap((box) => [box.bottom + 5, box.top - height - 5]),
    ]),
  ]
    .filter((top) => top >= near.top && top + height <= near.bottom)
    .sort((a, b) => Math.abs(a - paragraph.top) - Math.abs(b - paragraph.top));
  for (const top of candidates) {
    const box = { left, right, top, bottom: top + height };
    if (
      !obstacles.some(
        (ink) =>
          box.left < ink.right + 3 &&
          box.right > ink.left - 3 &&
          box.top < ink.bottom + 3 &&
          box.bottom > ink.top - 3,
      )
    )
      return box;
  }
  return null;
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
