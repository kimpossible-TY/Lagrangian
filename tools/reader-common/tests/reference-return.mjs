import assert from "node:assert/strict";
import test from "node:test";
import { ReferenceReturn } from "../navigation/reference-return.js";

function fixture() {
  const button = new EventTarget();
  const restored = [];
  const navigation = new ReferenceReturn(button, (origin) => restored.push(origin));
  return { button, restored, navigation, click: () => button.dispatchEvent(new Event("click")) };
}

test("reference return consumes one origin and cannot repeat it", () => {
  const view = fixture();
  const anchor = { key: "passage", section: "section-1", offset: -25, url: "https://reader/" };
  assert.equal(view.button.hidden, true);
  view.navigation.remember(anchor);
  view.click();
  assert.deepEqual(view.restored, [anchor]);
  assert.equal(view.button.hidden, false, "a failed return remains available for retry");
  view.navigation.consume(anchor);
  assert.equal(view.button.hidden, true);
  view.click();
  assert.equal(view.restored.length, 1);
});

test("latest reference replaces the origin and obsolete completion cannot consume it", () => {
  const view = fixture();
  const first = { key: "first" };
  const latest = { key: "latest" };
  view.navigation.remember(first);
  view.navigation.remember(latest);
  view.navigation.consume(first);
  view.navigation.remember(null);
  view.click();
  assert.deepEqual(view.restored, [latest]);
  view.navigation.consume(latest);
  view.click();
  assert.equal(view.restored.length, 1);
  assert.equal(view.button.hidden, true);
});

test("disposal releases the return origin and click listener", () => {
  const view = fixture();
  view.navigation.remember({ key: "passage" });
  view.navigation.dispose();
  view.navigation.remember({ key: "obsolete asynchronous completion" });
  view.click();
  assert.deepEqual(view.restored, []);
  assert.equal(view.button.hidden, true);
});

test("the shared return keeps paged and HTML positions opaque", () => {
  for (const origin of [
    { page: 3, x: 0.2, y: 0.8 },
    { key: "passage", section: "section-1", offset: -25, url: "https://reader/" },
  ]) {
    const view = fixture();
    view.navigation.remember(origin);
    view.click();
    assert.equal(view.restored[0], origin);
    view.navigation.consume(origin);
    assert.equal(view.button.hidden, true);
    view.navigation.dispose();
  }
});
