import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

// Exercise the delivered Homepage with explicit events and a scoped transport.
// Credentials, real browser storage and provider requests are never involved.
async function homepage(
  t,
  {
    eligible = true,
    retainedManagementCookie = false,
    authUrl = "https://auth.openai.com/authorize?state=fixture",
    hash = "",
    inventory = [],
  } = {},
) {
  const stats = { activeWrites: 0, callbacks: 0 };
  class Element extends EventTarget {
    constructor() {
      super();
      this.listeners = new Map();
      this.registered = new Map();
      this.children = [];
      this.dataset = {};
      this.value = "";
      this.hidden = false;
      this.customStates = { set() {} };
    }
    set active(value) {
      if (this._active === value) return;
      this._active = value;
      stats.activeWrites++;
      if (!this._renderQueued) {
        this._renderQueued = true;
        this.updateComplete = Promise.resolve().then(() => {
          this._renderQueued = false;
          itemUpdated.call(this, new Map([["active", undefined]]));
        });
      }
    }
    get active() {
      return this._active;
    }
    addEventListener(name, listener, options) {
      this.listeners.set(name, listener);
      if (!this.registered.has(name)) this.registered.set(name, new Set());
      this.registered.get(name).add(listener);
      super.addEventListener(name, listener, options);
    }
    removeEventListener(name, listener, options) {
      this.registered.get(name)?.delete(listener);
      super.removeEventListener(name, listener, options);
    }
    closest(selector) {
      for (let ancestor = this; ancestor; ancestor = ancestor.parentElement) {
        if (selector.includes(ancestor.localName) && ancestor.localName) return ancestor;
      }
      return null;
    }
    replaceChildren(...children) {
      this.children = [];
      this.append(...children);
    }
    append(...children) {
      for (const child of children) this.insertBefore(child, null);
    }
    insertBefore(child, before) {
      child.remove();
      const index = before ? this.children.indexOf(before) : this.children.length;
      this.children.splice(index, 0, child);
      child.parent = this;
    }
    remove() {
      if (this.parent) {
        if (this === document.activeElement || this.contains(document.activeElement))
          document.activeElement = null;
        const index = this.parent.children.indexOf(this);
        if (index >= 0) this.parent.children.splice(index, 1);
        this.parent = null;
      }
    }
    get parentElement() {
      return this.parent || null;
    }
    get firstElementChild() {
      return this.children[0] || null;
    }
    get nextElementSibling() {
      if (!this.parent) return null;
      return this.parent.children[this.parent.children.indexOf(this) + 1] || null;
    }
    setAttribute(name, value) {
      this[name] = value;
      if (name === "tabindex")
        for (const observer of observers) {
          if (observer.target && (observer.target === this || observer.target.contains(this)))
            observer.schedule();
        }
    }
    get isConnected() {
      for (let ancestor = this; ancestor; ancestor = ancestor.parentElement)
        if (ancestor === document) return true;
      return false;
    }
    removeAttribute(name) {
      delete this[name];
    }
    showModal() {
      this.open = true;
    }
    close() {
      this.open = false;
    }
    focus() {
      if (document.activeElement === this) return;
      this.focused = true;
      document.activeElement = this;
      // Model document capture followed by light-DOM focusin bubbling.
      document.dispatchEvent(new Event("focusin"));
      for (
        let ancestor = this;
        ancestor && ancestor !== document;
        ancestor = ancestor.parentElement
      )
        ancestor.dispatchEvent(new Event("focusin"));
    }
    blur() {
      if (document.activeElement === this) document.activeElement = document.body;
    }
    scrollIntoView() {}
    contains(child) {
      return this.children.some((item) => item === child || item.contains(child));
    }
    querySelectorAll() {
      return [];
    }
  }
  const elements = new Map();
  const element = (id) => {
    if (!elements.has(id)) {
      const result = new Element();
      result.parent = document;
      elements.set(id, result);
    }
    return elements.get(id);
  };
  const document = Object.assign(new Element(), {
    hidden: false,
    getElementById: element,
    createElement: (tag) => Object.assign(new Element(), { localName: tag }),
    createTextNode: (text) => Object.assign(new Element(), { textContent: text }),
  });
  const window = new EventTarget();
  const state = {
    instance: "first-start",
    version: 0,
    signedIn: true,
    pending: false,
    notices: {},
  };
  let csrf = "",
    managementSession = retainedManagementCookie;
  const calls = [],
    destinations = [];
  const fetch = async (path, options) => {
    calls.push({ path, ...options });
    const capability = options.headers["X-Reader-Host-Capability"];
    let result = { instance: state.instance, version: state.version };
    if (path.endsWith("documents")) result = { documents: inventory, loading: false };
    if (path.endsWith("session")) {
      assert.ok(eligible);
      const manage = capability === "private-proof";
      if (!manage) assert.equal(JSON.parse(options.body).purpose, "oauth");
      managementSession ||= manage;
      csrf = `csrf-${state.version}`;
      result = { ...result, management: manage, csrf };
    }
    if (path.endsWith("account") && options.method === "POST") {
      assert.ok(eligible);
      assert.ok(csrf);
      assert.equal(options.headers["X-Reader-CSRF"], csrf);
      const operation = JSON.parse(options.body).operation;
      // Matching a scoped OAuth CSRF never borrows management from a cookie.
      const manage = Boolean(capability && managementSession);
      if (operation === "cancel") {
        assert.equal(capability, "private-proof");
        assert.ok(managementSession);
      }
      if (operation === "login") state.pending = true;
      else state.pending = false;
      if (operation === "logout") {
        state.signedIn = false;
        managementSession = false;
      }
      csrf = operation === "logout" ? "" : `csrf-${++state.version}`;
      result = {
        ...result,
        version: state.version,
        csrf,
        management: manage && operation !== "logout",
        notice: state.notices[operation] || "",
        ...(operation === "login" ? { authUrl } : {}),
      };
    } else if (path.endsWith("account")) {
      result = {
        ...result,
        signedIn: state.signedIn,
        pending: state.pending,
        eligible,
        management: Boolean(capability && managementSession),
      };
    }
    return { ok: true, json: async () => result };
  };
  const observers = [];
  class Observer {
    constructor(callback) {
      this.callback = callback;
      observers.push(this);
    }
    observe(target) {
      this.target = target;
    }
    schedule() {
      if (this.pending) return;
      this.pending = true;
      queueMicrotask(() => {
        this.pending = false;
        if (this.target) {
          if (++stats.callbacks > 1000) throw new Error("observer did not converge");
          this.callback([]);
        }
      });
    }
    disconnect() {
      this.target = null;
    }
  }
  const globals = {
    MutationObserver: Observer,
    document,
    window,
    fetch,
    BroadcastChannel: undefined,
    location: { hash, assign: (url) => destinations.push(url) },
    localStorage: { setItem: () => assert.fail("proof/CSRF must not enter storage") },
    sessionStorage: { setItem: () => assert.fail("proof/CSRF must not enter storage") },
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
  await import(`../web/home/home.js?lifecycle=${Math.random()}`);
  await new Promise(setImmediate);
  const click = (id) => element(id).listeners.get("click")();
  const unlock = async () => {
    element("host-proof").value = "private-proof";
    await element("unlock").listeners.get("submit")({ preventDefault() {} });
    assert.equal(element("host-proof").value, "");
  };
  return {
    element,
    observers,
    stats,
    calls,
    destinations,
    click,
    unlock,
    state,
    window,
    document,
    location: globals.location,
  };
}

const source = readFileSync(
  new URL("../web/vendor/webawesome-3.14.0/chunks/chunk.W2C46OQX.js", import.meta.url),
  "utf8",
);
const start = source.indexOf("  updated(changedProperties) {");
const end = source.indexOf("  /** Update the has-submenu custom state", start);
assert.ok(start >= 0 && end > start);
const itemUpdated = new Function("return ({" + source.slice(start, end) + "}).updated;")();
export { homepage };
