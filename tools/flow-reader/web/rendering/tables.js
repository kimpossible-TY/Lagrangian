// Retain the original table, cells and mathematical nodes. Column hints are CSS
// generated text, so they cannot duplicate source quotations or mathematical IDs.
const headerNames = new Set([
  "name",
  "feature",
  "constant",
  "symbol",
  "aspect",
  "type",
  "property",
  "parameter",
  "quantity",
  "method",
  "term",
  "description",
  "이름",
  "항목",
  "기호",
  "설명",
  "분류",
]);
let serial = 0;

function prose(cell) {
  const copy = cell.cloneNode(true);
  copy.querySelectorAll("math,svg,[data-flow-targets]").forEach((node) => node.remove());
  return copy.textContent
    .replace(/\(\s*\)/g, "")
    .replace(/\s+/g, " ")
    .replace(/^\s*[:;,]+\s*/, "")
    .trim();
}

export function prepareResponsiveTables(root) {
  for (const table of root.querySelectorAll("table")) {
    if (table.dataset.readerTable) continue;
    table.dataset.readerTable = "stacked";
    table.classList.add("flow-table");
    table.setAttribute("role", "table");
    const rows = [...table.rows];
    if (!rows.length || !rows[0].cells.length) continue;
    const number = ++serial;
    const explicit = new Set(table.tHead ? [...table.tHead.rows] : []);
    if (!explicit.size && [...rows[0].cells].every((cell) => cell.tagName === "TH"))
      explicit.add(rows[0]);
    const inferred =
      !explicit.size && rows.length > 1 && headerNames.has(prose(rows[0].cells[0]).toLowerCase());
    const headerRows = explicit.size ? explicit : new Set(inferred ? [rows[0]] : []);
    table.dataset.readerTableHeaders = explicit.size ? "explicit" : inferred ? "inferred" : "none";
    const occupied = [],
      columns = [];
    const mapped = rows.map((row, r) => {
      row.setAttribute("role", "row");
      let column = 0;
      return [...row.cells].map((cell, c) => {
        while ((occupied[column] ?? 0) > r) column++;
        const start = column,
          span = Math.max(1, cell.colSpan);
        for (let i = start; i < start + span; i++) occupied[i] = r + Math.max(1, cell.rowSpan);
        column += span;
        cell.setAttribute("aria-colindex", start + 1);
        if (span > 1) cell.setAttribute("aria-colspan", span);
        if (cell.rowSpan > 1) cell.setAttribute("aria-rowspan", cell.rowSpan);
        if (headerRows.has(row)) {
          cell.id ||= `reader-table-${number}-header-${r}-${c}`;
          cell.setAttribute("role", "columnheader");
          for (let i = start; i < start + span; i++) {
            columns[i] ??= [];
            columns[i].push({ id: cell.id, text: prose(cell) });
          }
        }
        return { cell, start, span, row };
      });
    });
    for (const cells of mapped)
      for (const { cell, start, span, row } of cells) {
        if (headerRows.has(row)) {
          row.classList.add("flow-table-headings");
          continue;
        }
        cell.setAttribute("role", headerRows.size && start === 0 ? "rowheader" : "cell");
        const headers = [
          ...new Map(
            columns
              .slice(start, start + span)
              .flat()
              .filter(Boolean)
              .map((header) => [header.id, header]),
          ).values(),
        ];
        if (headers.length)
          cell.setAttribute("headers", headers.map((header) => header.id).join(" "));
        if (!headerRows.size || start > 0) {
          const names = [...new Set(headers.map((header) => header.text).filter(Boolean))];
          cell.dataset.readerColumnLabel = names.join(" / ") || `열 ${start + 1}`;
        }
      }
    table.setAttribute(
      "aria-colcount",
      Math.max(...mapped.flat().map(({ start, span }) => start + span)),
    );
    table.setAttribute("aria-rowcount", rows.length);
    table
      .querySelectorAll(":scope > thead,:scope > tbody,:scope > tfoot")
      .forEach((group) => group.setAttribute("role", "rowgroup"));
  }
}
