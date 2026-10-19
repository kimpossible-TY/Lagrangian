/** Reader-origin requests preserve the hosted base path and bound pending work. */
export class ReaderTransport {
  constructor(request = globalThis.fetch.bind(globalThis)) {
    this.request = request;
    this.pending = new Set();
  }

  async post(path, body, timeout) {
    const controller = new AbortController();
    this.pending.add(controller);
    const timer = setTimeout(() => controller.abort(), timeout);
    try {
      const response = await this.request(path, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(body),
        signal: controller.signal,
      });
      if (!response.ok) throw new Error(`Reader HTTP ${response.status}`);
      return await response.json();
    } finally {
      clearTimeout(timer);
      this.pending.delete(controller);
    }
  }
  dispose() {
    for (const controller of this.pending) controller.abort();
    this.pending.clear();
  }
}
