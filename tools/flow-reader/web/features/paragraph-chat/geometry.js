/** Expanded capsules use paragraph-local whitespace, with at most 24px of margin spill. */
export function panelPosition({ edge, start = 0, anchor, viewport, height = 0, obstacles = [], previous }) {
  if (viewport.right < 960) return null;
  const right = Math.min(edge + 24, viewport.right - 12);
  const width = Math.min(420, right - start);
  if (width < 360) return null;
  const nearby = obstacles.filter((ink) => ink.bottom >= anchor.top - 160 - 8 &&
    ink.top <= anchor.top + 160 + height + 8);
  const gap = (box) => Math.hypot(
    Math.max(anchor.left - box.right, box.left - anchor.right, 0),
    Math.max(anchor.top - box.bottom, box.top - anchor.bottom, 0),
  );
  const boxAt = (left, top) => ({ left, right: left + width, top, bottom: top + height, width });
  const fits = (box) => box.left >= start && box.right <= right &&
    Math.abs(box.top - anchor.top) <= 160 && gap(box) <= 160 && !overlapsInk(box, nearby);
  if (previous) {
    const box = boxAt(anchor.left + previous.left, anchor.top + previous.top);
    if (fits(box)) return box;
  }
  const direct = boxAt(anchor.right + 16, anchor.top);
  if (fits(direct)) return direct;
  // Leave an extra pixel beyond the collision gap for browser subpixel rounding.
  const xs = [...new Set([anchor.right + 16, right - width,
    ...nearby.flatMap((ink) => [ink.right + 9, ink.left - width - 9])])]
    .filter((left) => left >= start && left + width <= right)
    .sort((a, b) => Math.abs(a - direct.left) - Math.abs(b - direct.left)).slice(0, 32);
  const ys = [...new Set([anchor.top,
    ...nearby.flatMap((ink) => [ink.bottom + 9, ink.top - height - 9])])]
    .filter((top) => Math.abs(top - anchor.top) <= 160)
    .sort((a, b) => Math.abs(a - anchor.top) - Math.abs(b - anchor.top)).slice(0, 32);
  const candidates = xs.flatMap((left) => ys.map((top) => boxAt(left, top)))
    .sort((a, b) => (gap(a) + Math.abs(a.top - anchor.top) * 0.1) -
      (gap(b) + Math.abs(b.top - anchor.top) * 0.1));
  return candidates.find(fits) || null;
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
  for (const marker of article.querySelectorAll(".reader-chat-marker"))
    rectangles.push(...marker.getClientRects());
  const toolbar = article.ownerDocument.querySelector(".reader-toolbar");
  if (toolbar) rectangles.push(...toolbar.getClientRects());
  return rectangles.filter((box) => box.width > 0 && box.height > 0);
}
