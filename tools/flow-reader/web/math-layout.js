// Typst explicitly marks alignment scaffolding as multiline-equation. Matrices,
// cases, vectors, and nested tables are mathematical structures and stay intact.
const NS = "http://www.w3.org/1998/Math/MathML";

function attributes(from, to, omitted = []) {
  for (const attribute of from.attributes) {
    if (!omitted.includes(attribute.name)) to.setAttribute(attribute.name, attribute.value);
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
