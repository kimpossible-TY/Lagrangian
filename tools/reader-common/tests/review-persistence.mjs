import assert from "node:assert/strict";
import test from "node:test";
import { BoundedReviewStore } from "../review-strikes/bounded-store.js";

const memory = () => {
  const values = new Map();
  return {
    getItem: (key) => values.get(key),
    setItem: (key, value) => values.set(key, value),
    values,
  };
};
for (const [namespace, mark, valid] of [
  [
    "tinymist-review-v1:",
    { fragments: [{ page: 1, x: 10 }], fingerprints: { 1: "page" } },
    (v) => !!v?.fingerprints,
  ],
  [
    "flow-reader:",
    { fragments: [{ key: "paragraph", text: "Text", start: 0, end: 4 }] },
    (v) => typeof v?.fragments?.[0]?.key === "string",
  ],
]) {
  test(`${namespace} persistence uses the same bounds without interpreting native records`, () => {
    const storage = memory();
    const store = new BoundedReviewStore(storage, (id) => namespace + id, valid);
    store.setDocument("one");
    for (let i = 0; i < 105; i++) assert.equal(store.add(structuredClone(mark)), true);
    assert.equal(store.marks.length, 100);
    assert.equal(store.add({}), false);
    const reload = new BoundedReviewStore(storage, (id) => namespace + id, valid);
    reload.setDocument("one");
    assert.deepEqual(reload.marks, store.marks);
    reload.reconcile(() => true);
    assert.equal(reload.marks.length, 100);
    reload.reconcile(() => false);
    assert.equal(reload.marks.length, 0);
    reload.setDocument("two");
    reload.add(mark);
    reload.undo();
    reload.add(mark);
    reload.clear();
    assert.equal(reload.marks.length, 0);
    reload.setDocument("one");
    assert.equal(reload.marks.length, 0);
  });
}
test("byte limit removes oldest complete records and corrupt storage cannot inflate memory", () => {
  const storage = memory();
  const valid = (v) => typeof v?.text === "string";
  const store = new BoundedReviewStore(storage, (id) => id, valid);
  store.setDocument("doc");
  for (let i = 0; i < 5; i++) store.add({ text: String(i).repeat(300000) });
  assert.equal(store.marks.length, 3);
  assert.ok(storage.values.get("doc").length <= 1024 * 1024);
  assert.equal(store.marks[0].text[0], "2");
  assert.equal(store.add({ text: "x".repeat(1024 * 1024) }), false);
  storage.setItem("doc", JSON.stringify([{ text: "safe" }, {}]));
  store.reload();
  assert.equal(store.marks.length, 0);
  storage.setItem("doc", "x".repeat(1024 * 1024 + 1));
  store.reload();
  assert.equal(store.marks.length, 0);
});
