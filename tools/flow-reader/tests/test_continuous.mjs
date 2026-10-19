// Network races and selection retention can regress independently of layout.
// Actual browser geometry is checked separately with the continuous fixture.
import assert from "node:assert/strict";
import test from "node:test";
import { ContinuousSections } from "../web/features/session/continuous-sections.js";

function stream(fetchSection) {
  const value = Object.create(ContinuousSections.prototype);
  Object.assign(value, {
    generation: 1,
    manifest: { revision: "old", sections: [{ id: "a" }, { id: "b" }] },
    first: 0,
    last: 0,
    entries: new Map(),
    retry: {},
    controller: new AbortController(),
    after: { textContent: "loading" },
    fetchSection,
    near: () => true,
    mutate: () => assert.fail("An obsolete or failed request changed the document"),
  });
  return value;
}

test("a delayed neighboring section cannot enter a new reading window", async () => {
  let complete;
  const value = stream(
    () =>
      new Promise((resolve) => {
        complete = resolve;
      }),
  );
  const pending = value.extend("after", 1);
  value.generation = 2;
  value.manifest = { revision: "new", sections: [{ id: "replacement" }] };
  complete("<p>old revision</p>");
  assert.equal(await pending, false);
  assert.equal(value.entries.size, 0);
  assert.equal(value.last, 0);
});

test("a delayed restoration cannot replace content after navigation", async () => {
  let complete;
  const value = stream(
    () =>
      new Promise((resolve) => {
        complete = resolve;
      }),
  );
  const entry = { index: 0, ready: false, retryAt: 0, node: {} };
  const pending = value.restoreEntry(entry, 1);
  value.generation++;
  complete("<p>stale content</p>");
  assert.equal(await pending, false);
  assert.equal(entry.ready, false);
});

test("a failed boundary request preserves content and schedules an automatic retry", async () => {
  let calls = 0;
  const value = stream(async () => {
    calls++;
    throw new Error("offline");
  });
  value.first = 0;
  value.park = () => {};
  const delays = [];
  value.schedule = (delay) => delays.push(delay);
  await value.pump();
  assert.match(value.after.textContent, /자동으로 다시 시도/);
  assert.ok(value.retry.after > Date.now());
  assert.equal(value.last, 0);
  assert.equal(value.entries.size, 0);
  assert.deepEqual(delays, [5000]);
  // Repeated scroll/resize callbacks do not flood the offline server.
  await value.pump();
  assert.equal(calls, 1);
});

test("parking retains selected, focused and open-note sections while bounding distant content", () => {
  const value = Object.create(ContinuousSections.prototype);
  const entries = Array.from({ length: 9 }, (_, index) => ({
    index,
    ready: true,
    node: {
      index,
      dataset: {},
      style: {},
      getBoundingClientRect: () => ({ top: -10000 + index * 100, height: 100 }),
      contains: (node) => node?.index === index,
      querySelector: () => (index === 2 ? {} : null),
      replaceChildren: () => {},
      setAttribute: () => {},
    },
  }));
  const selected = entries[0].node;
  const focused = entries[1].node;
  const originals = [globalThis.window, globalThis.document, globalThis.innerHeight];
  globalThis.window = {
    getSelection: () => ({
      rangeCount: 1,
      isCollapsed: false,
      getRangeAt: () => ({ intersectsNode: (node) => node === selected }),
    }),
  };
  globalThis.document = {
    activeElement: focused,
    querySelector: () => null,
    createElement: () => ({}),
  };
  globalThis.innerHeight = 844;
  Object.assign(value, {
    entries: new Map(entries.map((entry) => [entry.index, entry])),
    near: () => false,
    mutate: (action) => action(),
  });
  try {
    value.park();
    assert.equal(entries.filter((entry) => entry.ready).length, 6);
    assert.equal(entries[0].ready, true);
    assert.equal(entries[1].ready, true);
    assert.equal(entries[2].ready, true);
    for (const entry of entries.filter((item) => !item.ready)) {
      assert.equal(entry.node.style.height, "100px");
      assert.equal(entry.node.dataset.sectionState, "parked");
    }
  } finally {
    [globalThis.window, globalThis.document, globalThis.innerHeight] = originals;
  }
});
