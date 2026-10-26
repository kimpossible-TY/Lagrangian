import assert from "node:assert/strict";
import test from "node:test";
import { createToolbarVisibility } from "../web/features/navigation/toolbar-visibility.js";

const OVERLAY_BASE = "dialog[open], [data-fallback]:not([hidden])";

// The fake only understands the selector vocabulary of the interactive-content contract,
// so a target reaches `closest` exactly when the module's selector list names it.
function matchesSelector(node, selector) {
  return selector.split(",").some((part) => {
    const clause = part.trim();
    if (clause === "a[href]") return node.tagName === "A" && node.hasAttribute("href");
    if (clause === '[role="button"]') return node.getAttribute("role") === "button";
    if (clause === '[role="link"]') return node.getAttribute("role") === "link";
    if (clause === '[tabindex]:not([tabindex="-1"])') {
      const tabindex = node.getAttribute("tabindex");
      return tabindex !== null && tabindex !== "-1";
    }
    if (clause === "[contenteditable]") return node.hasAttribute("contenteditable");
    if (clause === ".reader-toolbar") return node.className === "reader-toolbar";
    return node.tagName === clause.toUpperCase();
  });
}

function fixture(t) {
  const originals = new Map();
  const replace = (name, value) => {
    originals.set(name, Object.getOwnPropertyDescriptor(globalThis, name));
    Object.defineProperty(globalThis, name, { value, configurable: true, writable: true });
  };
  t.after(() => {
    for (const [name, descriptor] of originals) {
      if (descriptor) Object.defineProperty(globalThis, name, descriptor);
      else delete globalThis[name];
    }
  });

  const state = { selection: { isCollapsed: true }, overlay: null, queries: [] };
  const owner = new EventTarget();
  owner.activeElement = null;
  owner.getSelection = () => state.selection;
  // An engine without the Popover API rejects any selector mentioning
  // `:popover-open`, so evaluating one would kill every tap.
  owner.querySelector = (selector) => {
    state.queries.push(selector);
    if (selector.includes(":popover-open"))
      throw new SyntaxError(`unknown pseudo-class in ${selector}`);
    return selector === OVERLAY_BASE ? state.overlay : null;
  };

  const element = (options = {}) => {
    const node = new EventTarget();
    const attributes = new Map();
    node.parent = options.parent ?? null;
    node.tagName = (options.tagName ?? "div").toUpperCase();
    node.className = options.className ?? "";
    node.focusCalls = 0;
    node.setAttribute = (name, value) => attributes.set(name, String(value));
    node.removeAttribute = (name) => attributes.delete(name);
    node.getAttribute = (name) => (attributes.has(name) ? attributes.get(name) : null);
    node.hasAttribute = (name) => attributes.has(name);
    for (const [name, value] of Object.entries(options.attributes ?? {})) {
      node.setAttribute(name, value);
    }
    node.focus = () => {
      node.focusCalls += 1;
      owner.activeElement = node;
    };
    node.contains = (candidate) => {
      for (let current = candidate; current; current = current.parent) {
        if (current === node) return true;
      }
      return false;
    };
    node.closest = (selector) => {
      for (let current = node; current; current = current.parent) {
        if (matchesSelector(current, selector)) return current;
      }
      return null;
    };
    return node;
  };

  const toolbar = element({ className: "reader-toolbar" });
  toolbar.ownerDocument = owner;
  const readingSurface = element({ tagName: "article" });
  const outside = element({ tagName: "aside" });

  // Listener removal is only observable through the abort signals the controller
  // is given, so track how many registrations are still live on its three targets.
  let registrations = 0;
  for (const node of [readingSurface, toolbar, owner]) {
    const add = node.addEventListener.bind(node);
    node.addEventListener = (type, listener, options) => {
      registrations += 1;
      options?.signal?.addEventListener("abort", () => registrations--);
      return add(type, listener, options);
    };
  }

  const frames = new Map();
  let frameSerial = 0;
  replace("requestAnimationFrame", (callback) => {
    frames.set(++frameSerial, callback);
    return frameSerial;
  });

  const event = (type, properties = {}) => {
    const value = new Event(type, { cancelable: true });
    const fields = {
      pointerId: 1,
      isPrimary: true,
      button: 0,
      clientX: 120,
      clientY: 240,
      timeStamp: 0,
      metaKey: false,
      ctrlKey: false,
      shiftKey: false,
      altKey: false,
      target: readingSurface,
      ...properties,
    };
    for (const [name, field] of Object.entries(fields)) {
      Object.defineProperty(value, name, { value: field, configurable: true });
    }
    return value;
  };
  const send = (type, properties) => readingSurface.dispatchEvent(event(type, properties));
  const tap = ({ down = {}, moves = [], up = {}, click = {} } = {}) => {
    send("pointerdown", down);
    for (const move of moves) send("pointermove", move);
    send("pointerup", up);
    if (click !== null) send("click", click);
  };
  const flush = () => new Promise((resolve) => setImmediate(resolve));
  const frame = () => {
    const entry = frames.entries().next().value;
    if (!entry) return;
    const [id, callback] = entry;
    frames.delete(id);
    callback();
  };
  const settle = async () => {
    await flush();
    frame();
  };

  const visibility = createToolbarVisibility({ toolbar, readingSurface });
  t.after(() => visibility.dispose());

  return {
    visibility,
    toolbar,
    readingSurface,
    outside,
    owner,
    state,
    element,
    event,
    send,
    tap,
    flush,
    frame,
    settle,
    frames,
    get listeners() {
      return registrations;
    },
  };
}

const escape = (h) => h.owner.dispatchEvent(h.event("keydown", { key: "Escape", target: h.owner }));

test("hide marks the toolbar inert and hidden, and reveal clears every marker", (t) => {
  const h = fixture(t);

  h.visibility.hide();

  assert.equal(h.visibility.hidden, true);
  assert.equal(h.toolbar.getAttribute("data-hidden"), "true");
  assert.equal(h.toolbar.getAttribute("aria-hidden"), "true");
  assert.equal(h.toolbar.hasAttribute("inert"), true);

  h.visibility.reveal();

  assert.equal(h.visibility.hidden, false);
  assert.equal(h.toolbar.hasAttribute("data-hidden"), false);
  assert.equal(h.toolbar.hasAttribute("aria-hidden"), false);
  assert.equal(h.toolbar.hasAttribute("inert"), false);
});

test("hide and reveal are idempotent and toggle flips the toolbar once per call", (t) => {
  const h = fixture(t);

  h.visibility.hide();
  h.visibility.hide();
  assert.equal(h.visibility.hidden, true);
  assert.equal(h.toolbar.getAttribute("data-hidden"), "true");

  h.visibility.reveal();
  h.visibility.reveal();
  assert.equal(h.visibility.hidden, false);
  assert.equal(h.toolbar.hasAttribute("data-hidden"), false);

  h.visibility.toggle();
  assert.equal(h.visibility.hidden, true);
  assert.equal(h.toolbar.getAttribute("aria-hidden"), "true");

  h.visibility.toggle();
  assert.equal(h.visibility.hidden, false);
  assert.equal(h.toolbar.hasAttribute("inert"), false);
});

test("a primary tap toggles the toolbar after the deferred flush, once per tap", async (t) => {
  const h = fixture(t);

  h.tap();
  assert.equal(h.visibility.hidden, false, "the toggle waits for the deferred checks");
  await h.settle();
  assert.equal(h.visibility.hidden, true);

  await h.settle();
  assert.equal(h.visibility.hidden, true, "one tap produces one toggle");

  h.tap();
  await h.settle();
  assert.equal(h.visibility.hidden, false);
  assert.equal(h.toolbar.hasAttribute("data-hidden"), false);
});

test("the tap waits for the microtask check before scheduling the animation frame", async (t) => {
  const h = fixture(t);

  h.tap();
  assert.equal(h.visibility.hidden, false);
  assert.equal(h.frames.size, 0, "no frame is requested before the microtask runs");

  await h.flush();
  assert.equal(h.visibility.hidden, false);
  assert.equal(h.frames.size, 1, "the microtask requests the animation frame");

  h.frame();
  assert.equal(h.visibility.hidden, true);
});

test("movement beyond ten pixels rejects the tap while exactly ten still toggles", async (t) => {
  const h = fixture(t);

  h.tap({ moves: [{ clientX: 130 }] });
  await h.settle();
  assert.equal(h.visibility.hidden, true, "exactly ten pixels is still a tap");

  h.tap({ moves: [{ clientX: 130.5 }] });
  await h.settle();
  assert.equal(h.visibility.hidden, true, "movement never reveals the hidden toolbar");

  h.tap({ moves: [{ clientX: 126, clientY: 248 }] });
  await h.settle();
  assert.equal(h.visibility.hidden, false, "ten pixels along the diagonal is still a tap");
});

test("a press held past 500ms is not a tap", async (t) => {
  const h = fixture(t);

  h.tap({ up: { timeStamp: 501 } });
  await h.settle();
  assert.equal(h.visibility.hidden, false);

  h.tap({ up: { timeStamp: 500 } });
  await h.settle();
  assert.equal(h.visibility.hidden, true, "exactly 500ms is still a tap");
});

test("a second pointer down cancels the tap", async (t) => {
  const h = fixture(t);

  h.send("pointerdown");
  h.send("pointerdown", { pointerId: 2 });
  h.send("pointerup", { pointerId: 1 });
  h.send("pointerup", { pointerId: 2 });
  h.send("click");
  await h.settle();

  assert.equal(h.visibility.hidden, false);
});

test("modifier keys on the press or on the click reject the tap", async (t) => {
  const h = fixture(t);

  for (const key of ["metaKey", "ctrlKey", "shiftKey", "altKey"]) {
    h.tap({ down: { [key]: true } });
    await h.settle();
    assert.equal(h.visibility.hidden, false, `${key} at pointerdown`);
  }

  h.tap({ click: { shiftKey: true } });
  await h.settle();
  assert.equal(h.visibility.hidden, false, "modifier at click");
});

test("non-primary pointers and non-left buttons are not taps", async (t) => {
  const h = fixture(t);

  h.tap({ down: { isPrimary: false } });
  await h.settle();
  assert.equal(h.visibility.hidden, false, "non-primary pointer");

  h.tap({ down: { button: 1 }, click: { button: 1 } });
  await h.settle();
  assert.equal(h.visibility.hidden, false, "middle button");

  h.tap({ down: { button: 2 }, click: { button: 2 } });
  await h.settle();
  assert.equal(h.visibility.hidden, false, "secondary button");

  h.tap({ click: { button: 2 } });
  await h.settle();
  assert.equal(h.visibility.hidden, false, "non-left click after a left press");
});

test("taps on interactive content never toggle the toolbar", async (t) => {
  const h = fixture(t);
  const targets = {
    "a[href]": h.element({
      tagName: "a",
      parent: h.readingSurface,
      attributes: { href: "#note" },
    }),
    button: h.element({ tagName: "button", parent: h.readingSurface }),
    input: h.element({ tagName: "input", parent: h.readingSurface }),
    select: h.element({ tagName: "select", parent: h.readingSurface }),
    textarea: h.element({ tagName: "textarea", parent: h.readingSurface }),
    label: h.element({ tagName: "label", parent: h.readingSurface }),
    summary: h.element({ tagName: "summary", parent: h.readingSurface }),
    '[role="button"]': h.element({ parent: h.readingSurface, attributes: { role: "button" } }),
    '[role="link"]': h.element({ parent: h.readingSurface, attributes: { role: "link" } }),
    '[tabindex="0"]': h.element({ parent: h.readingSurface, attributes: { tabindex: "0" } }),
    "[contenteditable]": h.element({
      parent: h.readingSurface,
      attributes: { contenteditable: "" },
    }),
    ".reader-toolbar": h.element({ parent: h.readingSurface, className: "reader-toolbar" }),
  };

  for (const [selector, target] of Object.entries(targets)) {
    h.tap({ down: { target }, click: { target } });
    await h.settle();
    assert.equal(h.visibility.hidden, false, selector);
  }

  const descendant = h.element({ tagName: "span", parent: targets.button });
  h.tap({ down: { target: descendant }, click: { target: descendant } });
  await h.settle();
  assert.equal(h.visibility.hidden, false, "descendant of an interactive control");

  const paragraph = h.element({ tagName: "p", parent: h.readingSurface });
  h.tap({ down: { target: paragraph }, click: { target: paragraph } });
  await h.settle();
  assert.equal(h.visibility.hidden, true, "plain reading content still toggles");
});

test("a click consumed by another handler does not toggle", async (t) => {
  const h = fixture(t);

  h.tap({ click: { defaultPrevented: true } });
  await h.settle();
  assert.equal(h.visibility.hidden, false, "prevented click");

  h.tap({ down: { defaultPrevented: true } });
  await h.settle();
  assert.equal(h.visibility.hidden, false, "prevented pointerdown");
});

test("a click without a qualifying press, or outside the surface, is ignored", async (t) => {
  const h = fixture(t);

  h.send("click");
  await h.settle();
  assert.equal(h.visibility.hidden, false, "click without pointerdown");

  h.send("pointerdown");
  h.send("click");
  await h.settle();
  assert.equal(h.visibility.hidden, false, "pointerdown without pointerup");

  h.send("pointerdown");
  h.send("pointerup");
  h.send("click", { target: h.outside });
  await h.settle();
  assert.equal(h.visibility.hidden, false, "click target outside the reading surface");
});

test("a cancelled press cannot toggle and the next gesture starts clean", async (t) => {
  const h = fixture(t);

  h.send("pointerdown");
  h.send("pointercancel");
  h.send("click");
  await h.settle();
  assert.equal(h.visibility.hidden, false);

  h.tap();
  await h.settle();
  assert.equal(h.visibility.hidden, true);
});

test("a tap while an overlay is open leaves the toolbar to the overlay", async (t) => {
  const h = fixture(t);

  h.state.overlay = { tagName: "DIALOG" };
  h.tap();
  await h.settle();
  assert.equal(h.visibility.hidden, false);

  h.state.overlay = null;
  h.tap();
  await h.settle();
  assert.equal(h.visibility.hidden, true);
});

test("a selection at click time, or settling at either deferred check, cancels the tap", async (t) => {
  const h = fixture(t);

  h.state.selection = { isCollapsed: false };
  h.tap();
  await h.settle();
  assert.equal(h.visibility.hidden, false, "selection at click time");

  h.state.selection = { isCollapsed: true };
  h.tap();
  h.state.selection = { isCollapsed: false };
  await h.flush();
  assert.equal(h.frames.size, 0, "the microtask check abandons the animation frame");
  assert.equal(h.visibility.hidden, false);

  h.state.selection = { isCollapsed: true };
  h.tap();
  await h.flush();
  assert.equal(h.frames.size, 1);
  h.state.selection = { isCollapsed: false };
  h.frame();
  assert.equal(h.visibility.hidden, false, "the frame check abandons the toggle");
});

test("a selection active at pointerdown rejects the tap even if it collapses before the click", async (t) => {
  const h = fixture(t);

  h.state.selection = { isCollapsed: false };
  h.send("pointerdown");
  // Dismissing a selection collapses it before the click the tap produces.
  h.state.selection = { isCollapsed: true };
  h.send("pointerup");
  h.send("click");
  await h.settle();

  assert.equal(h.visibility.hidden, false);
});

test("a double click after a tap hide reveals the toolbar again", async (t) => {
  const h = fixture(t);

  h.tap();
  await h.settle();
  assert.equal(h.visibility.hidden, true);

  // The second press starts on an unselected surface; the word selection lands
  // on the click that follows it.
  h.send("pointerdown", { pointerId: 3 });
  h.state.selection = { isCollapsed: false };
  h.send("pointerup", { pointerId: 3 });
  h.send("click", { pointerId: 3, detail: 2 });
  assert.equal(h.visibility.hidden, true, "the selecting click does not toggle");

  h.send("dblclick", { pointerId: 3 });
  assert.equal(h.visibility.hidden, false);
  assert.equal(h.toolbar.hasAttribute("data-hidden"), false);

  h.state.selection = { isCollapsed: true };
  h.send("dblclick");
  assert.equal(h.visibility.hidden, false, "a later double click leaves the bar visible");
});

test("a selection that appears after a tap hide takes the toolbar back", async (t) => {
  const h = fixture(t);

  h.tap();
  await h.settle();
  assert.equal(h.visibility.hidden, true);

  h.owner.dispatchEvent(h.event("selectionchange"));
  assert.equal(h.visibility.hidden, true, "a collapsed selection keeps the bar hidden");

  h.state.selection = { isCollapsed: false };
  h.owner.dispatchEvent(h.event("selectionchange"));
  assert.equal(h.visibility.hidden, false);
});

test("a direct hide is not undone by a double click or a new selection", (t) => {
  const h = fixture(t);

  h.visibility.hide();
  h.state.selection = { isCollapsed: false };
  h.send("dblclick");
  h.owner.dispatchEvent(h.event("selectionchange"));

  assert.equal(h.visibility.hidden, true, "only a tap hide is undone");
});

test("an engine without popover support never evaluates :popover-open", async (t) => {
  const h = fixture(t);

  assert.equal(h.owner.body, undefined, "the fake models an engine without the Popover API");

  h.tap();
  await h.settle();

  assert.equal(h.visibility.hidden, true, "a normal tap still toggles");
  assert.ok(
    !h.state.queries.some((selector) => selector.includes(":popover-open")),
    "the predicate never names a pseudo-class the engine cannot parse",
  );
  assert.throws(() => h.owner.querySelector("[popover]:popover-open"), SyntaxError);
});

test("a release the reading surface missed does not disable the next tap", async (t) => {
  const h = fixture(t);

  h.send("pointerdown", { pointerId: 7 });
  // The pointer left the surface, so only the owner saw the release.
  h.owner.dispatchEvent(h.event("pointerup", { pointerId: 7 }));

  h.tap({ down: { pointerId: 8 }, up: { pointerId: 8 }, click: { pointerId: 8 } });
  await h.settle();
  assert.equal(h.visibility.hidden, true, "a stale pointer id does not cancel the tap");

  h.tap({ down: { pointerId: 9 }, up: { pointerId: 9 }, click: { pointerId: 9 } });
  await h.settle();
  assert.equal(h.visibility.hidden, false);

  h.send("pointerdown", { pointerId: 10 });
  h.owner.dispatchEvent(h.event("pointercancel", { pointerId: 10 }));

  h.tap({ down: { pointerId: 11 }, up: { pointerId: 11 }, click: { pointerId: 11 } });
  await h.settle();
  assert.equal(h.visibility.hidden, true, "a cancel the surface missed clears the same way");
});

test("Escape reveals the toolbar and restores the focus it remembers", (t) => {
  const h = fixture(t);
  const control = h.element({ tagName: "button", parent: h.toolbar });
  h.owner.activeElement = control;

  h.visibility.hide();
  assert.equal(h.visibility.hidden, true);
  assert.equal(h.owner.activeElement, h.readingSurface, "focus leaves the inert toolbar");

  escape(h);

  assert.equal(h.visibility.hidden, false);
  assert.equal(h.owner.activeElement, control);
  assert.equal(control.focusCalls, 1);
  assert.equal(h.toolbar.hasAttribute("inert"), false);
});

test("Escape while visible, or with no focus inside the toolbar, changes nothing", (t) => {
  const h = fixture(t);
  const paragraph = h.element({ tagName: "p", parent: h.readingSurface });
  h.owner.activeElement = paragraph;

  escape(h);
  assert.equal(h.visibility.hidden, false);
  assert.equal(paragraph.focusCalls, 0);

  h.visibility.hide();
  assert.equal(h.owner.activeElement, paragraph, "hiding does not steal focus from outside");
  escape(h);
  assert.equal(h.visibility.hidden, false);
  assert.equal(paragraph.focusCalls, 0);
  assert.equal(h.owner.activeElement, paragraph);
});

test("only Escape reveals a hidden toolbar", (t) => {
  const h = fixture(t);
  h.visibility.hide();

  h.owner.dispatchEvent(h.event("keydown", { key: "Enter", target: h.owner }));

  assert.equal(h.visibility.hidden, true);
  assert.equal(h.toolbar.getAttribute("data-hidden"), "true");
});

test("Escape does not return focus to a control removed while hidden", (t) => {
  const h = fixture(t);
  const control = h.element({ tagName: "button", parent: h.toolbar });
  h.owner.activeElement = control;
  h.visibility.hide();

  control.parent = h.readingSurface;
  escape(h);

  assert.equal(h.visibility.hidden, false);
  assert.equal(control.focusCalls, 0);
  assert.equal(h.owner.activeElement, h.readingSurface);
});

test("focus entering the hidden toolbar reveals it", (t) => {
  const h = fixture(t);
  h.visibility.hide();

  h.toolbar.dispatchEvent(h.event("focusin", { target: h.toolbar }));

  assert.equal(h.visibility.hidden, false);
  assert.equal(h.toolbar.hasAttribute("inert"), false);
});

test("dispose reveals the toolbar, is idempotent and detaches every listener", async (t) => {
  const h = fixture(t);
  h.visibility.hide();
  assert.ok(h.listeners > 0, "the controller attaches its listeners on creation");

  h.visibility.dispose();
  h.visibility.dispose();

  assert.equal(h.visibility.hidden, false);
  assert.equal(h.toolbar.hasAttribute("data-hidden"), false);
  assert.equal(h.toolbar.hasAttribute("inert"), false);
  assert.equal(h.listeners, 0, "every registered listener is aborted");

  h.visibility.hide();
  assert.equal(h.visibility.hidden, false, "a disposed controller cannot hide again");

  h.tap();
  await h.settle();
  escape(h);
  h.toolbar.dispatchEvent(h.event("focusin", { target: h.toolbar }));

  assert.equal(h.visibility.hidden, false);
  assert.equal(h.toolbar.hasAttribute("data-hidden"), false);
});

test("a tap pending at dispose never toggles the toolbar", async (t) => {
  const h = fixture(t);

  h.tap();
  h.visibility.dispose();
  await h.settle();

  assert.equal(h.visibility.hidden, false);
  assert.equal(h.toolbar.hasAttribute("data-hidden"), false);
});
