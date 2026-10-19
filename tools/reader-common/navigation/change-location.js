/** Shared by the paged preview and HTML Reader: hints wait for rendered content. */
export class ChangeLocationQueue {
  constructor(preserveReadingState) {
    this.preserveReadingState = preserveReadingState;
    this.hasRendered = false;
    this.pending = undefined;
    this.lastLocation = undefined;
  }

  queue(location, resume = false) {
    if (resume && (this.preserveReadingState || this.hasRendered)) return;
    this.pending = location;
  }

  clear() {
    // A transport reset does not turn an existing reader into a new viewer.
    this.pending = undefined;
    this.lastLocation = undefined;
  }

  afterRender(now, lastGesture) {
    this.hasRendered = true;
    if (!this.pending) return undefined;
    this.lastLocation = this.pending;
    this.pending = undefined;
    return { location: this.lastLocation, deferred: now - lastGesture < 2500 };
  }
}
