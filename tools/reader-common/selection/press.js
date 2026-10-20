/** Retain a toolbar's selection until its click survives native range collapse. */
export class SelectionPress {
  constructor(released = () => {}) {
    this.released = released;
    this.active = false;
    this.selection = undefined;
    this.timer = undefined;
  }

  begin(selection) {
    this.active = true;
    this.selection = selection;
  }

  release() {
    clearTimeout(this.timer);
    this.timer = setTimeout(() => {
      this.timer = undefined;
      this.active = false;
      this.selection = undefined;
      this.released();
    }, 0);
  }

  consume(current) {
    const selection = this.selection ?? current;
    this.active = false;
    this.selection = undefined;
    return selection;
  }

  dispose() {
    clearTimeout(this.timer);
    this.timer = undefined;
    this.active = false;
    this.selection = undefined;
  }
}
