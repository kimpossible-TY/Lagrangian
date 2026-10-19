import assert from "node:assert/strict";
import test from "node:test";
import { ChangeLocationQueue } from "../../reader-common/navigation/change-location.js";

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

test("HTML change navigation keeps explicit destinations and defers late automatic publication", async () => {
  const { ReaderChangeNavigation } = await import(
    "../web/features/navigation/change-navigation.js"
  );
  const previous = globalThis.document;
  const listeners = new Map();
  globalThis.document = {
    addEventListener: (name, listener) => listeners.set(name, listener),
    removeEventListener: (name) => listeners.delete(name),
  };
  let revision;
  let active = false;
  const navigated = [];
  const change = { token: "t1", revision: "r1", target: "paragraph", section: "section-1" };
  const manifest = { revision: "r1", anchors: { paragraph: "section-1" }, lastChange: change };
  const button = { hidden: true, addEventListener() {}, removeEventListener() {} };
  const navigation = new ReaderChangeNavigation(button, {
    revision: () => revision,
    manifest: () => manifest,
    selectionActive: () => active,
    navigate: (...args) => navigated.push(args),
  });
  try {
    navigation.queue(manifest, true);
    revision = "r1";
    navigation.afterRender();
    assert.equal(navigated.length, 0, "named/history destination retains priority");
    navigation.queue({ ...manifest, lastChange: { ...change, token: "t2" } }, false);
    navigation.markGesture();
    navigation.afterRender();
    assert.equal(button.hidden, false);
    assert.equal(navigated.length, 0);
    active = true;
    assert.equal(
      navigation.allowPublication(manifest, { changeToken: "t2", automaticChange: true }),
      false,
    );
    await navigation.jump(change);
    assert.equal(navigated.length, 1, "explicit navigation is available during a recent gesture");
    assert.equal(navigation.allowPublication(manifest, { changeToken: "obsolete" }), false);
    assert.equal(navigation.allowPublication(manifest, { changeToken: "t2" }), true);
    navigation.dispose();
    assert.equal(listeners.size, 0);
  } finally {
    globalThis.document = previous;
  }
});
