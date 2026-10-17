// Mathematical reading order belongs to the source, not the layout renderer.
// A token can have several visual occurrences after line breaking. Bind every
// occurrence and reject missing text rather than guessing a quotation location.
const models = new WeakMap();
const markedSources = new WeakMap();
const excluded =
  "svg,script,style,nav,[data-flow-targets],.flow-math-accessible,mjx-assistive-mml,.flow-math-stage,.flow-math-status,.flow-canvas-status,.flow-canvas-markers,.flow-canvas-label-number";
const tokenTags = new Set(["mi", "mn", "mo", "mtext", "ms"]);
const ignorable = /[\u2061-\u2064\ufe00-\ufe0f]/u;
const spacing = /\s/u;
function glyphCharacter(character) {
  const code = character.codePointAt(0);
  // MathJax may encode the requested mathematical alphabet in Unicode instead
  // of CSS. Keep the original character in quotations; compare only its glyph
  // identity here. Do not broadly normalize symbols such as h-bar or fractions.
  return (code >= 0x1d400 && code <= 0x1d7ff) || "ℂℋℌℍℐℑℒℕℙℚℛℜℝℤℬℭℯℰℱℳℴℎ".includes(character)
    ? character.normalize("NFKD")
    : character;
}

function textNodes(root) {
  const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
    acceptNode: (node) =>
      node.parentElement.closest("svg,script,style,mjx-assistive-mml")
        ? NodeFilter.FILTER_REJECT
        : NodeFilter.FILTER_ACCEPT,
  });
  const result = [];
  for (let node = walker.nextNode(); node; node = walker.nextNode()) result.push(node);
  return result;
}

function units(nodes) {
  const result = [];
  for (const node of nodes) {
    let offset = 0;
    for (const character of node.data) {
      const end = offset + character.length;
      result.push({ character, start: [node, offset], end: [node, end] });
      offset = end;
    }
  }
  return result;
}

export function matchToken(expected, occurrences) {
  const source = [...expected];
  const significant = (items) =>
    items.filter((item) => !ignorable.test(item.character) && !spacing.test(item.character));
  const sourceText = source
    .filter((c) => !ignorable.test(c) && !spacing.test(c))
    .map(glyphCharacter)
    .join("");
  const normalized = (items) =>
    significant(items)
      .map((item) => glyphCharacter(item.character))
      .join("");
  // Some operators are deliberately repeated at a continuation. They are one
  // logical token, with several independently selectable/highlightable ranges.
  const copies =
    occurrences.length > 1 && occurrences.every((part) => normalized(part) === sourceText)
      ? occurrences
      : [occurrences.flat()];
  if (copies.some((copy) => normalized(copy) !== sourceText)) return null;
  const result = [];
  let cursor = 0;
  const visible = copies.map(significant);
  for (const character of source) {
    const ignored = ignorable.test(character) || spacing.test(character);
    const position = ignored ? Math.max(0, cursor - 1) : cursor++;
    const alternatives = visible.map((copy) => copy[position]).filter(Boolean);
    if (!alternatives.length && !ignored) return null;
    const point = alternatives.length ? { ...alternatives[0], alternatives } : null;
    for (let offset = 0; offset < character.length; offset++) result.push(point);
  }
  return result;
}

export class MathIdentity {
  constructor(math, prefix) {
    this.source = math;
    this.tokens = [];
    this.segments = [];
    this.marks = [];
    this.bound = false;
    const owners = new Map();
    const tokenNodes = [];
    for (const node of [math, ...math.querySelectorAll("*")]) {
      if (node.closest("svg")) continue;
      if (node.hasAttribute("data-flow-mark") || node.hasAttribute("data-flow-decoration")) {
        const id = `${prefix}-mark-${this.marks.length}`;
        node.dataset.flowMarkInstance = id;
        const mark = { id, source: node, model: this };
        this.marks.push(mark);
        markedSources.set(node, mark);
      }
      if (
        node.namespaceURI !== "http://www.w3.org/1998/Math/MathML" ||
        !tokenTags.has(node.localName)
      )
        continue;
      if (tokenNodes.some((parent) => parent.contains(node))) continue;
      tokenNodes.push(node);
      const id = `${prefix}-token-${this.tokens.length}`;
      node.dataset.flowToken = id;
      const nodes = textNodes(node);
      const token = {
        id,
        source: node,
        kind: node.localName,
        text: nodes.map((n) => n.data).join(""),
      };
      let offset = 0;
      for (const child of nodes) {
        owners.set(child, { token, offset });
        offset += child.data.length;
      }
      this.tokens.push(token);
    }
    for (const node of textNodes(math)) {
      this.segments.push({ text: node.data, source: node, ...owners.get(node) });
    }
    this.text = this.segments.map((segment) => segment.text).join("");
  }

  bind(root, { view = root } = {}) {
    const occurrences = new Map();
    const elements = new Map();
    for (const node of root.querySelectorAll("[data-flow-token]")) {
      if (node.closest("mjx-assistive-mml")) continue;
      const id = node.dataset.flowToken;
      if (!occurrences.has(id)) occurrences.set(id, []);
      occurrences.get(id).push(units(textNodes(node)));
      if (!elements.has(id)) elements.set(id, []);
      elements.get(id).push(node);
    }
    const errors = [];
    const bindings = new Map();
    for (const token of this.tokens) {
      const parts = occurrences.get(token.id) ?? [];
      let points = matchToken(token.text, parts);
      // Stretchy operators can be drawn from glyph pieces with no text node,
      // or use a glyph alias (e.g. | -> ∣). Their carried source token ID maps
      // the complete visual operator, not a guessed replacement character.
      const visible = elements.get(token.id) ?? [];
      const atomic =
        token.kind === "mo" && [...token.text].filter((c) => !ignorable.test(c)).length === 1;
      if (
        !points &&
        atomic &&
        visible.length &&
        visible.every((node) => node.getClientRects().length)
      ) {
        const alternatives = visible.map((node) => {
          const offset = [...node.parentNode.childNodes].indexOf(node);
          return { start: [node.parentNode, offset], end: [node.parentNode, offset + 1] };
        });
        points = Array.from({ length: token.text.length }, () => ({
          ...alternatives[0],
          alternatives,
        }));
      }
      bindings.set(token, points);
      if ((!parts.length && token.text) || !points)
        errors.push({
          token: token.id,
          kind: token.kind,
          expected: token.text,
          observed: parts.map((part) => part.map((unit) => unit.character).join("")),
          occurrences: parts.length,
        });
    }
    const fragments = new Map();
    for (const mark of this.marks) {
      fragments.set(
        mark,
        [...root.querySelectorAll(`[data-flow-mark-instance="${CSS.escape(mark.id)}"]`)].filter(
          (node) => !node.closest("mjx-assistive-mml"),
        ),
      );
      if (!fragments.get(mark).length) errors.push({ mark: mark.id });
    }
    // A rejected candidate must not invalidate the currently readable view.
    if (!errors.length) {
      for (const [token, points] of bindings) token.points = points;
      for (const [mark, nodes] of fragments) mark.fragments = nodes;
      this.bound = true;
      this.view = view;
      models.set(view, this);
    }
    return errors;
  }

  entries() {
    return this.segments.flatMap((segment) => {
      const points = segment.token?.points;
      return [...Array(segment.text.length)].map((_, offset) => ({
        character: segment.text[offset],
        point: points?.[segment.offset + offset] ?? null,
      }));
    });
  }
}

// Relationship records retain the authored node while a renderer replaces its
// presentation. Never collapse its line fragments to the first occurrence.
export function visualFragments(source) {
  const mark = markedSources.get(source);
  return mark?.model.bound ? mark.fragments : [source];
}

export function logicalTextIndex(block, { includeNested = false, includeNotes = false } = {}) {
  const entries = [];
  function visit(node) {
    if (node.nodeType === Node.TEXT_NODE) {
      for (let offset = 0; offset < node.data.length; offset++) {
        entries.push({
          character: node.data[offset],
          point: { start: [node, offset], end: [node, offset + 1] },
        });
      }
      return;
    }
    if (node.nodeType !== Node.ELEMENT_NODE) return;
    if (
      node.matches(excluded) ||
      (!includeNotes && node.matches(".flow-notes")) ||
      (!includeNested && node !== block && node.hasAttribute("data-reader-key"))
    )
      return;
    const model = models.get(node);
    if (model?.bound) entries.push(...model.entries());
    else for (const child of node.childNodes) visit(child);
  }
  visit(block);
  let text = "";
  const points = [];
  let space = null;
  let hasSpace = false;
  for (const { character, point } of entries) {
    if (/\s/.test(character)) {
      hasSpace = true;
      if (point) space = space ? { ...space, end: point.end } : point;
    } else {
      if (hasSpace && text) {
        text += " ";
        points.push(space);
      }
      space = null;
      hasSpace = false;
      text += character;
      points.push(point);
    }
  }
  return { text, points };
}

export function selectedIntervals(index, range) {
  const intervals = [];
  let start = -1;
  for (let i = 0; i <= index.points.length; i++) {
    const point = index.points[i];
    const selected =
      point &&
      (point.alternatives ?? [point]).some(
        (part) => range.comparePoint(...part.start) >= 0 && range.comparePoint(...part.end) <= 0,
      );
    if (selected && start < 0) start = i;
    if (!selected && start >= 0) {
      let end = i;
      while (start < end && index.text[start] === " ") start++;
      while (end > start && index.text[end - 1] === " ") end--;
      if (end > start) intervals.push([start, end]);
      start = -1;
    }
  }
  return intervals;
}

export function rangesFor(index, start, end) {
  const ranges = [];
  let previous;
  for (const point of index.points.slice(start, end)) {
    for (const part of point?.alternatives ?? (point ? [point] : [])) {
      if (
        previous &&
        previous.startContainer === part.start[0] &&
        previous.startOffset === part.start[1] &&
        previous.endContainer === part.end[0] &&
        previous.endOffset === part.end[1]
      )
        continue;
      if (previous?.endContainer === part.start[0] && previous.endOffset === part.start[1]) {
        previous.setEnd(...part.end);
      } else {
        previous = document.createRange();
        previous.setStart(...part.start);
        previous.setEnd(...part.end);
        ranges.push(previous);
      }
    }
  }
  return ranges;
}
