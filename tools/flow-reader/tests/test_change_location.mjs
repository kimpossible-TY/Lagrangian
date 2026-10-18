import assert from "node:assert/strict";
import test from "node:test";
import { ChangeLocationQueue } from "../web/change-location.js";

test("HTML targets use the PDF queue's rendered, gesture-aware delivery", () => {
  const queue = new ChangeLocationQueue(false);
  const location = { target: "body", section: "section-10", revision: "r1" };
  queue.queue(location, true);
  assert.equal(queue.lastLocation, undefined);
  assert.deepEqual(queue.afterRender(3000, 2500), { location, deferred: true });
  assert.equal(queue.afterRender(4000, 2500), undefined);
  queue.queue({ ...location, revision: "r2" }, true);
  assert.equal(queue.afterRender(6000, 2500), undefined, "reconnect must not replay restoration");
  queue.queue({ ...location, revision: "r3" });
  assert.equal(queue.afterRender(6000, 2500).deferred, false);
});

test("a reset does not turn a rendered HTML reader into a fresh viewer", () => {
  const queue = new ChangeLocationQueue(false);
  queue.afterRender(0, -Infinity);
  queue.clear();
  queue.queue({ target: "outdated" }, true);
  assert.equal(queue.afterRender(4000, -Infinity), undefined);
  queue.queue({ target: "new edit" });
  assert.equal(queue.afterRender(5000, -Infinity).location.target, "new edit");
});
