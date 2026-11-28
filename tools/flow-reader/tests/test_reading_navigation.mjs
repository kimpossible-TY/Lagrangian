import test from "node:test";
import assert from "node:assert/strict";
import {
  pinchFont,
  SwipeTracker,
  springState,
  drawerMotionState,
  ReaderGestures,
} from "../web/features/navigation/reading-navigation.js";

import { createFontSize } from "../web/features/appearance/font-size.js";

test("pinch text reflow respects readable bounds, noise and invalid contacts", () => {
  assert.equal(pinchFont(13, 160, 100), 21);
  assert.equal(pinchFont(24, 75, 100), 18);
  assert.equal(pinchFont(13, 50, 100), 13);
  assert.equal(pinchFont(24, 200, 100), 30);
  assert.equal(pinchFont(20, 103, 100), 20);
  assert.equal(pinchFont(20, 40, 0), 20);
  assert.equal(pinchFont(20, NaN, 100), 20);
});

const swipe = (open = false) => new SwipeTracker({ x: 50, y: 200, time: 0, open, width: 300 });

test("vertical and diagonal reading movements do not claim the drawer", () => {
  for (const [x, y] of [
    [53, 230],
    [65, 225],
    [35, 201],
  ]) {
    const gesture = swipe();
    assert.equal(gesture.move(x, y, 40), "rejected");
    assert.equal(gesture.release(x, y, 80).open, false);
  }
});

test("distance opens/closes the drawer and cancellation restores its initial state", () => {
  const opening = swipe();
  opening.move(210, 204, 400);
  assert.equal(opening.release(210, 204, 600).open, true);
  const closing = swipe(true);
  closing.move(-120, 203, 400);
  assert.equal(closing.release(-120, 203, 600).open, false);
  assert.deepEqual(closing.release(-120, 203, 610, true), { open: true, velocity: 0 });
  assert.deepEqual(opening.release(210, 204, 610, true), { open: false, velocity: 0 });
});

test("a short intentional flick commits but a pause retires its old velocity", () => {
  const flick = swipe();
  flick.move(85, 200, 20);
  assert.equal(flick.release(90, 200, 30).open, true);
  const paused = swipe();
  paused.move(85, 200, 20);
  assert.deepEqual(paused.release(85, 200, 400), { open: false, velocity: 0 });
});

test("retargeting a drawer preserves its current position and velocity", () => {
  const current = springState(-300, 0, 900, 0.045);
  const reverse = springState(current.position, -300, current.velocity, 0);
  assert.equal(reverse.position, current.position);
  assert.equal(reverse.velocity, current.velocity);
  const settled = springState(current.position, -300, current.velocity, 1);
  assert.ok(Math.abs(settled.position + 300) < 0.001);
  assert.ok(Math.abs(settled.velocity) < 0.001);
});

test("outside dismissal anticipates gently then exits with continuous velocity", () => {
  const motion = { from: 0, to: -390, velocity: 0, playful: true };
  assert.deepEqual(drawerMotionState(motion, 0), { position: 0, velocity: 0 });
  assert.equal(drawerMotionState(motion, 0.08).position, 8);
  assert.equal(drawerMotionState(motion, 0.08).velocity, 0);
  assert.ok(Math.abs(drawerMotionState(motion, 0.079999).velocity) < 0.01);
  assert.ok(drawerMotionState(motion, 0.2).position < -300);
  assert.ok(Math.abs(drawerMotionState(motion, 0.4).position + 390) < 0.3);
  const interrupted = drawerMotionState(motion, 0.04);
  const resumed = springState(interrupted.position, 0, interrupted.velocity, 0);
  assert.deepEqual(resumed, interrupted);
});

function desktopFixture(t) {
  const previous = [globalThis.window, globalThis.document];
  const win = new EventTarget();
  const doc = new EventTarget();
  const controls = new Map();
  for (const id of ["#reader-smaller", "#reader-larger", "#reader-size"])
    controls.set(id, new EventTarget());
  const styles = new Map();
  doc.documentElement = {
    clientWidth: 1280,
    style: { setProperty: (key, value) => styles.set(key, value) },
  };
  doc.querySelector = (key) => controls.get(key) ?? null;
  win.getSelection = () => ({ isCollapsed: true });
  globalThis.window = win;
  globalThis.document = doc;
  t.mock.timers.enable({ apis: ["setTimeout"] });
  const writes = [],
    anchors = [];
  let captures = 0;
  const font = createFontSize({
    preferences: { write: (...args) => writes.push(args) },
    capture: () => ({ id: ++captures }),
    restore: (anchor) => anchors.push(anchor),
    changed() {},
  });
  font.set(18);
  writes.length = anchors.length = 0;
  const article = new EventTarget();
  article.dataset = {};
  const options = [];
  const add = win.addEventListener.bind(win);
  win.addEventListener = (name, callback, settings) => {
    options.push([name, settings]);
    add(name, callback, settings);
  };
  const gestures = new ReaderGestures(
    article,
    { dialog: new EventTarget() },
    {
      getFont: () => font.size,
      setFont: font.set,
      previewFont: font.preview,
      cancelFont: font.cancelPreview,
      preview: { hidden: true },
      announce: {},
    },
  );
  t.after(() => {
    gestures.dispose();
    font.dispose();
    [globalThis.window, globalThis.document] = previous;
  });
  const send = (name, properties) => {
    const event = new Event(name, { cancelable: true });
    Object.assign(event, properties);
    win.dispatchEvent(event);
    return event.defaultPrevented;
  };
  return { font, gestures, writes, anchors, styles, options, send, win };
}

test("Ctrl wheel normalizes pixel/line/page deltas, previews and commits once after 180ms", (t) => {
  const r = desktopFixture(t);
  assert.equal(r.options.find(([name]) => name === "wheel")[1].passive, false);
  assert.equal(r.send("wheel", { ctrlKey: false, deltaY: -100 }), false);
  for (const [deltaY, deltaMode] of [
    [-20, 0],
    [-1.25, 1],
    [-0.4, 2],
  ])
    assert.equal(r.send("wheel", { ctrlKey: true, deltaY, deltaMode }), true);
  assert.equal(r.font.size, 20);
  assert.equal(r.styles.get("--reader-font-size"), "20px");
  assert.equal(r.gestures.active, true);
  assert.deepEqual(r.writes, []);
  assert.equal(r.anchors[0], r.anchors[1]);
  t.mock.timers.tick(179);
  assert.deepEqual(r.writes, []);
  t.mock.timers.tick(1);
  assert.deepEqual(r.writes, [["fontSizeV2", 20]]);
  assert.equal(r.gestures.active, false);
  assert.equal(r.anchors[0], r.anchors.at(-1));
});

for (const interruption of ["cancel", "dispose"]) {
  test(`wheel ${interruption} rolls back and cancels its pending commit`, (t) => {
    const r = desktopFixture(t);
    r.send("wheel", { ctrlKey: true, deltaY: -10000 });
    assert.equal(r.font.size, 30);
    r.gestures[interruption]();
    t.mock.timers.tick(200);
    assert.equal(r.font.size, 18);
    assert.deepEqual(r.writes, []);
    if (interruption === "dispose")
      assert.equal(r.send("wheel", { ctrlKey: true, deltaY: -40 }), false);
  });
}

test("a selection interrupts wheel preview without leaving a delayed font commit", (t) => {
  const r = desktopFixture(t);
  r.send("wheel", { ctrlKey: true, deltaY: -80 });
  assert.equal(r.font.size, 20);
  r.win.getSelection = () => ({ isCollapsed: false });
  assert.equal(r.send("wheel", { ctrlKey: true, deltaY: -40 }), true);
  t.mock.timers.tick(200);
  assert.equal(r.font.size, 18);
  assert.equal(r.gestures.active, false);
  assert.deepEqual(r.writes, []);
});

test("a keyboard font change is not overwritten by a pending wheel commit", (t) => {
  const r = desktopFixture(t);
  r.send("wheel", { ctrlKey: true, deltaY: -80 });
  r.send("keydown", { ctrlKey: true, key: "0" });
  t.mock.timers.tick(200);
  assert.equal(r.font.size, 13);
  assert.deepEqual(r.writes, [["fontSizeV2", 13]]);
  r.send("wheel", { ctrlKey: true, deltaY: -40 });
  r.send("keydown", { ctrlKey: true, key: "+" });
  r.send("wheel", { ctrlKey: true, deltaY: -40 });
  t.mock.timers.tick(200);
  assert.equal(r.font.size, 16);
});

test("disposing a Safari preview rolls back and removes all desktop gesture listeners", (t) => {
  const r = desktopFixture(t);
  r.send("gesturestart", { scale: 1 });
  r.send("gesturechange", { scale: 1.5 });
  assert.equal(r.font.size, 27);
  r.gestures.dispose();
  assert.equal(r.font.size, 18);
  for (const type of ["gesturestart", "gesturechange", "gestureend"])
    assert.equal(r.send(type, { scale: 2 }), false);
  assert.deepEqual(r.writes, []);
});

test("Safari scale previews at readable bounds and commits the final gestureend scale", (t) => {
  const r = desktopFixture(t);
  assert.equal(r.send("gesturestart", { scale: 1 }), true);
  r.send("gesturechange", { scale: 1.5 });
  assert.equal(r.font.size, 27);
  assert.deepEqual(r.writes, []);
  r.send("gesturechange", { scale: NaN });
  assert.equal(r.font.size, 27);
  r.send("gestureend", { scale: 0.1 });
  assert.equal(r.font.size, 13);
  assert.deepEqual(r.writes, [["fontSizeV2", 13]]);
  assert.equal(r.anchors[0], r.anchors.at(-1));
  r.send("gesturestart", { scale: 1 });
  r.send("gesturechange", { scale: 2 });
  r.gestures.cancel();
  assert.equal(r.font.size, 13);
});

test("Safari gesture cannot overwrite an intervening keyboard font change", (t) => {
  const r = desktopFixture(t);
  for (const [key, changeFirst] of [
    ["0", false],
    ["+", true],
    ["-", true],
  ]) {
    r.font.set(18);
    r.writes.length = 0;
    r.send("gesturestart", { scale: 1 });
    r.send("gesturechange", { scale: 1.5 });
    r.send("keydown", { metaKey: true, key });
    const size = r.font.size;
    if (changeFirst) r.send("gesturechange", { scale: 2 });
    r.send("gestureend", { scale: 2 });
    assert.equal(r.font.size, size);
    assert.deepEqual(r.writes, [["fontSizeV2", size]]);
    assert.equal(r.gestures.active, false);
  }
});

test("window Ctrl/Cmd keyboard zoom handles symbols and numpad, reset, bounds and disposal", (t) => {
  const r = desktopFixture(t);
  for (const properties of [
    { ctrlKey: true, key: "+" },
    { metaKey: true, key: "=" },
    { ctrlKey: true, code: "NumpadAdd" },
  ])
    assert.equal(r.send("keydown", properties), true);
  assert.equal(r.font.size, 21);
  for (const properties of [
    { ctrlKey: true, key: "-" },
    { metaKey: true, key: "_" },
    { ctrlKey: true, code: "NumpadSubtract" },
  ])
    assert.equal(r.send("keydown", properties), true);
  assert.equal(r.font.size, 18);
  assert.equal(r.send("keydown", { ctrlKey: true, altKey: true, key: "+" }), false);
  assert.equal(r.send("keydown", { key: "+" }), false);
  for (const properties of [
    { ctrlKey: true, key: "0" },
    { metaKey: true, code: "Numpad0" },
  ]) {
    r.font.set(30);
    assert.equal(r.send("keydown", properties), true);
    assert.equal(r.font.size, 13);
  }
  r.send("keydown", { ctrlKey: true, key: "-" });
  assert.equal(r.font.size, 13);
  r.font.set(30);
  r.send("keydown", { metaKey: true, key: "+" });
  assert.equal(r.font.size, 30);
  r.font.dispose();
  assert.equal(r.send("keydown", { ctrlKey: true, key: "+" }), false);
});
