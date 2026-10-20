/** One renderer-native origin; only its accepted completion consumes the return. */
export class ReferenceReturn {
  constructor(button, restore) {
    this.button = button;
    this.origin = null;
    this.disposed = false;
    this.clicked = () => {
      if (this.origin !== null) restore(this.origin);
    };
    button.hidden = true;
    button.addEventListener("click", this.clicked);
  }

  remember(origin) {
    if (this.disposed || origin === null || origin === undefined) return;
    this.origin = origin;
    this.button.hidden = false;
  }

  consume(origin) {
    if (this.origin !== origin) return;
    this.origin = null;
    this.button.hidden = true;
  }

  dispose() {
    this.disposed = true;
    this.origin = null;
    this.button.hidden = true;
    this.button.removeEventListener("click", this.clicked);
  }
}
