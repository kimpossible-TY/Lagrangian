/** Coalesces browser-local rendering without owning document data or geometry. */
export class RenderScheduler {
  constructor({ render, blocked = () => false, onBlocked, onIdle, onError = console.error }) {
    Object.assign(this, { render, blocked, onBlocked, onIdle, onError });
    this.pending = false;
    this.running = false;
    this.disposed = false;
    this.generation = 0;
    this.ticket = 0;
    this.delay = 0;
  }

  get active() {
    return !this.disposed && (this.running || this.frame !== undefined || this.timer !== undefined);
  }

  request(delay = 0) {
    if (this.disposed) return;
    this.pending = true;
    this.delay = delay;
    if (this.running || (this.frame !== undefined && delay === 0)) return;
    this.clearScheduled();
    this.schedule();
  }

  clearScheduled() {
    this.ticket++;
    if (this.timer !== undefined) clearTimeout(this.timer);
    if (this.frame !== undefined) cancelAnimationFrame(this.frame);
    this.timer = this.frame = undefined;
  }

  schedule() {
    const ticket = this.ticket;
    const frame = () => {
      if (this.disposed || ticket !== this.ticket) return;
      this.timer = undefined;
      this.frame = requestAnimationFrame(() => {
        if (this.disposed || ticket !== this.ticket) return;
        this.frame = undefined;
        return this.flush();
      });
    };
    if (this.delay > 0) this.timer = setTimeout(frame, this.delay);
    else frame();
  }

  async flush() {
    if (!this.pending || this.disposed) return;
    if (this.blocked()) {
      // The adapter signals selection release; do not spin on held work.
      this.onBlocked?.();
      return;
    }
    this.pending = false;
    this.running = true;
    const generation = this.generation;
    let failed = false;
    let failure;
    try {
      await this.render();
    } catch (error) {
      failed = true;
      failure = error;
    } finally {
      this.running = false;
    }
    if (this.disposed) return;
    // Release running state before callbacks: completion can enqueue navigation.
    if (generation === this.generation) {
      if (failed) this.onError(failure);
      else if (!this.pending) {
        try {
          this.onIdle?.();
        } catch (error) {
          this.onError(error);
        }
      }
    }
    if (this.pending && this.frame === undefined && this.timer === undefined) this.schedule();
  }

  cancel() {
    this.generation++;
    this.pending = false;
    this.clearScheduled();
  }

  dispose() {
    this.disposed = true;
    this.cancel();
  }
}
