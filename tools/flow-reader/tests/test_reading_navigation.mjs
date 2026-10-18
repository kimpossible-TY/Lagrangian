import test from "node:test";
import assert from "node:assert/strict";
import { pinchFont, SwipeTracker, springState } from "../web/reading-navigation.js";

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
