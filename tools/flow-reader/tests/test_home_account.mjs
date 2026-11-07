import assert from "node:assert/strict";
import test from "node:test";

// Exercise the delivered Homepage with explicit events and a scoped transport.
// Credentials, real browser storage and provider requests are never involved.
async function homepage(
  t,
  { eligible = true, authUrl = "https://auth.openai.com/authorize?state=fixture" } = {},
) {
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
  const state = { instance: "first-start", version: 0, signedIn: true, pending: false };
  let csrf = "",
    managementSession = false;
  const calls = [],
    destinations = [];
  const fetch = async (path, options) => {
    calls.push({ path, ...options });
    const capability = options.headers["X-Reader-Host-Capability"];
    let result = { instance: state.instance, version: state.version };
    if (path.endsWith("documents")) result = { documents: [], loading: false };
    if (path.endsWith("session")) {
      assert.ok(eligible);
      managementSession = capability === "private-proof";
      if (!managementSession) assert.equal(JSON.parse(options.body).purpose, "oauth");
      csrf = `csrf-${state.version}`;
      result = { ...result, management: managementSession, csrf };
    }
    if (path.endsWith("account") && options.method === "POST") {
      assert.ok(eligible);
      assert.ok(csrf);
      assert.equal(options.headers["X-Reader-CSRF"], csrf);
      const operation = JSON.parse(options.body).operation;
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
        management: managementSession,
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
  const globals = {
    document,
    window,
    fetch,
    BroadcastChannel: undefined,
    location: { assign: (url) => destinations.push(url) },
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
  await import(`../web/home/home.js?account=${Math.random()}`);
  await new Promise(setImmediate);
  const click = (id) => element(id).listeners.get("click")();
  const unlock = async () => {
    element("host-proof").value = "private-proof";
    await element("unlock").listeners.get("submit")({ preventDefault() {} });
    assert.equal(element("host-proof").value, "");
  };
  return { element, calls, destinations, click, unlock, state };
}

test("local login/logout work before unlock with OAuth CSRF and direct OpenAI navigation", async (t) => {
  const { element, calls, destinations, click } = await homepage(t);
  assert.ok(calls.every((call) => call.method === "GET"));
  assert.equal(element("account-controls").hidden, false);
  assert.equal(element("account-picker").hidden, true);
  await click("login");
  assert.deepEqual(destinations, ["https://auth.openai.com/authorize?state=fixture"]);
  assert.equal(element("login").hidden, false, "local OAuth can be restarted without unlocking");
  assert.equal(element("logout").hidden, false);
  assert.equal(element("cancel").hidden, true);
  const before = calls.length;
  await click("cancel");
  assert.equal(calls.length, before, "OAuth permission cannot cancel login");
  await click("logout");
  assert.equal(
    element("account-controls").hidden,
    false,
    "local sign-in remains available after logout",
  );
  await click("login");
  assert.equal(calls.filter((call) => call.path.endsWith("session")).length, 2);
  assert.ok(calls.every((call) => !call.headers["X-Reader-Host-Capability"]));
  assert.equal(
    calls.filter((call) => call.path.endsWith("account") && call.method === "POST").length,
    3,
  );
});

test("management keeps proof in memory for cancel and survives explicit unlock after restart", async (t) => {
  const { element, calls, click, unlock, state } = await homepage(t);
  await unlock();
  assert.equal(element("account-picker").hidden, false);
  await click("login");
  assert.equal(element("cancel").hidden, false);
  await click("cancel");
  state.instance = "second-start";
  await unlock();
  await click("cancel");
  await click("logout");
  assert.equal(calls.at(-1).headers["X-Reader-Host-Capability"], undefined);
  assert.equal(element("account-picker").hidden, true);
  const mutations = calls.filter((call) => call.path.endsWith("account") && call.method === "POST");
  assert.equal(mutations.length, 4);
  assert.ok(
    mutations.every((call) => call.headers["X-Reader-Host-Capability"] === "private-proof"),
  );
});

test("remote Homepage remains status-only and cannot trigger OAuth session or mutations", async (t) => {
  const { element, calls, click, destinations } = await homepage(t, { eligible: false });
  assert.equal(element("account-controls").hidden, true);
  assert.equal(element("unlock").hidden, true);
  const count = calls.length;
  for (const operation of ["login", "logout", "cancel"]) await click(operation);
  assert.equal(calls.length, count);
  assert.deepEqual(destinations, []);
});

test("credential changes require fresh OAuth CSRF on the next explicit action", async (t) => {
  const { click, calls, state } = await homepage(t);
  await click("login");
  state.version++;
  state.signedIn = true;
  state.pending = false;
  await click("refresh");
  await click("logout");
  assert.equal(calls.filter((call) => call.path.endsWith("session")).length, 2);
});

test("login never navigates to an untrusted provider URL", async (t) => {
  const { click, destinations, element } = await homepage(t, {
    authUrl: "https://attacker.invalid/authorize",
  });
  await click("login");
  assert.deepEqual(destinations, []);
  assert.equal(element("account-controls").hidden, true);
  assert.match(element("account-notice").textContent, /로그인 주소/);
});
