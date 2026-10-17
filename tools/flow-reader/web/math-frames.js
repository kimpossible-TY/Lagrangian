const NS = "http://www.w3.org/1998/Math/MathML";
const bars = new Set(["⎴", "⎵", "⏞", "⏟", "¯", "̅", "̲"]);
const pairs = new Map([
  ["(", ")"],
  ["[", "]"],
  ["{", "}"],
  ["‖", "‖"],
  ["|", "|"],
  ["⟨", "⟩"],
]);

function decoration(node) {
  if (!["mover", "munder"].includes(node.localName)) return false;
  const [base, accent] = node.children;
  return (accent?.localName === "mo" && bars.has(accent.textContent)) || (base && decoration(base));
}

function box(node, width) {
  const wrapper = document.createElementNS(NS, "mpadded");
  if (width) {
    wrapper.setAttribute("data-overflow", "linebreak");
    wrapper.setAttribute("width", width);
  }
  node.replaceWith(wrapper);
  wrapper.append(node);
}

function productBreaks(root) {
  const factors = new Set([
    "mi",
    "mn",
    "mfrac",
    "msqrt",
    "mroot",
    "msup",
    "msub",
    "msubsup",
    "mrow",
    "mover",
    "munder",
    "munderover",
    "mpadded",
  ]);
  let count = 0;
  for (const row of [root, ...root.querySelectorAll("math,mrow,mstyle")]) {
    if (
      !["math", "mrow", "mstyle"].includes(row.localName) ||
      row.closest("mpadded:not([data-overflow])")
    )
      continue;
    const children = [...row.children];
    for (let index = 1; index < children.length; index++) {
      const previous = children[index - 1];
      const next = children[index];
      if (!factors.has(previous.localName) || !factors.has(next.localName)) continue;
      let head = previous;
      while (["msup", "msub", "msubsup"].includes(head.localName)) head = head.firstElementChild;
      const opening =
        next.localName === "mpadded"
          ? next.firstElementChild?.firstElementChild
          : next.firstElementChild;
      if (
        head.localName === "mi" &&
        opening?.localName === "mo" &&
        ["(", "["].includes(opening.textContent)
      )
        continue;
      const gap = document.createElementNS(NS, "mspace");
      gap.setAttribute("width", "0em");
      gap.setAttribute("linebreak", "badbreak");
      next.before(gap);
      count++;
    }
  }
  return count;
}

// A fraction or a spanning brace is atomic to the outer line breaker. Give
// only its wide children an explicit inner line-breaking context. Keep the
// operator tree, scripts, labels, and token identities in their original order.
export class MathFrames {
  constructor(source) {
    for (const node of source.querySelectorAll("*")) {
      for (const name of ["part", "atom", "table", "fence", "script", "scripts"])
        node.removeAttribute(`data-flow-frame-${name}`);
    }
    this.parts = new Map();
    this.atoms = new Map();
    this.tables = new Map();
    this.fences = new Map();
    this.scripts = new Map();
    for (const node of source.querySelectorAll("msqrt,mtd")) {
      if (node.children.length === 1 && node.firstElementChild.localName === "mrow") continue;
      const row = document.createElementNS(NS, "mrow");
      row.append(...node.childNodes);
      node.append(row);
    }
    for (const table of source.querySelectorAll("mtable")) {
      const id = String(this.tables.size);
      table.dataset.flowFrameTable = id;
      this.tables.set(id, table);
      const first = table.previousElementSibling;
      const last = table.nextElementSibling;
      if (
        table.closest('[data-flow-math-kind="matrix"]') &&
        first?.localName === "mo" &&
        last?.localName === "mo" &&
        pairs.get(first.textContent) === last.textContent
      ) {
        for (const [side, node] of [first, last].entries()) {
          const key = `${id}-${side}`;
          node.dataset.flowFrameFence = key;
          this.fences.set(key, node);
        }
      }
    }
    for (const node of source.querySelectorAll(
      "mfrac,mover,munder,msup,msub,msubsup,msqrt,mroot,mtd",
    )) {
      let children = [];
      if (node.localName === "mfrac") children = [...node.children];
      else if (decoration(node)) {
        children = [...node.children].filter(
          (child, index) => index === 0 || child.localName !== "mo",
        );
      } else if (["msup", "msub", "msubsup"].includes(node.localName)) {
        children = [node.firstElementChild];
        const scriptIDs = [];
        for (const script of [...node.children].slice(1)) {
          const key = String(this.scripts.size);
          script.dataset.flowFrameScript = key;
          this.scripts.set(key, script);
          scriptIDs.push(key);
        }
        node.firstElementChild.dataset.flowFrameScripts = scriptIDs.join(",");
      } else if (["msqrt", "mroot", "mtd"].includes(node.localName)) {
        children = [node.firstElementChild];
      }
      for (const child of children) {
        if (!child || child.hasAttribute("data-flow-frame-part")) continue;
        const id = String(this.parts.size);
        child.dataset.flowFramePart = id;
        this.parts.set(id, child);
      }
    }
    for (const row of source.querySelectorAll("mrow")) {
      const first = row.firstElementChild;
      const last = row.lastElementChild;
      if (
        first?.localName !== "mo" ||
        last?.localName !== "mo" ||
        pairs.get(first.textContent) !== last.textContent
      )
        continue;
      const id = String(this.atoms.size);
      row.dataset.flowFrameAtom = id;
      this.atoms.set(id, row);
    }
    this.source = source.cloneNode(true);
  }

  measure(rendered) {
    const measured = (attribute) => {
      const result = new Map();
      for (const node of rendered.querySelectorAll(`[${attribute}]`)) {
        if (node.closest("mjx-assistive-mml")) continue;
        const id = node.getAttribute(attribute);
        const rect = node.getBoundingClientRect();
        const previous = result.get(id);
        result.set(id, {
          width: (previous?.width ?? 0) + rect.width,
          font: parseFloat(getComputedStyle(node).fontSize),
        });
      }
      return result;
    };
    this.measurements = measured("data-flow-frame-part");
    this.atomMeasurements = measured("data-flow-frame-atom");
    this.tableMeasurements = measured("data-flow-frame-table");
    this.fenceMeasurements = measured("data-flow-frame-fence");
    this.scriptMeasurements = measured("data-flow-frame-script");
  }

  compose(width) {
    const root = this.source.cloneNode(true);
    let count = 0;
    for (const table of root.querySelectorAll("[data-flow-frame-table]")) {
      const measured = this.tableMeasurements.get(table.dataset.flowFrameTable);
      if (!measured || measured.width <= width || !table.closest('[data-flow-math-kind="matrix"]'))
        continue;
      table.setAttribute("columnspacing", "0.1em");
      table.setAttribute("rowspacing", "0.1em");
      for (const side of [0, 1]) {
        const key = `${table.dataset.flowFrameTable}-${side}`;
        const fence = root.querySelector(`[data-flow-frame-fence="${key}"]`);
        const size = this.fenceMeasurements.get(key);
        if (!fence || !size || size.font <= 0) continue;
        // Tall matrix parentheses need less horizontal curvature on a phone.
        // Only their geometry changes; entries keep the selected math font.
        fence.setAttribute("mathsize", "60%");
      }
      count++;
    }
    for (const node of root.querySelectorAll("[data-flow-frame-part]")) {
      const measured = this.measurements.get(node.dataset.flowFramePart);
      const scriptWidth = Math.max(
        0,
        ...(node.dataset.flowFrameScripts?.split(",") ?? []).map(
          (key) => this.scriptMeasurements.get(key)?.width ?? 0,
        ),
      );
      const budget = Math.max(measured?.font ?? 0, width - scriptWidth);
      if (!measured || measured.width <= budget || measured.font <= 0) continue;
      // MathJax calibrates ems to the actual math/script font, not body CSS ems.
      box(node, `${budget / measured.font}em`);
      count++;
    }
    for (const node of root.querySelectorAll("[data-flow-frame-atom]")) {
      const measured = this.atomMeasurements.get(node.dataset.flowFrameAtom);
      if (!measured || measured.width > width) continue;
      // A short norm/interval stays intact inside a multi-line structured body.
      box(node);
    }
    count += productBreaks(root);
    return count ? root : null;
  }
}
