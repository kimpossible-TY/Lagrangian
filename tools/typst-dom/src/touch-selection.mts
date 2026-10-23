/** Only a real range in the mobile HTML overlay holds rendering. */
export function hasTouchSelection(root: Element, selection = root.ownerDocument.getSelection()) {
  if (!selection || selection.isCollapsed) return false;
  const overlay = root.querySelector(":scope > .typst-touch-selection");
  return (
    !!overlay && (overlay.contains(selection.anchorNode) || overlay.contains(selection.focusNode))
  );
}

/** Retain desktop SVG text ranges as well as mobile overlay ranges during updates. */
export function hasPreviewSelection(root: Element, selection = root.ownerDocument.getSelection()) {
  if (!selection || selection.isCollapsed) return false;
  if (hasTouchSelection(root, selection)) return true;
  const isText = (node: Node | null) => {
    if (!node || !root.contains(node)) return false;
    const element = node.nodeType === 1 ? (node as Element) : node.parentElement;
    return Boolean(element?.closest(".tsel"));
  };
  return isText(selection.anchorNode) || isText(selection.focusNode);
}
