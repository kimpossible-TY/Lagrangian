/** Bounded browser-local review persistence; renderers own record validation. */
export class BoundedReviewStore {
  constructor(storage, keyForDocument, validMark) {
    this.storage = storage;
    this.keyForDocument = keyForDocument;
    this.validMark = validMark;
    this.marks = [];
  }

  setDocument(id) {
    const key = this.keyForDocument(id);
    if (key === this.key) return;
    this.key = key;
    this.reload();
  }

  reload() {
    this.marks = [];
    try {
      const raw = this.storage?.getItem(this.key);
      if (!raw || raw.length > maximumBytes) return;
      const saved = JSON.parse(raw);
      if (Array.isArray(saved) && saved.length <= maximumMarks && saved.every(this.validMark))
        this.marks = saved;
    } catch {
      // Unavailable or corrupt storage retains in-memory review controls.
    }
  }

  add(mark) {
    if (!this.validMark(mark) || JSON.stringify(mark).length > maximumBytes) return false;
    this.marks.push(mark);
    this.marks = this.marks.slice(-maximumMarks);
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

  reconcile(keep) {
    const before = this.marks.length;
    this.marks = this.marks.filter(keep);
    if (before !== this.marks.length) this.save();
  }

  save() {
    let value = JSON.stringify(this.marks);
    while (value.length > maximumBytes && this.marks.length) {
      this.marks.shift();
      value = JSON.stringify(this.marks);
    }
    if (!this.key) return;
    try {
      this.storage?.setItem(this.key, value);
    } catch {
      // Undo and clear remain usable when storage is blocked or full.
    }
  }
}

const maximumMarks = 100;
const maximumBytes = 1024 * 1024;
