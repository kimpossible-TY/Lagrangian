import assert from "node:assert/strict";
import test from "node:test";

// Exercise the delivered Homepage module with explicit user events and a fake
// transport. No browser, provider, filesystem account or storage is involved.
test("Homepage retains proof only in memory and includes it on each account operation", async (t) => {
  class Element extends EventTarget {
    constructor() {
      super();
      this.listeners = new Map();
      this.children = [];
      this.dataset = {};
      this.value = "";
      this.hidden = false;
    }
    addEventListener(name, listener) {
      this.listeners.set(name, listener);
    }
    replaceChildren(...children) {
      this.children = children;
    }
    append(...children) {
      this.children.push(...children);
    }
    removeAttribute(name) {
      delete this[name];
    }
    contains() {
      return false;
    }
    querySelectorAll() {
      return [];
    }
  }
  const elements = new Map();
  const element = (id) => {
    if (!elements.has(id)) elements.set(id, new Element());
    return elements.get(id);
  };
  const document = Object.assign(new Element(), {
    hidden: false,
    getElementById: element,
    createElement: () => new Element(),
  });
  const window = new EventTarget();
  let instance = "first-start",
    version = 0,
    signedIn = true;
  const calls = [];
  const fetch = async (path, options) => {
    calls.push({ path, ...options });
    let result = { instance, version };
    if (path.endsWith("documents")) result = { documents: [], loading: false };
    if (path.endsWith("session")) {
      assert.equal(options.headers["X-Reader-Host-Capability"], "private-proof");
      result = { ...result, management: true, csrf: "current-csrf" };
    }
    if (path.endsWith("account") && options.method === "POST") {
      assert.equal(options.headers["X-Reader-Host-Capability"], "private-proof");
      assert.equal(options.headers["X-Reader-CSRF"], "current-csrf");
      const operation = JSON.parse(options.body).operation;
      if (operation === "logout") signedIn = false;
      result = {
        ...result,
        version: ++version,
        csrf: operation === "logout" ? "" : "current-csrf",
      };
    } else if (path.endsWith("account")) {
      result = {
        ...result,
        signedIn,
        eligible: true,
        management: Boolean(options.headers["X-Reader-Host-Capability"]),
      };
    }
    return { ok: true, json: async () => result };
  };
  const globals = {
    document,
    window,
    fetch,
    BroadcastChannel: undefined,
    localStorage: { setItem: () => assert.fail("proof must not enter storage") },
    sessionStorage: { setItem: () => assert.fail("proof must not enter storage") },
  };
  for (const [key, value] of Object.entries(globals)) {
    const descriptor = Object.getOwnPropertyDescriptor(globalThis, key);
    Object.defineProperty(globalThis, key, { configurable: true, writable: true, value });
    t.after(() => {
      if (descriptor) Object.defineProperty(globalThis, key, descriptor);
      else delete globalThis[key];
    });
  }
  t.after(() => window.dispatchEvent(new Event("pagehide")));
  await import(`../web/home/home.js?account-proof=${Date.now()}`);
  await new Promise(setImmediate);
  assert.ok(calls.length >= 2);
  assert.ok(calls.every((call) => !call.headers["X-Reader-Host-Capability"]));
  const unlock = async () => {
    element("host-proof").value = "private-proof";
    await element("unlock").listeners.get("submit")({ preventDefault() {} });
    assert.equal(element("host-proof").value, "");
    assert.equal(element("account-controls").hidden, false);
  };
  await unlock();
  for (const operation of ["login", "cancel"]) await element(operation).listeners.get("click")();
  // A restart encountered during explicit unlock must not erase the new proof.
  instance = "second-start";
  await unlock();
  await element("cancel").listeners.get("click")();
  await element("logout").listeners.get("click")();
  const finalStatus = calls.at(-1);
  assert.ok(finalStatus.path.endsWith("account"));
  assert.equal(finalStatus.method, "GET");
  assert.equal(finalStatus.headers["X-Reader-Host-Capability"], undefined);
  assert.equal(element("account-controls").hidden, true);
  assert.equal(
    calls.filter((call) => call.path.endsWith("account") && call.method === "POST").length,
    4,
  );
});
