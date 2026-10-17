import assert from "node:assert/strict";
import test from "node:test";
import { MathDecorations } from "../web/decorations.js";

test("a split term retains every rectangle without painting the gap between lines", () => {
  const original = [globalThis.getComputedStyle, globalThis.innerHeight];
  globalThis.getComputedStyle = () => ({ fontSize: "18px", color: "rgb(36, 44, 52)" });
  globalThis.innerHeight = 844;
  const surface = {
    clientLeft: 0,
    clientTop: 0,
    scrollLeft: 0,
    scrollTop: 0,
    getBoundingClientRect: () => ({ left: 10, top: 20 }),
  };
  const rects = [
    { left: 20, top: 30, bottom: 50, width: 80, height: 20 },
    { left: 30, top: 60, bottom: 80, width: 40, height: 20 },
  ];
  const node = { closest: () => surface, getClientRects: () => rects };
  const value = Object.create(MathDecorations.prototype);
  value.getRevision = () => "revision";
  try {
    const before = value.measure({ id: "d", nodes: [node] });
    assert.deepEqual(before.request.fragments, [
      { width: 80, height: 20 },
      { width: 40, height: 20 },
    ]);
    assert.equal(before.request.ink, "#242c34");
    rects[1].left += 5;
    const after = value.measure({ id: "d", nodes: [node] });
    assert.equal(before.signature, after.signature, "Unchanged fragment sizes can reuse paint");
    assert.notEqual(before.key, after.key, "Moved fragments must reposition that paint");
  } finally {
    [globalThis.getComputedStyle, globalThis.innerHeight] = original;
  }
});

test("decoration responses from an obsolete document cannot paint the new one", async () => {
  let complete;
  const original = globalThis.fetch;
  globalThis.fetch = () =>
    new Promise((resolve) => {
      complete = resolve;
    });
  const value = Object.create(MathDecorations.prototype);
  let oldPaintRemoved = false;
  const record = {
    id: "d",
    nodes: [{ dataset: { flowAnchor: "old geometry" } }],
    svgs: [
      {
        remove: () => {
          oldPaintRemoved = true;
        },
      },
    ],
  };
  Object.assign(value, {
    sequence: 1,
    revision: "old",
    cache: new Map(),
    records: new Map([["d", record]]),
    getRevision: () => value.revision,
    measure: () => ({ request: {}, key: "position", signature: "geometry" }),
    status: () => {},
    changed: () => {},
    apply: () => assert.fail("Stale decoration painted"),
    schedule: () => {
      value.scheduled = true;
    },
  });
  try {
    const pending = value.render();
    assert.equal(oldPaintRemoved, true, "Old paint must not cover newly laid-out symbols");
    assert.equal(record.nodes[0].dataset.flowAnchor, undefined);
    value.sequence++;
    value.revision = "new";
    complete({ ok: true, json: async () => ({ revision: "old", decorations: { d: [] } }) });
    await pending;
    assert.equal(value.cache.size, 0);
    assert.equal(value.scheduled, true);
  } finally {
    globalThis.fetch = original;
  }
});
