import assert from "node:assert/strict";
import test from "node:test";
import { ResponsiveMath } from "../web/rendering/math/renderer.js";

function reader(t) {
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
  let serial = 0;
  const frames = new Map();
  const timers = new Map();
  const window = new EventTarget();
  const document = new EventTarget();
  document.fonts = { ready: Promise.resolve() };
  class Observer {
    observe() {}
    disconnect() {}
  }
  replace("window", window);
  replace("document", document);
  replace("ResizeObserver", Observer);
  replace("IntersectionObserver", Observer);
  replace("requestAnimationFrame", (callback) => {
    frames.set(++serial, callback);
    return serial;
  });
  replace("cancelAnimationFrame", (id) => frames.delete(id));
  t.mock.method(globalThis, "setTimeout", (callback) => {
    timers.set(++serial, callback);
    return serial;
  });
  t.mock.method(globalThis, "clearTimeout", (id) => timers.delete(id));
  let selected = false;
  const value = new ResponsiveMath(new EventTarget(), {
    preserve: (change) => change(),
    changed() {},
    selectionActive: () => selected,
  });
  return {
    value,
    window,
    document,
    frames,
    timers,
    select: (held) => (selected = held),
    frame() {
      const [id, callback] = frames.entries().next().value;
      frames.delete(id);
      return callback();
    },
    timer() {
      const [id, callback] = timers.entries().next().value;
      timers.delete(id);
      callback();
    },
  };
}

test("HTML math shares selection-held scheduling and resumes through its native event", async (t) => {
  const r = reader(t);
  await Promise.resolve(); // Initial font-ready request uses the same scheduler.
  let calls = 0;
  r.value.render = () => calls++;
  r.select(true);
  r.timer();
  await r.frame();
  assert.equal(calls, 0);
  assert.equal(r.frames.size + r.timers.size, 0);
  r.select(false);
  r.document.dispatchEvent(new Event("selectionchange"));
  r.timer();
  await r.frame();
  assert.equal(calls, 1);
  r.value.dispose();
});

test("HTML section replacement waits for old composition, and disposal removes event work", async (t) => {
  const r = reader(t);
  await Promise.resolve();
  let finish;
  let calls = 0;
  r.value.render = () => (++calls === 1 ? new Promise((resolve) => (finish = resolve)) : undefined);
  r.timer();
  const running = r.frame();
  const generation = r.value.generation;
  r.value.clear();
  assert.equal(r.value.generation, generation + 1);
  r.value.schedule(0);
  assert.equal(r.frames.size, 0, "Replacement must not race the old asynchronous compositor");
  finish();
  await running;
  await r.frame();
  assert.equal(calls, 2);
  r.value.schedule();
  r.value.dispose();
  r.window.dispatchEvent(new Event("resize"));
  r.document.dispatchEvent(new Event("selectionchange"));
  assert.equal(r.frames.size + r.timers.size, 0);
});
