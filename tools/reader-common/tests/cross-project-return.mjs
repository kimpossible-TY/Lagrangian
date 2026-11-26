import assert from "node:assert/strict";
import test from "node:test";
import { CrossProjectReturnStack, CROSS_PROJECT_RETURN_KEY as KEY,
  CROSS_PROJECT_PENDING_KEY as PENDING, isReturnPath } from "../navigation/cross-project-return.js";

const entry = (n = 1) => ({ path: `/d/book/?section=s${n}#anchor`, documentTitle: `Book ${n}`,
  sectionId: `s${n}`, anchor: "anchor", scrollOffset: 123.75 });
function storage() {
  const values = new Map();
  return { values, getItem: (k) => values.get(k) ?? null,
    setItem: (k, v) => values.set(k, v), removeItem: (k) => values.delete(k) };
}

test("LIFO stack persists exactly the five origin fields, copies entries and evicts oldest at 32", () => {
  const store = storage(), stack = new CrossProjectReturnStack({ storage: store });
  assert.equal(stack.canGoBack, false);
  assert.equal(stack.pop(), null);
  for (let n = 1; n <= 35; n++) assert.equal(stack.push(entry(n)), true);
  assert.equal(JSON.parse(store.getItem(KEY)).entries.length, 32);
  const reloaded = new CrossProjectReturnStack({ storage: store });
  const peek = reloaded.peek();
  peek.documentTitle = "mutated";
  assert.deepEqual(reloaded.pop(), entry(35));
  for (let n = 34; n >= 4; n--) assert.deepEqual(reloaded.pop(), entry(n));
  assert.equal(reloaded.canGoBack, false);
  assert.equal(reloaded.push({ ...entry(), extra: "discarded" }), true);
  assert.deepEqual(reloaded.peek(), entry());
  assert.equal(reloaded.clear(), true);
  assert.equal(store.getItem(KEY), null);
});

test("same-origin canonical paths only; no executable, network, traversal or encoded path escapes", () => {
  for (const path of ["/", "/d/book/#한글", "/d/a/?section=s#foo", "/d/a/#javascript:literal"])
    assert.equal(isReturnPath(path), true, path);
  const stack = new CrossProjectReturnStack();
  for (const path of ["//evil/a", "///evil", "https://evil", "javascript:alert(1)", "data:x", "book", " /d/a/", "/\\evil", "/d/a/../b/", "/d/%2e%2e/", "/%2F%2Fevil", "/%5cevil", "/d/\na/"])
    assert.equal(stack.push({ ...entry(), path }), false, path);
  for (const value of [null, {}, { ...entry(), sectionId: "" }, { ...entry(), documentTitle: null },
    { ...entry(), anchor: {} }, { ...entry(), scrollOffset: Infinity }, { ...entry(), scrollOffset: "12" }])
    assert.equal(stack.push(value), false);
  assert.equal(stack.push({ ...entry(), anchor: null, scrollOffset: -2.25 }), true);
});

test("depth is capped, configurable down to zero, and persisted oversized input is trimmed", () => {
  const store = storage();
  store.setItem(KEY, JSON.stringify({ version: 1, entries: Array.from({ length: 40 }, (_, i) => entry(i)) }));
  const stack = new CrossProjectReturnStack({ storage: store, maxDepth: 3 });
  assert.deepEqual(stack.pop(), entry(39));
  assert.deepEqual(stack.pop(), entry(38));
  assert.deepEqual(stack.pop(), entry(37));
  assert.equal(stack.pop(), null);
  assert.equal(new CrossProjectReturnStack({ maxDepth: 0 }).push(entry()), false);
  const capped = new CrossProjectReturnStack({ maxDepth: 100 });
  for (let n = 0; n < 40; n++) capped.push(entry(n));
  assert.equal(capped.entries.length, 32);
});

test("corrupt JSON, wrong versions and invalid persisted entries recover without unsafe history", () => {
  for (const raw of ["{", "null", "false", "0", '"text"', "[]", '{"version":2,"entries":[]}', '{"version":1,"entries":{}}',
    JSON.stringify({ version: 1, entries: [entry(), { ...entry(), path: "//evil" }] })]) {
    const store = storage();
    store.setItem(KEY, raw);
    const stack = new CrossProjectReturnStack({ storage: store });
    assert.equal(stack.canGoBack, false);
    assert.equal(store.getItem(KEY), null);
    assert.equal(stack.push(entry()), true);
  }
});

test("pending records match the exact route, survive wrong document/transition and consume only once", () => {
  const store = storage(), stack = new CrossProjectReturnStack({ storage: store });
  assert.equal(stack.savePending(entry(), "return-1"), true);
  assert.equal(stack.peekPending("/d/other/"), null);
  assert.equal(stack.consumePending(entry().path, "obsolete"), null);
  assert.equal(stack.savePending(entry(2), "return-2"), true);
  assert.equal(stack.consumePending(entry().path, "return-1"), null);
  assert.deepEqual(stack.consumePending(entry(2).path, "return-2"), entry(2));
  assert.equal(stack.consumePending(entry(2).path, "return-2"), null);
  assert.equal(store.getItem(PENDING), null);
  assert.equal(stack.savePending(entry(), ""), false);
  for (const raw of ["{", "null", "false", "[]", '{"version":2}', JSON.stringify({ version: 1, transitionId: "x", entry: { ...entry(), scrollOffset: null } })]) {
    store.setItem(PENDING, raw);
    assert.equal(stack.peekPending(entry().path), null);
    assert.equal(store.getItem(PENDING), null);
  }
});

test("storage exceptions fail closed and keep the previous in-memory stack recoverable", () => {
  const store = storage(), stack = new CrossProjectReturnStack({ storage: store });
  stack.push(entry());
  store.setItem = () => { throw new Error("quota"); };
  assert.equal(stack.push(entry(2)), false);
  assert.equal(stack.pop(), null);
  assert.deepEqual(stack.peek(), entry());
  assert.equal(stack.savePending(entry(), "return-1"), false);
  store.removeItem = () => { throw new Error("denied"); };
  assert.equal(stack.clear(), false);
  assert.equal(stack.canGoBack, true);
  assert.doesNotThrow(() => new CrossProjectReturnStack({ storage: { getItem() { throw Error(); }, removeItem() { throw Error(); } } }));
});
