import assert from "node:assert/strict";
import test from "node:test";
import { createFontSize } from "../web/features/appearance/font-size.js";
import { ReaderGestures } from "../web/features/navigation/reading-navigation.js";
import { AdaptiveCanvases } from "../web/rendering/graphics/canvases.js";
import { GraphicalAnnotations } from "../web/rendering/graphics/annotations.js";

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
  const window = new EventTarget();
  const document = new EventTarget();
  const article = new EventTarget();
  article.dataset = {};
  article.contains = (node) => node === article;
  article.closest = () => null;
  const controls = Object.fromEntries(
    ["#reader-smaller", "#reader-larger", "#reader-size"].map((id) => [id, new EventTarget()]),
  );
  const styles = new Map();
  const preview = {
    hidden: true,
    style: { setProperty() {} },
    querySelector: () => ({}),
  };
  document.documentElement = {
    clientWidth: 390,
    style: { setProperty: (key, value) => styles.set(key, value) },
  };
  document.querySelector = (selector) => controls[selector] ?? null;
  const selection = { isCollapsed: true };
  window.getSelection = () => selection;
  replace("window", window);
  replace("document", document);
  replace("innerWidth", 390);
  let next = 0;
  const frames = new Map();
  replace("requestAnimationFrame", (callback) => {
    frames.set(++next, callback);
    return next;
  });
  replace("cancelAnimationFrame", (id) => frames.delete(id));
  const writes = [];
  const anchors = [];
  let captures = 0;
  let changes = 0;
  const appearance = createFontSize({
    preferences: { write: (...args) => writes.push(args) },
    capture: () => ({ id: ++captures }),
    restore: (anchor) => anchors.push(anchor),
    changed: () => changes++,
  });
  appearance.set(18);
  writes.length = anchors.length = 0;
  const gestures = new ReaderGestures(
    article,
    { dialog: new EventTarget() },
    {
      getFont: () => appearance.size,
      setFont: appearance.set,
      previewFont: appearance.preview,
      cancelFont: appearance.cancelPreview,
      preview,
      announce: {},
    },
  );
  t.after(() => {
    gestures.dispose();
    appearance.dispose();
  });
  const touch = (id, x) => ({ identifier: id, clientX: x, clientY: 250, target: article });
  const left = touch(1, 80),
    right = touch(2, 180);
  const send = (name, touches, changed = touches) => {
    const event = new Event(name, { cancelable: true });
    Object.defineProperties(event, {
      touches: { value: touches },
      changedTouches: { value: changed },
    });
    article.dispatchEvent(event);
  };
  return {
    appearance,
    gestures,
    writes,
    anchors,
    styles,
    frames,
    document,
    window,
    selection,
    controls,
    get changes() {
      return changes;
    },
    start: () => send("touchstart", [left, right]),
    move: (ratio) => send("touchmove", [left, touch(2, 80 + ratio * 100)]),
    end: () => {
      send("touchend", [left], [right]);
      send("touchend", [], [left]);
    },
    cancel: () => send("touchcancel", [], [left, right]),
    third: () => send("touchstart", [left, right, touch(3, 140)]),
    frame() {
      const [id, callback] = frames.entries().next().value;
      frames.delete(id);
      callback();
    },
  };
}

test("live pinch coalesces movement, reflows before release and persists only its final size", (t) => {
  const r = fixture(t);
  r.start();
  r.move(1.2);
  r.move(1.5);
  assert.equal(r.frames.size, 1);
  assert.equal(r.appearance.size, 18);
  r.frame();
  assert.equal(r.appearance.size, 27);
  assert.equal(r.styles.get("--reader-font-size"), "27px");
  assert.equal(r.writes.length, 0);
  r.move(0.8);
  r.frame();
  assert.equal(r.appearance.size, 14);
  assert.equal(r.anchors[0], r.anchors[1], "All previews retain the starting reading anchor");
  r.end();
  assert.deepEqual(r.writes, [["fontSizeV2", 14]]);
  assert.equal(r.anchors[0], r.anchors[2]);
});

test("release flushes the last movement and a cancelled frame cannot overwrite it", (t) => {
  const r = fixture(t);
  r.start();
  r.move(1.4);
  const obsolete = [...r.frames.values()][0];
  r.end();
  assert.equal(r.appearance.size, 25);
  assert.deepEqual(r.writes, [["fontSizeV2", 25]]);
  r.start();
  r.move(0.8);
  obsolete();
  assert.equal(r.appearance.size, 25);
  assert.equal(r.frames.size, 1, "An old frame cannot lose the new gesture's scheduled frame");
  r.cancel();
  assert.equal(r.frames.size, 0);
});

test("cancellation rolls back live sizing without storage writes, even after returning to the start", (t) => {
  const r = fixture(t);
  r.start();
  r.move(1.5);
  r.frame();
  r.move(1);
  r.frame();
  const changes = r.changes;
  r.cancel();
  assert.equal(r.appearance.size, 18);
  assert.equal(r.writes.length, 0);
  assert.ok(r.changes > changes, "Rollback resumes renderer work held by the gesture");
  assert.equal(r.anchors[0], r.anchors.at(-1));
});

test("a third finger rolls back the preview and remaining contacts cannot restart it", (t) => {
  const r = fixture(t);
  r.start();
  r.move(1.5);
  r.frame();
  r.third();
  assert.equal(r.appearance.size, 18);
  r.start();
  r.move(1.5);
  assert.equal(r.frames.size, 0);
  r.end();
  assert.equal(r.writes.length, 0);
  r.start();
  r.move(0.1);
  r.frame();
  assert.equal(r.appearance.size, 13);
  r.end();
  assert.deepEqual(r.writes, [["fontSizeV2", 13]]);
});

for (const interruption of ["blur", "pagehide", "hidden", "width", "selection", "dispose"]) {
  test(`${interruption} cancels live sizing and prevents stale frame publication`, (t) => {
    const r = fixture(t);
    r.start();
    r.move(1.5);
    r.frame();
    r.move(1.6);
    const stale = [...r.frames.values()][0];
    if (interruption === "hidden") {
      r.document.hidden = true;
      r.document.dispatchEvent(new Event("visibilitychange"));
    } else if (interruption === "width") {
      r.document.documentElement.clientWidth = 430;
      r.window.dispatchEvent(new Event("resize"));
    } else if (interruption === "selection") {
      r.selection.isCollapsed = false;
      r.move(1.6);
    } else if (interruption === "dispose") r.gestures.dispose();
    else r.window.dispatchEvent(new Event(interruption));
    stale();
    assert.equal(r.appearance.size, 18);
    assert.equal(r.writes.length, 0);
    assert.equal(r.frames.size, 0);
  });
}

test("selection before pinch is retained, while settings buttons still persist 1px changes", (t) => {
  const r = fixture(t);
  r.selection.isCollapsed = false;
  r.start();
  r.move(1.5);
  r.end();
  assert.equal(r.appearance.size, 18);
  assert.equal(r.frames.size, 0);
  r.controls["#reader-larger"].dispatchEvent(new Event("click"));
  assert.equal(r.appearance.size, 19);
  assert.deepEqual(r.writes, [["fontSizeV2", 19]]);
});

test("legacy canvas and graphical annotation requests wait for the gesture hold", async () => {
  for (const Renderer of [AdaptiveCanvases, GraphicalAnnotations]) {
    const renderer = Object.create(Renderer.prototype);
    renderer.selectionActive = () => true;
    // No geometry or network dependencies are available while the adapter holds work.
    await renderer.render();
  }
});
