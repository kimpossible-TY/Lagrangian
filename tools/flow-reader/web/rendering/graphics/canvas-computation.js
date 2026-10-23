import { composeCanvas } from "./canvas-layout.js";

/** One bounded, disposable placement worker per reader; identical local fallback. */
export class CanvasComputation {
  constructor(
    factory = () => new Worker(new URL("./canvas-worker.js", import.meta.url), { type: "module" }),
    timeout = 10000,
  ) {
    Object.assign(this, { factory, timeout });
    this.pending = new Map();
    this.sequence = 0;
  }

  run(input) {
    if (this.disposed) return Promise.reject(new DOMException("Disposed", "AbortError"));
    if (this.failed || this.pending.size >= 64)
      return Promise.resolve().then(() => composeCanvas(...input));
    return new Promise((resolve, reject) => {
      const id = ++this.sequence;
      const timer = setTimeout(() => this.fail(), this.timeout);
      this.pending.set(id, { input, resolve, reject, timer });
      try {
        if (!this.worker) {
          this.worker = this.factory();
          this.worker.onmessage = ({ data }) => {
            const job = this.pending.get(data.id);
            if (!job) return;
            if (data.error || !data.plan) return this.fail();
            clearTimeout(job.timer);
            this.pending.delete(data.id);
            job.resolve(data.plan);
          };
          this.worker.onerror = () => this.fail();
          this.worker.onmessageerror = () => this.fail();
        }
        this.worker.postMessage({ id, input });
      } catch {
        this.fail();
      }
    });
  }

  fail() {
    this.failed = true;
    this.worker?.terminate();
    this.worker = null;
    const jobs = [...this.pending.values()];
    this.pending.clear();
    for (const job of jobs) {
      clearTimeout(job.timer);
      Promise.resolve()
        .then(() => composeCanvas(...job.input))
        .then(job.resolve, job.reject);
    }
  }

  reset() {
    this.worker?.terminate();
    this.worker = null;
    for (const job of this.pending.values()) {
      clearTimeout(job.timer);
      job.reject(new DOMException("Document replaced", "AbortError"));
    }
    this.pending.clear();
    this.failed = false;
  }

  dispose() {
    this.disposed = true;
    this.reset();
  }
}
