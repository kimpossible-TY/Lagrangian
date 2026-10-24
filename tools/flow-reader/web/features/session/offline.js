/** The page owns visible status; the Service Worker owns complete snapshot commits. */
export class OfflineReader {
  constructor({ changed = () => {}, updateAvailable = () => {} } = {}) {
    this.changed = changed;
    this.updateAvailable = updateAvailable;
    this.disposed = false;
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
        { type: "module", updateViaCache: "none", scope: new URL("../../", import.meta.url).href },
      );
      if (this.disposed) return null;
      this.registration = registration;
      this.watchUpdate = () => {
        if (!this.disposed) this.updateAvailable(Boolean(registration.waiting));
      };
      this.onUpdateFound = () => {
        this.installing?.removeEventListener("statechange", this.watchUpdate);
        this.installing = registration.installing;
        this.installing?.addEventListener("statechange", this.watchUpdate);
      };
      registration.addEventListener("updatefound", this.onUpdateFound);
      this.onUpdateFound();
      this.watchUpdate();
      await navigator.serviceWorker.ready;
      return this.disposed ? null : registration;
    } catch {
      this.changed("unavailable");
      return null;
    }
  }

  async applyUpdate() {
    const registration = await this.ready;
    if (!registration?.waiting || this.disposed) return false;
    return new Promise((resolve) => {
      const finish = (applied) => {
        clearTimeout(timer);
        navigator.serviceWorker.removeEventListener("controllerchange", changed);
        this.cancelUpdate = null;
        resolve(applied);
      };
      const changed = () => finish(true);
      const timer = setTimeout(() => finish(false), 15000);
      this.cancelUpdate = () => finish(false);
      navigator.serviceWorker.addEventListener("controllerchange", changed);
      registration.waiting.postMessage({ type: "activate-update" });
    });
  }

  dispose() {
    this.disposed = true;
    this.cancelUpdate?.();
    this.registration?.removeEventListener("updatefound", this.onUpdateFound);
    this.installing?.removeEventListener("statechange", this.watchUpdate);
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
