import assert from "node:assert/strict";
import test from "node:test";
import { GraphicalAnnotations } from "../web/graphics.js";

test("measuring a wrapped mark keeps every rectangle and no empty union", () => {
  const rectangle = (left, top, width, height) => ({
    left,
    top,
    width,
    height,
    right: left + width,
    bottom: top + height,
  });
  const fragments = [rectangle(90, 30, 40, 20), rectangle(20, 70, 70, 20)];
  const originalStyle = globalThis.getComputedStyle;
  globalThis.getComputedStyle = () => ({ fontSize: "18px" });
  try {
    const value = Object.create(GraphicalAnnotations.prototype);
    value.getRevision = () => "revision";
    let ink = [];
    value.ink = () => ink;
    const record = {
      id: "graphic-1",
      tags: ["left"],
      nodes: [{ dataset: {}, getClientRects: () => fragments }],
      scene: { body: { getBoundingClientRect: () => rectangle(10, 10, 300, 100) } },
    };
    const before = value.measure(record);
    assert.deepEqual(before.geometry.markers.left.fragments, [
      { x: 80, y: 20, width: 40, height: 20 },
      { x: 10, y: 60, width: 70, height: 20 },
    ]);
    fragments[1] = rectangle(20, 75, 70, 20);
    assert.notEqual(value.measure(record).key, before.key);
    const still = value.measure(record);
    ink = [{ rect: rectangle(150, 35, 10, 20), tag: null }];
    const changedInk = value.measure(record);
    assert.equal(changedInk.signature, still.signature, "The original drawing cache can be reused");
    assert.notEqual(changedInk.key, still.key, "Moved non-target text invalidates routing");
    fragments.length = 0;
    assert.equal(value.measure(record), null);
  } finally {
    globalThis.getComputedStyle = originalStyle;
  }
});

function renderer() {
  const record = {
    id: "graphic-1",
    nodes: [{ closest: () => null }],
    note: { dataset: {} },
    scene: { visible: true, node: { isConnected: true } },
  };
  const value = Object.create(GraphicalAnnotations.prototype);
  Object.assign(value, {
    sequence: 1,
    revision: "old",
    records: new Map([[record.id, record]]),
    cache: new Map(),
    getRevision: () => value.revision,
    measure: () => ({ key: "old-position", signature: "request", geometry: {} }),
    apply: () => assert.fail("Obsolete geometry changed the body"),
    schedule: () => {
      value.scheduled = true;
    },
  });
  return { value, record };
}

test("temporary native math cannot trigger an obsolete annotation compile", async () => {
  const { value, record } = renderer();
  value.measure = () => assert.fail("Initial math geometry is not ready");
  for (const mathState of ["native", "pending"]) {
    record.nodes = [{ closest: () => ({ dataset: { mathState } }) }];
    await value.render();
  }
  assert.equal(value.busy, undefined);
});

test("an annotation response cannot enter a newer document", async () => {
  const { value } = renderer();
  let complete;
  const original = globalThis.fetch;
  globalThis.fetch = () =>
    new Promise((resolve) => {
      complete = resolve;
    });
  try {
    const rendering = value.render();
    value.sequence++;
    value.revision = "new";
    complete({
      ok: true,
      json: async () => ({ revision: "old", graphics: { "graphic-1": "svg" } }),
    });
    await rendering;
    assert.equal(value.cache.size, 0);
    assert.equal(value.scheduled, true);
  } finally {
    globalThis.fetch = original;
  }
});

test("a changed term position rejects the old overlay and schedules a new measurement", async () => {
  const { value } = renderer();
  let complete;
  const original = globalThis.fetch;
  globalThis.fetch = () =>
    new Promise((resolve) => {
      complete = resolve;
    });
  try {
    const rendering = value.render();
    value.measure = () => ({ key: "new-position" });
    complete({
      ok: true,
      json: async () => ({ revision: "old", graphics: { "graphic-1": "svg" } }),
    });
    await rendering;
    assert.equal(value.scheduled, true);
    assert.equal(value.cache.get("request"), "svg");
  } finally {
    globalThis.fetch = original;
  }
});

test("parking an older scene does not remove a replacement with the same annotation ID", () => {
  const { value, record } = renderer();
  const old = { id: record.id };
  const scene = { node: { isConnected: false }, body: {}, records: [old] };
  value.scenes = new Set([scene]);
  value.intersection = { unobserve: () => {} };
  value.resize = { unobserve: () => {} };
  value.sync();
  assert.equal(value.scenes.size, 0);
  assert.equal(value.records.get(record.id), record);
  assert.equal(value.scheduled, true);
});

test("a failed annotation request retries automatically without a reveal control", async () => {
  const { value, record } = renderer();
  const original = globalThis.fetch;
  globalThis.fetch = async () => ({ ok: false });
  try {
    await value.render();
    assert.equal(record.note.dataset.graphicState, "error");
    assert.match(record.note.textContent, /자동으로 다시 시도/);
    assert.ok(value.timer);
  } finally {
    clearTimeout(value.timer);
    globalThis.fetch = original;
  }
});
