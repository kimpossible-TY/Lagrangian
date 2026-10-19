import test from "node:test";
import assert from "node:assert/strict";
import { ReviewMarkStore } from "../web/features/review-strikes/store.js";

const fragment = { key: "paragraph", text: "Selected text.", start: 0, end: 8 };
const memory = () => {
  const values = new Map();
  return { getItem: (key) => values.get(key), setItem: (key, value) => values.set(key, value) };
};

test("red strikes persist per document and undo/clear do not touch other documents", () => {
  const storage = memory();
  const marks = new ReviewMarkStore(storage);
  marks.setDocument("first");
  assert.equal(marks.add([fragment]), true);
  marks.add([fragment]);
  marks.undo();
  const reload = new ReviewMarkStore(storage);
  reload.setDocument("first");
  assert.equal(reload.marks.length, 1);
  reload.setDocument("second");
  assert.equal(reload.marks.length, 0);
  reload.add([fragment]);
  reload.clear();
  reload.setDocument("first");
  assert.equal(reload.marks.length, 1);
});

test("parked blocks retain marks but changed block text invalidates them", () => {
  const marks = new ReviewMarkStore(memory());
  marks.setDocument("fixture");
  marks.add([fragment]);
  marks.reconcile(new Map());
  assert.equal(marks.marks.length, 1);
  marks.reconcile(new Map([[fragment.key, fragment.text]]));
  assert.equal(marks.marks.length, 1);
  marks.reconcile(new Map([[fragment.key, "Different text."]]));
  assert.equal(marks.marks.length, 0);
});

test("unavailable and corrupt storage retain bounded in-memory review controls", () => {
  const marks = new ReviewMarkStore({
    getItem() {
      throw new Error();
    },
    setItem() {
      throw new Error();
    },
  });
  marks.setDocument("fixture");
  for (let i = 0; i < 110; i++) marks.add([fragment]);
  assert.equal(marks.marks.length, 100);
  assert.equal(marks.add([{ ...fragment, end: 1000 }]), false);
  marks.undo();
  assert.equal(marks.marks.length, 99);
  marks.clear();
  assert.equal(marks.marks.length, 0);
  const corrupt = new ReviewMarkStore({ getItem: () => '[{"fragments":[{}]}]' });
  corrupt.setDocument("fixture");
  assert.equal(corrupt.marks.length, 0);
});
