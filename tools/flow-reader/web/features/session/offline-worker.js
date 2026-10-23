/** Transactional accepted snapshots. A failed download never changes the pointer. */
export class OfflineSnapshots {
  constructor({ caches, fetch, base, prefix, nonce = () => crypto.randomUUID() }) {
    Object.assign(this, { caches, fetch, base, prefix, nonce });
  }

  url(path) {
    const url = new URL(path, this.base);
    if (!url.href.startsWith(this.base) || url.origin !== new URL(this.base).origin)
      throw new Error("Snapshot resource is outside the Reader");
    return url.href;
  }

  async pointer() {
    const meta = await this.caches.open(this.prefix + "meta");
    const response = await meta.match(this.url("__offline_pointer__"));
    return response ? response.json() : {};
  }

  async download(path) {
    const response = await this.fetch(this.url(path), { cache: "no-store" });
    if (!response.ok) throw new Error(`Offline download HTTP ${response.status}`);
    return response;
  }

  async save() {
    const inventory = await (await this.download("api/offline")).json();
    const { state, manifest, resources } = inventory;
    if (
      !state.revision ||
      state.revision !== manifest.revision ||
      state.documentID !== manifest.documentID ||
      !Array.isArray(resources)
    )
      throw new Error("Invalid offline snapshot");
    const pointer = await this.pointer();
    const identity = JSON.stringify([state.documentID, state.revision, state.service]);
    if (pointer.identity === identity) return;
    const name = this.prefix + "snapshot-" + this.nonce();
    const cache = await this.caches.open(name);
    try {
      // Sequential downloads bound peak memory even for the full PDE document.
      for (const path of resources) {
        if (!path.startsWith("api/sections/") && !path.startsWith("api/assets/"))
          throw new Error("Invalid offline resource");
        await cache.put(this.url(path), await this.download(path));
      }
      const current = await (await this.download("api/offline")).json();
      if (
        JSON.stringify([
          current.state.documentID,
          current.state.revision,
          current.state.service,
        ]) !== identity
      )
        throw new Error("Document changed while saving offline snapshot");
      await cache.put(this.url("api/state"), Response.json(state));
      await cache.put(
        this.url(`api/manifest?revision=${encodeURIComponent(state.revision)}`),
        Response.json(manifest),
      );
      const meta = await this.caches.open(this.prefix + "meta");
      await meta.put(
        this.url("__offline_pointer__"),
        Response.json({
          current: name,
          previous: pointer.current,
          identity,
        }),
      );
    } catch (error) {
      await this.caches.delete(name);
      throw error;
    }
    // Keep the previous revision for a reader already displaying its manifest.
    // Cleanup failure cannot invalidate the committed pointer.
    for (const old of await this.caches.keys()) {
      if (old.startsWith(this.prefix + "snapshot-") && old !== name && old !== pointer.current)
        await this.caches.delete(old).catch(() => {});
    }
  }

  async match(request) {
    const pointer = await this.pointer();
    for (const name of [pointer.current, pointer.previous].filter(Boolean)) {
      const response = await (await this.caches.open(name)).match(request);
      if (response) return response;
    }
    return undefined;
  }
}

export function runOfflineWorker(scope, config) {
  const base = scope.registration.scope;
  const prefix = `flow-offline-v1:${base}:`;
  const shellName = prefix + "shell-" + config.version;
  const snapshots = new OfflineSnapshots({
    caches: scope.caches,
    fetch: scope.fetch.bind(scope),
    base,
    prefix,
  });
  const staticURLs = new Set(config.files.map((path) => new URL(path, base).href));
  let saving = null;
  scope.addEventListener("install", (event) => {
    event.waitUntil(
      (async () => {
        const cache = await scope.caches.open(shellName);
        try {
          // All manifest-listed MathJax chunks/fonts are needed for offline reflow.
          for (const url of staticURLs) await cache.add(new Request(url, { cache: "reload" }));
        } catch (error) {
          await scope.caches.delete(shellName);
          throw error;
        }
      })(),
    );
  });
  scope.addEventListener("activate", (event) => event.waitUntil(scope.clients.claim()));
  scope.addEventListener("message", (event) => {
    if (event.data?.type !== "save-offline") return;
    if (!saving)
      saving = snapshots.save().finally(() => {
        saving = null;
      });
    event.waitUntil(
      saving.then(
        () => event.ports[0]?.postMessage({ saved: true }),
        (error) => event.ports[0]?.postMessage({ saved: false, error: String(error) }),
      ),
    );
  });
  scope.addEventListener("fetch", (event) => {
    const { request } = event;
    if (request.method !== "GET" || !request.url.startsWith(base)) return;
    const url = new URL(request.url);
    url.search = "";
    if (request.mode === "navigate" || staticURLs.has(url.href)) {
      event.respondWith(
        (async () => {
          const shell = await scope.caches.open(shellName);
          return (
            (await shell.match(
              request.mode === "navigate" ? new URL("index.html", base).href : url.href,
            )) ?? scope.fetch(request)
          );
        })(),
      );
    } else {
      event.respondWith(
        (async () => {
          const controller = new AbortController();
          const timer = setTimeout(() => controller.abort(), 5000);
          try {
            return await scope.fetch(request, { signal: controller.signal });
          } catch {
            const cached = await snapshots.match(request);
            if (cached) return cached;
            // Optional live services have no offline representation. A bounded
            // HTTP failure lets callers recover without rejecting respondWith.
            return Response.json(
              { error: "Reader service is unavailable offline" },
              {
                status: 503,
                headers: { "Cache-Control": "no-store" },
              },
            );
          } finally {
            clearTimeout(timer);
          }
        })(),
      );
    }
  });
}
