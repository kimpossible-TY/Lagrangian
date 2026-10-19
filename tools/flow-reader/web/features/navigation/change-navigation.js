import { ChangeLocationQueue } from "../../reader-common/navigation/change-location.js";

/** HTML targets adapt the shared queue without turning block IDs into page points. */
export class ReaderChangeNavigation {
  constructor(button, adapter) {
    this.button = button;
    this.adapter = adapter;
    this.queueState = new ChangeLocationQueue(false);
    this.lastToken = null;
    this.lastGesture = -Infinity;
    this.markGesture = () => {
      this.lastGesture = performance.now();
    };
    this.clicked = () => this.jump(this.queueState.lastLocation);
    for (const event of ["pointerdown", "touchmove", "wheel", "keydown"])
      document.addEventListener(event, this.markGesture, { passive: true });
    button.addEventListener("click", this.clicked);
  }

  recentGesture() {
    return performance.now() - this.lastGesture < 2500;
  }

  queue(manifest, explicit) {
    const change = manifest.lastChange;
    if (
      !change ||
      change.revision !== manifest.revision ||
      manifest.anchors[change.target] !== change.section
    ) {
      this.queueState.clear();
      this.button.hidden = true;
      return;
    }
    if (this.queueState.lastLocation?.token === change.token) this.queueState.lastLocation = change;
    if (this.lastToken === change.token) return;
    this.lastToken = change.token;
    this.queueState.clear();
    this.button.hidden = true;
    if (!explicit) this.queueState.queue(change, !this.adapter.revision());
  }

  afterRender() {
    const change = this.queueState.afterRender(performance.now(), this.lastGesture);
    if (!change) return;
    if (change.deferred) this.button.hidden = false;
    else this.jump(change.location, true);
  }

  async jump(change, automatic = false) {
    if (!change || !this.adapter.manifest() || change.revision !== this.adapter.revision()) return;
    if (automatic && (this.recentGesture() || this.adapter.selectionActive())) {
      this.button.hidden = false;
      return;
    }
    await this.adapter.navigate(change, automatic);
  }

  allowPublication(manifest, options) {
    if (manifest.revision !== this.adapter.revision() || options.changeToken !== this.lastToken)
      return false;
    if (options.automaticChange && (this.recentGesture() || this.adapter.selectionActive())) {
      this.button.hidden = false;
      return false;
    }
    this.button.hidden = true;
    return true;
  }

  show() {
    this.button.hidden = false;
  }
  hide() {
    this.button.hidden = true;
  }

  dispose() {
    for (const event of ["pointerdown", "touchmove", "wheel", "keydown"])
      document.removeEventListener(event, this.markGesture);
    this.button.removeEventListener("click", this.clicked);
  }
}
