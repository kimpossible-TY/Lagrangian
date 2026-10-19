/** Browser-local document preferences, retaining the existing storage namespace. */
export class DocumentStorage {
  constructor(key) {
    this.key = key;
  }
  read(key, fallback) {
    try {
      return JSON.parse(localStorage.getItem(`${this.key}:${key}`)) ?? fallback;
    } catch {
      return fallback;
    }
  }
  write(key, value) {
    try {
      localStorage.setItem(`${this.key}:${key}`, JSON.stringify(value));
    } catch {
      // Reading remains available in private mode or when browser storage is full.
    }
  }
}
