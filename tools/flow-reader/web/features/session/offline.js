/** The page owns visible status; the Service Worker owns complete snapshot commits. */
export class OfflineReader {
  constructor({ changed = () => {} } = {}) {
    this.changed = changed;
    this.ready = this.register();
  }

  async register() {
    if (!globalThis.isSecureContext || !navigator.serviceWorker) {
      this.changed("unavailable");
      return null;
    }
    try {
      const registration = await navigator.serviceWorker.register(
        new URL("../../service-worker.js", import.meta.url),
        { type: "module", scope: new URL("../../", import.meta.url).href },
      );
      await navigator.serviceWorker.ready;
      return registration;
    } catch {
      this.changed("unavailable");
      return null;
    }
  }

  async save(manifest) {
    const key = JSON.stringify([manifest.documentID, manifest.revision, manifest.service]);
    if (this.saved === key || this.saving) return;
    this.saving = true;
    try {
      const registration = await this.ready;
      if (!registration?.active) return;
      this.changed("saving");
      const saved = await new Promise((resolve) => {
        const channel = new MessageChannel();
        const finish = (value) => {
          clearTimeout(timer);
          channel.port1.close();
          resolve(value);
        };
        const timer = setTimeout(() => finish(false), 120000);
        channel.port1.onmessage = (event) => finish(event.data?.saved === true);
        registration.active.postMessage({ type: "save-offline" }, [channel.port2]);
      });
      if (saved) this.saved = key;
      this.changed(saved ? "saved" : "failed");
    } catch {
      this.changed("failed");
    } finally {
      this.saving = false;
    }
  }
}
