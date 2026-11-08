import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

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
  class Element extends EventTarget {
    constructor() {
      super();
      this.listeners = new Map();
      this.children = [];
      this.dataset = {};
      this.value = "";
      this.hidden = false;
    }
    set active(value) {
      this._active = value;
      this.tabindex = value ? "0" : "-1";
    }
    get active() {
      return this._active;
    }
    addEventListener(name, listener) {
      this.listeners.set(name, listener);
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
    }
    get isConnected() {
      return Boolean(this.parent);
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
      this.focused = true;
      document.activeElement = this;
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
    if (!elements.has(id)) elements.set(id, new Element());
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
  await import(`../web/home/home.js?account=${Math.random()}`);
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

test("a fresh page with a retained management cookie can log in and out using OAuth CSRF", async (t) => {
  const { element, calls, destinations, click } = await homepage(t, {
    retainedManagementCookie: true,
  });
  assert.equal(element("account-picker").hidden, true);
  await click("login");
  assert.equal(destinations.length, 1);
  assert.equal(element("cancel").hidden, true);
  await click("logout");
  assert.equal(element("account-controls").hidden, false);
  assert.ok(calls.every((call) => !call.headers["X-Reader-Host-Capability"]));
  assert.deepEqual(
    calls
      .filter((call) => call.path.endsWith("account") && call.method === "POST")
      .map((call) => JSON.parse(call.body).operation),
    ["login", "logout"],
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
  await click("refresh");
  assert.equal(element("account-notice").textContent, "");
});

test("settings opens for connection hashes and explicit controls", async (t) => {
  const { element, click, window, location } = await homepage(t, { hash: "#connection" });
  assert.equal(element("settings").open, true);
  assert.equal(element("connection").focused, true);
  click("settings-close");
  assert.equal(element("settings").open, false);
  click("settings-open");
  assert.equal(element("settings").open, true);
  click("settings-close");
  location.hash = "#connection";
  window.dispatchEvent(new Event("hashchange"));
  assert.equal(element("settings").open, true);
});

test("library chooses safe HTML then Paged and retains a destination across polls", async (t) => {
  const inventory = [
    {
      id: "doc",
      name: "원래 제목",
      state: "ready",
      variants: [
        { kind: "html", url: "javascript:alert(1)" },
        { kind: "paged", url: "https://example.test/paged" },
        { kind: "html", url: "https://example.test/html" },
      ],
    },
  ];
  const { element, click, document } = await homepage(t, { inventory });
  const card = element("document-list").children[0];
  const [title, status] = card.children[0].children;
  const alternatives = card.children[1];
  const primary = title;
  const link = primary.children[0];
  assert.equal(link.textContent, "원래 제목");
  assert.equal(status.dataset.state, "ready");
  assert.equal(link.href, "https://example.test/html");
  assert.equal(link.textContent, "원래 제목");
  assert.equal(alternatives.children[1].children[0].href, "https://example.test/paged");
  link.focus();
  inventory[0].state = "stale";
  await click("refresh");
  assert.equal(primary.children[0], link);
  assert.equal(document.activeElement, link);
  assert.equal(status.dataset.state, "stale");
  inventory[0].variants = [
    { kind: "html", url: "javascript:alert(1)" },
    { kind: "paged", url: "https://example.test/paged" },
  ];
  await click("refresh");
  assert.equal(primary.children[0].href, "https://example.test/paged");
  assert.equal(alternatives.hidden, true);
  assert.equal(document.activeElement, element("documents"));
});

test("hidden alternatives return trigger focus and retain surviving links", async (t) => {
  const inventory = [
    {
      id: "doc",
      name: "문서",
      state: "ready",
      variants: [
        { kind: "html", url: "https://example.test/html" },
        { kind: "paged", url: "https://example.test/paged" },
      ],
    },
  ];
  const { element, click, document } = await homepage(t, { inventory });
  const card = element("document-list").children[0];
  const [primary] = card.children[0].children;
  const alternatives = card.children[1];
  const primaryLink = primary.children[0];
  const alternativeHost = alternatives.children[1];
  const alternativeLink = alternativeHost.children[0];
  alternatives.open = true;
  alternativeHost.focus();
  await click("refresh");
  assert.equal(alternatives.children[1].children[0], alternativeLink);
  assert.equal(document.activeElement, alternativeHost);
  assert.equal(alternatives.open, true);
  alternatives.children[0].focus();
  inventory[0].variants.pop();
  await click("refresh");
  assert.equal(alternatives.hidden, true);
  assert.equal(document.activeElement, element("documents"));
  assert.equal(primary.children[0], primaryLink);
});

test("missing public address is independent of state and clears when a safe link returns", async (t) => {
  const inventory = [
    {
      id: "doc",
      name: "문서",
      state: "ready",
      variants: [
        { kind: "html", url: null },
        { kind: "paged", url: null },
      ],
    },
  ];
  const { element, click } = await homepage(t, { inventory });
  const card = element("document-list").children[0];
  const [primary, status, noAddress] = card.children[0].children;
  const alternatives = card.children[1];
  assert.equal(status.dataset.state, "ready");
  assert.equal(primary.children[0].textContent, "문서");
  assert.equal(noAddress.hidden, false);
  assert.equal(noAddress.textContent, "공개 주소 없음");
  inventory[0].variants = [{ kind: "html", url: "javascript:alert(1)" }];
  await click("refresh");
  assert.equal(primary.children[0].textContent, "문서");
  assert.equal(noAddress.hidden, false);
  inventory[0].variants.push({ kind: "paged", url: "https://example.test/paged" });
  await click("refresh");
  assert.equal(primary.children[0].href, "https://example.test/paged");
  assert.equal(alternatives.hidden, true);
  assert.equal(noAddress.hidden, true);
  inventory[0].variants = [{ kind: "html", url: null }];
  await click("refresh");
  assert.equal(noAddress.hidden, false);
  inventory[0].variants = [{ kind: "html", url: "https://example.test/html" }];
  await click("refresh");
  assert.equal(primary.children[0].href, "https://example.test/html");
  assert.equal(noAddress.hidden, true);
});

test("action notice survives polling and is replaced or cleared by later authority", async (t) => {
  const { element, click, state, calls } = await homepage(t);
  state.notices.logout = "Remote revocation was not confirmed.";
  state.notices.login = "New login notice";
  await click("logout");
  assert.equal(element("account-notice").textContent, state.notices.logout);
  await click("refresh");
  assert.equal(element("account-notice").textContent, state.notices.logout);
  await click("login");
  assert.equal(element("account-notice").textContent, state.notices.login);
  await click("refresh");
  assert.equal(element("account-notice").textContent, state.notices.login);
  state.version++;
  await click("refresh");
  assert.equal(element("account-notice").textContent, "");
  state.notices.logout = "Host-specific notice";
  await click("logout");
  assert.equal(element("account-notice").textContent, state.notices.logout);
  state.instance = "new-host";
  state.version = 0;
  await click("refresh");
  assert.equal(element("account-notice").textContent, "");
  assert.equal(calls.filter((c) => c.path.endsWith("account") && c.method === "POST").length, 3);
  assert.equal(calls.filter((c) => c.path.endsWith("models")).length, 0);
});

test("focus follows a surviving destination between primary link and menu host", async (t) => {
  const inventory = [
    {
      id: "doc",
      name: "문서",
      state: "ready",
      variants: [{ kind: "paged", url: "https://example.test/paged" }],
    },
  ];
  const { element, click, document } = await homepage(t, { inventory });
  const card = element("document-list").children[0];
  const [primary] = card.children[0].children;
  const alternatives = card.children[1];
  const link = primary.children[0];
  link.focus();
  inventory[0].variants.push({ kind: "html", url: "https://example.test/html" });
  await click("refresh");
  const host = alternatives.children[1];
  assert.equal(alternatives.open, true);
  assert.equal(host.children[0], link);
  assert.equal(document.activeElement, host);
  await click("refresh");
  assert.equal(alternatives.children[1], host);
  assert.equal(document.activeElement, host);
  assert.equal(alternatives.open, true);
  inventory[0].variants.pop();
  await click("refresh");
  assert.equal(primary.children[0], link);
  assert.equal(document.activeElement, link);
  inventory[0].variants = [];
  await click("refresh");
  assert.equal(document.activeElement, element("documents"));
});

test("focused menu host promotes even when other alternatives remain", async (t) => {
  const inventory = [
    {
      id: "doc",
      name: "문서",
      state: "ready",
      variants: [
        { kind: "html", url: "https://example.test/html" },
        { kind: "paged", url: "https://example.test/paged" },
        { kind: "paged", url: "https://example.test/other" },
      ],
    },
  ];
  const { element, click, document } = await homepage(t, { inventory });
  const card = element("document-list").children[0];
  const [primary] = card.children[0].children;
  const menu = card.children[1];
  const host = menu.children[1];
  const link = host.children[0];
  menu.open = true;
  host.focus();
  inventory[0].variants.shift();
  await click("refresh");
  assert.equal(primary.children[0], link);
  assert.equal(document.activeElement, link);
  assert.equal(menu.open, true);
  assert.equal(menu.hidden, false);
});

test("removed focused menu destination returns focus to documents", async (t) => {
  const inventory = [
    {
      id: "doc",
      name: "문서",
      state: "ready",
      variants: [
        { kind: "html", url: "https://example.test/html" },
        { kind: "paged", url: "https://example.test/paged" },
        { kind: "paged", url: "https://example.test/other" },
      ],
    },
  ];
  const { element, click, document } = await homepage(t, { inventory });
  const menu = element("document-list").children[0].children[1];
  menu.open = true;
  menu.children[1].focus();
  inventory[0].variants.splice(1, 1);
  await click("refresh");
  assert.equal(document.activeElement, element("documents"));
});

test("menu show restores a demoted destination after the library focuses its first item", async (t) => {
  const inventory = [
    {
      id: "doc",
      name: "문서",
      state: "ready",
      variants: [
        { kind: "paged", url: "https://example.test/first" },
        { kind: "paged", url: "https://example.test/second" },
      ],
    },
  ];
  const { element, click, document } = await homepage(t, { inventory });
  const card = element("document-list").children[0];
  const primary = card.children[0].children[0];
  const menu = card.children[1];
  // Make the second Paged destination primary, then demote it behind two URLs.
  inventory[0].variants.shift();
  await click("refresh");
  const link = primary.children[0];
  link.focus();
  inventory[0].variants.unshift(
    { kind: "html", url: "https://example.test/html" },
    { kind: "paged", url: "https://example.test/first" },
  );
  await click("refresh");
  const movedHost = menu.children[2];
  assert.equal(movedHost.children[0], link);
  assert.equal(document.activeElement, movedHost);
  menu.children[1].focus();
  menu.listeners.get("wa-after-show")();
  assert.equal(document.activeElement, movedHost);
});

// Execute the shipped Web Awesome key and selection methods against the same
// fake DOM as the Home tests. This models scheduling, not a real browser.
function vendorActivation(menu, document) {
  const source = readFileSync(
    new URL("../web/vendor/webawesome-3.14.0/chunks/chunk.LOCSL3WJ.js", import.meta.url),
    "utf8",
  );
  const keyStart = source.indexOf("    this.handleDocumentKeyDown = async (event) => {");
  const keyEnd = source.indexOf("    /** Handles pointer down", keyStart);
  const selectionStart = source.indexOf("  makeSelection(item, sourceEvent) {");
  const selectionEnd = source.indexOf("  /** Syncs aria attributes", selectionStart);
  assert.ok(
    keyStart >= 0 && keyEnd > keyStart && selectionStart >= 0 && selectionEnd > selectionStart,
  );
  const registration = source.slice(keyStart, keyEnd);
  const selection = source
    .slice(selectionStart, selectionEnd)
    .replace("  makeSelection(", "function makeSelection(");
  class WaSelectEvent extends Event {
    constructor(detail) {
      super("wa-select", { cancelable: true });
      this.detail = detail;
    }
  }
  menu.localize = { dir: () => "ltr" };
  menu.userTypedQuery = "";
  menu.getCurrentSubmenuItem = () => null;
  menu.getItems = () => menu.children.slice(1);
  menu.getTrigger = () => menu.children[0];
  menu.makeSelection = new Function("WaSelectEvent", `return (${selection});`)(WaSelectEvent);
  const install = new Function(
    "activeElements",
    "isTopDismissible",
    `return function() { ${registration} return this.handleDocumentKeyDown; };`,
  )(
    () => [document.activeElement],
    () => true,
  );
  const handler = install.call(menu);
  let selected;
  for (const item of menu.children.slice(1))
    item.navigate = () => {
      selected = item.href;
    };
  return async (key) => {
    menu.listeners.get("keydown")();
    await handler({ key, preventDefault() {}, stopPropagation() {} });
    return selected;
  };
}

test("vendor selection follows the focused destination after show and slot resets", async (t) => {
  const html = { kind: "html", url: "https://example.test/html" };
  const a = { kind: "paged", url: "https://example.test/a" };
  const b = { kind: "paged", url: "https://example.test/b" };
  const inventory = [{ id: "doc", name: "문서", state: "ready", variants: [b] }];
  const { element, click, document, observers } = await homepage(t, { inventory });
  const card = element("document-list").children[0];
  const title = card.children[0].children[0];
  const menu = card.children[1];
  title.children[0].focus();
  inventory[0].variants = [html, a, b];
  await click("refresh");
  let items = menu.children.slice(1);
  const host = items[1];
  // Model showMenu's first-item reset followed by its public completion event.
  items.forEach((item, index) => {
    item.active = index === 0;
  });
  items[0].focus();
  menu.listeners.get("wa-after-show")();
  assert.equal(document.activeElement, host);
  assert.deepEqual(
    items.map((item) => item.active),
    [false, true],
  );
  assert.deepEqual(
    items.map((item) => item.tabindex),
    ["-1", "0"],
  );
  assert.equal(await vendorActivation(menu, document)("Enter"), b.url);
  // Open, focus B, change siblings and model asynchronous slotchange after polling.
  menu.open = true;
  host.focus();
  inventory[0].variants = [html, b, a];
  await click("refresh");
  items = menu.children.slice(1);
  assert.equal(items[0], host);
  items.forEach((item, index) => {
    item.active = index === 0;
  });
  observers.find((observer) => observer.target === menu).callback();
  assert.equal(document.activeElement, host);
  assert.deepEqual(
    items.map((item) => item.active),
    [true, false],
  );
  inventory[0].variants = [html, a, b];
  await click("refresh");
  items = menu.children.slice(1);
  items.forEach((item, index) => {
    item.active = index === 0;
  });
  observers.find((observer) => observer.target === menu).callback();
  assert.equal(document.activeElement, host);
  assert.deepEqual(
    items.map((item) => item.active),
    [false, true],
  );
  assert.deepEqual(
    items.map((item) => item.tabindex),
    ["-1", "0"],
  );
  assert.equal(await vendorActivation(menu, document)(" "), b.url);
  menu.open = true;
  host.focus();
  const extra = { kind: "paged", url: "https://example.test/extra" };
  inventory[0].variants.push(extra);
  await click("refresh");
  items = menu.children.slice(1);
  items.forEach((item, index) => {
    item.active = index === 0;
  });
  observers.find((observer) => observer.target === menu).callback();
  assert.equal(document.activeElement, host);
  assert.deepEqual(
    items.map((item) => item.active),
    [false, true, false],
  );
  inventory[0].variants.pop();
  await click("refresh");
  items = menu.children.slice(1);
  items.forEach((item, index) => {
    item.active = index === 0;
  });
  // The capture listener repairs state even before the attribute observer fires.
  assert.equal(await vendorActivation(menu, document)("Enter"), b.url);
});

for (const [key, expectedIndex, activation] of [
  ["ArrowUp", 0, "Enter"],
  ["ArrowDown", 2, " "],
]) {
  test(`opening preserves the latest ${key} destination through ${activation}`, async (t) => {
    const html = { kind: "html", url: "https://example.test/html" };
    const a = { kind: "paged", url: "https://example.test/a" };
    const b = { kind: "paged", url: "https://example.test/b" };
    const c = { kind: "paged", url: "https://example.test/c" };
    const inventory = [{ id: "doc", name: "문서", state: "ready", variants: [b] }];
    const { element, click, document } = await homepage(t, { inventory });
    const card = element("document-list").children[0];
    const menu = card.children[1];
    card.children[0].children[0].children[0].focus();
    inventory[0].variants = [html, a, b, c];
    await click("refresh");
    const items = menu.children.slice(1);
    for (const item of items) {
      const originalFocus = item.focus.bind(item);
      item.focus = (...args) => {
        originalFocus(...args);
        menu.listeners.get("focusin")();
      };
      item.scrollIntoView = () => {};
    }
    await vendorActivation(menu, document)(key);
    assert.equal(document.activeElement, items[expectedIndex]);
    // Model the component's first-item reset immediately before wa-after-show.
    items.forEach((item, index) => {
      item.active = index === 0;
    });
    items[0].focus();
    menu.listeners.get("wa-after-show")();
    assert.equal(document.activeElement, items[expectedIndex]);
    assert.deepEqual(
      items.map((item) => item.active),
      items.map((item) => item === items[expectedIndex]),
    );
    assert.deepEqual(
      items.map((item) => item.tabindex),
      items.map((item) => (item === items[expectedIndex] ? "0" : "-1")),
    );
    assert.equal(await vendorActivation(menu, document)(activation), items[expectedIndex].href);
  });
}

for (const close of [false, true]) {
  test(`opening preserves ${close ? "trigger after close" : "focus outside"}`, async (t) => {
    const inventory = [
      {
        id: "doc",
        name: "문서",
        state: "ready",
        variants: [{ kind: "paged", url: "https://example.test/b" }],
      },
    ];
    const { element, click, document } = await homepage(t, { inventory });
    const card = element("document-list").children[0];
    const menu = card.children[1];
    card.children[0].children[0].children[0].focus();
    inventory[0].variants.unshift(
      { kind: "html", url: "https://example.test/html" },
      { kind: "paged", url: "https://example.test/a" },
    );
    await click("refresh");
    const outside = close ? menu.children[0] : element("document-search");
    if (!close) outside.parent = document;
    if (close) menu.open = false;
    outside.focus();
    document.listeners.get("focusin")();
    menu.children[1].focus();
    menu.listeners.get("wa-after-show")();
    assert.equal(document.activeElement, outside);
  });
}

test("pointer intent during opening survives the vendor first-item reset", async (t) => {
  const b = { kind: "paged", url: "https://example.test/b" };
  const inventory = [{ id: "doc", name: "문서", state: "ready", variants: [b] }];
  const { element, click, document } = await homepage(t, { inventory });
  const card = element("document-list").children[0];
  const menu = card.children[1];
  card.children[0].children[0].children[0].focus();
  inventory[0].variants = [
    { kind: "html", url: "https://example.test/html" },
    { kind: "paged", url: "https://example.test/a" },
    b,
    { kind: "paged", url: "https://example.test/c" },
  ];
  await click("refresh");
  const desired = menu.children[3];
  menu.listeners.get("pointerdown")({ target: { closest: () => desired } });
  desired.focus();
  menu.listeners.get("focusin")();
  await Promise.resolve();
  menu.children[1].focus();
  menu.listeners.get("wa-after-show")();
  assert.equal(document.activeElement, desired);
  assert.equal(await vendorActivation(menu, document)("Enter"), desired.href);
});

for (const remove of [false, true]) {
  test(`pending destination ${remove ? "removal" : "promotion"} updates restoration`, async (t) => {
    const b = { kind: "paged", url: "https://example.test/b" };
    const html = { kind: "html", url: "https://example.test/html" };
    const a = { kind: "paged", url: "https://example.test/a" };
    const inventory = [{ id: "doc", name: "문서", state: "ready", variants: [b] }];
    const { element, click, document } = await homepage(t, { inventory });
    const card = element("document-list").children[0];
    const title = card.children[0].children[0];
    const menu = card.children[1];
    title.children[0].focus();
    inventory[0].variants = [html, a, b];
    await click("refresh");
    inventory[0].variants = remove ? [html, a] : [b, a];
    const documents = element("documents");
    documents.parent = document;
    await click("refresh");
    const expected = remove ? documents : title.children[0];
    menu.children[1].focus();
    menu.listeners.get("wa-after-show")();
    assert.equal(document.activeElement, expected);
  });
}

test("a new opening invalidates an earlier pending restoration", async (t) => {
  const b = { kind: "paged", url: "https://example.test/b" };
  const inventory = [{ id: "doc", name: "문서", state: "ready", variants: [b] }];
  const { element, click, document } = await homepage(t, { inventory });
  const card = element("document-list").children[0];
  const menu = card.children[1];
  card.children[0].children[0].children[0].focus();
  inventory[0].variants = [
    { kind: "html", url: "https://example.test/html" },
    { kind: "paged", url: "https://example.test/a" },
    b,
  ];
  await click("refresh");
  menu.listeners.get("wa-show")();
  menu.listeners.get("wa-show")();
  menu.children[1].focus();
  menu.listeners.get("wa-after-show")();
  assert.equal(document.activeElement, menu.children[1]);
});
