import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { homepage } from "./home_lifecycle_model_helper.mjs";

// Source composition model. No custom elements, layout, shadow DOM, trusted
// input, popover, real MutationObserver or Safari is executed here.
const vendorSource = readFileSync(
  new URL("../web/vendor/webawesome-3.14.0/chunks/chunk.LOCSL3WJ.js", import.meta.url),
  "utf8",
);
function extract(start, end) {
  const index = vendorSource.indexOf(start);
  const stop = vendorSource.indexOf(end, index);
  assert.ok(index >= 0 && stop > index);
  return vendorSource.slice(index, stop);
}
const parts = {
  pointer: extract(
    "    this.handleDocumentPointerDown = (event) => {",
    "    /** Handle global mouse",
  ),
  keyRegistration: extract(
    "    this.handleDocumentKeyDown = async (event) => {",
    "    /** Handles pointer down",
  ),
  selection: extract("  makeSelection(item, sourceEvent) {", "  /** Syncs aria attributes"),
  show: extract("  async showMenu() {", "  /** Hides the dropdown menu."),
  hide: extract("  async hideMenu() {", "  /** Handles clicks on the menu."),
  slot: extract("  async handleMenuSlotChange() {", "  /** Toggles the dropdown menu"),
  updated: extract("  async updated(changedProperties) {", "  /** Gets all dropdown items"),
};
const settle = () => new Promise(setImmediate);
const html = { kind: "html", url: "https://example.test/html" };
const a = { kind: "paged", url: "https://example.test/a" };
const b = { kind: "paged", url: "https://example.test/b" };
const c = { kind: "paged", url: "https://example.test/c" };
class ComponentEvent extends Event {
  constructor(detail) {
    super("wa-select", { cancelable: true });
    this.detail = detail;
  }
}
class ShowEvent extends Event {
  constructor() {
    super("wa-show", { cancelable: true });
  }
}
class AfterShowEvent extends Event {
  constructor() {
    super("wa-after-show");
  }
}
function vendor(menu, document) {
  let selected;
  menu.getItems = () => menu.children.filter((item) => item.localName === "wa-dropdown-item");
  menu.getTrigger = () => menu.children[0];
  menu.localize = { dir: () => "ltr" };
  menu.userTypedQuery = "";
  menu.getCurrentSubmenuItem = () => null;
  menu.syncItemSizes = () => {};
  menu.syncAriaAttributes = () => {};
  new Function("HTMLElement", "return function() {" + parts.pointer + "};")(menu.constructor).call(
    menu,
  );
  menu.handleGlobalMouseMove = () => {};
  menu.makeSelection = new Function(
    "WaSelectEvent",
    "return ({" + parts.selection + "}).makeSelection;",
  )(ComponentEvent);
  menu.handleMenuSlotChange = new Function("return ({" + parts.slot + "}).handleMenuSlotChange;")();
  const keyHandler = new Function(
    "activeElements",
    "isTopDismissible",
    "return function() {" + parts.keyRegistration + "return this.handleDocumentKeyDown;};",
  )(
    () => [document.activeElement],
    () => true,
  ).call(menu);
  const animationSource = readFileSync(
    new URL("../web/vendor/webawesome-3.14.0/chunks/chunk.L6CIKOFQ.js", import.meta.url),
    "utf8",
  );
  const animationText = animationSource.slice(
    animationSource.indexOf("function animateWithClass("),
    animationSource.indexOf("function parseDuration("),
  );
  const raf = [];
  const cancellations = [];
  const animateWithClass = new Function(
    "requestAnimationFrame",
    animationText + "return animateWithClass;",
  )((callback) => raf.push(callback));
  class MenuSurface extends EventTarget {
    constructor() {
      super();
      this.classes = new Set();
      this.activeAnimations = new Set();
      this.classList = {
        contains: (name) => this.classes.has(name),
        add: (name) => {
          this.classes.add(name);
          this.activeAnimations.add(name);
        },
        remove: (name) => {
          this.classes.delete(name);
          if (this.activeAnimations.delete(name) && !this.suppressCancel)
            cancellations.push(() => this.dispatchEvent(new Event("animationcancel")));
        },
      };
    }
    getAnimations() {
      return [...this.activeAnimations];
    }
    end() {
      this.activeAnimations.clear();
      this.dispatchEvent(new Event("animationend"));
    }
    flushRAF() {
      for (const fn of raf.splice(0)) fn();
    }
  }
  const surface = new MenuSurface();
  const showMenu = new Function(
    "WaShowEvent",
    "WaAfterShowEvent",
    "animateWithClass",
    "openDropdowns",
    "registerDismissible",
    "document",
    "return ({" + parts.show + "}).showMenu;",
  )(ShowEvent, AfterShowEvent, animateWithClass, new Set(), () => {}, document);
  class HideEvent extends Event {
    constructor() {
      super("wa-hide", { cancelable: true });
    }
  }
  class AfterHideEvent extends Event {
    constructor() {
      super("wa-after-hide");
    }
  }
  const hideMenu = new Function(
    "WaHideEvent",
    "WaAfterHideEvent",
    "animateWithClass",
    "openDropdowns",
    "unregisterDismissible",
    "document",
    "return ({" + parts.hide + "}).hideMenu;",
  )(HideEvent, AfterHideEvent, animateWithClass, new Set(), () => {}, document);
  menu.popup = { active: false };
  menu.menu = surface;
  return {
    slot: () => menu.handleMenuSlotChange(),
    show: () => showMenu.call(menu),
    finishShow: () => surface.end(),
    hide: () => hideMenu.call(menu),
    finishHide: () => surface.end(),
    flushRAF: () => surface.flushRAF(),
    flushCancel: () => {
      for (const cancel of cancellations.splice(0)) cancel();
    },
    enableLitUpdates() {
      menu.showMenu = () => showMenu.call(menu);
      menu.hideMenu = () => hideMenu.call(menu);
      menu.closeAllSubmenus = () => {};
      const updated = new Function("return ({" + parts.updated + "}).updated;")();
      let value = Boolean(menu.open);
      let scheduled = false;
      let old;
      Object.defineProperty(menu, "open", {
        configurable: true,
        get: () => value,
        set: (next) => {
          if (value === next) return;
          if (!scheduled) {
            old = value;
            scheduled = true;
            queueMicrotask(() => {
              scheduled = false;
              // Lit invokes updated without awaiting its returned Promise.
              updated.call(menu, new Map([["open", old]]));
            });
          }
          value = next;
        },
      });
    },
    async press(key) {
      selected = undefined;
      if (!document.registered.get("keydown")?.has(keyHandler)) return undefined;
      // Model the Home capture phase only when the event's focus is inside.
      if (menu.contains(document.activeElement)) menu.listeners.get("keydown")?.();
      for (const item of menu.getItems())
        item.navigate = () => {
          selected = item.href;
        };
      await keyHandler({ key, preventDefault() {}, stopPropagation() {} });
      return selected;
    },
  };
}
async function setup(t, variants = [html, a, b, c]) {
  const inventory = [{ id: "doc", name: "합성 문서", state: "ready", variants }];
  const env = await homepage(t, { inventory });
  const card = env.element("document-list").children[0];
  const title = card.children[0].children[0];
  const menu = card.children[1];
  const api = vendor(menu, env.document);
  return { ...env, inventory, title, menu, api };
}
function aligned(menu, document, href) {
  const items = menu.children.slice(1);
  assert.equal(document.activeElement.href, href);
  assert.deepEqual(
    items.map((item) => Boolean(item.active)),
    items.map((item) => item === document.activeElement),
  );
  assert.deepEqual(
    items.map((item) => item.tabindex),
    items.map((item) => (item === document.activeElement ? "0" : "-1")),
  );
}

async function opening(t) {
  const env = await setup(t, [b]);
  env.title.children[0].focus();
  env.inventory[0].variants = [html, a, b, c];
  await env.click("refresh");
  const showing = env.api.show();
  return { ...env, showing };
}
function pointer(env, target) {
  const event = new Event("pointerdown", { cancelable: true });
  Object.defineProperty(event, "target", { value: target });
  event.composedPath = () => {
    const path = [];
    for (let node = target; node; node = node.parentElement) path.push(node);
    return path;
  };
  env.document.dispatchEvent(event);
  if (env.menu.contains(target)) env.menu.listeners.get("pointerdown")?.(event);
}
function listenerCount(document, type) {
  return document.registered.get(type)?.size || 0;
}

test("animationcancel during hide: trigger reopen waits for both completions and re-registers keys", async (t) => {
  const env = await opening(t);
  await env.api.press("Escape");
  const hiding = env.api.hide();
  const event = {
    preventDefault() {
      this.prevented = true;
    },
    stopPropagation() {
      this.stopped = true;
    },
  };
  env.menu.children[0].listeners.get("click")(event);
  assert.equal(event.stopped, true);
  env.api.flushCancel();
  await env.showing;
  await hiding;
  await settle();
  assert.equal(env.menu.open, true);
  assert.equal(env.menu.popup.active, false);
  const reopening = env.api.show();
  env.api.finishShow();
  await reopening;
  await settle();
  assert.equal(listenerCount(env.document, "keydown"), 1);
  await env.api.press("ArrowDown");
  await settle();
  const focus = env.document.activeElement.href;
  assert.equal(await env.api.press("Enter"), focus);
});

test("RAF fallback resolves the actual animation helper without an animation", async (t) => {
  const env = await opening(t);
  env.menu.menu.activeAnimations.clear();
  env.api.flushRAF();
  await env.showing;
  await settle();
  assert.equal(listenerCount(env.document, "keydown"), 1);
  assert.equal(env.menu.open, true);
});

test("Lit does not await show: canceled opening and queued reopen retain latest C", async (t) => {
  const env = await setup(t, [b]);
  env.api.enableLitUpdates();
  env.title.children[0].focus();
  env.inventory[0].variants = [html, a, b, c];
  await env.click("refresh");
  assert.equal(listenerCount(env.document, "keydown"), 1);
  await env.api.press("Escape");
  assert.equal(listenerCount(env.document, "keydown"), 0);
  const event = {
    preventDefault() {},
    stopPropagation() {
      this.stopped = true;
    },
  };
  env.menu.children[0].listeners.get("click")(event);
  assert.equal(event.stopped, true);
  const desired = env.menu.children[3];
  pointer(env, desired);
  desired.focus();
  await settle();
  env.api.flushCancel();
  await settle();
  assert.equal(env.menu.open, true);
  assert.equal(env.menu.popup.active, true);
  assert.equal(listenerCount(env.document, "keydown"), 1);
  env.api.finishShow();
  await settle();
  aligned(env.menu, env.document, c.url);
  assert.equal(await env.api.press(" "), c.url);
  await settle();
  assert.equal(env.menu.open, false);
});

test("programmatic reopen during hide is closed again before the next show", async (t) => {
  const env = await setup(t, [b]);
  const transitions = [];
  for (const name of ["wa-show", "wa-hide", "wa-after-show", "wa-after-hide"])
    env.menu.addEventListener(name, () => transitions.push(name));
  env.api.enableLitUpdates();
  env.title.children[0].focus();
  env.inventory[0].variants = [html, a, b, c];
  await env.click("refresh");
  await env.api.press("Escape");
  env.menu.open = true;
  await settle();
  env.api.flushCancel();
  await settle();
  // An extra close is needed because the early show saw an active popup.
  env.api.finishHide();
  await settle();
  assert.equal(env.menu.open, true);
  assert.equal(listenerCount(env.document, "keydown"), 1);
  env.api.finishShow();
  await settle();
  await env.api.press("ArrowDown");
  await settle();
  const destination = env.document.activeElement.href;
  assert.ok(transitions.filter((name) => name === "wa-show").length <= 3);
  assert.ok(transitions.filter((name) => name === "wa-hide").length <= 2);
  assert.equal(await env.api.press("Enter"), destination);
});

test("ordinary close then reopen registers one keyboard listener and Escape closes once", async (t) => {
  const env = await setup(t, [b]);
  env.api.enableLitUpdates();
  env.title.children[0].focus();
  env.inventory[0].variants = [html, a, b, c];
  await env.click("refresh");
  env.api.finishShow();
  await settle();
  await env.api.press("Escape");
  env.api.flushCancel();
  env.api.finishHide();
  await settle();
  assert.equal(env.menu.open, false);
  env.menu.open = true;
  await settle();
  env.api.finishShow();
  await settle();
  assert.equal(listenerCount(env.document, "keydown"), 1);
  await env.api.press("Escape");
  await settle();
  assert.equal(env.menu.open, false);
  assert.equal(listenerCount(env.document, "keydown"), 0);
});

test("another menu pointer cancels queued reopening and releases temporary listeners", async (t) => {
  const env = await setup(t, [b]);
  env.api.enableLitUpdates();
  env.title.children[0].focus();
  env.inventory[0].variants = [html, a, b, c];
  env.inventory.push({ id: "other", name: "다른 문서", state: "ready", variants: [html, a] });
  await env.click("refresh");
  await env.api.press("Escape");
  env.menu.children[0].listeners.get("click")({ preventDefault() {}, stopPropagation() {} });
  const otherTrigger = env.element("document-list").children[1].children[1].children[0];
  pointer(env, otherTrigger);
  otherTrigger.focus();
  env.api.flushCancel();
  await settle();
  assert.equal(env.menu.open, false);
  assert.equal(listenerCount(env.document, "keydown"), 0);
  assert.equal(env.document.activeElement, otherTrigger);
});

test("removing a document cancels a queued reopen and its observer", async (t) => {
  const env = await setup(t, [b]);
  env.api.enableLitUpdates();
  env.title.children[0].focus();
  env.inventory[0].variants = [html, a, b, c];
  await env.click("refresh");
  await env.api.press("Escape");
  env.menu.children[0].listeners.get("click")({ preventDefault() {}, stopPropagation() {} });
  env.inventory.splice(0);
  await env.click("refresh");
  env.api.flushCancel();
  await settle();
  assert.equal(env.menu.open, false);
  assert.equal(env.observers.filter((observer) => observer.target).length, 0);
  assert.equal(listenerCount(env.document, "focusin"), 0);
  assert.equal(listenerCount(env.document, "keydown"), 0);
});

test("Escape cancels a queued reopen without leaving Home listeners", async (t) => {
  const env = await setup(t, [b]);
  env.api.enableLitUpdates();
  env.title.children[0].focus();
  env.inventory[0].variants = [html, a, b, c];
  await env.click("refresh");
  await env.api.press("Escape");
  env.menu.children[0].listeners.get("click")({ preventDefault() {}, stopPropagation() {} });
  const event = new Event("keydown", { cancelable: true });
  Object.defineProperty(event, "key", { value: "Escape" });
  env.document.dispatchEvent(event);
  assert.equal(event.defaultPrevented, true);
  env.api.flushCancel();
  await settle();
  assert.equal(env.menu.open, false);
  assert.equal(listenerCount(env.document, "keydown"), 0);
  assert.equal(listenerCount(env.document, "pointerdown"), 0);
  assert.equal(env.document.activeElement, env.menu.children[0]);
});

test("reopen during closing after a completed show retains keyboard navigation", async (t) => {
  const env = await setup(t, [b]);
  env.api.enableLitUpdates();
  env.title.children[0].focus();
  env.inventory[0].variants = [html, a, b, c];
  await env.click("refresh");
  env.api.finishShow();
  await settle();
  await env.api.press("Escape");
  const event = {
    preventDefault() {},
    stopPropagation() {
      this.stopped = true;
    },
  };
  env.menu.children[0].listeners.get("click")(event);
  assert.equal(event.stopped, true);
  env.api.finishHide();
  await settle();
  assert.equal(env.menu.open, true);
  assert.equal(listenerCount(env.document, "keydown"), 1);
  env.api.finishShow();
  await settle();
  await env.api.press("ArrowDown");
  await settle();
  const destination = env.document.activeElement.href;
  assert.equal(await env.api.press(" "), destination);
});

test("a second trigger activation cancels a queued reopen", async (t) => {
  const env = await setup(t, [b]);
  env.api.enableLitUpdates();
  env.title.children[0].focus();
  env.inventory[0].variants = [html, a, b, c];
  await env.click("refresh");
  await env.api.press("Escape");
  const activate = () =>
    env.menu.children[0].listeners.get("click")({ preventDefault() {}, stopPropagation() {} });
  activate();
  activate();
  env.api.flushCancel();
  await settle();
  assert.equal(env.menu.open, false);
  assert.equal(listenerCount(env.document, "keydown"), 0);
  assert.equal(listenerCount(env.document, "pointerdown"), 0);
});

test("outside nonfocusable pointer is not replaced by late show focus", async (t) => {
  const env = await opening(t);
  const heading = env.element("outside-heading");
  const body = env.element("body");
  env.document.body = body;
  pointer(env, heading);
  env.document.activeElement = body;
  const hiding = env.api.hide();
  await Promise.resolve();
  env.api.flushCancel();
  await env.showing;
  await hiding;
  await settle();
  assert.equal(env.menu.open, false);
  assert.equal(env.document.activeElement, body);
});

test("before animation starts, RAF waits for the hide animation and queued reopen", async (t) => {
  const env = await opening(t);
  env.menu.menu.suppressCancel = true;
  await env.api.press("Escape");
  const hiding = env.api.hide();
  env.menu.children[0].listeners.get("click")({ preventDefault() {}, stopPropagation() {} });
  env.api.flushRAF();
  await Promise.resolve();
  assert.equal(env.menu.open, false);
  env.api.finishHide();
  await env.showing;
  await hiding;
  await settle();
  assert.equal(env.menu.open, true);
  const reopening = env.api.show();
  env.api.finishShow();
  await reopening;
  assert.equal(listenerCount(env.document, "keydown"), 1);
});
