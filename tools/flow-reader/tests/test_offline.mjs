import assert from "node:assert/strict";
import test from "node:test";
import { OfflineSnapshots, runOfflineWorker } from "../web/features/session/offline-worker.js";

const base = "https://reader.test/project/";
class MemoryCaches {
  stores = new Map();
  async open(name) {
    if (!this.stores.has(name)) this.stores.set(name, new Map());
    const store = this.stores.get(name);
    return {
      put: async (key, value) => {
        if (this.fail?.(name, key)) throw new Error("Quota exceeded");
        store.set(key, value.clone());
      },
      match: async (key) => store.get(typeof key === "string" ? key : key.url)?.clone(),
    };
  }
  async keys() {
    return [...this.stores.keys()];
  }
  async delete(name) {
    return this.stores.delete(name);
  }
}

function fixture() {
  const caches = new MemoryCaches();
  let revision = "r1";
  let generation = 0;
  let fail = null;
  const snapshot = new OfflineSnapshots({
    caches,
    base,
    prefix: "fixture:",
    nonce: () => String(++generation),
    fetch: async (url) => {
      const path = url.slice(base.length);
      if (fail?.(path)) return new Response("unavailable", { status: 409 });
      if (path === "api/offline")
        return Response.json({
          state: { documentID: "book", revision, offline: true, service: { pid: 1 } },
          manifest: { documentID: "book", revision, sections: [{ id: "one" }, { id: "two" }] },
          resources: [
            `api/sections/one?revision=${revision}`,
            `api/sections/two?revision=${revision}`,
            "api/assets/figure.svg",
          ],
        });
      return new Response(`${revision}:${path}`);
    },
  });
  return {
    caches,
    snapshot,
    revision: (value) => {
      revision = value;
    },
    fail: (value) => {
      fail = value;
    },
  };
}

test("commit includes every section and asset, scoped to the hosted reader path", async () => {
  const { snapshot } = fixture();
  await snapshot.save();
  const state = await (await snapshot.match(base + "api/state")).json();
  assert.equal(state.offline, true);
  assert.equal(state.revision, "r1");
  assert.ok(await snapshot.match(base + "api/sections/two?revision=r1"));
  assert.ok(await snapshot.match(base + "api/assets/figure.svg"));
  assert.equal(await snapshot.match("https://reader.test/other/api/state"), undefined);
  assert.throws(() => snapshot.url("../private"));
});

test("failed section download preserves last complete pointer and removes staging cache", async () => {
  const f = fixture();
  await f.snapshot.save();
  const before = await f.snapshot.pointer();
  f.revision("r2");
  f.fail((path) => path.startsWith("api/sections/two"));
  await assert.rejects(f.snapshot.save());
  assert.deepEqual(await f.snapshot.pointer(), before);
  assert.equal((await f.caches.keys()).filter((name) => name.includes("snapshot")).length, 1);
  assert.equal(await f.snapshot.match(base + "api/sections/one?revision=r2"), undefined);
});

test("quota failure during pointer publication cannot discard the accepted cache", async () => {
  const f = fixture();
  await f.snapshot.save();
  const before = await f.snapshot.pointer();
  f.revision("r2");
  f.caches.fail = (name) => name.endsWith("meta");
  await assert.rejects(f.snapshot.save(), /Quota/);
  assert.deepEqual(await f.snapshot.pointer(), before);
  assert.ok(await f.snapshot.match(base + "api/sections/one?revision=r1"));
});

test("source revision changes during download cannot publish mixed content", async () => {
  const f = fixture();
  await f.snapshot.save();
  const before = await f.snapshot.pointer();
  f.revision("r2");
  f.fail((path) => {
    if (path.startsWith("api/assets")) f.revision("r3");
    return false;
  });
  await assert.rejects(f.snapshot.save(), /changed/);
  assert.deepEqual(await f.snapshot.pointer(), before);
});

test("retains previous revision for active readers and bounds obsolete caches", async () => {
  const f = fixture();
  for (const revision of ["r1", "r2", "r3"]) {
    f.revision(revision);
    await f.snapshot.save();
  }
  assert.equal((await f.caches.keys()).filter((name) => name.includes("snapshot")).length, 2);
  assert.ok(await f.snapshot.match(base + "api/sections/one?revision=r2"));
  assert.ok(await f.snapshot.match(base + "api/sections/one?revision=r3"));
  assert.equal(await f.snapshot.match(base + "api/sections/one?revision=r1"), undefined);
});

test("uncached live compiler service returns recoverable HTTP failure offline", async () => {
  const listeners = new Map();
  const scope = {
    registration: { scope: base },
    caches: new MemoryCaches(),
    fetch: async () => {
      throw new TypeError("Network disconnected");
    },
    addEventListener: (name, callback) => listeners.set(name, callback),
  };
  runOfflineWorker(scope, { version: "test", files: [] });
  let pending;
  listeners.get("fetch")({
    request: new Request(base + "api/compiler/config"),
    respondWith: (response) => {
      pending = response;
    },
  });
  const response = await pending;
  assert.equal(response.status, 503);
  assert.match((await response.json()).error, /offline/);
});

test("waiting shell only activates after an explicit apply-update message", async () => {
  const listeners = new Map();
  let activations = 0;
  const scope = {
    registration: { scope: base },
    caches: new MemoryCaches(),
    fetch: async () => new Response(""),
    skipWaiting: async () => {
      activations++;
    },
    addEventListener: (name, callback) => listeners.set(name, callback),
  };
  runOfflineWorker(scope, { version: "new", files: [] });
  assert.equal(activations, 0);
  let pending;
  listeners.get("message")({
    data: { type: "activate-update" },
    waitUntil(value) {
      pending = value;
    },
  });
  await pending;
  assert.equal(activations, 1);
});

test("page update is opt-in, bypasses import HTTP cache, and cancels on disposal", async () => {
  const { OfflineReader } = await import("../web/features/session/offline.js");
  const keys = ["isSecureContext", "navigator"];
  const saved = keys.map((key) => Object.getOwnPropertyDescriptor(globalThis, key));
  const container = new EventTarget();
  const registration = new EventTarget();
  let messages = 0;
  registration.waiting = {
    postMessage(message) {
      assert.equal(message.type, "activate-update");
      messages++;
      queueMicrotask(() => container.dispatchEvent(new Event("controllerchange")));
    },
  };
  container.register = async (_, options) => {
    assert.equal(options.updateViaCache, "none");
    return registration;
  };
  container.ready = Promise.resolve(registration);
  Object.defineProperty(globalThis, "isSecureContext", { configurable: true, value: true });
  Object.defineProperty(globalThis, "navigator", {
    configurable: true,
    value: { serviceWorker: container },
  });
  try {
    let available = false;
    const reader = new OfflineReader({
      updateAvailable(value) {
        available = value;
      },
    });
    await reader.ready;
    assert.equal(available, true);
    assert.equal(messages, 0);
    assert.equal(await reader.applyUpdate(), true);
    registration.waiting.postMessage = () => {};
    const pending = reader.applyUpdate();
    await Promise.resolve();
    reader.dispose();
    assert.equal(await pending, false);
  } finally {
    keys.forEach((key, i) =>
      saved[i] ? Object.defineProperty(globalThis, key, saved[i]) : delete globalThis[key],
    );
  }
});
