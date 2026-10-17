// Typst explicitly marks alignment scaffolding as multiline-equation. Matrices,
// cases, vectors, and nested tables are mathematical structures and stay intact.
const NS = "http://www.w3.org/1998/Math/MathML";

export function mathOverflow(
  root,
  { width = root.clientWidth, left = root.getBoundingClientRect().left } = {},
) {
  const rects = [...root.querySelectorAll("mjx-c,mjx-utext,mjx-stretchy-h,mjx-stretchy-v,svg")]
    .filter((node) => {
      if (node.closest("mjx-assistive-mml")) return false;
      // Stretched operators stencil overlapping glyph pieces. Their raw piece
      // rectangles extend past the visible bar/fence; measure its surface once.
      const stretch = node.closest("mjx-stretchy-h,mjx-stretchy-v");
      return !stretch || stretch === node;
    })
    .flatMap((node) => [...node.getClientRects()])
    .filter((rect) => rect.width && rect.height);
  return {
    left: Math.max(0, ...rects.map((rect) => left - rect.left)),
    right: Math.max(0, root.scrollWidth - width, ...rects.map((rect) => rect.right - left - width)),
  };
}

function attributes(from, to, omitted = []) {
  for (const attribute of from.attributes) {
    if (!omitted.includes(attribute.name)) to.setAttribute(attribute.name, attribute.value);
  }
}

export function promoteInlineMath(root) {
  for (const math of root.querySelectorAll("math")) {
    if (math.parentElement.closest("math") || math.getAttribute("display") === "block") continue;
    // Display controls the line-breaking context; displaystyle controls math
    // typography. Preserve the inline fraction/limit/script presentation.
    const displaystyle = math.getAttribute("displaystyle") ?? "false";
    math.setAttribute("displaystyle", displaystyle);
    const style = document.createElementNS(NS, "mstyle");
    style.setAttribute("displaystyle", displaystyle);
    style.append(...math.childNodes);
    math.append(style);
    math.setAttribute("display", "block");
  }
}

// Only enclosures backed by the original Typst paint callback may become
// breakable rows. Keep arbitrary menclose elements as mathematical structures.
export function prepareNativeDecorations(root) {
  for (const enclosure of root.querySelectorAll("menclose[data-flow-cancel]")) {
    const row = document.createElementNS(NS, "mrow");
    attributes(enclosure, row, ["notation"]);
    row.append(...enclosure.childNodes);
    enclosure.replaceWith(row);
  }
}

export function restoreNativeDecorations(root) {
  for (const row of root.querySelectorAll("mjx-assistive-mml mrow[data-flow-cancel]")) {
    const enclosure = document.createElementNS(NS, "menclose");
    attributes(row, enclosure);
    enclosure.setAttribute("notation", row.dataset.flowCancel);
    enclosure.append(...row.childNodes);
    row.replaceWith(enclosure);
  }
}

export function splitDerivations(root) {
  let count = 0;
  for (const math of [...root.querySelectorAll('math[display="block"]')]) {
    if (math.parentElement.closest("math")) continue;
    const children = [...math.children];
    if (children.length !== 1) continue;
    const table = children[0];
    if (table.localName !== "mtable" || !table.classList.contains("multiline-equation")) continue;
    if (table.closest("[data-flow-math-kind]")) continue;
    const rows = [...table.children];
    if (
      rows.some(
        (row) =>
          row.localName !== "mtr" ||
          [...row.children].some(
            (cell) =>
              cell.localName !== "mtd" ||
              Number(cell.getAttribute("rowspan") ?? 1) !== 1 ||
              Number(cell.getAttribute("columnspan") ?? 1) !== 1,
          ),
      )
    )
      continue;
    const group = document.createElement("div");
    group.className = "flow-derivation";
    if (math.id) group.id = math.id;
    rows.forEach((row, index) => {
      const line = document.createElementNS(NS, "math");
      attributes(math, line, ["id"]);
      line.dataset.flowDerivationRow = String(index);
      const style = document.createElementNS(NS, "mstyle");
      attributes(table, style, [
        "id",
        "class",
        "columnalign",
        "columnspacing",
        "rowspacing",
        "width",
      ]);
      const body = document.createElementNS(NS, "mrow");
      attributes(row, body);
      [...row.children].forEach((cell, column) => {
        // Each pair of alignment columns forms a clause. Extra clauses/notes
        // retain visible separation after removing fixed shared column widths.
        if (column >= 2 && column % 2 === 0 && cell.childNodes.length) {
          const gap = document.createElementNS(NS, "mspace");
          gap.setAttribute("width", "1em");
          body.append(gap);
        }
        const part = document.createElementNS(NS, "mrow");
        attributes(cell, part, ["columnalign", "rowalign", "columnspan", "rowspan"]);
        part.append(...cell.childNodes);
        body.append(part);
      });
      style.append(body);
      line.append(style);
      group.append(line);
    });
    if (table.id) {
      const anchor = document.createElement("span");
      anchor.id = table.id;
      group.prepend(anchor);
    }
    math.replaceWith(group);
    count++;
  }
  return count;
}
