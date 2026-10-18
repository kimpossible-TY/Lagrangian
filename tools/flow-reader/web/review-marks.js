// Temporary review marks follow canonical text, never the compiler or source.
import { logicalTextIndex, rangesFor } from "./math-identity.js";

const maximum = 100;
const maximumBytes = 1024 * 1024;

function validMark(mark) {
  return (
    Array.isArray(mark?.fragments) &&
    mark.fragments.length > 0 &&
    mark.fragments.length <= 32 &&
    mark.fragments.every(
      (part) =>
        typeof part.key === "string" &&
        part.key.length <= 128 &&
        typeof part.text === "string" &&
        part.text.length <= 200000 &&
        Number.isInteger(part.start) &&
        Number.isInteger(part.end) &&
        part.start >= 0 &&
        part.end > part.start &&
        part.end <= part.text.length,
    )
  );
}

export class ReviewMarkStore {
  constructor(storage) {
    this.storage = storage;
    this.marks = [];
  }

  setDocument(id) {
    const key = `flow-reader:${id}:strikes:v1`;
    if (key === this.key) return;
    this.key = key;
    this.marks = [];
    try {
      const raw = this.storage?.getItem(key);
      if (!raw || raw.length > maximumBytes) return;
      const records = JSON.parse(raw);
      if (Array.isArray(records) && records.length <= maximum && records.every(validMark))
        this.marks = records;
    } catch {
      /* Unavailable storage retains in-memory review. */
    }
  }

  add(fragments) {
    const mark = { fragments };
    if (!validMark(mark) || JSON.stringify(mark).length > maximumBytes) return false;
    this.marks.push(mark);
    this.marks = this.marks.slice(-maximum);
    this.save();
    return true;
  }

  undo() {
    this.marks.pop();
    this.save();
  }
  clear() {
    this.marks = [];
    this.save();
  }

  reconcile(blocks) {
    const before = this.marks.length;
    this.marks = this.marks.filter((mark) =>
      mark.fragments.every((part) => !blocks.has(part.key) || blocks.get(part.key) === part.text),
    );
    if (before !== this.marks.length) this.save();
  }

  save() {
    let value = JSON.stringify(this.marks);
    while (value.length > maximumBytes && this.marks.length) {
      this.marks.shift();
      value = JSON.stringify(this.marks);
    }
    try {
      this.storage?.setItem(this.key, value);
    } catch {
      /* Undo and clear remain usable without browser storage. */
    }
  }
}

export class ReaderReviewMarks {
  constructor(article, changed) {
    this.article = article;
    this.changed = changed;
    let storage;
    try {
      storage = localStorage;
    } catch {
      /* Memory still works. */
    }
    this.store = new ReviewMarkStore(storage);
    this.layer = document.createElement("div");
    this.layer.className = "reader-review-marks";
    this.layer.setAttribute("aria-hidden", "true");
    article.classList.add("reader-review-host");
    this.resize = new ResizeObserver(() => this.schedule());
    this.resize.observe(article);
    window.addEventListener("resize", () => this.schedule());
    window.addEventListener("storage", (event) => {
      if (event.key !== this.store.key && event.key !== null) return;
      const id = this.documentID;
      this.store.key = null;
      this.store.setDocument(id);
      this.repaint();
      this.changed();
    });
  }

  onDocument(id) {
    this.documentID = id;
    this.store.setDocument(id);
    this.schedule();
  }

  add(fragments) {
    const nodes = new Map(
      [...this.article.querySelectorAll("[data-reader-key]")].map((node) => [
        node.dataset.readerKey,
        node,
      ]),
    );
    const parts = fragments.map((part) => {
      const block = nodes.get(part.key);
      if (!block) return null;
      const text = logicalTextIndex(block).text;
      if (text.slice(part.start, part.end) !== part.exact) return null;
      return { key: part.key, text, start: part.start, end: part.end };
    });
    if (parts.some((part) => !part) || !this.store.add(parts)) return false;
    this.repaint();
    return true;
  }

  schedule() {
    if (this.frame) return;
    this.frame = requestAnimationFrame(() => {
      this.frame = null;
      this.repaint();
    });
  }

  repaint() {
    if (!this.layer.isConnected) this.article.append(this.layer);
    const blocks = new Map(
      [...this.article.querySelectorAll("[data-reader-key]")].map((node) => [
        node.dataset.readerKey,
        logicalTextIndex(node),
      ]),
    );
    this.store.reconcile(new Map([...blocks].map(([key, index]) => [key, index.text])));
    const host = this.article.getBoundingClientRect();
    const lines = [];
    for (const mark of this.store.marks)
      for (const part of mark.fragments) {
        const index = blocks.get(part.key);
        if (!index || index.text !== part.text) continue;
        for (const range of rangesFor(index, part.start, part.end))
          for (const rect of range.getClientRects()) {
            if (rect.width <= 0 || rect.height <= 0) continue;
            const line = document.createElement("span");
            Object.assign(line.style, {
              left: `${rect.left - host.left}px`,
              top: `${rect.top - host.top + rect.height / 2}px`,
              width: `${rect.width}px`,
            });
            lines.push(line);
          }
      }
    this.layer.replaceChildren(...lines);
    this.changed();
  }
}

export function sourceSegments(index, start, end) {
  const owner = (point) => {
    const node = point?.start[0];
    const element = node?.nodeType === Node.ELEMENT_NODE ? node : node?.parentElement;
    // Equation numbers belong to the surrounding block, not the mathematical
    // expression whose complete source must be selected.
    return (
      element?.closest(".flow-math-view,math") ??
      element?.closest(".flow-equation,.flow-inline-equation") ??
      null
    );
  };
  const groups = [];
  for (let i = start; i < end; i++) {
    const math = owner(index.points[i]);
    let group = groups.at(-1);
    if (!group || group.math !== math) groups.push((group = { math, start: i, end: i }));
    group.end = i + 1;
  }
  return groups.map((group) => {
    const text = index.text.slice(group.start, group.end);
    if (!group.math) return { text };
    const whole = logicalTextIndex(group.math).text;
    return { text, math: true, complete: text.trim() === whole.trim() };
  });
}
