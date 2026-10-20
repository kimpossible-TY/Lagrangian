import assert from "node:assert/strict";
import test from "node:test";
import { ReaderSelectionActions } from "../web/features/selection/controller.js";

function fixture(t) {
  const element = () =>
    Object.assign(new EventTarget(), {
      style: {},
      classList: { add() {}, remove() {}, toggle() {} },
      setAttribute() {},
      contains: () => false,
      querySelector: () => ({ textContent: "" }),
      remove() {},
    });
  const elements = new Map();
  const page = Object.assign(new EventTarget(), {
    createElement: element,
    querySelector: (selector) => {
      if (selector === "dialog[open]") return null;
      if (!elements.has(selector)) elements.set(selector, element());
      return elements.get(selector);
    },
  });
  const globals = {
    document: page,
    window: Object.assign(new EventTarget(), { getSelection: () => null }),
    localStorage: undefined,
    ResizeObserver: class {
      observe() {}
      disconnect() {}
    },
  };
  const previous = new Map();
  for (const [key, value] of Object.entries(globals)) {
    previous.set(key, Object.getOwnPropertyDescriptor(globalThis, key));
    Object.defineProperty(globalThis, key, { configurable: true, value });
  }
  t.mock.timers.enable({ apis: ["setTimeout"] });
  const actions = new ReaderSelectionActions(element());
  const selected = [{ key: "body", exact: "Selected", revision: "r1" }];
  actions.selection = selected;
  const submitted = [];
  actions.source.submit = (selection) => submitted.push(selection);
  t.after(() => {
    actions.dispose();
    for (const [key, descriptor] of previous) {
      if (descriptor) Object.defineProperty(globalThis, key, descriptor);
      else delete globalThis[key];
    }
  });
  const button = elements.get("#reader-source-highlight");
  const event = (type) => {
    const event = new Event(type, { cancelable: true });
    button.dispatchEvent(event);
    return event;
  };
  return { actions, selected, submitted, event };
}

test("HTML capture preserves a pressed range through native collapse and pointerup until click", (t) => {
  const h = fixture(t);
  assert.equal(h.event("pointerdown").defaultPrevented, true);
  assert.equal(h.event("mousedown").defaultPrevented, true);
  h.event("pointerup");
  h.actions.capture();
  assert.equal(h.actions.selection, h.selected, "capture waits while toolbar interaction is held");
  h.event("click");
  assert.equal(h.submitted[0], h.selected);
  t.mock.timers.tick(0);
  h.actions.capture();
  assert.equal(h.actions.selection, null, "ordinary collapsed capture resumes after release");
});

test("HTML cancelled presses resume capture and removed controls cannot submit", (t) => {
  const h = fixture(t);
  h.event("pointerdown");
  h.event("pointercancel");
  t.mock.timers.tick(0);
  h.actions.capture();
  assert.equal(h.actions.selection, null);
  h.event("pointerdown");
  h.event("pointerup");
  h.actions.dispose();
  t.mock.timers.tick(0);
  h.event("click");
  assert.deepEqual(h.submitted, []);
});
