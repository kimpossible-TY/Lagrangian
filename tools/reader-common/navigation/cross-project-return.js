export const CROSS_PROJECT_RETURN_KEY = "lagrangian:cross-project-return:v1";
export const CROSS_PROJECT_PENDING_KEY = "lagrangian:cross-project-pending:v1";

/** A canonical origin-relative URL, never a network path or executable URL. */
export function isReturnPath(path) {
  if (typeof path !== "string" || !path.startsWith("/") || path.startsWith("//")) return false;
  if (path.includes("\\") || /\s/u.test(path) ||
    [...path].some((char) => char.codePointAt(0) < 32 || char.codePointAt(0) === 127)) return false;
  try {
    decodeURI(path);
    const url = new URL(path, "https://reader.invalid");
    const pathname = path.split(/[?#]/u)[0];
    return url.origin === "https://reader.invalid" && url.pathname === pathname &&
      !/%(?:2f|5c|2e|0[0-9a-f]|1[0-9a-f]|7f)/iu.test(pathname);
  } catch {
    return false;
  }
}

function entryCopy(value) {
  if (!value || !isReturnPath(value.path) || typeof value.documentTitle !== "string" ||
      typeof value.sectionId !== "string" || !value.sectionId ||
      !(value.anchor === null || typeof value.anchor === "string") ||
      !Number.isFinite(value.scrollOffset)) return null;
  const { path, documentTitle, sectionId, anchor, scrollOffset } = value;
  return { path, documentTitle, sectionId, anchor, scrollOffset };
}

/** Storage failures never commit an in-memory mutation which a new page would lose. */
export class CrossProjectReturnStack {
  constructor({ storage = null, maxDepth = 32 } = {}) {
    this.storage = storage;
    this.maxDepth = Number.isInteger(maxDepth) ? Math.max(0, Math.min(32, maxDepth)) : 32;
    this.reload();
  }

  /** A bfcache page must reread state changed by other full-page documents. */
  reload() {
    const saved = this.read(CROSS_PROJECT_RETURN_KEY);
    this.entries = saved?.version === 1 && Array.isArray(saved.entries) &&
      saved.entries.every((entry) => entryCopy(entry))
      ? saved.entries.map(entryCopy).slice(-this.maxDepth) : [];
    if (!this.maxDepth) this.entries = [];
    if (saved !== null && (!Array.isArray(saved.entries) || saved.version !== 1 ||
      saved.entries.some((entry) => !entryCopy(entry)))) this.remove(CROSS_PROJECT_RETURN_KEY);
  }

  read(key) {
    try {
      const raw = this.storage?.getItem(key);
      if (raw == null) return null;
      const value = JSON.parse(raw);
      if (!value || typeof value !== "object" || Array.isArray(value)) {
        this.remove(key);
        return null;
      }
      return value;
    } catch {
      this.remove(key);
      return null;
    }
  }

  write(key, value) {
    try {
      this.storage?.setItem(key, JSON.stringify(value));
      return true;
    } catch {
      return false;
    }
  }

  remove(key) {
    try {
      this.storage?.removeItem(key);
      return true;
    } catch {
      return false;
    }
  }

  commit(entries) {
    if (!this.write(CROSS_PROJECT_RETURN_KEY, { version: 1, entries })) return false;
    this.entries = entries;
    return true;
  }

  push(value) {
    const entry = entryCopy(value);
    if (!entry || !this.maxDepth) return false;
    return this.commit([...this.entries, entry].slice(-this.maxDepth));
  }

  pop() {
    const entry = this.peek();
    return entry && this.commit(this.entries.slice(0, -1)) ? entry : null;
  }

  peek() { return this.entries.length ? entryCopy(this.entries.at(-1)) : null; }
  get canGoBack() { return this.entries.length > 0; }
  clear() {
    if (!this.remove(CROSS_PROJECT_RETURN_KEY)) return false;
    this.entries = [];
    return true;
  }

  savePending(value, transitionId) {
    const entry = entryCopy(value);
    if (!entry || typeof transitionId !== "string" || !transitionId) return false;
    return this.write(CROSS_PROJECT_PENDING_KEY, { version: 1, transitionId, entry });
  }

  peekPending(path) {
    const record = this.read(CROSS_PROJECT_PENDING_KEY);
    if (!record) return null;
    const entry = entryCopy(record.entry);
    if (record.version !== 1 || !entry || typeof record.transitionId !== "string" ||
      !record.transitionId) {
      this.remove(CROSS_PROJECT_PENDING_KEY);
      return null;
    }
    return entry.path === path ? { version: 1, transitionId: record.transitionId, entry } : null;
  }

  consumePending(path, transitionId) {
    const record = this.peekPending(path);
    return record?.transitionId === transitionId && this.remove(CROSS_PROJECT_PENDING_KEY)
      ? record.entry : null;
  }
}
