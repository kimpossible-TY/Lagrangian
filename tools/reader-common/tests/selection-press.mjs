import assert from "node:assert/strict";
import test from "node:test";
import { SelectionPress } from "../selection/press.js";

for (const [name, selected, newer] of [
  ["paged", { start: { page_no: 1, x: 10, y: 20 } }, { start: { page_no: 2, x: 10, y: 20 } }],
  [
    "semantic HTML",
    [{ key: "paragraph", start: 10, end: 20 }],
    [{ key: "next", start: 0, end: 5 }],
  ],
]) {
  test(`${name} toolbar click consumes its pressed range before deferred release`, (t) => {
    t.mock.timers.enable({ apis: ["setTimeout"] });
    const released = t.mock.fn();
    const press = new SelectionPress(released);
    press.begin(selected);
    press.release();
    assert.equal(press.active, true, "pointerup must not lose the range before click");
    assert.equal(press.consume(newer), selected);
    assert.equal(press.active, false);
    assert.equal(press.consume(newer), newer, "keyboard clicks use the current selection");
    assert.equal(released.mock.callCount(), 0);
    t.mock.timers.tick(0);
    assert.equal(released.mock.callCount(), 1);
    assert.equal(press.consume(newer), newer);
  });

  test(`${name} abandoned presses release once and disposal cancels pending feedback`, (t) => {
    t.mock.timers.enable({ apis: ["setTimeout"] });
    const released = t.mock.fn();
    const press = new SelectionPress(released);
    press.begin(selected);
    press.release();
    press.release();
    t.mock.timers.tick(0);
    assert.equal(press.active, false);
    assert.equal(released.mock.callCount(), 1);
    assert.equal(press.consume(newer), newer, "pointer cancellation retires the pressed range");
    press.begin(selected);
    press.release();
    press.dispose();
    t.mock.timers.tick(0);
    assert.equal(released.mock.callCount(), 1);
    assert.equal(press.active, false);
    assert.equal(press.consume(null), null);
  });
}
