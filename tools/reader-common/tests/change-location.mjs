import assert from "node:assert/strict";
import test from "node:test";
import { ChangeLocationQueue } from "../navigation/change-location.js";

for (const location of [[3, 0, 400], { section: "methods", target: "paragraph-2", token: "r2" }]) {
  test(`render-before-jump retains native location ${JSON.stringify(location)}`, () => {
    const queue = new ChangeLocationQueue(false);
    queue.queue(location, true);
    assert.deepEqual(queue.afterRender(3000, -Infinity), { location, deferred: false });
    queue.clear();
    queue.queue(location, true);
    assert.equal(queue.afterRender(3000, -Infinity), undefined);
    queue.queue(location);
    assert.deepEqual(queue.afterRender(3000, 2900), { location, deferred: true });
  });
}
