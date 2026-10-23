/** Reader-origin requests preserve the hosted base path and bound pending work. */
export class ReaderTransport {
  constructor(request = globalThis.fetch.bind(globalThis)) {
    this.request = request;
    this.pending = new Set();
  }

  async post(path, body, timeout) {
    return this.fetch(
      path,
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(body),
      },
      timeout,
      "json",
    );
  }

  async get(path, { signal, timeout = 10000, format = "json" } = {}) {
    return this.fetch(path, { cache: "no-store", signal }, timeout, format);
  }

  async fetch(path, options, timeout, format) {
    const controller = new AbortController();
    const abort = () => controller.abort();
    if (options.signal?.aborted) abort();
    else options.signal?.addEventListener("abort", abort, { once: true });
    this.pending.add(controller);
    const timer = setTimeout(() => controller.abort(), timeout);
    try {
      const response = await this.request(path, {
        ...options,
        signal: controller.signal,
      });
      if (!response.ok) throw new Error(`Reader HTTP ${response.status}`);
      const result = await response[format]();
      if (controller.signal.aborted) throw new DOMException("Request aborted", "AbortError");
      return result;
    } finally {
      clearTimeout(timer);
      options.signal?.removeEventListener("abort", abort);
      this.pending.delete(controller);
    }
  }
  dispose() {
    for (const controller of this.pending) controller.abort();
    this.pending.clear();
  }
}
