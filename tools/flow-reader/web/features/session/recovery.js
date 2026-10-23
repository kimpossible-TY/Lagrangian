/** Accepted HTML identity is independent of a service's process lifetime. */
export function sameSnapshot(left, right) {
  return Boolean(
    left && right && left.documentID === right.documentID && left.revision === right.revision,
  );
}

export function sameSession(left, right) {
  return (
    sameSnapshot(left, right) &&
    left.service?.pid === right.service?.pid &&
    left.service?.startedAt === right.service?.startedAt
  );
}

/** One visible, online HTTP polling lifetime; wake supersedes hung/obsolete work. */
export class ReaderRecovery {
  constructor({
    refresh,
    disconnected,
    resumed = () => {},
    window: view = window,
    document: page = document,
    navigator: network = navigator,
    schedule = (action, delay) => setTimeout(action, delay),
    cancel = (timer) => clearTimeout(timer),
  }) {
    Object.assign(this, { refresh, disconnected, resumed, view, page, network, schedule, cancel });
    this.failures = 0;
    this.generation = 0;
    this.listeners = [];
    const listen = (target, event, handler) => {
      target.addEventListener(event, handler);
      this.listeners.push(() => target.removeEventListener(event, handler));
    };
    listen(view, "online", () => this.wake());
    listen(view, "offline", () => {
      this.pause();
      this.disconnected();
    });
    listen(view, "pagehide", () => {
      this.suspended = true;
      this.pause();
    });
    listen(view, "pageshow", () => {
      this.suspended = false;
      this.wake();
    });
    listen(page, "visibilitychange", () => (this.available() ? this.wake() : this.pause()));
  }

  available() {
    return !this.disposed && !this.suspended && this.network.onLine !== false && !this.page.hidden;
  }

  pause() {
    this.generation++;
    this.cancel(this.timer);
    this.controller?.abort();
    this.controller = null;
    this.requested = false;
  }

  wake() {
    if (this.disposed) return;
    this.pause();
    this.failures = 0;
    if (!this.available()) return;
    this.resumed();
    this.request();
  }

  request() {
    if (!this.available()) return;
    if (this.controller) {
      this.requested = true;
      return;
    }
    this.cancel(this.timer);
    this.timer = this.schedule(() => this.run(), 0);
  }

  async run() {
    if (!this.available() || this.controller) return;
    const controller = (this.controller = new AbortController());
    const generation = this.generation;
    const current = () => generation === this.generation && this.available();
    this.requested = false;
    try {
      await this.refresh(controller.signal, current);
      if (current()) this.failures = 0;
    } catch {
      if (current()) {
        this.failures++;
        this.disconnected();
      }
    } finally {
      if (current()) {
        this.controller = null;
        const delay = this.requested ? 0 : Math.min(30000, 3000 * 2 ** Math.min(this.failures, 4));
        this.timer = this.schedule(() => this.run(), delay);
      }
    }
  }

  dispose() {
    this.disposed = true;
    this.pause();
    for (const remove of this.listeners) remove();
  }
}
